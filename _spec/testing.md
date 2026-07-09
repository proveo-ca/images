# Testing Approach

How this repo verifies its harnesses, from fast pure-logic checks up to a real
agent doing a real task against a local model. Each layer trades speed for
fidelity; higher layers are gated so the fast path stays fast and keyless.

## The four layers

| Layer | Where | Needs | Deterministic? | Gate |
|-------|-------|-------|----------------|------|
| **1. Unit** | `internal/*/*_test.go` (no build tags) | Go only | yes | always (`go test -race`; coverage via `-test.gocoverdir`) |
| **2. Contract** | Go builders + goldens (`cmd/proveo`, `internal/{runner,provider,egress,workspace}`); residual bash for image smoke / live LLM | Go | yes | always (no Docker) |
| **3. Infra integration** | `internal/egress` (`//go:build integration`) | Docker, internet | yes (no model) | `-tags=integration` **and** `PROVEO_EGRESS_INTEGRATION=1` |
| **4. Agent E2E ("promptful")** | `internal/tmux` (`//go:build e2e`) | Docker, tmux, Ollama+model | **no** (asserts side-effects) | `-tags=e2e` **and** `PROVEO_LLM_TEST=1` |

Host orchestration under test is **Go** (`cmd/proveo`, `internal/{runner,workspace,egress,dind,gitidentity,manifest}`). Fat bash runners and `defs/lib/egress.sh` lifecycle are retired. Layer 2 is **Go-first**: contracts execute builders (`DockerRunArgs`, `BuildPlan`, `Detect`, `writeBrokerEnv`) instead of grepping source; bash remains only for image smoke and optional live LLM.

Default `go test ./...` never compiles Layer 3/4 (build tags). That keeps the PR path fast and keyless.

## Coverage

Unit and in-process integration profiles use Go 1.20+ coverage data dirs:

1. **Unit / contract:** `go test -race -cover -covermode=atomic ./... -args -test.gocoverdir=cov/unit`
2. **In-process broker/proxy:** included in the same unit lane (`internal/egressproxy`, `internal/broker`)
3. **Merge / report:** `go tool covdata merge` then `percent` / `textfmt` (see `scripts/go-test-coverage.sh`, `mise coverage`)

**Stage 0b (optional):** rebuild `proveo/egress-proxy:cover` from `go build -cover` and bind-mount `GOCOVERDIR` into the Layer 3 proxy container. Topology coverage (networks / CA / flows) does not require statement % from the containerized binary in v1.

No hard coverage % gate until a baseline exists; CI publishes `go tool covdata percent` as an artifact.

## Component diagrams (`_spec/tests/`)
The *components* of each layer are diagrammed; this doc is the prose rationale.

- [`00-testing-overview.puml`](tests/00-testing-overview.puml) — the four layers, gates, coverage merge.
- [`10-unit.puml`](tests/10-unit.puml) — Layer 1 packages under test (`go test -race -cover`).
- [`20-contract.puml`](tests/20-contract.puml) — Layer 2 Go builders + goldens (bash residual).
- [`30-infra-integration.puml`](tests/30-infra-integration.puml) — Layer 3 live egress topology (real containers, no model).
- [`40-agent-e2e-components.puml`](tests/40-agent-e2e-components.puml) — Layer 4 promptful topology.
- [`41-agent-e2e-sequence.puml`](tests/41-agent-e2e-sequence.puml) — Layer 4 flow over time.

## Layer 3 — infra integration (Docker)

Orchestration stays `BuildPlan` + `ExecRunner` (owned topology). Do **not** introduce
testcontainers-go for Squid/proxy — that would duplicate what we already own. Apply
Testcontainers *practices*: wait for CA file / HTTP ready (never sleep-only sync),
`t.Cleanup` teardown, env gate + `docker` LookPath skip.

Broker-aware case: host `.env` with `CURSOR_API_KEY` only → `writeBrokerEnv` + firewall
plan mounts `/broker`; agent plan carries the sentinel. Inject/strip semantics stay in
the in-process martian suite (`internal/egressproxy`).

```bash
PROVEO_EGRESS_INTEGRATION=1 go test -tags=integration -race ./internal/egress/ -v -timeout 120s
```

## Layer 4 — the promptful / agent-E2E pattern

### Why a local model (Ollama / gemma4), not a cloud provider
Cloud keys make agent E2E impossible to run in CI honestly: they cost money, hit
rate limits, leak spend, and can't run offline. The repo already ships an Ollama
sidecar (`--local-model`, `internal/egress`): it mounts
the host's already-pulled models **read-only** and serves them on the agent
network, reached directly via `NO_PROXY` so the model call bypasses the egress
proxy while every other destination stays policed. That makes agent E2E:

- **keyless** — no `ANTHROPIC_API_KEY`/`OPENAI_API_KEY` needed;
- **offline & free** — no network egress, no spend, no rate limits;
- **hermetic** — the model is pinned to a host-local artifact (`gemma4`).

