# Plan 3 — Docker-first Go tests + coverage (bash contract retirement)

**Builds on:** Plan 4 (Bash→Go substrate). **Parallel with:** Plan 5 (white-labelling) once
Plan 4's core CLI/egress packages are stable.

**Spec-first:** `_spec/testing.md` + `_spec/tests/*.puml` document build tags, Go-first
contracts, and coverage *before* bash deletion. Conventions live in
`docs/go-testing-standards.md`.

## Problem

~35 Bash test scripts remain (`defs/*/tests/*.sh`, `defs/tests/test_harness_contracts.sh`,
`apps/cli/public/cli/tests/run_tests.sh`). The largest — `test_harness_contracts.sh` (~380 lines) —
asserts behavior by **grep-for-substring** in source files. That pattern:

- Missed real bugs the Go migration surfaced (Squid ACL glued onto `http_access` with no newline;
  host `.env` keys not reaching the egress broker because only `os.Getenv` was consulted).
- Duplicates knowledge already encoded in Go packages (`internal/provider`, `internal/egress`,
  `internal/runner`) — two sources of truth that drift.
- Depends on Bash 3.2 portability hacks the Go migration was meant to retire.

Industry practice (Testcontainers patterns, Go 1.20+ `GOCOVERDIR`) prioritizes **real Docker
integration/e2e** with wait strategies + cleanup, and **merged coverage** from unit + binary
runs — not grep contracts. This plan follows that order.

## Strategy (execution order)

### Stage 0 — Coverage plumbing (first)

- [x] Spec/docs: build tags, coverage merge, no hard % gate
- [x] `scripts/go-test-coverage.sh` + mise `test-go` / `coverage`
- [x] Unit lane: `go test -race -cover -covermode=atomic ./... -args -test.gocoverdir=cov/unit`
- [x] Merge: `go tool covdata merge` → `percent` / `textfmt` (CI artifact)
- [ ] Stage 0b (later): `proveo/egress-proxy:cover` from `go build -cover` + bind-mount `GOCOVERDIR`

**v1 scope:** unit + in-process egressproxy/broker. Docker Layer 3 remains topology coverage
without requiring containerized statement % until 0b.

### Stage 1 — Harden Layer 3 / 4 (Docker-first)

- [x] `//go:build integration` on `internal/egress/integration_test.go`
- [x] `//go:build e2e` on `internal/tmux/e2e_test.go`
- [x] Wait helpers (CA / HTTP ready); `t.Cleanup` teardown audited
- [x] Broker-aware case: host `.env` `CURSOR_API_KEY` only → `broker.env` + firewall sentinel in plan
- [x] mise `test-go-integration`, `test-go-e2e`

Keep `BuildPlan` orchestration — do **not** add testcontainers-go for Squid/proxy.

### Stage 2 — Replace bash contract Layer 2

Port `defs/tests/test_harness_contracts.sh` Go-owned assertions into package tests:

- [x] `internal/runner` hardening baseline
- [x] `cmd/proveo` env forwarding / sentinel / host `.env` → `broker.env`
- [x] `internal/egress` plan goldens (already largely present)
- [x] `internal/provider` registry pins
- [x] `internal/workspace` `.env` mask + `EnvFileSource`
- [x] Shim contracts (`defs/*/run.sh` exec `proveo run`)
- [x] `internal/contract` package + thin bash wrapper (detect-verify residual only)

**Deliverable:** `go test ./internal/... ./cmd/...` replaces the no-Docker contract runner;
`defs/tests/test_harness_contracts.sh` is a thin `go test` wrapper + detect-verify residual.

### Stage 3 — Selective harness bash → Go

| Script | Action |
|--------|--------|
| `detect-verify.sh` | **Done** — `internal/verify` + `proveo-entrypoint verify`; thin wrapper remains for image paths |
| `env-mount.sh`, `git-identity.sh` | **Deleted** — Go `internal/workspace`, `internal/gitidentity` |
| Cursor/OpenCode defaults/security needles | **Done** — `internal/contract/defaults_test.go` |
| `test_config.sh` (cursor/opencode) | Keep Docker-gated (smoke/preamble need image) |
| `test_tools.sh`, `test_build.sh` | Keep Bash (image presence) |
| `test_llm.sh` | Keep as optional live test |

Do **not** port TUI/interactive tests (`test_tui.sh`) unless a headless harness exists.

## Why migrate (value)

| Bash contract test | Go replacement wins |
|--------------------|---------------------|
| `grep -qF` on source | Executes or golden-tests the real builder |
| Static file presence | `go:embed` + `manifest.LoadFS` tests |
| Provider ACL substring | `egress.ProviderAllowConf` golden |
| Env / broker invariants | Table-driven `providerLookup` / `writeBrokerEnv` / `assemble` |
| No coverage from Docker | `GOCOVERDIR` + `go tool covdata` merge |

## Acceptance criteria

- Default `go test ./...` is fast, no Docker, writes `cov/unit`.
- `go test -tags=integration` + `PROVEO_EGRESS_INTEGRATION=1` exercises real topology.
- `mise coverage` merges profiles; CI can upload percent/HTML (no hard % gate yet).
- `_spec/testing.md` + diagrams mention build tags + coverage.
- Regression: `CURSOR_API_KEY` in host `.env` only still detects provider, writes `broker.env`,
  and appears as firewall sentinel in assembled agent env.
- `test_harness_contracts.sh` deleted or reduced to a `go test` one-liner.
