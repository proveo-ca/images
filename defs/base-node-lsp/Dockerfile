# SPEC: _spec/components.puml
# proveo/base-node-lsp — proveo/base-node + the workspace language servers the
# shared LSP detector (packages/lib/entrypoint-lib.sh §8) can run in a Node
# image. Kept OUT of base-node so non-LSP Node consumers don't carry servers
# they never use. Shared by the LSP-capable Node harnesses (opencode, claudecode).
ARG BASE_IMAGE=proveo/base-node:latest
FROM ${BASE_IMAGE}

# Language servers matching _lsp_server() in the shared detector. Node + pnpm
# come from base-node. vscode-langservers-extracted provides the json/html/css
# servers. Re-run the scoped harden after installing into /usr and /opt.
RUN npm install -g --no-optional \
    typescript-language-server \
    vscode-langservers-extracted \
    bash-language-server \
    dockerfile-language-server-nodejs \
    yaml-language-server \
    pyright \
    && npm cache clean --force \
    && rm -rf /tmp/* /var/tmp/* \
    && /usr/local/sbin/proveo-harden /usr /opt

LABEL security.hardened=true \
      org.opencontainers.image.title="proveo harness base (node + LSP servers)"
