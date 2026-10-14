#!/bin/sh
# Wrapper of the Hyper+Q/W/1-0 (+Shift) workspace bindings: while the sway-apps overview
# is open it holds the selected con_id in this file, and the binding acts on THAT window
# (focus it, then run the command). Closed = no file = one `test -s`, then exec.
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
