# Plan 4 — Migrate the project from Bash (+ Python/JS glue) to Go

**Directive:** no new Python; move the project to Go. This plan is the substrate the other three
plans now build on — the credential broker (Plan 1) becomes a Go proxy, and the single harness
runner (Plan 2) becomes a Go package.

## Why Go (each point maps to an adversarial-review finding)
- **One signed, versioned, checksummed binary** replaces the `curl … proveo.ca/cli/install.sh |
  bash` pipeline that verifies/pins nothing — closes the installer-RCE HIGH.
- **One typed `docker run` builder** replaces the run logic triplicated across the consumer CLI
  (442-line reimpl), `lib/runners.sh`, and every `defs/*/run.sh` — closes the triplication +
  6-way-copied hardening baseline.
- **Real tests + typed config** replace grep-string contract tests and bash-3.2 hacks (nameref
  emulation via `eval`, `+`-guarded empty arrays, `set -a` .env sourcing).
- **A first-class MITM proxy** (Go) lets the credential broker inject/strip decrypted traffic
  **without** a Python mitmproxy addon — removes Python from the egress path entirely.
- **Cross-platform** (macOS/Linux × arm64/amd64) with `CGO_ENABLED=0` static binaries — no shell
  portability branches.

## Two Bash surfaces, both ported
1. **Host-side orchestration** — the `proveo` CLI, maintainer `mise`/`lib/*.sh`, per-def
   `run/build/test.sh`, and the egress lifecycle. Shells out to `docker` via `os/exec`.
2. **In-container entrypoint** — `packages/lib/entrypoint-lib.sh` + per-def `entrypoint.sh` (incl.
   the embedded Python `apply_env_bridges`). Becomes a small static Go binary baked into each image.

## Strategy: strangler-fig, behavior-parity, incremental
Each phase ships a working product; Bash is deleted only after its Go replacement passes parity.

**Phase 0 — Scaffold + CLI parity**
- Go module (`github.com/proveo-ca/proveo`), `cmd/proveo`, `internal/…`. Min Go 1.22.
- Reproduce the consumer surface (`help`, `list`, `run <target>`, `init`, `uninstall`,
  `--egress-mode`, monorepo scope pick) shelling out to `docker` — typed, same behavior.
- `goreleaser` → multi-arch binaries + `checksums.txt` (+ optional cosign). New `install.sh` only
  downloads the right binary and **verifies the checksum** (kills the curl|bash HIGH).
- Golden tests over the composed `docker run` argv.

**Phase 1 — Unify docker-run + CLI + installer** — *core landed*
- [x] `internal/runner`: the single hardened-argv builder (cap-drop, no-new-privileges, pids-limit,
      uid, tmpfs, mounts) — the one place the baseline lives. Golden-tested.
- [x] `cmd/proveo` (cobra): `version`, `list`, `run <target> [--egress-mode] [--local-model]
      [--print]`. `run` composes runner + egress plan + provider detection + monorepo scope;
      `--print` renders the full docker plan (verified). **All egress modes exec**: it stages the
      Squid config (`egress.StageSquidConfig`), applies the plan, waits for the inspector CA, runs
      the agent attached to the terminal, and tears down. (The multi-container run itself is covered
      by the gated Docker test; the composed pieces are each verified.)
- [x] Installer: `.goreleaser.yaml` (multi-arch static `proveo` + `proveo-egress` + sha256
      `checksums.txt`) and `dist/install.sh` that **downloads a pinned release + verifies the
      checksum before install** — kills the unverified `curl | bash` RCE. install.sh shellcheck-clean;
      both binaries cross-compile (linux/darwin × amd64/arm64).
- [x] `internal/manifest`: reads `defs/<name>/harness.manifest` (YAML) — the single registration
      point (Plan 2). Manifests **and the Squid config are `go:embed`ed** (root `embed.go`), so the
      binary is standalone — verified: `proveo list` works from `/tmp` with no defs tree. Targets
      enumerate from the manifests; `PROVEO_DEFS_DIR` overrides for dev. No hardcoded target list.
- [x] `internal/workspace`: monorepo scope (git root + repo-relative prefix); `proveo run` from a
      subproject mounts the repo root and reports the subpath. Injectable git func → unit-tested.
- [x] Git identity forwarding in Go (`internal/gitidentity`).

**Phase 2 — Egress + credential broker in Go (Plan 1 lands)** — *in progress*
- [x] `cmd/proveo-egress` + `internal/{egressproxy,broker,provider}`: a martian MITM proxy that
      terminates TLS with a generated CA, records flows as NDJSON (**replaces `ndjson_dump.py`**,
      query string dropped), forwards to Squid upstream, and does the credential **inject/strip**
      broker. Built, unit-tested (15 tests), smoke- and image-verified (3.4 MB distroless, non-root).
