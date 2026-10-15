#!/usr/bin/env bash
# mic-toggle [toggle|on|off|status] [-q]
#
# Mutes/unmutes the default capture source in PipeWire (every app recording from it gets
# silence, as W11's AkuWM k-mic does for the default capture device) and says so in a desktop
# notification ("Micro ON" / "Micro MUTED"). Bound to Hyper+Shift+F12 in sway-apps; the
# DeathAdder V3 side button sends Hyper+M from its firmware (shared with W11), and keyd turns
# only that device's Hyper+M into Hyper+Shift+F12 (system/wm/keyd.nix), so the keyboard's
# Hyper+M stays Mission Center.
set -u

WPCTL="/run/current-system/sw/bin/wpctl"
[[ -x "$WPCTL" ]] || WPCTL="$(command -v wpctl || true)"
NOTIFY="$(command -v notify-send || true)"
[[ -n "$NOTIFY" ]] || NOTIFY="/run/current-system/sw/bin/notify-send"
PKILL="/run/current-system/sw/bin/pkill"
[[ -x "$PKILL" ]] || PKILL="$(command -v pkill || true)"

# Keybindings run us with sway's env; agents may not have the user bus.
if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$(id -u)" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

SRC="@DEFAULT_AUDIO_SOURCE@"
verb=toggle; quiet=0
for a in "$@"; do case "$a" in -q|--quiet) quiet=1 ;; *) verb="$a" ;; esac; done

notify() {   # $1 summary, $2 body, $3 icon
  (( quiet )) || [[ ! -x "$NOTIFY" ]] || "$NOTIFY" -a mic-toggle -t 1500 -i "$3" \
    -h string:x-canonical-private-synchronous:mic-toggle "$1" "$2" || true
}

[[ -n "$WPCTL" ]] || { notify "Micro: ERROR" "wpctl not found" dialog-error; echo "wpctl not found" >&2; exit 1; }

vol="$("$WPCTL" get-volume "$SRC" 2>/dev/null)" || {
  notify "Micro: ERROR" "no default input device" dialog-error; echo "no default source" >&2; exit 1; }
desc="$("$WPCTL" inspect "$SRC" 2>/dev/null | sed -n 's/.*node\.description = "\(.*\)"/\1/p' | head -n1)"

state() { [[ "$("$WPCTL" get-volume "$SRC" 2>/dev/null)" == *MUTED* ]] && echo muted || echo on; }

apply() {   # $1 = 1 mute, 0 unmute
  "$WPCTL" set-mute "$SRC" "$1" || { notify "Micro: ERROR" "set-mute failed" dialog-error; exit 1; }
  [[ -z "$PKILL" ]] || "$PKILL" -RTMIN+9 -x '(\.waybar-wrapped|waybar)' 2>/dev/null || true   # custom/mic signal 9
  if [[ "$(state)" == muted ]]; then
    notify "Micro MUTED" "$desc" microphone-sensitivity-muted
  else
    notify "Micro ON" "$desc" microphone-sensitivity-high
  fi
}

case "$verb" in
  status) state ;;
  on) apply 0; state ;;
  off|mute) apply 1; state ;;
  toggle)
    # keyd's virtual keyboard can deliver a fast down/up pair: one toggle per press.
    LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}/mic-toggle.lock"
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0
    trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
    if [[ "$vol" == *MUTED* ]]; then apply 0; else apply 1; fi
    state ;;
  *) echo "usage: mic-toggle [toggle|on|off|status] [-q]" >&2; exit 2 ;;
esac
