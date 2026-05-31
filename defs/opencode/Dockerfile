FROM golang:1.22-bookworm AS plantuml-lsp-builder

RUN GOBIN=/out go install github.com/ptdewey/plantuml-lsp@latest

FROM node:22-slim

ARG USER_ID=1000
ARG USER_NAME=opencode

# node images already include uid/gid 1000 as node:node. Reuse that uid by
# renaming the existing account so host-owned files remain writable by opencode.
RUN if getent passwd "${USER_ID}" >/dev/null; then \
      existing_user="$(getent passwd "${USER_ID}" | cut -d: -f1)"; \
      existing_group="$(getent group "${USER_ID}" | cut -d: -f1)"; \
      if [ "${existing_group}" != "${USER_NAME}" ]; then \
        groupmod -n "${USER_NAME}" "${existing_group}"; \
      fi; \
      if [ "${existing_user}" != "${USER_NAME}" ]; then \
        usermod -l "${USER_NAME}" -d "/home/${USER_NAME}" -m "${existing_user}"; \
      fi; \
      usermod -s /bin/bash "${USER_NAME}"; \
    else \
      groupadd -g "${USER_ID}" "${USER_NAME}" && \
      useradd -m -u "${USER_ID}" -g "${USER_ID}" -s /bin/bash "${USER_NAME}"; \
    fi
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates dumb-init unzip xclip python3 plantuml \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && find / -xdev -perm -4000 -type f -exec chmod u-s {} \; 2>/dev/null || true \
    && find / -xdev -perm -2000 -type f -exec chmod g-s {} \; 2>/dev/null || true \
    && rm -f /usr/bin/nc /usr/bin/netcat /bin/netstat /usr/bin/ss || true

RUN npm install -g pnpm@10.33.0

RUN npm install -g \
    opencode-ai@latest \
    typescript-language-server \
    vscode-langservers-extracted \
    bash-language-server \
    dockerfile-language-server-nodejs \
    yaml-language-server \
    pyright

COPY --from=plantuml-lsp-builder /out/plantuml-lsp /usr/local/bin/plantuml-lsp

RUN mkdir -p /workspace \
             /home/${USER_NAME}/.config/opencode \
             /home/${USER_NAME}/.local/share/opencode \
             /opt/opencode/defaults \
    && chown -R ${USER_NAME}:${USER_NAME} /workspace /home/${USER_NAME}

# Pre-baked defaults (config + subagents). Seeded into ~/.config/opencode on first run
# by entrypoint.sh, or re-seeded when OPENCODE_RESEED=1.
COPY defaults/ /opt/opencode/defaults/
COPY sample_opencode.json /opt/opencode/sample_opencode.json

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER ${USER_NAME}
WORKDIR /workspace

ENV DEBIAN_FRONTEND=noninteractive \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    RLIMIT_CORE=0 \
    RLIMIT_NOFILE=1024 \
    OPENCODE_AUTO_UPDATE=false \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    PATH="/usr/local/bin:${PATH}"

LABEL security.non-root=true \
      security.hardened=true \
      security.version="1.0"

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD opencode --version >/dev/null 2>&1 || exit 1

ENTRYPOINT ["dumb-init", "--", "/entrypoint.sh"]
