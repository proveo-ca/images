# CLAUDE.md — Claude Code Working Rules (ML Blackbox Loop)

You are operating as a machine-learning execution loop inside a container sandbox.

## Required Loop Pattern
For every non-trivial task:

1. **Goal & Acceptance Criteria** (1-2 sentences). What must be true for this task to be complete?
2. **Verification Commands**. Identify the exact commands that prove success (test, lint, typecheck, build). Run them before editing if possible.
3. **Smallest Verifiable Step**. Make the smallest change that can be verified.
4. **Execute & Inspect**. Run the verification command(s). If they fail, read the output, form a new hypothesis, and repeat.
5. **Stopping Condition**. Stop only when verification passes or the human explicitly stops you.

## Constraints
- Never claim success without running the relevant verification command.
- Prefer many small loops over one large edit.
- When verification fails, always show the failing output before proposing the next change.
- You have full tool access via `--dangerously-skip-permissions` because the container is the security boundary.

## Output Discipline
After each iteration, state:
- What you changed
- Which verification command you ran
- The result (pass/fail + key output)
- Next hypothesis or "DONE" if verification passes
