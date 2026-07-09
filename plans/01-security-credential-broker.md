# Plan 1 — Security: Credential Broker + Egress Enforcement Hardening

**Paradigm imported from omnigent:** `inner/credential_proxy.py` — *"inject keys, never expose."*
omnigent can do this cleanly because it *owns* the model call. Here the **vendor CLI**
makes the call, so we adapt: the real credential is confined to the mitmproxy sidecar,
injected onto the wire for the one pinned provider host, and **stripped** from every other
destination. The agent's own copy of a key becomes useless off-provider.

## Problem (from the adversarial review — all three reviewers converged)
1. **HTTPS write-pinning is unenforceable at Squid** — Squid sees only `CONNECT host:443`;
   `unsafe_methods`/`blocked_sites` match cleartext HTTP only (`squid.conf:63-76`).
2. **Static `provider_sites` list broadens the tight generated allowlist** — `squid.conf:52,67`
   always `allow unsafe_methods provider_sites` for all 9 providers incl. the `.googleapis.com`
   cloud-wide wildcard, undoing the per-provider pin in `egress.sh` `proveo_egress_provider_acl`.
3. **Provider keys live in the agent's environment** — `load_env` does `set -a; source .env`
   (`entrypoint-lib.sh:71-97`) and `run.sh` forwards `-e CLAUDE_CODE_OAUTH_TOKEN`, so the Cursor
   `Read(.env*)` deny rule and "credential reads denied" README claim are theater
   (`cli-config.json:14-15`).
4. **opencode/cecli wire in no egress boundary at all** — default bridge, unrestricted egress.
5. **DNS/53 is an unconstrained exfil channel** — Docker's embedded resolver forwards regardless
   of `--internal`.
6. **Dashboard**: stored XSS + binds `0.0.0.0` + no auth + serves URL-embedded secrets.

## Design — the credential broker (this plan's core)
The mitmproxy hop is the **only** place TLS is decrypted, so it is the only place method-level
and credential-level enforcement can happen. Make it the credential broker:

- **Inject.** On a request to a pinned-provider host, mitmproxy sets the correct auth header
  from a secret it reads at start — from a file mounted **outside every agent mount** (same
  discipline as the CA private key). The real secret never enters the agent container's env or
  argv; it lives only in the sidecar.
- **Strip.** On a request to any *other* host, mitmproxy deletes credential headers
  (`authorization`, `x-api-key`, `x-goog-api-key`, `api-key`, `proxy-authorization`). Even if the
  agent reads a key from a mounted `.env` and tries to POST it to `evil.com`, the header is
  stripped at egress → exfil-proof at the network layer, independent of what the agent holds.
- **Sentinel (strong form).** For credentials the wrapper forwards via `-e` (e.g. the OAuth
  token), pass the real value to the broker and give the **agent a sentinel**. `load_env` learns
  `PROVEO_CREDENTIAL_BROKER_KEYS` and re-writes those names to the sentinel after sourcing `.env`,
  so the agent process holds no real key. Honest caveat: a key committed to a *mounted* `.env` is
  still readable as a file — documented; recommend host-env provisioning for full isolation.

Broker is a property of **firewall** mode only (the only mode that decrypts). Default
on there; disable with `PROVEO_CREDENTIAL_BROKER=off`. proxy/firewall modes keep today's behavior with
the existing honest warnings.

## Implementation — in Go, not a Python mitmproxy addon
Per the no-Python directive and Plan 4, the broker is **not** a mitmproxy addon (mitmproxy's only
extension API is Python). It is a feature of the **Go egress-inspection proxy** built in Plan 4
Phase 2, which terminates TLS with a generated CA, records flows, and forwards to Squid upstream.
The broker logic — inject on the pinned-provider host, strip credential headers elsewhere, secret
read from a `0600` file mounted outside every agent mount — lives in that Go proxy (`internal/
egressproxy`). This supersedes the Python `mitmproxy` sidecar on the inspection path. **Plan 1 is
therefore gated on Plan 4 Phases 0→2.**

