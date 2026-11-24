# Deploy and Host an Ubuntu Dev Box on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/ubuntu-dev-box?referralCode=sLjDXb&utm_medium=integration&utm_source=button&utm_campaign=ubuntu-dev-box)

This template gives you an always-on Ubuntu 26.04 dev box with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and the [OpenAI Codex CLI](https://github.com/openai/codex) pre-installed. Open your Railway domain for a terminal in the browser, or SSH in through Railway's TCP proxy. Both land in the same `tmux` session, so a job you start from your laptop is still running when you reconnect from your phone. Your home directory lives on a volume, so repos, agent logins, GitHub auth and dotfiles survive every redeploy.

## About Hosting an Ubuntu Dev Box

One service, one volume. The image ships `claude`, `codex`, `git`, `gh`, Node 24, Python 3 + `uv`, `tmux`, `ripgrep`, `jq`, `vim`, build tools and an OpenSSH server. A `ttyd` web terminal (basic-auth gated) and `sshd` (password or key) both drop you into the same `tmux` session. SSH host keys are stored on the volume, so your client never sees a "host key changed" warning after a redeploy. Both agents are optional: the box is a plain Ubuntu shell until you sign one in.

## Common Use Cases

- Run Claude Code or Codex 24/7 on a task without keeping your laptop open
- Code from an iPad, Chromebook or phone: the browser terminal needs no SSH client
- A remote dev machine for VS Code Remote-SSH, Cursor or any editor that speaks SSH
- Keep a persistent workspace for side projects that is reachable from anywhere

## Dependencies for Ubuntu Dev Box Hosting

- None. Single service, no database.

### Deployment Dependencies

- [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code)
- [Codex CLI](https://github.com/openai/codex) and [its docs](https://developers.openai.com/codex)
- [ttyd](https://github.com/tsl0922/ttyd) web terminal
- [GitHub CLI](https://cli.github.com/)

### Implementation Details

**First use:** open your Railway domain and log in with `WEB_USER` and the generated `WEB_PASSWORD` (service Variables tab). You are in a `tmux` session named `main`; close the tab, reopen it, and everything is still there.

**SSH:** Railway creates a TCP proxy for port 22 on deploy. Copy the host and port from Settings → Networking and run `ssh root@<host> -p <port>` with `ROOT_PASSWORD`, or add your public key to `AUTHORIZED_KEYS` and clear `ROOT_PASSWORD` for key-only login.

**Sign the agents in** (either, both or neither):

- **Claude Code:** run `claude` and complete `/login` by pasting the URL into a browser. Or set `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token` on your own machine) or `ANTHROPIC_API_KEY` as a service variable.
- **Codex:** run `codex login --device-auth`, open the URL it prints on any device and enter the code. Or set `OPENAI_API_KEY` as a service variable; the box saves it as Codex's login on every boot.

**Handy commands inside the box:**

- `cl` and `cx` start Claude Code and Codex inside detachable `tmux` sessions named `claude` and `codex`; `tmux attach -t claude` resumes one
- `gh auth login` or set `GH_TOKEN` to push to GitHub
- `apt install <pkg>` works (you are root); anything outside `/root` is gone after a redeploy

Notes and limits:

- You are root. Anything you install outside `/root` disappears on redeploy; anything under `/root` stays. New Claude Code and Codex versions arrive as template updates.
- 0.5 GB of RAM runs the shell and an idle agent; give the service 1 GB or more when an agent builds Node or Python projects.
- Codex's own command sandbox (bubblewrap) cannot start in Railway's container, so the box writes `sandbox_mode = "danger-full-access"` to `~/.codex/config.toml` on first boot: Codex runs commands directly, and the container is the boundary. Edit that file to change it; it is never overwritten.
- There is no Docker daemon inside the box.
- The web terminal password is the whole security model for a root shell. Keep it strong and do not share the URL.

## Why Deploy an Ubuntu Dev Box on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying an Ubuntu dev box on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
