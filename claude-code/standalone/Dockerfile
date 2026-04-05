FROM node:20-bookworm-slim

# Security: Use specific user ID and avoid conflicts
ARG USER_ID=1001
ARG USER_NAME=claude

# Create non-root user with specific UID/GID
RUN groupadd -g ${USER_ID} ${USER_NAME} && \
    useradd -m -u ${USER_ID} -g ${USER_ID} -s /bin/bash ${USER_NAME}

# Install system dependencies with security hardening
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget ca-certificates python3 python3-pip build-essential \
    dumb-init \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/* \
    && find / -xdev -perm -4000 -type f -exec chmod u-s {} \; 2>/dev/null || true \
    && find / -xdev -perm -2000 -type f -exec chmod g-s {} \; 2>/dev/null || true \
    && rm -f /usr/bin/nc /usr/bin/netcat /bin/netstat /usr/bin/ss || true

# Install basic Python tools
RUN pip3 install --no-cache-dir --break-system-packages \
    requests \
    python-dotenv

# Install Python security tools
RUN pip3 install --no-cache-dir --break-system-packages \
    semgrep \
    solc-select

# Setup solc-select with a default Solidity compiler
RUN solc-select install 0.8.20 && solc-select use 0.8.20

# Install Node.js tools
RUN npm install -g --no-optional \
    typescript \
    ts-node \
    prettier \
    eslint \
    solhint

# Install Foundry (Solidity toolkit)
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:$PATH"
RUN /root/.foundry/bin/foundryup
RUN cp -r /root/.foundry /home/${USER_NAME}/ && chown -R ${USER_NAME}:${USER_NAME} /home/${USER_NAME}/

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Setup secure workspace with proper permissions
RUN mkdir -p /workspace/input \
    && mkdir -p /workspace/output \
    && mkdir -p /workspace/data \
    && mkdir -p /workspace/temp \
    && mkdir -p /workspace/mcp-servers \
    && mkdir -p /workspace/.claude \
    && mkdir -p /home/${USER_NAME}/.claude \
    && chown -R ${USER_NAME}:${USER_NAME} /workspace /home/${USER_NAME}/.claude \
    && chmod 755 /workspace \
    && chmod 750 /workspace/input \
    && chmod 750 /workspace/data \
    && chmod 755 /workspace/output \
    && chmod 755 /workspace/temp \
    && chmod 755 /workspace/mcp-servers

# Copy Claude configuration directly into final locations
COPY --chown=${USER_NAME}:${USER_NAME} claude-config.json /home/${USER_NAME}/.claude.json
COPY --chown=${USER_NAME}:${USER_NAME} settings.local.json /home/${USER_NAME}/.claude/settings.local.json
COPY --chown=${USER_NAME}:${USER_NAME} settings.local.json /workspace/.claude/settings.local.json

# Switch to non-root user for security
USER ${USER_NAME}
WORKDIR /workspace
ENV PATH="/home/${USER_NAME}/.foundry/bin:$PATH"

# Create simple startup script for runtime
RUN echo '#!/bin/bash\n\
set -e\n\
echo "Starting Claude Code..."\n\
exec claude --dangerously-skip-permissions "$@"\n\
' > /home/${USER_NAME}/start-claude.sh \
    && chmod +x /home/${USER_NAME}/start-claude.sh

# Security: Set secure environment variables and limits
ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    RLIMIT_CORE=0 \
    RLIMIT_NOFILE=1024 \
    YAMA_PTRACE_SCOPE=1

# Add security labels
LABEL security.non-root=true \
      security.hardened=true \
      security.version="1.0"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD test -f /home/claude/.claude.json && test -f /home/claude/.claude/settings.local.json || exit 1

# Security: Use dumb-init for proper signal handling and process reaping
ENTRYPOINT ["dumb-init", "--", "/home/claude/start-claude.sh"]
