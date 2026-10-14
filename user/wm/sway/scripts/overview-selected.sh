#!/bin/sh
# Wrapper of the Hyper+Shift+Q/W/1-0 move bindings: while the sway-apps overview is open
# it holds the selected con_id in this file, and the move acts on THAT window (focus it,
# then run the command). Closed = no file = one `test -s`, then exec. Not used on the
# workspace switches: with workspace_auto_back_and_forth, focusing a window already on
# the target made "workspace N" jump back (measured live on DESK, 2026-10-14).
f="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sway-apps-overview.sel"
if [ -s "$f" ]; then
  id=
  read -r id < "$f" || true   # read fails at EOF without a newline but still sets id
  case "$id" in
    '' | *[!0-9]*) ;;
    *) swaymsg -q "[con_id=$id] focus" ;;
  esac
fi
exec "$@"
