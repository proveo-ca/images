# SPEC: _spec/components.puml
# proveo/base — the shared floor every Node-based harness image builds FROM:
# one common apt layer (git/gh/curl/python3/dumb-init), one pnpm layer, one
# Playwright Chromium + OS deps layer, one baked hardening pass. Registries
# and consumer machines then store/download these layers ONCE across harnesses
# instead of per image. Per-harness users, toolchains, configs, and entrypoints
# stay in the harness Dockerfiles.
#
# Build context is the repo root:
#   docker build -f defs/base/Dockerfile -t proveo/base:latest .
FROM node:22-slim

# Hardening is a callable script (see its header): base runs it here, and every
# harness apt layer re-runs `proveo-harden` after installing extras.
COPY defs/base/proveo-harden /usr/local/sbin/proveo-harden

RUN chmod +x /usr/local/sbin/proveo-harden \
    && apt-get update && apt-get install -y --no-install-recommends \
       git gh curl ca-certificates python3 dumb-init \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && /usr/local/sbin/proveo-harden

RUN npm install -g pnpm@10.33.0 && npm cache clean --force

# Shared Playwright floor for every Node harness: global CLI + Chromium and its
# Debian deps, browsers in a world-readable path so non-root runtime users
# (and project-local playwright installs that honor PLAYWRIGHT_BROWSERS_PATH)
# can launch without re-downloading. Re-run harden after --with-deps apt work.
ENV DEBIAN_FRONTEND=noninteractive \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    RLIMIT_CORE=0 \
    RLIMIT_NOFILE=1024 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

RUN npm install -g playwright \
    && npx playwright install --with-deps chromium \
    && chmod -R a+rX /ms-playwright \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && /usr/local/sbin/proveo-harden

LABEL security.hardened=true \
      org.opencontainers.image.title="proveo harness base"
