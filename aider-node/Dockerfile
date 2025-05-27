FROM ghcr.io/tarampampam/curl AS curl-static
FROM node:22-slim AS node-tools

RUN corepack enable && corepack use pnpm@latest-10
RUN npm i -g playwright && npx playwright install --with-deps chromium

# https://github.com/Aider-AI/aider/blob/main/docker/Dockerfile
FROM paulgauthier/aider-full AS aider

USER root

COPY --from=curl-static /bin/curl /usr/local/bin/curl
COPY --from=node-tools /usr/local/bin/ /usr/local/bin/
COPY --from=node-tools /usr/local/lib/node_modules/ /usr/local/lib/node_modules/
COPY --from=node-tools /root/.cache/ms-playwright/ /home/appuser/.cache/ms-playwright/

RUN chown -R appuser:appuser /usr/local/bin /usr/local/lib/node_modules /home/appuser/.cache/ms-playwright/

# Install xclip for clipboard support
RUN apt-get update && apt-get install -y xclip && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/bin:${PATH}"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER appuser

ENTRYPOINT ["/entrypoint.sh"]
