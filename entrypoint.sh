#!/bin/bash
# Never exits on a bad variable or a full volume: each step logs and falls back, so a
# typo or a cleared password can't leave the service crash-looping (Railway then marks
# the deploy CRASHED). The web terminal is never served without a login.
log() { echo "railway: $*"; }

# Railway's healthcheck probes $PORT, so nginx always listens there; the other ports
# step aside instead (ttyd's internal port, and sshd if PORT is 22).
case "${PORT:-}" in
  ''|*[!0-9]*) log "PORT='${PORT:-}' is not a number, using 7681"; PORT=7681 ;;
esac
export PORT
TTYD_PORT=7682
[ "$PORT" = 7682 ] && TTYD_PORT=7683

# /root is a Railway volume: empty on first boot, root-owned. Seed dotfiles once
# (flag file, not per-file checks: local docker pre-copies the image's /root into a
# fresh volume, which would otherwise shadow our skel).
if [ ! -f /root/.dev-box-seeded ]; then
  cp -af /opt/skel/. /root/ && touch /root/.dev-box-seeded
fi
# Dotfiles added to skel later reach existing volumes; edited ones are kept.
cp -an /opt/skel/. /root/ 2>/dev/null || true
mkdir -p /root/.ssh /root/src && chmod 700 /root/.ssh || log "warning: can't write /root (is the volume full?)"

# Persist SSH host keys on the volume so clients don't see "host key changed" after redeploys.
mkdir -p /root/.ssh-host
for t in rsa ed25519; do
  if [ -s "/root/.ssh-host/ssh_host_${t}_key" ] || ssh-keygen -q -t "$t" -N '' -f "/root/.ssh-host/ssh_host_${t}_key" </dev/null; then
    cp -f "/root/.ssh-host/ssh_host_${t}_key" "/root/.ssh-host/ssh_host_${t}_key.pub" /etc/ssh/
  else
    # Volume full or read-only: a host key for this boot only, so sshd still starts.
    log "warning: can't keep the $t SSH host key on the volume, using one for this boot"
    rm -f "/etc/ssh/ssh_host_${t}_key" "/etc/ssh/ssh_host_${t}_key.pub"
    ssh-keygen -q -t "$t" -N '' -f "/etc/ssh/ssh_host_${t}_key" </dev/null
  fi
  chmod 600 "/etc/ssh/ssh_host_${t}_key"
done

# Root login: password from ROOT_PASSWORD, optional keys from AUTHORIZED_KEYS.
if [ -n "${ROOT_PASSWORD:-}" ]; then
  printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd || log "warning: ROOT_PASSWORD could not be set (one line, no newlines)"
fi
if [ -n "${AUTHORIZED_KEYS:-}" ]; then
  { printf '%s\n' "$AUTHORIZED_KEYS" > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys; } \
    || log "warning: can't write /root/.ssh/authorized_keys (is the volume full?)"
fi
mkdir -p /run/sshd /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/railway.conf <<CFG
Port 22
ListenAddress 0.0.0.0
ListenAddress ::
PermitRootLogin yes
PasswordAuthentication $([ -n "${ROOT_PASSWORD:-}" ] && echo yes || echo no)
ClientAliveInterval 60
CFG
if [ "$PORT" = 22 ]; then
  log "PORT is 22, which SSH uses: the web terminal takes it and sshd is not started"
else
  /usr/sbin/sshd || log "warning: sshd did not start; the web terminal still works"
fi

# Make service variables visible to SSH sessions too (sshd strips the environment).
env | grep -E '^(ANTHROPIC_|CLAUDE_|OPENAI_|CODEX_|GH_TOKEN|GITHUB_TOKEN|TZ|PORT)' \
  | sed 's/^/export /; s/=/="/; s/$/"/' > /etc/profile.d/railway-env.sh || true

