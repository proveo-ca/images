FROM node:22-slim AS node-tools
RUN corepack enable

# https://github.com/Aider-AI/aider/blob/main/docker/Dockerfile
FROM paulgauthier/aider-full AS aider

USER root

COPY --from=node-tools /usr/local/bin/ /usr/local/bin/
COPY --from=node-tools /usr/local/lib/node_modules/ /usr/local/lib/node_modules/

RUN chown -R appuser:appuser /usr/local/bin /usr/local/lib/node_modules

ENV PATH="/usr/local/bin:${PATH}"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER appuser
ENTRYPOINT ["/entrypoint.sh"]
