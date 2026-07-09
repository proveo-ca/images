# dind sidecar

Docker-in-Docker is a **sidecar only** — never a runnable harness target.

Unlike `mitmproxy` (a custom `proveo/mitmproxy` image built from this tree) it
has **no image definition to build**: it runs straight from the public
`docker:dind` image. The harness runner provisions it on demand — see the
sibling-DinD block in `apps/cli/public/cli/lib/runners.sh`, which launches a
privileged `docker:dind` container, links it to a DinD-capable harness
(e.g. `opencode`, `cursor`), and tears it down on exit.

This directory exists so `defs/sidecars/` is the single home for every sidecar
in the topology (egress proxies + dind), even the ones that ship no Dockerfile.
