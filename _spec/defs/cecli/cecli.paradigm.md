# Cecli Paradigm (Pair-Programming Specialist)

## Intended Working Mode
Cecli is operated as a precise pair-programming partner for contained, well-scoped responsibilities. It is the “sniper” tool: slow to lift entire projects alone, but extremely accurate and low-token when guided to specific files, functions, or web links.

## Core Principles
- Prefer reading named files and functions over broad inference.
- Keep token consumption minimal.
- Favor small, deliberate edits.
- Use subagents sparingly for adversarial review, debugging, or spec review.
- Human provides exact references; the agent does not autonomously explore the whole repo.

## Entrypoint Responsibilities (`defs/cecli/entrypoint.sh`)
- Run as the invoking host user, never root: the wrapper launches with `--user $(id -u):$(id -g)` and the shared `ensure_runtime_user` helper (entrypoint-lib) gives any uid a usable identity and writable `HOME`. No gosu, no privilege drop.
- Load `.env` and bridge model variables.
- Bridge env-provided git identity: cecli resolves commit identity via `git config --get user.name/email` and seeds placeholder identity into the workspace `.git/config` when unresolvable. The wrapper auto-forwards the developer's identity as `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env (explicit env wins over host `git config`; see `paradigms.md` — Git Identity & Context) and the shared `bridge_git_identity` helper exposes it through git's config-env (`GIT_CONFIG_*`) — file-free, and repo-local identity stays authoritative.
- Report git context at startup (shared `report_git_context`): git-tracked repo or not, remote origin (or "not tracking a remote repo"), commit identity, and whether a gh session is authenticated.
- Seed default subagents.
- Configure agent paths and `CECLI_AGENT_CONFIG`.
- Read `CONVENTIONS.md` on startup.
- Keep Node installs opt-in.
- Smoke-test mode support.
- Surface verification commands as advisory only.
- Keep subagent usage capped and specialist-only.

## Required Steering (`CONVENTIONS.md`)
- Instruct the agent to ask for specific files/functions when scope is unclear.
- Require the agent to confirm the exact change location before editing.
- Limit subagent usage to narrow specialist roles.
- Enforce low-token, high-precision behavior.
- Avoid broad repo exploration unless explicitly requested or required by missing references.
- Avoid opportunistic refactors outside the requested responsibility.

## Permission Posture
- Follows the underlying Aider model with conservative defaults.
- `auto-commits` are allowed; `/undo` is the intended recovery path.
- No blanket dangerous permissions.

## Differentiation from Other Paradigms
- Lowest token usage and most manual control.
- Strongest emphasis on human-provided references.
- Not intended for autonomous repo-wide work or large ML-style loops.
- Subagents exist but are secondary to the pair-programming flow.
