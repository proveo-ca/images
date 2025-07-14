FROM node:22-slim AS node-tools
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN corepack enable
RUN corepack use pnpm@latest-10
RUN npm install -g playwright
RUN npx playwright install chromium

# https://github.com/Aider-AI/aider/blob/main/docker/Dockerfile
FROM paulgauthier/aider-full AS aider

USER root

COPY --from=node-tools /usr/local/bin/ /usr/local/bin/
COPY --from=node-tools /usr/local/lib/node_modules/ /usr/local/lib/node_modules/
COPY --from=node-tools /root/.cache/ms-playwright/ /home/appuser/.cache/ms-playwright/

RUN chown -R appuser:appuser /usr/local/bin /usr/local/lib/node_modules /usr/bin/curl /home/appuser/.cache/ms-playwright/

ENV PATH="/usr/local/bin:${PATH}"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER appuser
ENTRYPOINT ["/entrypoint.sh"]