### Why headless tmux is the driver
The harnesses are interactive TUIs launched with `docker run -it`, so they need a
**PTY** to render into — which a plain CI runner doesn't have. `tmux new-session
-d` gives a detached, headless PTY server (no attached terminal required), and it
is the one multiplexer with a truly serverless-of-client model, so it's the
durable choice for CI (over zellij, which must render to a terminal, or a young
solo-maintained framework). It also gives the two scripting primitives:

- `tmux send-keys` → inject the prompt + control keys (drive the TUI);
- `tmux capture-pane -p` → read the rendered screen (assert / wait-for-text).

One reusable driver (`internal/tmux`) is used across every harness — "tmux across
the board".

### The load-bearing principle: assert side-effects, not prose
A local model's output is **non-deterministic**; asserting exact text is a flaky
test. A sound agent-E2E gives a task with a **crisp binary success signal** and
asserts *that*:

- a **file** appears in the output mount with an expected marker (best);
- a **command** ran (observable in a log the harness writes);
- a **keyword** the task demanded is present on the captured screen.

The prompt is engineered so success is unambiguous and prose-independent, e.g.:

> "Create the file `/workspace/output/DONE.txt` containing exactly the word
> BANANA, then stop."

Then assert `DONE.txt` exists and contains `BANANA`. The model can phrase its
narration however it likes; the *effect* is binary.

### Model endpoint & the thinking-model caveat (verified on this host)
`gemma4` is a **reasoning/thinking** model. Consequences observed against the
host Ollama:
- `POST /api/generate` (raw completion) returns an **empty** `response` (the
 output is consumed as reasoning) — do **not** test through this path.
- `POST /api/chat` and `POST /v1/chat/completions` return usable content
 (`"BANANA"`), with a separate `thinking` field on the native chat endpoint.

The harnesses (opencode/cecli via litellm `ollama/<model>`) use the
**OpenAI-compatible `/v1/chat/completions`** endpoint, so gemma4 is usable — but
its replies may carry a reasoning preamble, which is exactly why Layer 4 asserts
the **side effect**, never the transcript.

### Determinism knobs (make the flake window small, accept it's non-zero)
- a tiny, tightly-scoped, single-step task;
- low temperature where the harness/model exposes it;
- generous **poll-with-timeout** on `capture-pane` / the output dir — never a
 fixed sleep;
- treat Layer 4 as *"does the whole loop work"* smoke, not a correctness oracle.

### Operational notes (verified live)
- **The sidecar cold-loads the model.** The host Ollama may have the model warm,
 but the `--local-model` sidecar is a *fresh* instance that loads the model into
 its own memory on the first request. For a 9.6 GB model (`gemma4`) that first
 call takes minutes. The agent must (a) wait for the sidecar API to accept
 connections, then (b) allow a long per-call timeout for the cold load. The
 `defs/tests/echo-agent` fixture does both.
- **CI wants a small model.** The pattern works with any model; pick a small one
 (fast cold-load) for CI and reserve `gemma4` for local runs with a long window.
- **Follow-up — sidecar readiness in `proveo run`.** Real harnesses race the same
 cold sidecar. `proveo run` should wait for the Ollama sidecar to be serving
 before launching the agent (analogous to the mitmproxy CA wait), so a harness's
 first model call doesn't hit a not-ready sidecar. Verified components: the
 agent→model→side-effect path and tmux keystroke delivery both work in isolation;
 the only fragility is this sidecar-readiness race.

### The echo-agent fixture
`defs/tests/echo-agent/` is a ~10-line Alpine "agent" (read prompt → call the
local model over `/v1/chat/completions` → write `DONE.txt`). It lets Layer 4 run
with **no vendor image** — only docker + tmux + Ollama — so the pattern is
exercised end to end in CI. Real harnesses are opt-in via `PROVEO_TEST_TARGET`.

### Topology
See [`tests/40-agent-e2e-components.puml`](tests/40-agent-e2e-components.puml)
(components) and [`tests/41-agent-e2e-sequence.puml`](tests/41-agent-e2e-sequence.puml)
(the drive → prompt → model → side-effect flow over time).

### What it validates vs. doesn't
- **Validates**: the full loop — harness boots, reads a prompt, calls the model
 via the Ollama sidecar, acts on the workspace, and the effect is observable.
 Plus that the egress boundary lets the local model through while staying
 otherwise closed.
- **Does not validate**: model quality or exact reasoning — that is the model's
 job, not the harness's, and asserting it would be flaky by construction.

### Harness applicability
- **opencode, cecli** — speak OpenAI-compatible / litellm `ollama/<model>`; the
 `--local-model` bridge points them at the sidecar. **Primary Layer-4 targets.**
- **cursor** — inference is vendor-pinned to the Cursor backend; `--local-model`
 does not apply, so its Layer-4 either uses a real key (out of CI) or is limited
 to non-model TUI assertions.
- **claudecode** — Claude Code speaks the Anthropic API shape, not Ollama's
 OpenAI shape, so the sidecar isn't a drop-in; documented limitation.

### Gating & hygiene (non-negotiable)
- Compile with `-tags=e2e`. **Skip, never fail**, unless `PROVEO_LLM_TEST=1` **and**
  `tmux`, `docker`, and a reachable Ollama with the model are all present.
- Unique tmux session name + egress session id + temp output dir per run.
- Tear down (`tmux kill-session`, egress cleanup) on every exit path, including
 failure (`t.Cleanup`).
- Pin the model name via `PROVEO_TEST_LOCAL_MODEL` (default `gemma4`).

## The driver (`internal/tmux`)
A thin, injectable-runner wrapper so the wait/capture logic is unit-tested
without tmux, and the integration test drives a real session:

- `Start(cmd…)` → `tmux new-session -d`
- `SendText` / `Enter` → `send-keys -l` / `send-keys Enter`
- `Capture` → `capture-pane -p`
- `WaitFor(substr, timeout)` → poll `Capture` until it appears (or time out)
- `Kill` → `kill-session`
- `Available` → is `tmux` on `PATH`

## Setup
```bash
brew install tmux # macOS (Linux: apt install tmux)
ollama pull gemma4 # already present on this host
PROVEO_LLM_TEST=1 go test -tags=e2e ./internal/tmux/ -run PromptfulE2E -v -timeout 300s

# Coverage (unit + merge)
mise run test-go
mise run coverage
```
