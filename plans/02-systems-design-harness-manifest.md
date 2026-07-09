# Plan 2 — Systems Design: One Harness Manifest, One Runner

**Paradigm imported from omnigent:** the `Executor` protocol. omnigent never special-cases a
vendor in the orchestrator — it defines **one contract** (`run_turn(messages, tools,
system_prompt)`) and every vendor is a conforming, discoverable backend. Apply that at the
harness-fleet level: one declarative manifest per def, one runner that reads it, everything else
enumerates from it.

## Problem (from the adversarial review)
- **Run logic is triplicated** — consumer `apps/cli/public/cli/lib/runners.sh` (442-line full
  reimplementation), maintainer `lib/runners.sh` (thin shim), and `defs/<name>/run.sh` (the real
  thing). The hardening baseline (`--cap-drop=ALL --security-opt=no-new-privileges --pids-limit`)
  is copy-pasted into 6 files; `proveo_git_identity_env_args` is defined twice (the consumer copy
  self-describes as "a standalone mirror").
- **Adding a harness touches ~8-10 hardcoded sites**; no single registration point.
- **The `registry/*.yaml` files are dead** — nothing parses them; the data is re-hardcoded in Bash.
- **cursor is tested-but-unshippable** — fully built + contract-tested, but absent from consumer
  `TARGETS`/`image_name`/`run_target`, maintainer `target_dir`/`build`, and the smoke suite. This
  is the coupling cost made visible: someone wired 5 of ~10 sites and the def can't run.
- **Contract tests are static grep assertions**, not behavior; Docker egress invariants never run.

## Status (landed via Plan 4)
The manifest + single runner now exist in Go: `internal/manifest` reads `defs/<name>/harness.manifest`
(one file per harness), `internal/runner` holds the one hardened `docker run` baseline, and the
`proveo` CLI enumerates targets from the manifests. Adding a harness = drop a def dir + manifest
(verified). Remaining: embed manifests into the distributed binary, retire the parallel Bash
`TARGETS`/`image_name`/`run_target` lists, and delete the dead `registry/*.yaml`.

## Design
1. **`defs/<name>/harness.manifest`** (or `manifest.yaml`) — the single source of truth per def:
   ```yaml
   name: cursor
   image: ${BRAND_IMAGE_ORG}/cursor:latest       # BRAND_* → Plan 3
   variants: [default]
   description: Policy-gated autonomous loop (Cursor CLI)
   egress: true            # sources defs/lib/egress.sh
   stability: candidate    # experimental | candidate | stable
   ```
2. **One `docker-run` helper** in a shared lib carrying the *single* canonical hardening baseline;
   both the consumer CLI bundle and `defs/*/run.sh` call it. Ship the shared lib **into** the
   published CLI bundle so the "standalone mirror" hack disappears.
3. **Enumerate, don't hardcode** — consumer `TARGETS`/`image_name`/`run_target`, maintainer mise
   tasks, the smoke suite, and the contract tests all read the manifest set instead of parallel
   literal lists. `is_ai_harness`, `target_description` derive from manifest fields.
4. **Contract test upgrade** — assert manifest-derived invariants (every def has a manifest; every
   manifest image uses `BRAND_IMAGE_ORG`; egress:true defs source egress.sh) rather than grepping
   for literal strings.

## Work items
- [ ] Define the manifest schema + a tiny pure-Bash/`yq`-free parser (repo already parses YAML in
      `workspace.sh` — reuse that style; no new dependency).
- [ ] Author `harness.manifest` for cecli, claudecode (mcp+solo), opencode, cursor, and the
      mitmproxy sidecar (flagged non-harness).
- [ ] Extract the hardening baseline + git-identity + monorepo-scope into one shared `docker-run`
      helper; make `defs/*/run.sh` and the consumer runner both consume it.
- [ ] Replace the hardcoded `TARGETS`/`image_name`/`target_description`/`run_target` dispatch and
      maintainer `target_dir`/`build_target` special-cases with manifest enumeration.
- [ ] Delete or wire the dead `registry/*.yaml` (fold into the manifest set or remove).
- [ ] **Wire cursor end-to-end** as the first proof the registration cost dropped to one file.
- [ ] Upgrade `defs/tests/test_harness_contracts.sh` to manifest-derived assertions.

## Acceptance criteria
- Adding a new harness = drop `defs/<name>/` + a `harness.manifest`; **no** other file edited.
- `proveo run cursor`, `mise run build cursor`, and the smoke suite all resolve cursor with no new
  hardcoding.
- The hardening baseline exists in exactly **one** place; the contract test proves no def defines
  its own copy.
- `git grep` finds no unused `registry/*.yaml`.
- Spec-first: update `_spec/components.puml` + `_spec/usage.puml` to show the manifest as the single
  registration point *before* refactoring.
