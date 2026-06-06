# Coding Harness Paradigms

This directory defines the intended working mode for each harness so that entrypoints, configs, and steering files can be optimized consistently.

## The Three Paradigms

| Harness     | Analogy              | Core Idea                                      | Key Files                     | Permission Posture                     |
|-------------|----------------------|------------------------------------------------|-------------------------------|----------------------------------------|
| Claude Code | ML blackbox algorithm | Spec → plan → implement → verify → loop        | `CLAUDE.md`, entrypoint.sh    | `--dangerously-skip-permissions` (intentional) |
| OpenCode    | GStack subagent crew  | Software engineering team with HITL oversight  | `AGENTS.md`, subagents, config | Role-based; reviewers read-only        |
| Cecli       | Pair-programming sniper | Precise, low-token, human-guided edits       | `CONVENTIONS.md`, config      | Conservative; no blanket dangerous     |

## Files in This Directory

- `claudecode.paradigm.md` — ML loop harness with explicit dangerous permissions.
- `opencode.paradigm.md` — Team workflow with subagent orchestration.
- `cecli.paradigm.md` — Pair-programming specialist with containment focus.

## Network Egress Boundary

The dangerous in-container posture (especially Claude Code's `--dangerously-skip-permissions`) is made acceptable by a network egress layer, not just the container. It is a reusable lifecycle (`defs/lib/egress.sh`, wired into `claudecode` run/debug today) with three modes:

- **open** — direct bridge egress (default).
- **proxy** — agent → Squid enforcement proxy; HTTP/HTTPS only, non-web protocols blocked by Docker network topology.
- **inspected-firewall** — agent → mitmproxy (TLS-decrypting recorder) → Squid → internet, with the agent trusting mitmproxy's CA.

It serves two purposes:

1. **No irreversible action without HITL** — write methods (and pushes/publishes) are denied except to the model provider; attempts are logged.
2. **No leaks when using cloud LLM providers** — inference egress is pinned to an allowlisted provider, auto-detected from the API key present, while web reads (docs/search/scraping) stay open so agents can still gather context.

A local model can be assigned with `--local-model` (an Ollama sidecar serving host models offline, `NO_PROXY`-bypassed). Each run writes a top-allowed/top-denied egress report. See `claudecode.paradigm.md` and `defs/claudecode/claudecode-egress-topology.puml` for the full topology.

## Usage

Entrypoints and default configs should reference these documents when seeding steering files or deciding defaults. Changes to any harness must preserve the paradigm described here.
