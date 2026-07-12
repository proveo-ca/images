# SPEC: _spec/components.puml
# proveo/base-node-browser — proveo/base-node-lsp + Playwright and a Chromium
# browser (plus its OS deps), so browser-capable Node harnesses (and the
# cursor-browser variant) can drive a real browser. Kept OUT of base-node-lsp so
# non-browser Node consumers don't carry the ~1GB browser floor. Chromium is
# installed once here and shared by every *-browser variant built FROM this image.
ARG BASE_IMAGE=proveo/base-node-lsp:latest
FROM ${BASE_IMAGE}

# Pin the Playwright version so the CLI/driver and the installed browser stay in
# lockstep (a mismatch yields "can't locate browser executables"). Override at
# build time to track a project's Playwright version.
ARG PLAYWRIGHT_VERSION=1.61.0

# Shared, world-readable browser store so the arbitrary run-as uid can launch
# Chromium (the harness never runs as root). A repo-local Playwright honors the
# same env var, so `npx playwright install` in a mounted repo reuses this store.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright

# `playwright install --with-deps chromium` pulls Chromium + its ~150 apt OS libs.
# Install as root into the shared path, make it world-readable, then re-run the
# scoped harden (apt may reintroduce setuid bits — note this strips Chromium's
# setuid sandbox helper, so agents must launch Chromium with --no-sandbox, which
# is the standard container posture anyway).
RUN npm install -g --no-optional "playwright@${PLAYWRIGHT_VERSION}" \
    && playwright install --with-deps chromium \
    && chmod -R a+rX "$PLAYWRIGHT_BROWSERS_PATH" \
    && npm cache clean --force \
    && rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/* \
    && /usr/local/sbin/proveo-harden /usr /opt

LABEL security.hardened=true \
      org.opencontainers.image.title="proveo harness base (node + LSP + Playwright/Chromium)"
