# Proveo Harness Definitions

This repository collects deterministic Docker-based coding and debugging harnesses for AI-assisted engineering workflows.

The project is intentionally centered on repeatable command surfaces rather than one-off local setup. Each harness definition captures:

- a Docker image definition (`Dockerfile` and supporting files)
- an entrypoint contract (`entrypoint.sh`) for environment loading, model defaults, and tool setup
- deterministic run/debug/build commands where available
- sample configuration for the underlying tool
- tests for image build, runtime tools, security posture, and selected live integrations where practical

The current repo is still personal-tooling oriented, but the direction is toward a small monorepo of reusable harness definitions, shared command utilities, and eventually portable agent skills.

## Repository Layout

```txt
cmd/proveo # Host orchestrator (Go): list / run / projects / setup
cmd/proveo-egress # MITM + credential broker
internal/ # runner, workspace mounts, egress plan, dind, manifests
dist/install.sh # Checksum-verified binary install (product path)

apps/cli/ # Optional CDN / transitional bash list+help surface

defs/
 */harness.manifest # Registration (embedded in proveo)
 */run.sh # Thin shims → proveo run <target>
 cecli/ · claudecode/ · opencode/ · cursor/
 sidecars/ # squid config, egress-proxy, mitmproxy (legacy), dind

_spec/ # Architecture specs (*.puml + paradigms/testing)
```

## Harness Definitions

`defs/` contains the image and runtime definitions. These are closer to packages than deployed applications: each definition is a buildable, runnable tool environment.

Current definitions:

| Definition | Purpose |
| --- | --- |
| `defs/cecli` | Cecli container variants for Python-only and Node-backed workflows. |
| `defs/opencode` | opencode container with non-root runtime, default agents, HITL-oriented permissions, and tests. |
| `defs/claudecode` | Claude Code containers for solo and MCP-enabled execution with explicit workspace mounts. |
| `defs/sidecars/mitmproxy` | Headless mitmproxy egress inspector (HTTPS interception, Squid upstream). |

Each mature definition should eventually expose a consistent contract:

```txt
defs/<name>/
 Dockerfile or Dockerfile.*
 entrypoint.sh
 build.sh
 run.sh
 test.sh
 debug.sh, optional
 help.sh, optional
 README.md
 sample config files
 tests/, if applicable
```

## Deterministic Commands

The preferred interaction model is to use committed commands rather than retyping long Docker invocations.

Examples:

```bash
# Preferred: Go CLI (install via dist/install.sh / goreleaser)
proveo list
proveo run opencode
proveo run cursor --egress-mode firewall
proveo run claudecode --local-model gemma4 --print

# Definition-local run.sh shims exec proveo run
./defs/opencode/run.sh
./defs/claudecode/run.sh --variant solo

# Maintainer build / test / deploy via mise
mise run test
mise run test-defs claudecode
mise run deploy claudecode --tag latest
```

The smoke suite generates and mounts a temporary `.env` with dummy non-secret
model/API values to keep CLIs from falling into authentication prompts before the
smoke-ready log is emitted.

The distributed `proveo` command under `apps/cli/public/cli/bin/proveo` is the consumer base CLI. Maintainer workflows with extra powers (build, test, debug, deploy) run via `mise` tasks that source the reusable `lib/*.sh` helpers. Maintainer behavior may extend or override the consumer surface, but consumer install/uninstall should only manage the distributed `~/.proveo` install.

New deterministic harness behavior should live under `defs/<name>/` first, with the `mise` tasks and `lib/*.sh` helpers delegating where useful.

The public consumer install URL is:

```bash
curl -fsSL https://proveo.ca/cli/install.sh | bash
```

Initialize a project `.env` from provider API keys already present in your host
environment with:

```bash
proveo init
```

For now, `apps/cli` is effectively the CLI distribution slice of `proveo/images`. The full install flow is served from `/cli`, which keeps the URL ready for a future standalone CLI without pretending that the CLI is already a separate package.

## Common Environment Variables

Several harnesses support a shared model-variable convention and translate it to the tool-specific names:

| Standard variable | Typical target |
| --- | --- |
| `ARCHITECT_MODEL` | Main/planning model (`AIDER_MODEL`, `CECLI_MODEL`, etc.) |
| `EDITOR_MODEL` | Editing model (`AIDER_EDITOR_MODEL`, `CECLI_EDITOR_MODEL`, etc.) |
| `SMALL_MODEL` | Weak/fast model (`AIDER_WEAK_MODEL`, `CECLI_WEAK_MODEL`, etc.) |
| `DARK_MODE=true` | Enables dark UI where supported |
| `CODE_THEME` | Code theme where supported |

Provider API keys are usually loaded from the host environment or from a project `.env` file when the harness entrypoint supports it. Common keys include:

- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `GEMINI_API_KEY` / `GOOGLE_API_KEY`
- `XAI_API_KEY`
- `DEEPSEEK_API_KEY`
- `OPENROUTER_API_KEY`
- `GROQ_API_KEY`

See each definition's README and sample config for tool-specific behavior.

## Security Model

These containers are intended to reduce host-environment coupling and make agent execution more explicit. Some harnesses intentionally enable permissive or "dangerous" tool modes inside the container for automation.

The practical safety boundary is therefore:

