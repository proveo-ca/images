# SPEC: _spec/components.puml
# proveo/base-node — proveo/base + a Node runtime. The shared layer for the Node
# harnesses (opencode, claudecode mcp/solo/sol). Node + pnpm live HERE, not in
# the universal base, so cursor and cecli don't carry a runtime they never use.
ARG BASE_IMAGE=proveo/base:latest
FROM ${BASE_IMAGE}

ARG NODE_MAJOR=22

# Node via the NodeSource apt repo (pinned major; the setup script adds the repo
# + runs apt-get update and pulls its own prereqs), then pnpm. Clean in-layer and
# re-harden only the prefixes touched.
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pnpm@10.33.0 \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && /usr/local/sbin/proveo-harden /usr /opt

LABEL security.hardened=true \
      org.opencontainers.image.title="proveo harness base (node)"
