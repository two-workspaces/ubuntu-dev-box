# ~/.bashrc — persisted on the Railway volume. Edit freely.
[ -z "$PS1" ] && return
export PATH="$HOME/.local/bin:$PATH"
export EDITOR=vim
alias ll='ls -alF'
PS1='\[\e[1;32m\]\u@dev-box\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
# `cl` / `cx` = Claude Code / Codex inside a tmux session that survives disconnects.
cl() { tmux new -A -s claude "claude $*"; }
cx() { tmux new -A -s codex "codex $*"; }
[ -f ~/.motd ] && cat ~/.motd
