#!/usr/bin/env bash
# Show/hide Waybar without restarting it.
#
# SIGUSR1 is Waybar's own visibility toggle, and it is PER PROCESS: every bar
# that process draws hides and shows together. Two things were tried first and
# do not work, so do not reach for them again:
#
#   - `swaymsg bar <id> mode invisible|dock`. Waybar's man page says `mode` "is
#     an equivalent of the sway-bar(5) mode command", which reads like remote
#     control. It is not: measured on X13 with waybar 0.14.0, a bar started as
#     `waybar -b bar-0` came up visible even though sway had bar-0 on
#     `mode invisible`, and later mode changes moved nothing. Waybar reads that
#     config once at startup and does not act on `barconfig_update`.
#   - Anything that restarts Waybar. Restarting tears down the SNI tray host,
#     and every tray icon that registered against it disappears until its own
#     app is restarted (see sync-posthook.sh, whose restart list exists for
#     exactly this reason).
#
# Consequence worth knowing: on a machine whose Waybar draws bars on SEVERAL
# outputs, this hides all of them at once. Per-monitor toggling would mean one
# Waybar process per output, which is a different and much larger change. The
# script says so out loud when it applies. Today it never does: DESK binds its
# bar to the primary monitor only, and X13 has a single output unless docked.
set -uo pipefail

SELF="${0##*/}"
note() { printf '%s: %s\n' "$SELF" "$*"; }
notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -t "${1}" "Waybar" "${2}" >/dev/null 2>&1 || true
}

# Callable from a keybinding, a terminal, or over ssh, so do not assume the
# session environment is present.
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export XDG_RUNTIME_DIR
fi
if [ -z "${SWAYSOCK:-}" ]; then
    SWAYSOCK="$(ls -t "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1)"
    [ -n "$SWAYSOCK" ] && export SWAYSOCK
fi

# ---------------------------------------------------------------------------
# Duplicate guard
#
# A stray Waybar is not cosmetic: it draws a second bar, claims its own
# exclusive zone, and takes SIGUSR1 independently, so the toggle would leave
# one bar behind. systemd owns the real one; anything else is a leftover from a
# crash, a hand-run instance, or a debugging session.
# ---------------------------------------------------------------------------
MAIN_PID="$(systemctl --user show -p MainPID --value waybar.service 2>/dev/null || true)"
[ "${MAIN_PID:-0}" = "0" ] && MAIN_PID=""

mapfile -t ALL_PIDS < <(pgrep -x waybar 2>/dev/null)

if [ -z "$MAIN_PID" ]; then
    if [ "${#ALL_PIDS[@]}" -eq 0 ]; then
        note "waybar is not running; starting the service instead of toggling"
        systemctl --user start waybar.service >/dev/null 2>&1 ||
            notify 5000 "not running, and the service failed to start"
        exit 0
    fi
    # Running, but not as the systemd unit. Signal it rather than killing the
    # only bar the user has.
    MAIN_PID="${ALL_PIDS[0]}"
    note "waybar is running outside systemd (pid $MAIN_PID); signalling it anyway"
fi

STRAYS=0
for pid in "${ALL_PIDS[@]}"; do
    [ "$pid" = "$MAIN_PID" ] && continue
    kill "$pid" 2>/dev/null && STRAYS=$((STRAYS + 1))
done
if [ "$STRAYS" -gt 0 ]; then
    note "killed $STRAYS stray waybar instance(s), kept pid $MAIN_PID"
    notify 4000 "Killed $STRAYS duplicate instance(s)"
fi

# ---------------------------------------------------------------------------
# Warn when the toggle is wider than "the focused monitor"
# ---------------------------------------------------------------------------
if command -v swaymsg >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    ACTIVE_OUTPUTS="$(swaymsg -t get_outputs 2>/dev/null |
        jq -r '[ .[] | select(.active) ] | length' 2>/dev/null || echo 1)"
    if [ "${ACTIVE_OUTPUTS:-1}" -gt 1 ]; then
        FOCUSED="$(swaymsg -t get_outputs 2>/dev/null |
            jq -r '.[] | select(.focused) | .name' 2>/dev/null | head -1)"
        # Only a real caveat if this Waybar actually draws on more than one of
        # them: a bar pinned to one output with `"output":` is unaffected.
        UNPINNED="$(jq -r '
            if type == "array" then [ .[] | select(has("output") | not) ] | length
            else (if has("output") then 0 else 1 end) end' \
            "${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config" 2>/dev/null || echo 0)"
        if [ "${UNPINNED:-0}" -gt 0 ]; then
            note "focused output is ${FOCUSED:-?}, but this waybar draws on all $ACTIVE_OUTPUTS — toggling every bar"
            notify 4000 "Toggling all $ACTIVE_OUTPUTS bars (Waybar hides per process, not per output)"
        fi
    fi
fi

kill -SIGUSR1 "$MAIN_PID" 2>/dev/null || {
    note "failed to signal waybar (pid $MAIN_PID)"
    notify 5000 "Toggle failed — could not signal pid $MAIN_PID"
    exit 1
}
exit 0
