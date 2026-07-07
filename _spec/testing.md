# Testing Approach

How this repo verifies its harnesses, from fast pure-logic checks up to a real
agent doing a real task against a local model. Each layer trades speed for
fidelity; higher layers are gated so the fast path stays fast and keyless.

## The four layers

| Layer | Where | Needs | Deterministic? | Gate |
|-------|-------|-------|----------------|------|
| **1. Unit** | `internal/*/*_test.go` | Go only | yes | always (`go test -race`) |
| **2. Contract** | `defs/tests/` | Go + Bash | yes | always (no Docker) |
| **3. Infra integration** | `internal/egress` (+ `defs/.../test_egress.sh`) | Docker, internet | yes (no model) | `PROVEO_EGRESS_INTEGRATION=1` |
| **4. Agent E2E ("promptful")** | `internal/tmux` + gated test | Docker, tmux, Ollama+model | **no** (asserts side-effects) | `PROVEO_LLM_TEST=1` |

Layers 1–3 already exist. This document defines **Layer 4** — driving a real
agent, headlessly, through a real task, using a **local** model.

## Component diagrams (`_spec/tests/`)
The *components* of each layer are diagrammed; this doc is the prose rationale.

- [`00-testing-overview.puml`](tests/00-testing-overview.puml) — the four layers, gates, speed/fidelity.
- [`10-unit.puml`](tests/10-unit.puml) — Layer 1 packages under test (`go test -race`).
- [`20-contract.puml`](tests/20-contract.puml) — Layer 2 suites + Bash↔Go delegation.
- [`30-infra-integration.puml`](tests/30-infra-integration.puml) — Layer 3 live egress topology (real containers, no model).
- [`40-agent-e2e-components.puml`](tests/40-agent-e2e-components.puml) — Layer 4 promptful topology.
- [`41-agent-e2e-sequence.puml`](tests/41-agent-e2e-sequence.puml) — Layer 4 flow over time.

## Layer 4 — the promptful / agent-E2E pattern

### Why a local model (Ollama / gemma4), not a cloud provider
Cloud keys make agent E2E impossible to run in CI honestly: they cost money, hit
rate limits, leak spend, and can't run offline. The repo already ships an Ollama
sidecar (`--local-model`, `defs/lib/egress.sh` → `internal/egress`): it mounts
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
- **Skip, never fail**, unless `PROVEO_LLM_TEST=1` **and** `tmux`, `docker`, and a
  reachable Ollama with the model are all present. Local-model infra is opt-in.
- Unique tmux session name + egress session id + temp output dir per run.
- Tear down (`tmux kill-session`, egress cleanup) on every exit path, including
  failure.
- Pin the model name via `PROVEO_TEST_LOCAL_MODEL` (default `gemma4`).

## The driver (`internal/tmux`)
A thin, injectable-runner wrapper so the wait/capture logic is unit-tested
without tmux, and the integration test drives a real session:

- `Start(cmd…)` → `tmux new-session -d`
- `SendText` / `Enter` → `send-keys -l` / `send-keys Enter`
- `Capture()` → `capture-pane -p`
- `WaitFor(substr, timeout)` → poll `Capture` until it appears (or time out)
- `Kill()` → `kill-session`
- `Available()` → is `tmux` on `PATH`

## Setup
```bash
brew install tmux                 # macOS (Linux: apt install tmux)
ollama pull gemma4                # already present on this host
PROVEO_LLM_TEST=1 go test ./internal/tmux/ -run E2E -v -timeout 300s
```
