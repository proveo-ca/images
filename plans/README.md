# Improvement Plans

Five plans, each importing one paradigm from `../../omnigent/_spec/` to close a class of gap the
adversarial review found in this repo. Ordered by execution priority.

| # | Theme | Imports from omnigent | Core move |
|---|-------|----------------------|-----------|
| [01](01-security-credential-broker.md) | Security | `inner/credential_proxy.py` ("inject keys, never expose") | Confine the provider secret to a broker proxy; inject on the pinned host, strip everywhere else |
| [02](02-systems-design-harness-manifest.md) | Systems design | the `Executor` protocol (one contract, pluggable backends) | One `harness.manifest` per def + one runner; everything enumerates from it |
| [03](03-bash-test-migration.md) | Quality | — | Docker-first Go integration/e2e + coverage; retire grep-based Bash contracts |
| [04](04-bash-to-go-migration.md) | Substrate | — | Move host CLI, egress proxy, and in-container entrypoint from Bash (+ Python/JS glue) to Go |
| [05](05-white-label-brand-manifest.md) | White-labelling | one upstream identity include ("change it once, everything updates") | One `brand.env` source of truth + build-time templating |

**Sequencing:** Plan 04 is the substrate the others build on — the broker (01) becomes a Go proxy,
the single runner (02) a Go package. Per the no-Python directive, the credential broker is **not** a
mitmproxy addon; it lives in the Go egress proxy (Plan 04 Phase 2), so Plan 01 is gated on Plan 04.

Plan 03 (test migration) is Docker-first: coverage plumbing and Layer 3/4 build tags land
before bash contract deletion. As each Bash surface moves to Go, delete the grep contract that
guarded it and add a typed test on the Go package. Plan 05 (white-labelling) is intentionally
last — a mechanical rename across hundreds of tokens is easier once the Go substrate and Go
tests are the source of truth.

**Discipline:** each plan updates `_spec/` *before* its code. Plan 01's design is in
`_spec/paradigms.md` (Credential Boundary — planned, Go); the egress topology diagram stays at
current-implementation truth until the Go broker ships. Already landed (language-agnostic): the
static provider allowlist was removed from `defs/sidecars/squid-proxy/squid.conf`.

Full review context: memory `project_images_vs_omnigent`.
