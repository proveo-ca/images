# Plan 2 — Systems Design: One Harness Manifest, One Runner

**Paradigm imported from omnigent:** the `Executor` protocol. omnigent never special-cases a
vendor in the orchestrator — it defines **one contract** (`run_turn(messages, tools,
system_prompt)`) and every vendor is a conforming, discoverable backend. Apply that at the
harness-fleet level: one declarative manifest per def, one runner that reads it, everything else
enumerates from it.

## Problem (from the adversarial review)
- **Run logic is triplicated** — consumer `apps/cli/public/cli/lib/runners.sh` (442-line full
  reimplementation), maintainer `lib/runners.sh` (thin shim), and `defs/<name>/run.sh` (the real
  thing). The hardening baseline (`--cap-drop=ALL --security-opt=no-new-privileges --pids-limit`)
  is copy-pasted into 6 files; `proveo_git_identity_env_args` is defined twice (the consumer copy
  self-describes as "a standalone mirror").
- **Adding a harness touches ~8-10 hardcoded sites**; no single registration point.
- **The `registry/*.yaml` files are dead** — nothing parses them; the data is re-hardcoded in Bash.
- **cursor is tested-but-unshippable** — fully built + contract-tested, but absent from consumer
  `TARGETS`/`image_name`/`run_target`, maintainer `target_dir`/`build`, and the smoke suite. This
  is the coupling cost made visible: someone wired 5 of ~10 sites and the def can't run.
- **Contract tests are static grep assertions**, not behavior; Docker egress invariants never run.

## Status (complete)
Manifest + single Go runner + embedded manifests + bash enumeration from `harness.manifest` for
mise/build. Consumer install still has a fallback target list when defs are absent.

## Design
1. **`defs/<name>/harness.manifest`** (or `manifest.yaml`) — the single source of truth per def:
   ```yaml
   name: cursor
   image: ${BRAND_IMAGE_ORG}/cursor:latest       # BRAND_* → Plan 5
   variants: [default]
   description: Policy-gated autonomous loop (Cursor CLI)
   egress: true            # sources defs/lib/egress.sh
   stability: candidate    # experimental | candidate | stable
   ```
2. **One `docker-run` helper** in a shared lib carrying the *single* canonical hardening baseline;
   both the consumer CLI bundle and `defs/*/run.sh` call it. Ship the shared lib **into** the
   published CLI bundle so the "standalone mirror" hack disappears.
3. **Enumerate, don't hardcode** — consumer `TARGETS`/`image_name`/`run_target`, maintainer mise
   tasks, the smoke suite, and the contract tests all read the manifest set instead of parallel
   literal lists. `is_ai_harness`, `target_description` derive from manifest fields.
4. **Contract test upgrade** — assert manifest-derived invariants (every def has a manifest; every
   manifest image uses `BRAND_IMAGE_ORG`; egress:true defs source egress.sh) rather than grepping
   for literal strings.

## Work items
- [x] Manifest schema in Go (`internal/manifest`) + bash enum helper (`lib/manifest-enum.sh`) for mise/CLI.
- [x] Author `harness.manifest` for cecli, claudecode (incl. sol), opencode, cursor.
- [x] Hardening + mounts + git-identity in Go (`internal/runner`, `workspace`, `gitidentity`); run.sh shims.
- [x] TARGETS / image_name / target_dir from manifests (maintainer `lib/runners.sh` + consumer fallback).
- [x] Dead `registry/*.yaml` removed.
- [x] Cursor wired end-to-end (`proveo run cursor`, build/test targets).
- [x] Contract tests assert manifest enum, proveo/* images, shims without redeclared hardening.

## Acceptance criteria
- Adding a new harness = drop `defs/<name>/` + a `harness.manifest`; **no** other file edited.
- `proveo run cursor`, `mise run build cursor`, and the smoke suite all resolve cursor with no new
  hardcoding.
- The hardening baseline exists in exactly **one** place; the contract test proves no def defines
  its own copy.
- `git grep` finds no unused `registry/*.yaml`.
- Spec-first: update `_spec/components.puml` + `_spec/usage.puml` to show the manifest as the single
  registration point *before* refactoring.
