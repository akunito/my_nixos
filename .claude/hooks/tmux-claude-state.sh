#!/bin/sh
# tmux-claude-state.sh STATE — Claude Code hook (OpenCode too, via user/app/opencode/plugins/tmux-state.js): stores
# busy|ask|wait|done in the tmux pane option @claude, which the tab pills (user/app/terminal/tmux.nix) turn into an
# icon, and the hook's session_id in @claude_session (read by the resurrect sidecar, docs/akunito/plans/tmux-session-persistence.md).
# Claude's pane title stays "✳ …" while it works (sampled mid-tool-call 2026-10-15) and tmux 3.6 ignores OSC 9;4
# progress, so hooks are the only signal. Runs in every live session on every tool call (3 s timeout): never block,
# never write to stdout, always exit 0. Manual run: echo '{}' | tmux-claude-state.sh busy
# wait only replaces busy: the 60 s idle Notification after Stop must not turn "done" into "needs you", nor "ask".
# done/wait on the tab already in view are dropped (read); visiting a tab later clears them (hook in tmux.nix); ask
# stays until the next event even in view.
[ -n "$TMUX_PANE" ] || exit 0
if [ -t 0 ]; then in=; else in=$(cat 2>/dev/null); fi
sid=$(printf '%s' "$in" | jq -r '.session_id // empty' 2>/dev/null) || sid=
case "$sid" in ????????-????-????-????-????????????) ;; *) sid= ;; esac
if [ -n "$sid" ] && [ "$(tmux show -pqv -t "$TMUX_PANE" @claude_session 2>/dev/null)" != "$sid" ]; then
  tmux set -p -t "$TMUX_PANE" @claude_session "$sid" 2>/dev/null
fi
cur=$(tmux show -pqv -t "$TMUX_PANE" @claude 2>/dev/null)
case "$1" in
  clear) tmux set -pu -t "$TMUX_PANE" @claude 2>/dev/null; tmux set -pu -t "$TMUX_PANE" @claude_session 2>/dev/null ;;
  start)
    # Session (re)started: no icon yet; a debounced save records the new id (no-op until @save-debounced exists).
    tmux set -pu -t "$TMUX_PANE" @claude 2>/dev/null
    d=$(tmux show -gqv @save-debounced 2>/dev/null); [ -n "$d" ] && tmux run-shell -b "$d" 2>/dev/null ;;
  done|wait)
    if [ "$(tmux display -p -t "$TMUX_PANE" '#{&&:#{window_active},#{session_attached}}' 2>/dev/null)" = 1 ]; then
      tmux set -pu -t "$TMUX_PANE" @claude 2>/dev/null
    elif [ "$1" = done ] || [ "$cur" = busy ]; then
      tmux set -p -t "$TMUX_PANE" @claude "$1" 2>/dev/null
    else exit 0; fi ;;
  busy|ask)
    [ "$cur" = "$1" ] && exit 0
    tmux set -p -t "$TMUX_PANE" @claude "$1" 2>/dev/null ;;
  *) exit 0 ;;
esac
tmux list-clients -F '#{client_name}' 2>/dev/null | while read -r c; do tmux refresh-client -S -t "$c"; done
exit 0