- [x] `defs/lib/egress.sh` wires it as the default inspector (`PROVEO_EGRESS_INSPECTOR=go`), writes
      the broker secret env-file, keeps mitmproxy selectable.
- [x] Port **provider detection + Squid write-pin ACL** into Go: unified ordered registry
      (`internal/provider`) is now the single source for detection vars, broker auth, and Squid
      ACL; `internal/egress.ProviderAllowConf` renders the allowlist. `proveo-egress detect` /
      `provider-allow` subcommands expose it; `egress.sh` delegates detection to the binary via
      `PROVEO_EGRESS_BIN` (parity-proven, Bash fallback preserved). The parity check **surfaced and
      fixed a real Bash bug** — `write_provider_allow` glued the ACL line onto `http_access` with no
      newline (malformed Squid config that the substring-based contract tests never caught).
- [x] Ported the docker-exec orchestration into `internal/egress` as a pure `BuildPlan` (networks,
      sidecars, connects, agent args, cleanup) + an injectable `Runner`/`ExecRunner`. Golden-tested
      per mode (broker|proxy|firewall_SLASH ± local-model ± broker) with security-invariant assertions
      (agent nets `--internal`, only Squid on the egress net, CA trust in firewall). The CLI's
      `run` executes it.
- [x] `egress.sh` now delegates **both** detection and `provider-allow` to the Go binary when
      `PROVEO_EGRESS_BIN` is set (parity-proven; Bash fallback retained). Fixed a real Bash bug the
      parity check surfaced (missing newline glued the ACL onto `http_access`).
- [x] End-to-end broker integration test (`internal/egressproxy`, in-process): drives real HTTP
      through the assembled martian proxy and asserts the credential is injected on the pinned
      provider host and stripped on an exfil host — validates Plan 1 through the full modifier
      chain, not just `broker.Apply`. Runs in the normal suite (no Docker).
- [x] Docker multi-container integration test (`internal/egress`, gated by
      `PROVEO_EGRESS_INTEGRATION=1`): `BuildPlan` brings up Squid + the Go proxy; a `curlimages/curl`
      agent then proves the live invariants — a real HTTPS GET succeeds through
      agent→mitmproxy→squid→internet with the generated CA trusted, the decrypted request is
      recorded to `flows.ndjson`, and a proxy-bypassing request fails (internal net = no direct
      egress). Teardown leaves no containers/networks. Skips cleanly without the env var.
- [x] **Bash retirement, round 1**: deleted the dead `registry/*.yaml`; retired the duplicated
      provider Bash from `egress.sh` (`provider_acl`, `key_present`, the detection list, the
      allowlist generator — ~120 lines) down to Go delegation via `proveo-egress`. The contract
      suite now builds the binary and exercises detection + allowlist **through Go** (live single
      source); `update-provider-allow.sh` reads the registry via `proveo-egress providers`. Also
      fixed the contract-runner's **masking bug** (`test_egress.sh` printed failures but exited 0)
      — verified an injected failure now fails the runner. The live bash integration
      (`PROVEO_EGRESS_INTEGRATION=1`) passes end to end through the rewired path, and caught a real
      regression along the way (custom-domains env not forwarded to the Go subprocess — fixed).
- [x] Bash retirement, round 2: `defs/*/run.sh` → thin `proveo run` shims;
      maintainer + consumer `runners.sh` `run`/`debug` exec the Go binary; host git identity
      in `internal/gitidentity`; DinD only via `internal/dind`; consumer install no longer ships
      `workspace.sh`/`dind.sh`. Specs updated (`_spec/components.puml`, `usage.puml`, paradigms).
- [x] `defs/lib/egress.sh` reduced to **proveo-egress CLI wrappers** (detect / provider-allow /
      providers). Topology orchestration is Go-only; bash `test_egress` static+provider contracts
      remain; live topology → `go test ./internal/egress/`.

## Round 3 (bounded security + CLI parity) — done
- [x] CLI flag parity for the coming shim cutover: `--shell` (via `runner.Entrypoint`), `--data-dir`,
      `--image` (+ `--scope`); verified composing in `--print`.
- [x] `dist/install.sh` hands off to `proveo setup` for cross-shell PATH (falls back to a note).
- [x] Egress dashboard hardened: HTML-escape all log fields (stored XSS), bind `127.0.0.1`, optional
      `PROVEO_EGRESS_DASHBOARD_TOKEN` gate.
- [x] DNS exfil channel closed: proxy/firewall agents get `--dns 0.0.0.0` (the proxy resolves
      targets; Docker still resolves sidecar aliases internally). Invariant-tested; live integration
      re-confirmed.
- [x] FireHOL fetch made pinnable (`FIREHOL_REF` commit) + optional `FIREHOL_SHA256` verification;
      warns on the mutable-`master` default.

