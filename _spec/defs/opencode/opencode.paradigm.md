# OpenCode Paradigm (GStack Subagent Crew)

## Intended Working Mode
OpenCode is operated as a software engineering team. A primary agent acts as team lead and delegates to specialized subagents (architect, backend, frontend, devops, adversarial-reviewer, security-reviewer, spec-keeper, sre, systems-design, monorepo-coordinator).

The human remains the HITL (human-in-the-loop) who reviews plans, approves risky commands, and merges work.

## Core Principles
- Context building and review loops are mandatory.
- Subagents collaborate and review each other.
- Built-in context rot/drift mitigation is used.
- Workflow-friendly configuration is the default.

## Entrypoint Responsibilities (`defs/opencode/entrypoint.sh`)
- Run as the invoking host user, never root (see `paradigms.md` — Runtime User Boundary): the wrapper passes `--user $(id -u):$(id -g)` and `ensure_runtime_user` makes any uid usable.
- Load `.env` and normalize model variables.
- Report git context at startup (shared `report_git_context`): git-tracked repo or not, remote origin (or "not tracking a remote repo"), commit identity, and whether a gh session is authenticated.
- Seed global config and default subagents.
- Detect workspace languages and auto-enable matching LSPs.
- Detect project config and surface available subagents.
- Install Node deps when needed.
- Smoke-test mode support.
- Seed `AGENTS.md` when missing and re-seed it when `OPENCODE_RESEED=1`.
- Discover verification commands and surface them at startup.
- Print the team workflow and review-gate summary before launch.

## Required Steering (`AGENTS.md`)
- Describe the team structure and delegation rules.
- Require the lead to invoke `architect` before non-trivial work.
- Require relevant domain subagent for implementation.
- Require `adversarial-reviewer` + `security-reviewer` (when applicable) before merge.
- Define permission boundaries for each role.
- Route tasks by domain: backend, frontend, devops, SRE, systems-design, monorepo, or spec-keeper.
- Treat `[BLOCKER]` and `[HIGH]` reviewer findings as completion blockers unless the human explicitly accepts the risk.

## Permission Posture
- `plan` agent: edit=deny, bash=deny.
- `build` agent: edit=allow, bash=ask.
- Reviewer agents: read-only, no bash.
- Primary agent never grants blanket dangerous permissions.

## Differentiation from Other Paradigms
- Strongest subagent ecosystem and orchestration.
- Explicit team workflow rather than single-loop or pair style.
- Highest flexibility and context management features.
