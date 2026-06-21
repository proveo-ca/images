# Proveo Coding Harnesses — Execution Plan

Status: Build mode. Items 1–7 completed.

## Completed (Priority 1–3)
1. Shared verification discovery design
   - Created `defs/lib/detect-verify.sh`
   - Integrated into all three entrypoints (opencode, claudecode, cecli)
   - Prints detected test/lint/build/typecheck commands at startup

2. Seed meaningful steering files
   - `defs/claudecode/defaults/CLAUDE.md` — ML loop rules
   - `defs/opencode/defaults/AGENTS.md` — team workflow rules
   - `defs/cecli/defaults/CONVENTIONS.md` — pair-programming rules
   - Entrypoints now seed these into the workspace when missing

3. Tune entrypoints to report paradigm + commands
   - Each entrypoint prints its paradigm banner on launch
   - Verification commands are discovered and displayed

## Completed (Priority 4–6)
4. Claude Code full-consent + egress boundary
   - Kept `--dangerously-skip-permissions` as the intended paradigm.
   - Removed the contradictory `CLAUDE_DANGEROUS=0` branch.
   - Added egress modes: `open`, `proxy`, `inspected-firewall`.
   - Added Squid policy proxy definition and mitmproxy inspection topology.
   - Defined HTTP/HTTPS-only network allowlist for proxy modes, with generic docs/search access.

5. OpenCode subagent orchestration
   - Expanded `AGENTS.md` with routing matrix, review gates, HITL rules, and verification rules.
   - Added OpenCode team workflow startup banner.
   - Added `OPENCODE_RESEED=1` behavior for project `AGENTS.md`.
   - Updated OpenCode paradigm and topology specs.

6. Cecli pair-programming containment
   - Strengthened `CONVENTIONS.md` for low-token, file/function-directed work.
   - Preserved `auto-commits: true` with `/undo` as recovery.
   - Added runtime `max_sub_agents: 3` default.
   - Updated Cecli paradigm and topology specs.

7. Tests for seeding, reseeding, smoke mode, env bridging, and command detection
   - Extend existing test suites in `defs/opencode/tests/`, `defs/claudecode/tests/`, `defs/cecli/`
   - Cover:
     - Seeding of steering files when absent
     - Reseed behavior with `*_RESEED=1`
     - Smoke test mode (`PROVEO_SMOKE_TEST=1`)
     - Model/env variable bridging
     - Verification command detection output
   - Tests must run without Docker where possible (unit-style) or mark Docker-dependent tests clearly
   - Added `defs/tests/run_contract_tests.sh` for no-Docker harness contract tests.
   - Added focused egress mode contracts in `defs/claudecode/tests/test_egress.sh`.
   - Docker integration tests remain explicitly gated/skipped where Docker is unavailable.

## Notes
- The three paradigms are now documented in `_spec/` with topology diagrams.
- Cecli auto-commit is intentionally allowed.
- No changes should weaken the `--dangerously-skip-permissions` behavior for Claude Code.
- Shared verification logic lives in `defs/lib/` and is sourced by entrypoints at runtime (copied into images at build time).

## Verification
- `defs/tests/run_contract_tests.sh` passes without Docker.
- Full image test suites remain Docker-dependent.

## Egress Follow-Ups Implemented
- Implemented reusable Docker egress lifecycle in `defs/lib/egress.sh`.
  - `open`: current direct bridge egress remains allowed.
  - `proxy`: `claudecode -> squid -> internet`; Claude must not attach to default bridge or any internet-capable network.
  - `inspected-firewall`: mitmproxy-first chain, `claudecode -> mitmproxy -> squid -> internet`; mitmproxy uses Squid as upstream and has no direct internet egress.
- Wired lifecycle into parent `defs/claudecode/run.sh`.
  - Generate a session ID.
  - Create internal networks for agent-to-mitmproxy and mitmproxy-to-Squid.
  - Create an internet-capable egress network only for Squid.
  - Start sidecars with mounted logs under `reports/egress/<session-id>/`.
  - Clean up sidecars/networks unless `PROVEO_KEEP_EGRESS=1`.
- Added egress observability scaffold.
  - Persist mitmproxy flow exports as NDJSON under `reports/egress/<session-id>/mitmproxy/flows/`.
  - Persist Squid `access.log` allow/deny decisions.
  - Initialize egress guard `reject.log` for raw non-web protocol bypass attempts that the inspector cannot see.
  - Added simple Vite + Node dashboard scaffold to normalize mitmproxy flows, Squid logs, and guard rejects into a timeline.