## Round 4 (partial) — opencode/cecli egress closed (interim)
- [x] Wired the egress lifecycle into `defs/opencode/run.sh` and `defs/cecli/run.sh` (the same
      `proveo_egress_prepare`/`append`/`cleanup` pattern as claudecode/cursor) + `--egress-mode`/
      `--local-model`/`--shell` flags; manifests flipped to `egress: true`. This closes the review's
      HIGH finding (those two harnesses ran with unrestricted egress + keys). Fake-docker dry-run
      confirms the Squid topology + `ENFORCEMENT_PROXY`. **Interim**: this is throwaway once the shim
      cutover lands (below), but it closes a live security hole now without touching mounts.

## Blocker found: the shim cutover needs a mount-model port first
Converting `defs/*/run.sh` to `proveo run` shims is NOT mechanical: cursor/opencode/cecli use a rich
`/app` monorepo mount model (whole-repo vs scope-subdir vs non-repo; `.git`; a root-file
preservation loop; `.cursor`/`.opencode`/`.cecli` config mounts; `.env`; per-harness
`APP_MOUNT_MODE`; `-w /app`) that `proveo run` does NOT implement — it only does claudecode's
`input:ro`+`output:rw`. A naive shim would silently break in-place editing + monorepo context, and
it can't be runtime-verified here (those images aren't built). So the shim cutover is gated on:
- [x] Port the `/app` monorepo mount model into `proveo run` (`internal/workspace` + manifests).
- [x] `run.sh` → shims; egress orchestration Bash retired; consumer runners exec Go `proveo`.

## In-container entrypoint → Go (Phase 3 — landed core)
- [x] `cmd/proveo-entrypoint` + `internal/entrypoint`: runtime user, .env load/skip, model bridges,
      git identity, smoke mode, **credential-broker sentinel**.
- [x] Baked into harness Dockerfiles (multi-stage build); bash `entrypoint-lib.sh` delegates to
      `proveo-entrypoint prep` when present and keeps a pure-bash fallback.
- [x] `proveo run` firewall mode injects sentinel values + `PROVEO_CREDENTIAL_BROKER_KEYS`.
- [x] Per-def entrypoints prefer `proveo-entrypoint prep`; keep seed + exec agent-specific logic in bash.

## Testing standard
All Go tests follow `docs/go-testing-standards.md` (from the official Go Wiki): table-driven +
`t.Run` subtests, `t.Parallel`, `go-cmp` diffs with got/want-and-input messages, `t.TempDir`, golden
files for generated config, no assert libraries. Run with `-race`.

**Phase 3 — In-container entrypoint in Go**
- `cmd/proveo-entrypoint`: `ensure_runtime_user`, `.env` load + model-alias bridging (replaces the
  embedded Python), git-identity bridge, git-context report, verify-command detection, smoke mode.
  Baked per image (multi-arch static). Per-def entrypoints shrink to one `exec`.

**Phase 4 — Retire Bash/JS**
- Delete `lib/*.sh`, consumer `lib/*.sh`, per-def `*.sh` wrappers, dead `registry/*.yaml`.
- egress-dashboard: port to a Go-served static page (and fix XSS/bind/auth), or keep as the one
  deliberate JS UI — decide in Phase 2.
- Contract tests → Go tests (see [Plan 3](03-bash-test-migration.md)).

## Sequencing — egress-proxy first (decided)
Plan 1's broker depends on the Go egress proxy, and the user chose to build it **first** (highest
security value, and the reason Python was rejected). So the order is: minimal Phase-0 scaffold →
Phase-2 egress proxy (with the broker) → then Phase-1 runner and Phase-0 CLI parity → Phase-3
entrypoint → Phase-4 retire. The `squid.conf` static-allowlist removal **already landed**
(language-agnostic) and stands alone.

## Decisions (resolved 2026-07-05)
| # | Decision | Chosen |
|---|----------|--------|
| 1 | Migration scope/order | **Egress-proxy first** (then CLI/runner, then entrypoint) |
| 2 | Egress proxy | **Full Go MITM via `github.com/google/martian/v3`** — replaces the mitmproxy sidecar, removes Python |
| 3 | CLI framework | **`spf13/cobra`** |
| 4 | Manifest/config format | YAML (`yaml.v3`) — recommended default, unconfirmed |
| 5 | Module path / org | `github.com/proveo-ca/proveo` — recommended default, unconfirmed |

## Acceptance criteria
- `proveo` is a single static binary; install verifies a checksum; no `curl|bash` of live scripts.
- No Python in the egress path (broker + flow recording are Go); remaining Python, if any, is
  explicitly justified.
- The hardened `docker run` argv exists in exactly one Go package with golden tests.
- Behavior parity proven per phase before the corresponding Bash is deleted.
- Spec-first: add a Go component/deployment view to `_spec/` before each phase's code.