## Work items
- [x] **squid.conf** — deleted the static `provider_sites` ACL + its `allow`; the tight generated
      `provider-allow.conf` is now the sole write-allow. *(Language-agnostic; landed.)*
- [x] **mitmproxy entrypoint** — smoke-ready sentinel now prints only in smoke mode (was a false
      "ready" on every run). *(Incidental Bash fix; landed.)*
- [x] **Go egress proxy** (`cmd/proveo-egress`, `internal/egressproxy`) — martian MITM that
      TLS-terminates, records flows to NDJSON (**query string dropped** → also fixes the old
      secret-in-flow-log finding), brokers credentials, forwards to Squid upstream. Runs as the
      invoking host uid (not root, unlike the mitmproxy sidecar). Smoke-verified: generates a valid
      CA, resolves the provider, reports `inject+strip`, leaks no secret.
- [x] **Broker core** (`internal/broker`) — inject-on-provider / strip-off-provider / pass-through
      when no value; secret from `Value` or a `0600` file; inert unless configured. **8 unit tests.**
- [x] **Provider registry** (`internal/provider`) — single source for provider → (hosts, header,
      query, key env vars, bearer); Bedrock/Azure/Vertex intentionally excluded (signed-request).
      **7 unit tests.**
- [x] **egress.sh wiring** — `PROVEO_EGRESS_INSPECTOR=go|mitmproxy` (default `go`);
      `proveo_egress_prepare_broker_secrets` writes present host-env provider keys to a `0600`
      env-file outside agent mounts (single-provider gated; skipped/off/passthrough cases verified
      under bash + bash 3.2); `proveo_egress_start_egress_proxy` starts the Go proxy. Fixed a
      `set -e` abort (a `while read` subshell ending non-zero). Secret file removed on cleanup.
- [x] **Dockerfile + build.sh** (`defs/sidecars/egress-proxy/`) — multi-stage static build on
      distroless.
- [ ] **Go entrypoint (Plan 4 Ph3)** — honor a broker-keys list: after `.env` load, replace those
      names with a sentinel so the agent process never holds the real key. *(sentinel = defense in
      depth; the network-layer inject/strip guarantee is already delivered above.)*
- [x] **End-to-end validation, split across two tests:** the in-process broker-through-proxy test
      (`internal/egressproxy`) proves inject-on-provider / strip-off-provider through the real
      martian modifier chain; the gated Docker test (`internal/egress`, `PROVEO_EGRESS_INTEGRATION=1`)
      proves the live topology — TLS interception with the trusted CA, decrypted flow recording, and
      no direct egress off the internal network. (A live credential-injection assertion against a
      fake provider is deferred — it needs a controllable TLS origin the proxy will accept.)

## Follow-ups (tracked, not in the first slice)
- Method enforcement at the mitm layer (block writes to non-provider even over HTTPS).
- Wire egress into opencode/cecli `run.sh` (removes finding 4).
- Constrain DNS (drop embedded resolver / route 53 through proxy or block).
- Dashboard: escape output, bind `127.0.0.1`, add a token; drop query strings from `flows.ndjson`.
- Pin the FireHOL ipset fetch to a commit + checksum; pin mitmproxy base (already 11.1.3 — assert).

## Acceptance criteria
- firewall + a detected provider → agent env has a **sentinel** for `-e`-forwarded keys;
  the real secret exists only in the mitm sidecar (file, 0600, outside agent mounts).
- A request to the provider host carries the real auth header; a request to any other host carries
  **no** credential header (verified by the addon unit test).
- `squid.conf` no longer contains `provider_sites`; `grep` in the contract test enforces it.
- No secret value is ever written to `flows.ndjson`, `access.log`, `report.*`, or stdout.
- Existing no-Docker contract suite stays green.