- Revisited FireHOL/IP-blocking posture.
  - Keep deterministic reserved/private/bogon destination blocks enabled by default at the Squid layer.
  - Treat live FireHOL blocklist-ipsets (for example `firehol_level1`) as optional generated ACLs because FireHOL documentation warns about false positives in third-party lists.
  - Use `defs/sidecars/squid-proxy/update-firehol-ipsets.sh` to generate `firehol-ipset.conf` when a deployment wants FireHOL threat-intel feeds.

## Egress Inspector: Charles → mitmproxy (Implemented)
Charles was migrated to mitmproxy as the `inspected-firewall` first-hop inspector.
The only reason Charles had been chosen was an available license; mitmproxy is
free (Apache-2.0), headless-native, and actually decrypts HTTPS — which the
Charles wiring never did (it only saw `CONNECT host:443`).
- Added `defs/sidecars/mitmproxy/` (image, `mitmdump` entrypoint, NDJSON flow addon, scripts).
  - Chain: `agent -> mitmproxy -> squid -> internet` via `--mode upstream:http://squid:3128`.
  - HTTPS interception is on; mitmproxy generates a per-session CA.
  - `addons/ndjson_dump.py` writes `flows.ndjson` with the dashboard's event shape.
- Reworked `defs/lib/egress.sh`.
  - `proveo_egress_start_mitm` replaces `proveo_egress_start_charles`.
  - Deleted the Charles GUI-config bootstrap (`PROVEO_CHARLES_CONFIG_DIR`,
    `com.xk72.Charles.config`, `UPSTREAM-SQUID.md`); upstream is a flag, so the
    chain is fail-closed by construction.
  - Agent trusts the generated CA via `SSL_CERT_FILE` / `REQUESTS_CA_BUNDLE` /
    `NODE_EXTRA_CA_CERTS` / `CURL_CA_BUNDLE` / `GIT_SSL_CAINFO`. Since all agent
    egress is forced through mitmproxy, pointing every CA var at the cert is both
    sufficient and correct — no host trust-store changes.
- Squid stays the enforcement + egress boundary (FireHOL reserved/bogon denies,
  protocol allowlist, provider exceptions). Inspection and enforcement remain
  separate and separately testable.
- Optional local model: `--local-model NAME` (or `PROVEO_LOCAL_MODEL`, e.g.
  `gemma4`) attaches an Ollama sidecar to the agent network serving the host's
  pulled models read-only and offline. `NO_PROXY=ollama,localhost,127.0.0.1`
  keeps model calls off the egress proxy, so local inference works under any
  mode while internet egress stays policed.
- Post-run report: when the agent container exits, `proveo_egress_report`
  (called from cleanup) summarizes the Squid access log into `report.txt` /
  `report.json` under `reports/egress/<session-id>/` — the top 5 allowed
  external network operations and the top 5 denied. Host-local destinations
  (the ollama sidecar, localhost) are excluded so "allowed" means real egress.
- Dashboard now parses `flows.ndjson` (`parseMitmNdjson`) instead of Charles XML.
- Non-web protocols remain blocked by Docker `--internal` network topology plus
  Squid's port allowlist, independent of the inspector.

## Remaining HITL/Docker Validation
- Validate egress invariants with Docker integration tests (`PROVEO_EGRESS_INTEGRATION=1`).
  - `open`: direct HTTP(S) and arbitrary mock protocol egress succeed.
  - `proxy`: HTTP(S) through Squid succeeds; direct bypass and non-web protocols fail.
  - `inspected-firewall`: HTTP(S) through mitmproxy then Squid succeeds with the CA
    trusted; mitmproxy records a decrypted flow; Squid records enforcement; raw
    bypass attempts are rejected/logged.
  - blocked actions (proxy mode): private RFC1918 destinations, cloud-metadata
    SSRF (169.254.169.254), non-web ports, and visible HTTP write methods are all
    denied; only read-oriented HTTP(S) to public hosts succeeds.
  - local model: the assigned Ollama model is reachable on the agent network
    (`ollama:11434`) while the above blocked destinations stay denied.
- Pin `defs/sidecars/mitmproxy/Dockerfile`'s `MITMPROXY_VERSION` to the latest published
  `mitmproxy/mitmproxy` tag and confirm the image builds.
- Add active readiness checks for Squid and mitmproxy sidecars after image/runtime
  behavior is confirmed by HITL (the CA-wait is the current readiness signal).
- Optional follow-up: make the inspector attachable to any agent via
  `PROVEO_EGRESS_INSPECTOR=mitmproxy|none`, reusing the same sidecar/log/dashboard
  pipeline for OpenCode and Cecli.

## Next Action
Run full image builds and `PROVEO_EGRESS_INTEGRATION=1` tests on a Docker-capable host.
