# Proveo Project Cleanup & Improvement Plan

**Goal**: Make the repository understandable as a collection of deterministic AI-coding harness definitions, while keeping the current personal-use workflow intact.

**Core Philosophy**: Document first, standardize second, refactor only when duplication becomes costly. The project should stay practical for one maintainer while moving toward team-usable tooling.

## How to Use This Plan

Use `ROADMAP.md` for strategy and sequencing. Use this file as the working execution checklist for the next cleanup passes.

Each phase should end with:

- updated docs for any behavior that changed
- a small `git diff` review
- a smoke check where scripts were touched
- a clear note of anything intentionally deferred

## Phase 1: Lock the Documentation Baseline

Status: mostly complete; keep it current as implementation changes.

Steps:

1. Keep the root `README.md` focused on repository purpose, layout, command surfaces, and safety model.
2. Keep `ROADMAP.md` focused on long-running direction and maturity criteria.
3. Keep this `PLAN.md` focused on next actions only.
4. Keep `_spec/components.puml` aligned with actual ownership boundaries:
   - consumer surface: `apps/cli/public/cli/install.sh`, with install assets under `apps/cli/public/cli/`
   - maintainer wrapper: `bin/proveo`
   - image definitions: `defs/`
   - future shared code: `packages/`

Acceptance checks:

- a new reader can tell where to build, run, and test a definition
- `PLAN.md` does not duplicate `ROADMAP.md` section-by-section
- component map labels match current terminology

## Phase 2: Apply the Definition Contract Under `defs/`

Status: in progress.

Steps:

1. Maintain `defs/README.md` as the canonical contract summary.
2. For each coding harness definition, keep its README explicit about:
   - contract status: candidate, experimental, or non-harness
   - image names and tags
   - mounts
   - environment variables
   - build/run/test/debug commands
3. Keep current classifications accurate:
   - candidate coding harnesses: `defs/cecli`, `defs/opencode`, `defs/claudecode`
   - experimental coding harness: `defs/aider-node`
   - non-harness image definition: `defs/charles-proxy`
4. Do not call any definition mature until its docs, scripts, tests, and expected runtime behavior have been validated together.

Acceptance checks:

- each candidate or experimental coding harness has a README contract section
- documented commands call definition-local scripts instead of raw Docker invocations where practical
- non-harness definitions are allowed without forcing the coding harness contract onto them

## Phase 3: Make Definition-Local Scripts the Source of Truth

Status: next implementation pass.

Steps:

1. Audit `bin/proveo` for harness-specific Docker behavior.
2. For each behavior found, decide whether it belongs in:
   - `defs/<name>/build.sh`
   - `defs/<name>/run.sh`
   - `defs/<name>/test.sh`
   - `defs/<name>/debug.sh`
3. Move behavior into the definition-local script first.
4. Change `bin/proveo` to delegate instead of duplicating the Docker invocation.
5. Keep compatibility output and flags stable where possible.

Acceptance checks:

- `./defs/<name>/build.sh`, `run.sh`, and `test.sh` work without `bin/proveo`
- `bin/proveo` is a thin maintainer wrapper
- command examples in definition READMEs match the scripts

## Phase 4: Clarify Maintainer vs Consumer CLI

Status: pending after Phase 3.

Steps:

1. Document the intended user for each surface:
    - `proveo`: consumer/distribution lifecycle
    - `bin/proveo`: maintainer/development compatibility wrapper
2. Keep the distributable `proveo` surface intentionally small:
   - `help`
   - `list`
   - `run`
   - `uninstall.sh`
3. Decide whether repo-local `bin/proveo` remains separate, becomes an internal consumer `proveo` mode, or is removed after delegation is complete.
4. Avoid adding new harness-specific behavior to `proveo` until the split is settled.

Acceptance checks:

- consumer docs use `https://proveo.ca/cli/install.sh` and do not require knowing `bin/proveo`
- maintainer docs can use definition-local scripts directly
- uninstall behavior is represented in docs/spec before distribution work expands

## Phase 5: Extract Shared Utilities Only After Repetition Hurts

Status: deferred until script behavior stabilizes.

Steps:

1. Track duplication across entrypoints and run scripts.
2. Extract only when at least two definitions need the same behavior changed.
3. Prefer small Bash utilities first for:
   - logging
   - `.env` loading
   - Docker argument assembly
   - workspace/mount validation
   - model environment variable bridging
   - Node dependency installation helpers
4. Move code to `packages/` only when there is a real package boundary.

Acceptance checks:

- extracted utilities remove duplicated maintenance work
- definition-specific behavior remains visible in each definition
- `packages/` does not become a dumping ground

## Phase 6: Prepare for Maturity Validation

Status: future readiness work.

Steps:

1. Define smoke-test expectations for each candidate coding harness.
2. Add or normalize CI coverage for image builds and basic command checks.
3. Pin mutable dependency versions where reproducibility matters.
4. Define image tag and release rules.
5. Document compatibility expectations per mature harness before calling any definition mature.
6. Consider provenance, SBOMs, and signing only after release flow is stable.

Acceptance checks:

- candidate harnesses have repeatable build/test checks
- release tags are intentional and documented
- maturity is based on validation, not repository age or usefulness

## Current Next Actions

1. Review the current `defs/` README changes for accuracy against scripts.
2. Move any remaining raw Docker examples in definition READMEs behind definition-local scripts where practical.
3. Audit `bin/proveo` for behavior that should delegate to `defs/<name>/*.sh`.
4. Update `_spec/components.puml` only when ownership boundaries change.
5. Keep `ROADMAP.md` strategic; keep this plan executable.
