FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    CHARLES_HOME=/var/lib/charles \
    CHARLES_CONFIG=/config/com.xk72.Charles.config

# deps + charles repo
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
  install -d -m 0755 /etc/apt/keyrings; \
  curl -fsSL https://www.charlesproxy.com/packages/apt/PublicKey \
    | gpg --dearmor -o /etc/apt/keyrings/charles.gpg; \
  chmod 0644 /etc/apt/keyrings/charles.gpg; \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/charles.gpg] https://www.charlesproxy.com/packages/apt/ charles-proxy main" \
    > /etc/apt/sources.list.d/charles.list; \
  apt-get update; \
  apt-get install -y --no-install-recommends charles-proxy5; \
  apt-get purge -y gnupg; apt-get autoremove -y; \
  rm -rf /var/lib/apt/lists/*

# non-root
RUN useradd -m -d ${CHARLES_HOME} -s /bin/bash charles \
 && install -d -m 0755 -o charles -g charles ${CHARLES_HOME} /sessions
USER charles

VOLUME ["/sessions", "/config"]
EXPOSE 8888

CMD ["/bin/bash","-lc","echo \"✅ PROVEO_SMOKE_READY ${PROVEO_SMOKE_TARGET:-charles-proxy}\"; \
 if [ \"${PROVEO_SMOKE_TEST:-0}\" = \"1\" ]; then exec sleep infinity; fi; \
 [ -f \"$CHARLES_CONFIG\" ] \
 && exec charles -headless -config \"$CHARLES_CONFIG\" \
 || exec charles -headless"]