# Small plans (Free 0.5 GB, Trial 1 GB) cap the whole service's memory. A busy agent
# session (or the Node build it runs) grows past that and the kernel OOM-kills it, which
# Railway counts as a failed deploy. Cap Node's heap at 60% of the limit there, so V8
# collects garbage harder instead. Services over 2 GB, or with NODE_OPTIONS set, keep
# the default.
mem=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo max)
case "$mem" in ''|*[!0-9]*) mem=max ;; esac
if [ -z "${NODE_OPTIONS:-}" ] && [ "$mem" != max ] && [ "$mem" -le $((2 * 1024 * 1024 * 1024)) ]; then
  heap=$((mem * 6 / 10 / 1024 / 1024))
  echo "export NODE_OPTIONS=\"--max-old-space-size=${heap}\"" >> /etc/profile.d/railway-env.sh
  export NODE_OPTIONS="--max-old-space-size=${heap}"
  log "memory limit $((mem / 1024 / 1024)) MB: capping Node's heap at ${heap} MB"
fi

# Codex's Linux sandbox (bubblewrap) needs user namespaces, which Railway's container
# runtime refuses ("bwrap: Creating new namespace failed: Permission denied"), so every
# sandboxed command would fail. The container is the sandbox here: give Codex full
# access inside it. Written only when there is no config yet, so edits stick.
if mkdir -p /root/.codex && [ ! -f /root/.codex/config.toml ]; then
  cat > /root/.codex/config.toml <<'TOML' || log "warning: can't write ~/.codex/config.toml (is the volume full?)"
# Written by the Railway template on first boot. Codex's own sandbox cannot start in
# Railway's container (no user namespaces), so it runs unsandboxed inside the box.
sandbox_mode = "danger-full-access"
approval_policy = "on-request"

# On first start Codex copies itself (424 MB) into ~/.codex/packages for its background
# app-server daemon. That copy takes about 1 GB of memory while it runs, so a 0.5 GB
# service kills Codex before it opens, and it nearly fills a 0.5 GB volume. Off here;
# set it to true on a bigger service if you use the daemon (remote control).
[features]
daemon_auto_start = false
TOML
fi

# OPENAI_API_KEY set: save it as Codex's login on every boot, so a changed key takes
# effect. A ChatGPT login done inside the box (tokens in auth.json) wins and is kept.
if [ -n "${OPENAI_API_KEY:-}" ] && ! grep -q '"tokens"' /root/.codex/auth.json 2>/dev/null; then
  if printenv OPENAI_API_KEY | timeout 30 codex login --with-api-key >/dev/null 2>&1; then
    log "codex signed in with OPENAI_API_KEY"
  else
    log "warning: codex login with OPENAI_API_KEY failed; sign in inside the box instead"
  fi
fi

# nginx on $PORT: unauthenticated /healthcheck for Railway, everything else to ttyd.
cat > /etc/nginx/sites-enabled/default <<CFG
server {
  listen ${PORT} default_server;
  listen [::]:${PORT} default_server;
  location = /healthcheck { return 200 "ok"; }
  location / {
    proxy_pass http://127.0.0.1:${TTYD_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_read_timeout 1d;
  }
}
CFG
nginx || log "error: nginx did not start on port $PORT"

# Railway counts the kernel's cache of files this container has touched as the
# service's memory, and with no memory pressure it is never freed: one npm
# install shows as hundreds of MB. Drop it for the home volume every 15 min.
( while sleep 900; do nice -n 19 drop-file-cache /root /tmp || true; done ) &

# Web terminal login. ttyd splits user:password at the first colon, so a user name
# can't hold one. An empty password gets a one-off one printed here, never open access.
web_user=$(printf '%s' "${WEB_USER:-}" | tr -d '[:space:]')
case "$web_user" in
  '') web_user=admin ;;
  *:*) log "WEB_USER may not contain ':', using 'admin'"; web_user=admin ;;
esac
web_pass=${WEB_PASSWORD:-}
if [ -z "$web_pass" ]; then
  web_pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=')
  log "WEB_PASSWORD is empty. A temporary password for this boot only: $web_pass"
  log "set the WEB_PASSWORD variable to keep one that survives restarts"
fi

echo "== dev-box ready: web terminal on :${PORT}, sshd on :22, claude $(claude --version 2>/dev/null), $(codex --version 2>/dev/null)"
# Web terminal: ttyd with basic auth, each tab attaches to the same tmux session, in ~.
cd /root
exec ttyd -i 127.0.0.1 -p "$TTYD_PORT" -W -c "$web_user:$web_pass" \
  -t titleFixed="dev-box" -t fontSize=14 \
  bash -lc 'exec tmux new -A -s main'
