# Coding Harness Paradigms

This directory defines the intended working mode for each harness so that entrypoints, configs, and steering files can be optimized consistently.

## The Four Paradigms

| Harness     | Analogy              | Core Idea                                      | Key Files                     | Permission Posture                     |
|-------------|----------------------|------------------------------------------------|-------------------------------|----------------------------------------|
| Claude Code | ML blackbox algorithm | Spec → plan → implement → verify → loop        | `CLAUDE.md`, entrypoint.sh    | `--dangerously-skip-permissions` (intentional) |
| Cursor CLI  | Policy-gated blackbox | Same autonomous loop, bounded by native deny rules + hooks | `.cursor/rules/*.mdc`, `cli-config.json`, `hooks.json` | `--force` (deny rules and enterprise hooks still win) |
| OpenCode    | GStack subagent crew  | Software engineering team with HITL oversight  | `AGENTS.md`, subagents, config | Role-based; reviewers read-only        |
| Cecli       | Pair-programming sniper | Precise, low-token, human-guided edits       | `CONVENTIONS.md`, config      | Conservative; no blanket dangerous     |

## Files in This Directory

- `claudecode.paradigm.md` — ML loop harness with explicit dangerous permissions.
- `cursor.paradigm.md` — ML loop harness whose safety boundary is layered: in-process deny rules and root-owned audit hooks survive `--force`.
- `opencode.paradigm.md` — Team workflow with subagent orchestration.
- `cecli.paradigm.md` — Pair-programming specialist with containment focus.

## Runtime User Boundary

Every harness container runs as the invoking host user, never root:

- **Wrappers** (`defs/*/run.sh`, the distributable CLI runners) launch with `docker run --user $(id -u):$(id -g)`, so files written to bind mounts come back owned by the developer — for any host uid, not just the image's baked default.
- **Images** bake a non-root default user (uid 1000) and set `USER`, so even a bare `docker run` without the wrapper is never root.
- **Entrypoints** call the shared `ensure_runtime_user` helper (`packages/lib/entrypoint-lib.sh`) first: it gives an arbitrary run-as uid a passwd identity and a writable `HOME` without root. There is no gosu and no in-container privilege drop; this is one generic helper, identical across harnesses.

## Git Identity & Context

Every harness image bakes `git` and `gh`. Containers ship no `~/.gitconfig` and never mount the host's, so commit identity flows through the environment:

- **Wrappers** forward the invoking developer's identity as `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env — explicit env wins, otherwise the host's `git config` identity — via the shared `defs/lib/git-identity.sh` helper (mirrored inside the distributable CLI's `runners.sh`, which cannot source the defs tree).
- **Entrypoints** bridge those env values into git's config-env (`bridge_git_identity` in `packages/lib/entrypoint-lib.sh`) so `git config --get` resolves file-free; repo-local identity stays authoritative. This keeps tools like cecli from seeding placeholder identity into the mounted repo's `.git/config`.
- **Entrypoints report** the git context at startup (`report_git_context`): git-tracked repo or not, remote origin (or "not tracking a remote repo"), commit identity, and whether a gh session is authenticated.

## Network Egress Boundary

The dangerous in-container posture (especially Claude Code's `--dangerously-skip-permissions`) is made acceptable by a network egress layer, not just the container. It is a reusable lifecycle (`defs/lib/egress.sh`, wired into `claudecode` run/debug today) with three modes:

- **open** — direct bridge egress (default).
- **proxy** — agent → Squid enforcement proxy; HTTP/HTTPS only, non-web protocols blocked by Docker network topology.
- **inspected-firewall** — agent → mitmproxy (TLS-decrypting recorder) → Squid → internet, with the agent trusting mitmproxy's CA.

It serves two purposes:

1. **No irreversible action without HITL** — write methods (and pushes/publishes) are denied except to the model provider; attempts are logged.
2. **No leaks when using cloud LLM providers** — inference egress is pinned to an allowlisted provider, auto-detected from the API key present, while web reads (docs/search/scraping) stay open so agents can still gather context.

A local model can be assigned with `--local-model` (an Ollama sidecar serving host models offline, `NO_PROXY`-bypassed). Each run writes a top-allowed/top-denied egress report. See `claudecode.paradigm.md` and `defs/claudecode/claudecode-egress-topology.puml` for the full topology.

Cursor CLI is the exception on local models: all of its inference transits the Cursor backend (no custom base-URL escape hatch), so `--local-model` does not apply and the provider pin maps `CURSOR_API_KEY` to the `.cursor.sh`/`.cursor.com` domains instead (see `defs/cursor/cursor.paradigm.md`).

## Usage

Entrypoints and default configs should reference these documents when seeding steering files or deciding defaults. Changes to any harness must preserve the paradigm described here.
