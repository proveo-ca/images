# SPEC: _spec/components.puml
# proveo/base — the shared floor every Node-based harness image builds FROM:
ARG PLAYWRIGHT_IMAGE=mcr.microsoft.com/playwright:v1.61.1-noble
FROM ${PLAYWRIGHT_IMAGE}

ARG PLAYWRIGHT_VERSION=1.61.1

# Hardening is a callable script (see its header): base runs it here, and every
# harness apt layer re-runs `proveo-harden` after installing extras.
COPY defs/base/proveo-harden /usr/local/sbin/proveo-harden

# MCR playwright already ships Node, git, ca-certificates, and Chromium/Firefox/
# WebKit with their Ubuntu OS libs under PLAYWRIGHT_BROWSERS_PATH=/ms-playwright.
# Add the harness floor extras that are not in that image.
RUN chmod +x /usr/local/sbin/proveo-harden \
    && apt-get update && apt-get install -y --no-install-recommends \
       gh python3 dumb-init \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && /usr/local/sbin/proveo-harden

# Global CLI matching the image tag so `playwright` resolves the baked browsers.
# Browsers stay world-readable for non-root runtime users (and project-local
# installs that honor PLAYWRIGHT_BROWSERS_PATH).
ENV DEBIAN_FRONTEND=noninteractive \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    RLIMIT_CORE=0 \
    RLIMIT_NOFILE=1024 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

RUN npm install -g pnpm@10.33.0 "playwright@${PLAYWRIGHT_VERSION}" \
    && chmod -R a+rX /ms-playwright \
    && npm cache clean --force \
    && /usr/local/sbin/proveo-harden

LABEL security.hardened=true \
      org.opencontainers.image.title="proveo harness base"
