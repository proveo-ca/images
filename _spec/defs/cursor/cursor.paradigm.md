# Cursor CLI Paradigm (Policy-Gated Autonomous Loop)

## Intended Working Mode
Cursor CLI (`agent`, legacy alias `cursor-agent`) operates in the same blackbox family as Claude Code:
spec → plan → implement → verify → repeat until the goal is achieved.

The harness launches with `agent --force` (the product's documented autonomous posture, alias
`--yolo`) — but unlike Claude Code, part of the safety boundary moves *inside* the process.
Cursor's native policy machinery keeps enforcing under `--force`:

- **Deny rules win over `--force`.** `permissions.deny` entries in `cli-config.json` are hard
  guardrails that full consent cannot override.
- **Hooks** (`hooks.json`) run allow/deny/ask scripts on tool events with
  enterprise > team > project > user precedence. The harness owns the enterprise layer
  (`/etc/cursor/hooks.json`, root-owned, immutable to the agent) and uses it for shell auditing.
- **Subagents** (`.cursor/agents/*.md`, `~/.cursor/agents/*.md`) carry a native `readonly` flag,
  making review gates structurally read-only instead of prompt-enforced.

This is the "as far as the paradigm can reach" position for Cursor: full blackbox autonomy,
with the native permission/hook layer as in-process defense-in-depth on top of the container
and network egress boundaries.

## Core Principles
- Small, verifiable loops over open-ended tasks; acceptance criteria and verification commands
  are stated before editing (same loop discipline as the Claude Code paradigm).
- Human provides the goal and stopping condition; the agent loops autonomously.
- Enforcement is layered: deny rules and hooks in-process, the container sandbox around the
  process, the egress layer around the container. No single layer is trusted alone.
- The harness never trusts prompt-level compliance where a structural control exists
  (`readonly` subagents, `permissions.deny`, root-owned hooks).
- Cursor's own OS sandbox (Landlock/seccomp) is disabled inside the container — Docker is the
  sandbox; stacking kernel LSM sandboxes inside a cap-dropped container is nondeterministic.

## Entrypoint Responsibilities (`defs/cursor/entrypoint.sh`)
- Run as the invoking host user, never root (see `paradigms.md` — Runtime User Boundary): the
  wrapper passes `--user $(id -u):$(id -g)` and `ensure_runtime_user` makes any uid usable.
- Load `.env`.
- Bridge env-provided git identity (`bridge_git_identity`) and report git context at startup
  (`report_git_context`): repo or not, remote origin, commit identity, gh session.
- Seed user-level Cursor config into `${CURSOR_CONFIG_DIR:-$HOME/.cursor}` from baked defaults
  (`/opt/cursor/defaults/`): `cli-config.json` (deny baseline) and `agents/*.md` (readonly
  reviewers). Missing-only; `CURSOR_RESEED=1` forces a refresh.
- Never mutate the mounted workspace on first run. Project steering (`.cursor/rules/*.mdc`,
  `AGENTS.md`, `CLAUDE.md`, `.cursorrules`) is *detected and reported*, not written. Seeding the
  baked loop rule into `.cursor/rules/` is opt-in via `CURSOR_SEED_RULES=1`.
- Detect a proxied environment (`HTTP_PROXY`/`HTTPS_PROXY`) and set `useHttp1ForAgent` in the
  seeded config — Cursor's HTTP/2 streaming does not survive every proxy chain; the CLI honors
  `NODE_EXTRA_CA_CERTS` for the mitmproxy CA.
- Surface detected verification commands (shared `detect_verify_commands`).
- Smoke-test mode support (`run_smoke_test`).
- Warn when `CURSOR_API_KEY` is absent (headless auth) and point at `agent login` for
  interactive auth.
- Launch `agent --force --sandbox disabled`, appending `--trust` for headless (`-p/--print`)
  invocations and `--model "$CURSOR_MODEL"` when set. Utility subcommands
  (`login`, `status`, `ls`, `mcp`, …) pass through without the autonomy flags.

## Required Steering (`.cursor/rules/*.mdc` / `AGENTS.md`)
Cursor reads project rules from `.cursor/rules/*.mdc` (MDC frontmatter: `description`, `globs`,
`alwaysApply`) and applies root `AGENTS.md` / `CLAUDE.md` as rules alongside them. The baked
default rule (`/opt/cursor/defaults/rules/proveo-loop.mdc`, `alwaysApply: true`) encodes:

- State acceptance criteria before starting.
- Identify verification commands before editing.
- Make the smallest verifiable change; run verification; inspect failures and adjust.
- Stop only when verification passes or the human intervenes.
- Use the readonly reviewer subagents as gates before declaring completion.

Existing project steering always wins — the harness only reports what it found.

## Permission Posture
`--force` is intentional, with three qualifications that distinguish it from Claude Code's
`--dangerously-skip-permissions`:

1. **`permissions.deny` still applies.** The seeded `cli-config.json` denies privilege
   escalation (`sudo`, `su`), host-power commands, raw exfil helpers (`nc`, `netcat`), and
   credential material reads (`.ssh`, `.env*`). Projects may extend via `.cursor/cli.json`.
2. **The enterprise hook layer is harness-owned.** `/etc/cursor/hooks.json` (root-owned; the
   run-as uid cannot edit it) audits every `beforeShellExecution` event to NDJSON. It is an
   audit hook — fail-open by design; *enforcement* belongs to the deny list and egress layer.
3. **Reviewer subagents are `readonly: true`** — a structural bit, not a prompt convention.

### Outbound Web Access Policy
Same protocol posture as the Claude Code paradigm: HTTP/HTTPS only through the configured
egress chain (`broker|proxy|firewall`); non-web protocols denied by Docker network
topology; read-oriented web access stays open.

One material difference: **all Cursor inference transits Cursor's backend** (`api5.cursor.sh`
for agent traffic, `api2.cursor.sh` for API/auth). There is no custom base-URL or local-model
escape hatch — BYOK requests are still proxied through Cursor's servers. Consequences:

- Provider pinning maps `CURSOR_API_KEY` → the `.cursor.sh` / `.cursor.com` domains in the
  shared egress lib; inference writes are pinned there while web reads stay open.
- `--local-model` (the Ollama sidecar) does not apply to this harness. A locked network that
  cannot reach the Cursor backend means no inference, full stop.

## Differentiation from Other Paradigms
- Same autonomous-loop shape as Claude Code, but the permission boundary is layered rather than
  fully externalized: native deny rules + immutable audit hooks survive full consent.
- Subagents exist (auto-delegation, `readonly`, background) but serve as in-loop review gates,
  not an orchestrated team — no opencode-style crew workflow.
- No pair-programming containment; not optimized for low-token precision work.
- Unique constraint: vendor-pinned inference (no local model), so the egress story pins the
  Cursor backend instead of a model provider chosen by API key.
