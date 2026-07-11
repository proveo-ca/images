# SPEC: _spec/components.puml
# proveo/base — the MINIMAL shared floor every harness image builds FROM.
# Only the universally-shared pieces live here: git, gh, ca-certs, curl, jq,
# dumb-init, bash, the proveo-entrypoint binary, and the proveo-harden pass.
# jq is the universal JSON tool for entrypoint config munging (no language
# runtime needed for a config edit).
# NO language runtime (Node/Python) and NO browsers — those are not universal
# (cursor needs neither; cecli is Python; opencode/claudecode are Node), so they
# live in thin per-runtime layers (proveo/base-node) or are installed on demand.
# This keeps the floor ~200MB instead of the multi-GB Playwright browser image
# it used to inherit.

# Single builder for proveo-entrypoint; every harness inherits it from here
# instead of recompiling it in its own stage. Context is the repo root.
FROM golang:1.26-bookworm AS proveo-entrypoint-builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/proveo-entrypoint ./cmd/proveo-entrypoint

FROM debian:bookworm-slim

COPY defs/base/proveo-harden /usr/local/sbin/proveo-harden
COPY --from=proveo-entrypoint-builder /out/proveo-entrypoint /usr/local/bin/proveo-entrypoint

# Universal harness floor. `gh` is not in Debian's default repos, so add the
# official GitHub CLI apt source (its published keyring is already dearmored, so
# no gnupg needed). Everything is cleaned in-layer; one harden pass.
RUN chmod +x /usr/local/sbin/proveo-harden /usr/local/bin/proveo-entrypoint \
    && apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
         -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
         > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends \
       git gh bash dumb-init passwd jq \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && /usr/local/sbin/proveo-harden

ENV DEBIAN_FRONTEND=noninteractive \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    RLIMIT_CORE=0 \
    RLIMIT_NOFILE=1024 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

LABEL security.hardened=true \
      org.opencontainers.image.title="proveo harness base"
