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
- Run as non-root when started as root.
- Load `.env` and bridge model variables.
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
