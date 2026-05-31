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
bin/
  proveo                        # Transitional maintainer wrapper; delegates toward defs/* commands

apps/
  cli/                          # Cloudflare-hosted consumer CLI installer/assets

defs/
  aider-node/                   # Aider runner with Node/pnpm/playwright support
  cecli/                        # Cecli runner, with Python and Node image variants
  charles-proxy/                # Charles Proxy headless container definition
  claudecode/                  # Claude Code solo and MCP-enabled harnesses
  opencode/                    # opencode runner with baked-in agents/defaults

_spec/                         # PlantUML architecture/spec diagrams only (*.puml)
packages/                       # Reserved for future shared libraries/utilities
skills/                         # Planned: portable agent skills/prompts for other harnesses
```

## Harness Definitions

`defs/` contains the image and runtime definitions. These are closer to packages than deployed applications: each definition is a buildable, runnable tool environment.

Current definitions:

| Definition | Purpose |
| --- | --- |
| `defs/aider-node` | Aider container with Node 22, pnpm, Playwright, `.env` loading, and model env bridging. |
| `defs/cecli` | Cecli container variants for Python-only and Node-backed workflows. |
| `defs/opencode` | opencode container with non-root runtime, default agents, HITL-oriented permissions, and tests. |
| `defs/claudecode` | Claude Code containers for solo and MCP-enabled execution with explicit workspace mounts. |
| `defs/charles-proxy` | Headless Charles Proxy container definition. |

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
# Definition-local commands are preferred
./defs/aider-node/build.sh --tag latest
./defs/aider-node/run.sh
./defs/cecli/run.sh
./defs/opencode/test.sh
./defs/claudecode/run.sh --variant solo
./defs/charles-proxy/run.sh

# Transitional maintainer compatibility wrapper
bin/proveo list
bin/proveo build aider-node --tag latest
bin/proveo test claudecode
bin/proveo run charles-proxy --tag latest
```

The distributed `proveo` command under `apps/cli/public/cli/bin/proveo` is the consumer base CLI. Root `bin/proveo` is the internal maintainer extension with extra powers such as build, test, debug, and deploy. Maintainer behavior may extend or override the consumer surface, but consumer install/uninstall should only manage the distributed `~/.proveo` install.

New deterministic harness behavior should live under `defs/<name>/` first, with `bin/proveo` delegating where useful.

The public consumer install URL is:

```bash
curl -fsSL https://proveo.ca/cli/install.sh | bash
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
4. the agent/tool permission model inside the container.

Do not treat a permissive agent running in a container as inherently safe. Mount only the directories the agent should see, prefer read-only input mounts where possible, and review each harness's `run.sh` before use.

## Roadmap Direction

Near-term documentation and structure goals:

- keep `defs/` as the source of harness definitions unless/until a package migration is justified
- standardize the per-definition contract for build/run/debug/test files
- consolidate duplicated Bash behavior into shared utilities
- clarify the relationship between repo-local `bin/proveo` and the consumer `proveo` CLI
- add `skills/` as portable, reusable agent instructions consumed by multiple harnesses
- use `packages/` for shared CLI/library code when duplication becomes costly

This is currently optimized for personal and maintainer workflows. To become production-grade team tooling, it still needs stricter version pinning, clearer compatibility contracts, CI image validation, shared shell utilities, and release/versioning policy.

## Conventions

See [`CONVENTIONS.md`](CONVENTIONS.md) for the current agent collaboration conventions.

Definition-specific conventions and examples live with each harness, for example:

- [`defs/aider-node/README.md`](defs/aider-node/README.md)
- [`defs/cecli/sample.cecli.conf.yml`](defs/cecli/sample.cecli.conf.yml)
- [`defs/opencode/README.md`](defs/opencode/README.md)
- [`defs/claudecode/README.md`](defs/claudecode/README.md)
