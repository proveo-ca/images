# TODO — CI / Pipeline

The adversarial review's Security / Correctness / Design / Testing findings are all
resolved in code (see git history). What remains is **pipeline work**: wiring the
gates and validation that keep those fixes from regressing. Ordered by leverage.

## 1. Static-analysis gate (the one review residual)
Nothing currently enforces `docs/go-testing-standards.md` — `staticcheck` /
`golangci-lint` aren't installed.
- [ ] Add `.golangci.yml` (enable `govet`, `staticcheck`, `errcheck`, `ineffassign`, `unused`, `gofmt`, `misspell`).
- [ ] CI job runs, as hard gates: `gofmt -l internal cmd` (fail if non-empty) · `go vet ./...` · `golangci-lint run` · `go build ./...` · `go test -race ./...`.

## 2. The four test layers in CI (`_spec/testing.md`)
- [ ] **Layer 1 unit + Layer 2 contract — every push, no Docker:** `go test -race ./...` and `bash defs/tests/run_contract_tests.sh` (Go↔Bash parity; currently 0 failures).
- [ ] **Layer 3 infra-integration — Docker runner:** build `proveo/egress-proxy` (`docker build -f defs/sidecars/egress-proxy/Dockerfile -t proveo/egress-proxy:latest .`), then `PROVEO_EGRESS_INTEGRATION=1 go test ./internal/egress/ -run TestFirewall`. Covers `TestFirewallIntegration` (chain + CA + flow record + no-direct-egress) and `TestFirewallPolicyIntegration` (read allowed; write/sink/secret blocked).
- [ ] **Layer 4 agent-E2E "promptful" — nightly/manual:** `PROVEO_LLM_TEST=1` with Docker + Ollama. **Use a small model, not `gemma4`** — its ~9.6 GB cold-load overruns the fixture window and flakes; pin a small model via `PROVEO_TEST_LOCAL_MODEL` for CI and reserve `gemma4` for local runs.

## 3. Image builds & supply chain
- [ ] Build all harness + sidecar images in CI (`.goreleaser.yaml` covers the `proveo` binary; add the images).
- [ ] **Digest-pin the enforcement images** (`ubuntu/squid`, `proveo/egress-proxy`, `ollama/ollama`) — they're the egress trust root and default to floating `:latest`. Resolve digests at release and set the defaults (or document pinning via `PROVEO_{SQUID_PROXY,EGRESS_PROXY,OLLAMA}_IMAGE`, already honored). *(Was review S6.)*

## 4. Egress validation matrix (folded from the retired PLAN.md)
Extend the gated Layer-3 job to the full matrix, so every mode's invariants are pinned:
- [ ] **firewall** — direct HTTP(S) and arbitrary protocol egress succeed.
- [ ] **proxy** — HTTP(S) via Squid succeeds; direct bypass and non-web protocols fail; RFC1918 + cloud-metadata (`169.254.169.254`) + write methods denied; only read-oriented public HTTP(S) passes.
- [ ] **firewall** — MITM decrypt + policy block/allow + CA trust + decrypted flow recorded; raw-bypass attempts rejected/logged. *(Core cases already covered live; broaden the matrix.)*
- [ ] **local model** — `ollama:11434` reachable on the agent network while all the above denies hold.
- [ ] Add active **Squid / egress-proxy readiness probes** (today the CA-wait and `WaitOllamaReady` are the only gates).

## 5. Optional / future
- [ ] `PROVEO_EGRESS_INSPECTOR=...` to attach the firewall inspector to any harness (opencode/cecli), reusing the sidecar/log/dashboard pipeline.
- [ ] Publish the egress-dashboard build in CI and smoke-test it against a recorded `flows.ndjson`.
