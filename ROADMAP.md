# Proveo AI Coding Agent Roadmap

## Overview

This roadmap tracks Proveo's evolution from a personal collection of containerized AI coding tools into a coherent harness-definition monorepo.

The repository currently contains multiple Docker-based harness definitions under `defs/`, a maintainer command surface in `bin/probe`, consumer CLI assets under `apps/cli/`, and planned space for shared packages and portable agent skills. The near-term goal is documentation clarity and consistent contracts before deeper refactors.

---

## 1. Documentation and Project Framing ✅

### Goal

Make the project understandable at first glance as a set of deterministic AI-coding harness definitions, not as a single Cecli wrapper.

### Current Status

- Root README now describes the broader repository purpose, layout, command model, environment variable conventions, and security model.
- `PLAN.md` captures the immediate documentation-first cleanup direction.
- This roadmap has been realigned with the current repository shape.

### Next Steps

1. Keep definition-specific details in each harness README.
2. Keep root docs focused on architecture, command surfaces, safety model, and roadmap.
3. Add install/distribution details only after the `probe`/`proveo` relationship is settled.

---

## 2. Harness Definition Contract ✅

### Goal

Standardize what it means for a folder under `defs/` to become a mature coding harness definition while still allowing non-harness image definitions.

### Target Contract

Each mature coding harness definition should expose, where applicable:

```txt
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

Non-harness image definitions may live under `defs/`, but they are not required to satisfy the coding harness contract.

### Current Classification

No current definition is considered mature yet; the project is new and these are target classifications.

- candidate coding harnesses: `defs/cecli`, `defs/opencode`, `defs/claudecode`
- useful but smaller/experimental coding harness: `defs/aider-node`
- non-harness image definition: `defs/charles-proxy`

### Remaining Follow-up

1. Keep definition READMEs current as image names, mounts, env vars, and run/test commands change.
2. Avoid moving `defs/` into `packages/` until the package boundary is justified.
3. Keep definition-local `build.sh`/`run.sh`/`test.sh` as the preferred contract; add `debug.sh` where it is useful, not mandatory.

---

## 3. Deterministic Command Surface

### Goal

Provide predictable commands that agents and humans can choose instead of reconstructing Docker invocations.

### Current Split

- `defs/<name>/*.sh`: preferred deterministic command surface for harness-specific build/run/debug/test behavior.
- `bin/probe`: transitional maintainer-facing wrapper for local build/test/run/debug/deploy workflows; it should delegate to `defs/` instead of owning harness-specific Docker behavior.
- `apps/cli/public/images/bin/proveo`: consumer-facing CLI asset for installed usage.

### Roadmap

1. Continue moving harness-specific Docker invocations from `bin/probe` into definition-local scripts.
2. Define the intended command matrix:

```bash
./defs/<definition>/build.sh
./defs/<definition>/run.sh
./defs/<definition>/debug.sh, optional
./defs/<definition>/test.sh

# Transitional maintainer wrapper, where useful
probe list
probe build <definition> --tag <tag>
probe test <definition>
probe run <definition> --tag <tag>
probe debug <definition> --tag <tag>
```

3. Decide whether `probe` remains separate, becomes `proveo --maintainer`, or is deleted once definition-local commands cover the maintainer workflow.
4. Keep Bash until the command contract stabilizes; reconsider Go/Node only when distribution needs justify it.
5. Ensure every definition-local command has deterministic image tags, mounts, and environment behavior.

---

## 4. Shared Utilities

### Goal

Reduce duplicated entrypoint/run-script behavior without prematurely abstracting the harnesses.

### Candidate Shared Modules

- `.env` loading
- model environment variable bridge (`ARCHITECT_MODEL`, `EDITOR_MODEL`, `SMALL_MODEL`, etc.)
- logging and version banners
- Docker argument assembly
- workspace/mount validation
- Node dependency installation helpers

### Rollout Strategy

1. Keep current scripts as-is until at least two or three definitions need the same behavior changed.
2. Extract a small Bash utility library when duplication becomes a maintenance problem.
3. Keep each harness's specific behavior visible in its own definition.

---

## 5. Portable Agent Skills

### Goal

Provide reusable prompt/agent capabilities that can be consumed by multiple harnesses.

### Current Seed Material

`defs/opencode/defaults/agents/*.md` already contains reusable agent roles such as:

- architect
- adversarial reviewer
- security reviewer
- backend/frontend reviewers
- SRE/devops reviewers
- spec keeper

### Roadmap

1. Keep these in `defs/opencode` while they are opencode-specific defaults.
2. Design a neutral `skills/` format before moving or duplicating them.
3. Add adapters only when another harness can actually consume the same skill content.
4. Avoid a renderer/exporter until there are at least two real consumers.

---

## 6. Security and Production Readiness

### Current Security Direction

The project uses containers to make agent execution more explicit, but some harnesses intentionally enable permissive agent modes. The actual safety boundary is the combination of Docker runtime options, mounts, user permissions, capabilities, and tool permissions.

### Production Readiness Gaps

- mutable dependency versions (`latest`, unpinned global installs)
- duplicated shell behavior
- limited CI coverage across all images
- unclear release/versioning policy
- candidate harness definitions still need maturity validation before any are called mature
- no image provenance/SBOM/signing workflow yet

### Future Hardening

Network stasis for Claude containers remains a possible future enhancement, but it should follow the documentation/contract work. If implemented, it should be optional first, tested with explicit allow/deny cases, and documented as a runtime mode rather than a blanket security guarantee.

---

## Timeline

- **Now**: Use the documented harness contract while continuing deterministic command cleanup.
- **Next**: Rationalize `probe` vs `proveo` and keep definition docs aligned with command behavior.
- **Then**: Extract shared utilities only where duplication hurts.
- **Later**: Add portable `skills/`, stronger CI/release policy, version pinning, and optional network stasis.

This roadmap keeps the project useful for personal workflows while creating a path toward maintainable team tooling and, eventually, production-quality distribution.
