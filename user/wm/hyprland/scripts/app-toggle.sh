#!/usr/bin/env bash
# Application Toggle Script (Hyprland)
# Toggle application: launch if not running, focus/hide if running
#
# Usage: app-toggle.sh <app_class> <launch_command...>
#   app_class:      window class to match (e.g. "kitty", "chromium-browser")
#   launch_command: command to launch when nothing matches
#
# Behaviour:
#   no windows        -> launch
#   1 window, focused -> hide into special:scratch_<class>
#   1 window, else    -> show/focus it (un-hiding its special workspace if needed)
#   2+ windows        -> cycle focus between them
#
# Debug instrumentation (off by default, zero cost when off):
#   touch ~/.config/hypr/app-toggle.debug     # enable
#   tail -f ~/.local/state/hypr/app-toggle.log
#   rm ~/.config/hypr/app-toggle.debug        # disable

# Deliberately no `set -e`: a toggle script legitimately runs commands that can
# fail, and aborting mid-way used to leave windows half-moved with no trace.
set -uo pipefail

# ---------------------------------------------------------------------------
# Instrumentation (marker-file gated)
# ---------------------------------------------------------------------------
DEBUG_MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/app-toggle.debug"
LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/app-toggle.log"
LOG_MAX_BYTES=$((2 * 1024 * 1024))

DEBUG=0
[ -e "$DEBUG_MARKER" ] && DEBUG=1
LOG_READY=0
T_START="${EPOCHREALTIME:-0}"

log() {
    [ "$DEBUG" -eq 1 ] || return 0
    local lvl="$1"; shift
    if [ "$LOG_READY" -eq 0 ]; then
        mkdir -p "${LOG_FILE%/*}" 2>/dev/null || { DEBUG=0; return 0; }
        local sz
        sz=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
        [ "$sz" -gt "$LOG_MAX_BYTES" ] && mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null
        LOG_READY=1
    fi
    printf '%s pid=%-7s %-5s app=%-28s %s\n' \
        "$(date '+%F %T.%3N')" "$$" "$lvl" "${APP_CLASS:-?}" "$*" >>"$LOG_FILE"
}

warn() { printf '%s: %s\n' "${0##*/}" "$*" >&2; log WARN "$*"; }

elapsed_ms() {
    [ -n "${EPOCHREALTIME:-}" ] || { echo "?"; return; }
    awk -v a="$T_START" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.0f", (b-a)*1000}'
}

finish() {
    local rc="${1:-0}"
    log INFO "run end rc=$rc elapsed=$(elapsed_ms)ms"
    exit "$rc"
}

