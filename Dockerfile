FROM ubuntu:26.04

# upgrade: npm @anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.330
# upgrade: npm @openai/codex
ARG CODEX_VERSION=0.171.0

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 PORT=7681

# Base toolbox: shell tools, ssh server, ttyd web terminal, build deps, Node 24.
# nginx `worker_processes auto` counts host cores, not the container quota
# (48 on Railway Metal hosts), so pin it to 2.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg git openssh-server ttyd nginx-light tmux \
      vim nano less htop ripgrep jq bubblewrap unzip zip tree procps sudo locales \
      python3 python3-pip python3-venv build-essential \
      iputils-ping dnsutils net-tools \
  && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends nodejs gh \
  && npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" "@openai/codex@${CODEX_VERSION}" \
  && npm cache clean --force \
  && curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh \
  && mkdir -p /run/sshd \
  && sed -i 's/^worker_processes .*/worker_processes 2;/' /etc/nginx/nginx.conf \
  && grep -q '^worker_processes 2;' /etc/nginx/nginx.conf \
  && claude --version && codex --version \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Skeleton for the persistent home (the volume mounts empty at /root on first boot).
COPY skel/ /opt/skel/
COPY entrypoint.sh /entrypoint.sh
COPY drop-file-cache /usr/local/bin/drop-file-cache
RUN chmod +x /entrypoint.sh /usr/local/bin/drop-file-cache

EXPOSE 22 7681
ENTRYPOINT ["/entrypoint.sh"]
