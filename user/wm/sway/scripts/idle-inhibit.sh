#!/usr/bin/env bash
# idle-inhibit on|off|toggle|status [--json] [-q]
#
# The caffeine state IS swayidle.service: running = idle allowed, stopped = idle inhibited.
# Waybar's custom/idle widget, Hyper+Mute and agents all go through this command; the widget
# repaints from swayidle.service's own ExecStartPost/ExecStopPost (signal 8), so it shows the
# real state whoever starts or stops the unit. Waybar's built-in idle_inhibitor was dropped
# (2026-10-15): it kept its own flag, never saw Hyper+Mute or a CLI change, and came back
# "off" after every deploy restarted waybar while swayidle was still stopped.
set -u

SERVICE="swayidle.service"
SYSTEMCTL="/run/current-system/sw/bin/systemctl"
[[ -x "$SYSTEMCTL" ]] || SYSTEMCTL="$(command -v systemctl || true)"
NOTIFY="/run/current-system/sw/bin/notify-send"
[[ -x "$NOTIFY" ]] || NOTIFY="$(command -v notify-send || true)"

# Waybar and keybindings can run us with a minimal env: find the user bus.
if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$(id -u)" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
ICON=$'\xef\x83\xb4'   # U+F0F4 (nf coffee), both states; CSS colours the class

# The marker is what makes the choice survive a deploy: Home Manager's
# activation starts every unit wanted by an active target that is not running
# ("Starting units: swayidle.service ..." on every install.sh, X13 2026-09-22),
# and gamemode's end hook does a plain `start` too. swayidle.service carries
# `ConditionPathExists=!%t/idle-inhibit.on`, so those starts are skipped while
# the marker exists. %t = XDG_RUNTIME_DIR: gone at logout, like the intent.
MARKER="${runtime_dir}/idle-inhibit.on"

verb="${1:-status}"; shift || true
json=0; quiet=0
for a in "$@"; do
  case "$a" in --json) json=1 ;; -q|--quiet) quiet=1 ;; esac
done

# activating/reloading count as running: ExecStartPost repaints the widget while the unit is
# still "activating"; "deactivating" (ExecStopPost) already means inhibited.
inhibited() {
  local s
  s="$("$SYSTEMCTL" --user show -p ActiveState --value "$SERVICE" 2>/dev/null || true)"
  case "$s" in active|activating|reloading) return 1 ;; *) return 0 ;; esac
}

print_status() {
  if inhibited; then
    if (( json )); then
      printf '{"text":"%s","alt":"activated","class":"activated","tooltip":"Idle inhibited (swayidle stopped)\\n\\nClick or Hyper+Mute: toggle · CLI: idle-inhibit on|off"}\n' "$ICON"
    else
      echo on
    fi
  else
    if (( json )); then
      printf '{"text":"%s","alt":"deactivated","class":"deactivated","tooltip":"Idle allowed (swayidle running)\\n\\nClick or Hyper+Mute: toggle · CLI: idle-inhibit on|off"}\n' "$ICON"
    else
      echo off
    fi
  fi
}

notify() {
  (( quiet )) || [[ -z "$NOTIFY" ]] || "$NOTIFY" -t 2000 -h string:x-canonical-private-synchronous:idle-inhibit "Idle inhibit" "$1" || true
}

set_on() {
  : > "$MARKER"
  "$SYSTEMCTL" --user stop "$SERVICE" >/dev/null 2>&1 || true
  notify "ON (swayidle stopped)"
}

set_off() {
  if [[ "$("$SYSTEMCTL" --user show -p LoadState --value "$SERVICE" 2>/dev/null)" != "loaded" ]]; then
    notify "ERROR: ${SERVICE} not loaded"
    return 1
  fi
  rm -f "$MARKER"
  "$SYSTEMCTL" --user reset-failed "$SERVICE" >/dev/null 2>&1 || true
  "$SYSTEMCTL" --user start "$SERVICE" >/dev/null 2>&1 || true
  notify "OFF (swayidle running)"
}

[[ -n "$SYSTEMCTL" ]] || { echo "systemctl not found" >&2; exit 1; }

case "$verb" in
  status) print_status ;;
  on) set_on; print_status ;;
  off) set_off; print_status ;;
  toggle)
    # The keyd virtual keyboard can deliver a fast down/up pair: one toggle per press.
    LOCK_DIR="${runtime_dir}/idle-inhibit-toggle.lock"
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0
    trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
    if inhibited; then set_off; else set_on; fi
    print_status ;;
  *) echo "usage: idle-inhibit on|off|toggle|status [--json] [-q]" >&2; exit 2 ;;
esac
