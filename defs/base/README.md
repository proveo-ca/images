# base

`proveo/base` is the shared floor for every Node-based harness image
(claudecode, opencode, cursor, cecli-node): Microsoft's official Playwright
image (`mcr.microsoft.com/playwright:v*-noble` — Node, Chromium/Firefox/WebKit,
and their Ubuntu OS deps under `PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`), plus
harness extras (`gh`, `python3`, `dumb-init`), pnpm, a version-matched global
`playwright` CLI, common env, and the baked `/usr/local/sbin/proveo-harden`
pass (setuid/setgid strip + raw-network-tool removal).

Why the MCR image (not `node:*-slim` + `playwright install --with-deps`):
hand-installing OS deps on a slim Node image is fragile (missing `libglib`,
stale apt lists, Debian/Ubuntu package-name drift). The official image is the
supported way to ship browsers + system libraries together; pin the image tag
and the npm `playwright` version to the same release.

Why a shared base exists (structural size work): before this base, each harness
carried its own copy of these layers on a slightly different parent, so nothing
was shared — a consumer pulling two harnesses downloaded the same bulk twice.
With one base, registries and consumer machines store the common layers once;
each harness image is only its delta.

Rules:

- Harness Dockerfiles start with `ARG BASE_IMAGE=proveo/base:latest` +
  `FROM ${BASE_IMAGE}` (the ARG is the white-label / pinning seam).
- Any harness layer that `apt-get install`s extras must end with
  `/usr/local/sbin/proveo-harden` — new packages can reintroduce setuid bits.
- Harness `build.sh` scripts call `defs/base/ensure.sh` first (present with a
  usable Playwright floor → pull → build), so a lone `mise build cursor` works
  on a clean machine and will not reuse a stale local tag that lacks browsers
  or `libglib`.
- Per-harness users, toolchains, configs, and entrypoints do NOT belong here.
  If two harnesses need the same new tool, that is the bar for adding it.
  Playwright Chromium cleared that bar (cecli-node advertised it; agents run
  browser e2e against mounted workspaces).

It is not a runnable harness: no `harness.manifest`, no entrypoint. It is a
mise build/deploy target (`mise build base`) like the sidecar images.