die() { warn "$*"; finish 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
APP_CLASS="${1:-}"
[ -n "$APP_CLASS" ] && [ "$#" -ge 2 ] || {
    echo "Usage: $0 <app_class> <launch_command...>" >&2
    exit 1
}
shift

# A single argument containing whitespace is re-split into words (the historical
# calling convention). Anything else is taken verbatim, so args keep their spaces
# and are never glob-expanded -- the old `LAUNCH_CMD="$@"` + unquoted expansion
# did both wrong (an arg containing `*` expanded against the cwd).
if [ "$#" -eq 1 ] && [[ "$1" == *[[:space:]]* ]]; then
    read -r -a CMD <<<"$1"
else
    CMD=("$@")
fi

log INFO "run start class=[$APP_CLASS] cmd=[${CMD[*]}]"

command -v hyprctl >/dev/null 2>&1 || die "hyprctl not found in PATH"
command -v jq >/dev/null 2>&1 || die "jq not found in PATH"

APP_NAME=$(printf '%s' "$APP_CLASS" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g')
SCRATCH_NAMESPACE="scratch_${APP_NAME}"

# ---------------------------------------------------------------------------
# Debounce: a rapid double-press used to race two instances, both see zero
# windows, and launch the app twice.
# ---------------------------------------------------------------------------
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/hypr-app-toggle/${HYPRLAND_INSTANCE_SIGNATURE:-nosig}"
mkdir -p "$RUN_DIR" 2>/dev/null
chmod 700 "${RUN_DIR%/*}" 2>/dev/null
if command -v flock >/dev/null 2>&1 && [ -d "$RUN_DIR" ]; then
    LOCK_KEY="$(printf '%s' "$APP_CLASS" | cksum | tr -d ' ')"
    # Braces keep the 2>/dev/null scoped to this group; `exec 9>f 2>/dev/null`
    # would redirect the *script's* stderr permanently and swallow every warning.
    { exec 9>"$RUN_DIR/.lock-$LOCK_KEY"; } 2>/dev/null
    if ! flock -n 9 2>/dev/null; then
        log INFO "debounced: another instance holds the lock"
        finish 0
    fi
fi

# ---------------------------------------------------------------------------
# Single clients fetch + parse
# ---------------------------------------------------------------------------
CLIENTS=$(hyprctl clients -j 2>/dev/null) || die "hyprctl clients failed"
[ -n "$CLIENTS" ] || die "hyprctl clients returned nothing"

JQ_ERR=$(mktemp 2>/dev/null) || JQ_ERR=/dev/null
WINDOW_JSON=$(printf '%s' "$CLIENTS" | jq -c --arg app "$APP_CLASS" '
    [ .[]
      | select(
          ((.class // "")        | ascii_downcase == ($app | ascii_downcase)) or
          ((.initialClass // "") | ascii_downcase == ($app | ascii_downcase))
        )
      | { address, ws: (.workspace.name // ""), wsid: (.workspace.id // 0), title: (.title // "") }
    ]' 2>"$JQ_ERR")
JQ_RC=$?

if [ "$JQ_RC" -ne 0 ] || [ -z "$WINDOW_JSON" ]; then
    # Never fall through to "launch" here: an unparseable reply used to look
    # identical to "no windows found" and spawned a duplicate app.
    die "clients parse failed (rc=$JQ_RC): $(head -c 300 "$JQ_ERR" 2>/dev/null)"
fi
[ "$JQ_ERR" = /dev/null ] || rm -f "$JQ_ERR"

WINDOW_COUNT=$(printf '%s' "$WINDOW_JSON" | jq 'length')
FOCUSED_ADDRESS=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty' 2>/dev/null)

log INFO "clients: focused=$FOCUSED_ADDRESS matched=$WINDOW_COUNT windows=$WINDOW_JSON"

hypr_do() {
    local out rc
    out=$(hyprctl "$@" 2>&1); rc=$?
    log CMD "hyprctl $* -> rc=$rc out=$(printf '%s' "$out" | tr -d '\n' | head -c 160)"
    [ "$rc" -eq 0 ] || warn "hyprctl $* failed (rc=$rc): $out"
    return $rc
}

# ---------------------------------------------------------------------------
# Wait for a window to appear after launch
# ---------------------------------------------------------------------------
wait_for_window() {
    local max_iterations=50 iteration=0 count
    while [ "$iteration" -lt "$max_iterations" ]; do
        count=$(hyprctl clients -j 2>/dev/null | jq --arg app "$APP_CLASS" '
            [ .[]
              | select(
                  ((.class // "")        | ascii_downcase == ($app | ascii_downcase)) or
                  ((.initialClass // "") | ascii_downcase == ($app | ascii_downcase))
                ) ] | length' 2>/dev/null)
        if [ "${count:-0}" -gt 0 ]; then
            log INFO "window appeared after ${iteration} poll(s) (~$((iteration * 100))ms)"
            return 0
        fi
        sleep 0.1
        iteration=$((iteration + 1))
    done
    warn "no window matching class [$APP_CLASS] appeared within 5s"
    return 1
}

# ---------------------------------------------------------------------------
# LAUNCH (no matching windows)
# ---------------------------------------------------------------------------
launch() {
    local bin="${CMD[0]}" resolved="" p
    local -a run=("${CMD[@]}")

    resolved=$(command -v "$bin" 2>/dev/null) || resolved=""
    if [ -z "$resolved" ]; then
        for p in "$HOME/.nix-profile/bin/$bin" "/run/current-system/sw/bin/$bin"; do
            [ -x "$p" ] && { resolved="$p"; break; }
        done
    fi
    # Case-insensitive fallback (some Nix packages install differently-cased bins).
    if [ -z "$resolved" ]; then
        for p in "$HOME/.nix-profile/bin" "/run/current-system/sw/bin"; do
            [ -d "$p" ] || continue
            resolved=$(find "$p" -maxdepth 1 -iname "$bin" -type f -executable 2>/dev/null | head -1)
            [ -n "$resolved" ] && break
        done
    fi

    if [ -z "$resolved" ]; then
        # Prefer a real binary over flatpak; only fall back when nothing native exists.
        if [[ "$APP_CLASS" =~ ^(org|com|io|net|de|app)\. ]] && flatpak info "$APP_CLASS" >/dev/null 2>&1; then
            log INFO "launch: flatpak run $APP_CLASS"
            if command -v setsid >/dev/null 2>&1; then
                setsid flatpak run "$APP_CLASS" >/dev/null 2>&1 9>&- &
            else
                flatpak run "$APP_CLASS" >/dev/null 2>&1 9>&- &
            fi
            return 0
        fi
        warn "launch failed: '$bin' not found in PATH, nix profile, or flatpak"
        return 1
    fi

    run[0]="$resolved"
    log INFO "launch: ${run[*]}"
    # 9>&- closes the debounce lock in the child; otherwise the launched app
    # inherits it and holds the lock for its entire lifetime.
    if command -v setsid >/dev/null 2>&1; then
        setsid "${run[@]}" >/dev/null 2>&1 9>&- &
    else
        "${run[@]}" >/dev/null 2>&1 9>&- &
    fi
    return 0
}

if [ "${WINDOW_COUNT:-0}" -eq 0 ]; then
    log INFO "decision=LAUNCH (no matching windows)"
    launch || finish 1
    wait_for_window || finish 1
    finish 0
fi

# ---------------------------------------------------------------------------
# TOGGLE (windows exist)
# ---------------------------------------------------------------------------
IS_FOCUSED=$(printf '%s' "$WINDOW_JSON" | jq -r --arg a "$FOCUSED_ADDRESS" \
    '[ .[].address ] | index($a) != null')

if [ "$IS_FOCUSED" = "true" ] && [ "$WINDOW_COUNT" -eq 1 ]; then
    # --- HIDE (focused -> special workspace) ---
    ADDR=$(printf '%s' "$WINDOW_JSON" | jq -r '.[0].address')
    log INFO "decision=HIDE addr=$ADDR -> special:$SCRATCH_NAMESPACE"
    # Scoped by address. A bare `movetoworkspacesilent` acts on whatever is
    # focused *now*; a focus change between the read and this call moved the
    # WRONG window into the scratchpad.
    hypr_do dispatch movetoworkspacesilent "special:${SCRATCH_NAMESPACE},address:${ADDR}"

elif [ "$IS_FOCUSED" = "true" ]; then
    # --- CYCLE (2+ windows, one of ours focused) ---
    NEXT_ADDRESS=$(printf '%s' "$WINDOW_JSON" | jq -r --arg a "$FOCUSED_ADDRESS" '
        [ .[].address ] as $addrs
        | ($addrs | index($a)) as $idx
        | if $idx then $addrs[($idx + 1) % ($addrs | length)] else $addrs[0] end')
    log INFO "decision=CYCLE from=$FOCUSED_ADDRESS to=$NEXT_ADDRESS of=$WINDOW_COUNT"
    hypr_do dispatch focuswindow "address:${NEXT_ADDRESS}"

else
    # --- SHOW (special workspace / unfocused -> focus) ---
    # Prefer a window parked in a special workspace over an already-visible one;
    # the old code always took the first match and could focus a visible window
    # while leaving the hidden one stranded.
    TARGET=$(printf '%s' "$WINDOW_JSON" | jq -c '
        ( [ .[] | select(.ws | startswith("special:")) ] + . ) | .[0]')
    ADDR=$(printf '%s' "$TARGET" | jq -r '.address')
    WS=$(printf '%s' "$TARGET" | jq -r '.ws')

    if [[ "$WS" == special:* ]]; then
        # togglespecialworkspace is a TOGGLE: firing it while the workspace is
        # already on screen would hide the window we are trying to reveal.
        SHOWN=$(hyprctl monitors -j 2>/dev/null \
            | jq -r --arg ws "$WS" '[ .[] | select((.specialWorkspace.name // "") == $ws) ] | length' 2>/dev/null)
        log INFO "decision=SHOW addr=$ADDR ws=$WS already_shown=${SHOWN:-?}"
        if [ "${SHOWN:-0}" -eq 0 ]; then
            hypr_do dispatch togglespecialworkspace "${WS#special:}"
        fi
        hypr_do dispatch focuswindow "address:${ADDR}"
    else
        log INFO "decision=SHOW addr=$ADDR ws=$WS (visible, focus only)"
        hypr_do dispatch focuswindow "address:${ADDR}"
    fi
fi

finish 0
