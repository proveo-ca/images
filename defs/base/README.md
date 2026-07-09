# base

`proveo/base` is the shared floor for every Node-based harness image
(claudecode, opencode, cursor, cecli-node): `node:22-slim` plus the common
apt set (`git gh curl ca-certificates python3 dumb-init`), pnpm, common env,
and the baked `/usr/local/sbin/proveo-harden` pass (setuid/setgid strip +
raw-network-tool removal).

Why it exists (structural size work): before this base, each harness carried
its own copy of these layers on a slightly different parent (`node:20` vs
`node:22`), so nothing was shared — a consumer pulling two harnesses
downloaded the same ~350 MB twice. With one base, registries and consumer
machines store the common layers once; each harness image is only its delta.

Rules:

- Harness Dockerfiles start with `ARG BASE_IMAGE=proveo/base:latest` +
  `FROM ${BASE_IMAGE}` (the ARG is the white-label / pinning seam).
- Any harness layer that `apt-get install`s extras must end with
  `/usr/local/sbin/proveo-harden` — new packages can reintroduce setuid bits.
- Harness `build.sh` scripts call `defs/base/ensure.sh` first (present →
  pull → build), so a lone `mise build cursor` works on a clean machine.
- Per-harness users, toolchains, configs, and entrypoints do NOT belong here.
  If two harnesses need the same new tool, that is the bar for adding it.

It is not a runnable harness: no `harness.manifest`, no entrypoint. It is a
mise build/deploy target (`mise build base`) like the sidecar images.
