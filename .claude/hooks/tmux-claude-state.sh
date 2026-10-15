#!/bin/sh
# tmux-claude-state.sh STATE — Claude Code hook: stores busy|wait|done|clear in the tmux pane option @claude,
# which the tab pills (user/app/terminal/tmux.nix) turn into an icon. Claude's pane title stays "✳ …" while it
# works (sampled mid-tool-call 2026-10-15) and tmux 3.6 ignores OSC 9;4 progress, so hooks are the only signal.
# wait only replaces busy: the 60 s idle Notification after Stop must not turn "done" into "needs you".
# done/wait on the tab already in view is dropped (read); visiting a tab later clears it (hook in tmux.nix).
[ -n "$TMUX_PANE" ] || exit 0
cat >/dev/null
case "$1" in
  clear) tmux set -pu -t "$TMUX_PANE" @claude 2>/dev/null ;;
  done|wait)
    # Already on screen = already read (the session-window-changed hook in tmux.nix clears it on later visits).
    if [ "$(tmux display -p -t "$TMUX_PANE" '#{&&:#{window_active},#{session_attached}}' 2>/dev/null)" = 1 ]; then
      tmux set -pu -t "$TMUX_PANE" @claude 2>/dev/null
    elif [ "$1" = done ] || [ "$(tmux show -pqv -t "$TMUX_PANE" @claude 2>/dev/null)" = busy ]; then
      tmux set -p -t "$TMUX_PANE" @claude "$1" 2>/dev/null
    else exit 0; fi ;;
  *) [ "$(tmux show -pqv -t "$TMUX_PANE" @claude 2>/dev/null)" = "$1" ] && exit 0
     tmux set -p -t "$TMUX_PANE" @claude "$1" 2>/dev/null ;;
esac
tmux list-clients -F '#{client_name}' 2>/dev/null | while read -r c; do tmux refresh-client -S -t "$c"; done
exit 0
