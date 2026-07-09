# base

`proveo/base` is the **minimal** shared floor for every harness image. It carries
only what is universal to all harnesses:

- `git`, `gh`, `ca-certificates`, `curl`, `dumb-init`, `bash`
- the `proveo-entrypoint` binary (built once here via a `golang` builder stage;
  every harness inherits `/usr/local/bin/proveo-entrypoint` instead of
  recompiling it)
- the `/usr/local/sbin/proveo-harden` pass (setuid/setgid strip + raw-network-tool
  removal)

It is `FROM debian:bookworm-slim` and lands at ~200 MB.

## What is deliberately NOT here

- **No language runtime.** Node and Python are not universal — `cursor` needs
  neither (its `cursor-agent` is a self-contained binary), `cecli` is Python,
  `opencode`/`claudecode` are Node. Node lives in the thin `proveo/base-node`
  intermediate (`defs/base-node`), which the Node harnesses build FROM; Python
  is added by the one harness that needs it (`cecli`).
- **No browsers.** No harness's runtime drives a browser; Playwright/Chromium was
  a speculative "agent runs browser e2e in the mounted repo" capability that
  fattened the shared floor to multiple GB. It is now install-on-demand: inside a
  harness run `npx playwright install chromium` (Node) or
  `python -m playwright install chromium` (cecli) into a mounted cache dir.

## FROM tree

```
debian:bookworm-slim
└── proveo/base                git/gh/curl/dumb-init/bash/proveo-entrypoint/harden
     ├── cursor                cursor-agent binary; no runtime
     ├── cecli                 + python3-venv (aider fork)
     └── proveo/base-node      + Node 22 LTS + pnpm
          ├── opencode
          └── claudecode (mcp) ├── claudecode-solo   └── claudecode-sol
```

## Rules

- Harness Dockerfiles start with `ARG BASE_IMAGE=proveo/base:latest` (or
  `proveo/base-node:latest`) + `FROM ${BASE_IMAGE}` (the ARG is the
  white-label / pinning seam).
- Any harness layer that `apt-get install`s extras must end with
  `/usr/local/sbin/proveo-harden <paths>` — new packages can reintroduce setuid
  bits. Pass the prefixes you touched (e.g. `proveo-harden /usr /opt`) so the
  scan doesn't re-walk the whole filesystem.
- Harness `build.sh` scripts call `defs/base/ensure.sh` (or
  `defs/base-node/ensure.sh` for Node harnesses) first, so a lone
  `mise build <harness>` works on a clean machine and won't reuse a stale local
  tag from a different lineage.
- Per-harness users, runtimes, configs, and entrypoints do NOT belong here. If
  two harnesses need the same new tool, that is the bar for adding it to the
  appropriate shared layer.

It is not a runnable harness: no `harness.manifest`, no entrypoint. It is a mise
build/deploy target (`mise build base`) like the sidecar images.