1. the Docker runtime configuration,
2. the mounted directories and their read/write mode,
3. the container user and Linux capabilities,
4. the agent/tool permission model inside the container,
5. the egress layer (`--egress-mode firewall`) and credential broker when provider keys are in play.

Do not treat a permissive agent running in a container as inherently safe. Mount only the directories the agent should see, prefer read-only input mounts where possible, and review each harness's `run.sh` before use.

### `.env` and provider secrets (do not mount)

**Security requirement:** a project `.env` that holds provider API keys must **not** be bind-mounted into the agent container when you want credential isolation. An autonomous agent with workspace access can read any mounted file; tool deny rules (for example Cursor's `Read(.env*)`) do not protect secrets that the entrypoint has already sourced into the process environment.

Preferred pattern:

- export provider keys in the **host** shell (or pass them with `docker run -e VAR`, never on argv);
- run with **`--egress-mode firewall`** so the credential broker holds the real secret in a `0600` file **outside** every agent mount and injects it only on the pinned provider host;
- keep `.env` on the host for local tooling (`proveo init`, editors, etc.) but treat it as **out of scope** for the container mount set.

**Current pragmatic behavior (not isolation):** when the whole repo is bind-mounted at `/app`, `.env` at the repo root is visible inside the container unless you exclude it. Wrappers may also overlay a **symlink-resolved** `.env` at `/app/.env` so entrypoint autoload works when the project symlink points outside the mount — that overlay is a **functional** convenience, not a security control. `proveo run` warns when a mounted `.env` and a detected provider key coincide.

### Credential isolation by egress mode

| Mode | Bare-minimum credential mounts (target) | Achievable today? | Notes |
| --- | --- | --- | --- |
| **firewall** | Real secrets only in `broker.env` on the egress sidecar (`proveo-egress`); agent gets no secret file and no real secret env | **Yes** | `.env` masked; `load_env` skipped; secret env sent as sentinel; host `.env` → `broker.env` |
| **proxy** | Same broker-style isolation | **No** (without topology change) | Squid sees `CONNECT host:443` only; it cannot decrypt TLS or inject auth headers. Agent must hold credentials in-process for HTTPS APIs |
| **broker** | Same broker-style isolation | **No** (by design) | Direct bridge; container boundary only. Dev-oriented path with in-process secret exposure. You can still avoid mounting `.env` as a file |

**Firewall mode — what works today**

- `broker.env` (`0600`) is written under the host egress state dir and mounted into `proveo-egress` at `/broker:ro` only — never into the agent.
- Bash wrappers (`defs/cursor/run.sh`, `defs/claudecode/run.sh`) withhold raw provider secrets from the agent in `proxy`/`firewall` (they pass `CURSOR_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN` only in `broker`).
- The broker injects auth on the pinned provider host and strips credential headers off-provider.

**Firewall mode — known gaps (incremental; partially closed)**

1. ~~**`.env` bind-mounted into the agent**~~ — **closed:** wrappers and `MountSpec` mask `/app/.env` with `/dev/null` in `proxy`/`firewall`; broker mode still overlays a resolved file.
2. ~~**Entrypoint always sources `.env`**~~ — **closed:** `load_env` skips when `PROVEO_EGRESS_MODE` is `proxy` or `firewall`.
3. ~~**Go CLI forwards secrets in all modes**~~ — **closed:** manifest `secret: true` vars are forwarded as `-e` only in `broker`.
4. ~~**Broker reads host env only**~~ — **closed:** host-side project `.env` / `PROVEO_EGRESS_ENV_FILE` feeds `broker.env` without mounting into the agent.
5. ~~**Sentinel replacement**~~ — **closed:** firewall mode injects sentinel values + `PROVEO_CREDENTIAL_BROKER_KEYS`; `proveo-entrypoint` / `apply_broker_sentinel` rewrite residuals.

**Proxy and broker modes**

- **Proxy** can limit destinations (Squid ACL) but cannot confine secrets to a sidecar without adding TLS inspection (i.e. making proxy ≈ firewall). Stopping `.env` file mounts is possible; the agent still needs credentials in-process.
- **Broker** has no interception point. Minimize exposure by not bind-mounting `.env` and using host `export` / `docker run -e`; treat as development-only.

## Roadmap Direction

Near-term documentation and structure goals:

- keep `defs/` as the source of harness definitions unless/until a package migration is justified
- standardize the per-definition contract for build/run/debug/test files
- consolidate duplicated Bash behavior into shared utilities
- keep the maintainer surface (`mise` tasks + `lib/*.sh` helpers) and the consumer `proveo` CLI cleanly separated
- add `skills/` as portable, reusable agent instructions consumed by multiple harnesses
- use `packages/` for shared CLI/library code when duplication becomes costly

This is currently optimized for personal and maintainer workflows. To become production-grade team tooling, it still needs stricter version pinning, clearer compatibility contracts, CI image validation, shared shell utilities, and release/versioning policy.

## Conventions

See [`CONVENTIONS.md`](CONVENTIONS.md) for the current agent collaboration conventions.

Definition-specific conventions and examples live with each harness, for example:

- [`defs/cecli/sample.cecli.conf.yml`](defs/cecli/sample.cecli.conf.yml)
- [`defs/opencode/README.md`](defs/opencode/README.md)
- [`defs/claudecode/README.md`](defs/claudecode/README.md)
