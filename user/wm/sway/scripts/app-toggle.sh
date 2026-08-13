#!/usr/bin/env bash
# Usage: app-toggle.sh <app_id|class|title:REGEX> <launch_command...>
#
# Examples:
#   app-toggle.sh cursor cursor --flags
#   app-toggle.sh kitty-ranger 'kitty --class kitty-ranger ranger'
#   app-toggle.sh title:^Element element-desktop   (apps with no useful Wayland app_id, e.g. Electron)
#
# Behaviour:
#   no windows        -> launch
#   1 window, focused -> hide to scratchpad (remembering whether it was tiled)
#   1 window, else    -> show/focus it, restoring its previous tiled/floating state
#   2+ windows        -> cycle focus between them
#
# Debug instrumentation (off by default, zero cost when off):
#   touch ~/.config/sway/app-toggle.debug     # enable
#   tail -f ~/.local/state/sway/app-toggle.log
#   rm ~/.config/sway/app-toggle.debug        # disable

set -uo pipefail

# ---------------------------------------------------------------------------
# Instrumentation (marker-file gated)
# ---------------------------------------------------------------------------
DEBUG_MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/sway/app-toggle.debug"
LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/sway/app-toggle.log"
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
        "$(date '+%F %T.%3N')" "$$" "$lvl" "${APP_ID:-?}" "$*" >>"$LOG_FILE"
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
APP_ID="${1:-}"
[ -n "$APP_ID" ] && [ "$#" -ge 2 ] || {
    echo "Usage: $0 <app_id|class|title:REGEX> <command...>" >&2
    exit 1
}
shift

# Preserve the historical calling convention: a single argument containing
# whitespace is re-split into words (e.g. 'kitty --class kitty-ranger ranger').
# Anything else is taken verbatim, so args keep their spaces and are never
# glob-expanded (the old `CMD="$@"` + unquoted `$CMD` did both wrong).
if [ "$#" -eq 1 ] && [[ "$1" == *[[:space:]]* ]]; then
    read -r -a CMD <<<"$1"
else
    CMD=("$@")
fi

MATCH_MODE="app"
PATTERN="$APP_ID"
if [[ "$APP_ID" == title:* ]]; then
    MATCH_MODE="title"
    PATTERN="${APP_ID#title:}"
    [ -n "$PATTERN" ] || die "empty title: regex"
fi

# app/class matching is case-insensitive via lowercasing both sides.
# title matching is a REGEX and must NOT be lowercased -- doing so silently
# corrupts escapes and classes (\S -> \s, [A-Z] -> [a-z]).
if [ "$MATCH_MODE" = "app" ]; then
    JQ_PATTERN="${PATTERN,,}"
else
    JQ_PATTERN="$PATTERN"
fi

log INFO "run start mode=$MATCH_MODE pattern=[$PATTERN] cmd=[${CMD[*]}]"

command -v swaymsg >/dev/null 2>&1 || die "swaymsg not found in PATH"
command -v jq >/dev/null 2>&1 || die "jq not found in PATH"

# ---------------------------------------------------------------------------
# State store
#
# Keyed by the sway IPC socket (which embeds sway's PID), inside XDG_RUNTIME_DIR
# (tmpfs, wiped when the session ends). The old /tmp/sway-window-state-<con_id>
# scheme survived reboots while con_ids restart low every session, so leftover
# files got applied to unrelated new windows -- silently floating/unfloating
# them. Stale entries are additionally pruned on every run.
# ---------------------------------------------------------------------------
SWAY_TAG="$(basename "${SWAYSOCK:-nosock}")"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/sway-app-toggle/${SWAY_TAG}"
mkdir -p "$STATE_DIR" 2>/dev/null || die "cannot create state dir $STATE_DIR"
chmod 700 "${STATE_DIR%/*}" 2>/dev/null

state_file() { printf '%s/win-%s' "$STATE_DIR" "$1"; }

# ---------------------------------------------------------------------------
# Debounce: a rapid double-press used to race two instances, both see zero
# windows, and launch the app twice. Hold the lock for the whole run so extra
# presses during a launch are dropped rather than duplicated.
# ---------------------------------------------------------------------------
if command -v flock >/dev/null 2>&1; then
    LOCK_KEY="$(printf '%s' "$APP_ID" | cksum | tr -d ' ')"
    # Braces keep the 2>/dev/null scoped to this group; `exec 9>f 2>/dev/null`
    # would redirect the *script's* stderr permanently and swallow every warning.
    { exec 9>"$STATE_DIR/.lock-$LOCK_KEY"; } 2>/dev/null
    if ! flock -n 9 2>/dev/null; then
        log INFO "debounced: another instance holds the lock"
        finish 0
    fi
fi

# ---------------------------------------------------------------------------
# Single tree fetch + combined parse
# ---------------------------------------------------------------------------
TREE=$(swaymsg -t get_tree 2>/dev/null) || die "swaymsg -t get_tree failed"
[ -n "$TREE" ] || die "swaymsg -t get_tree returned nothing"

JQ_ERR=$(mktemp 2>/dev/null) || JQ_ERR=/dev/null
PARSED=$(printf '%s' "$TREE" | jq -c --arg pat "$JQ_PATTERN" --arg mode "$MATCH_MODE" '
  def wins: [ recurse(.nodes[]?, .floating_nodes[]?)
              | select(.type == "con" or .type == "floating_con") ];
  {
    focused_id: ([ recurse(.nodes[]?, .floating_nodes[]?)
                   | select(.focused == true) | .id ] | .[0] // null),
    all_ids: [ wins[] | .id ],
    windows: [ wins[]
      | select(
          if $mode == "title" then
              ((.name // "") | test($pat; "i"))
          else
              ((.app_id // "") | ascii_downcase == $pat) or
              ((.window_properties.class // "") | ascii_downcase == $pat)
          end
        )
      | { id,
          floating: (.floating == "user_on" or .floating == "auto_on"),
          hidden:   (.visible == false),
          scratch:  (.scratchpad_state // "none"),
          w: .rect.width, h: .rect.height,
          name: (.name // "") }
    ]
  }' 2>"$JQ_ERR")
JQ_RC=$?

if [ "$JQ_RC" -ne 0 ] || [ -z "$PARSED" ]; then
    # Never fall through to "launch" here: a bad regex or an unparseable tree
    # used to look identical to "no windows found" and spawned a duplicate app.
    die "tree parse failed (rc=$JQ_RC): $(head -c 300 "$JQ_ERR" 2>/dev/null)"
fi
[ "$JQ_ERR" = /dev/null ] || rm -f "$JQ_ERR"

ACTUAL_COUNT=$(printf '%s' "$PARSED" | jq '.windows | length')
FOCUSED_ID=$(printf '%s' "$PARSED" | jq -r '.focused_id // "none"')

log INFO "tree: focused_id=$FOCUSED_ID matched=$ACTUAL_COUNT windows=$(printf '%s' "$PARSED" | jq -c '.windows')"

# Prune state entries whose window no longer exists.
prune_state() {
    local live pruned=0 f id
    live=" $(printf '%s' "$PARSED" | jq -r '.all_ids | join(" ")') "
    for f in "$STATE_DIR"/win-*; do
        [ -e "$f" ] || continue
        id="${f##*/win-}"
        case "$live" in
            *" $id "*) ;;
            *) rm -f "$f" && pruned=$((pruned + 1)) ;;
        esac
    done
    [ "$pruned" -gt 0 ] && log INFO "pruned $pruned stale state entr$([ "$pruned" -eq 1 ] && echo y || echo ies)"
    return 0
}
prune_state

# swaymsg wrapper that records the command and whether sway accepted it.
sway_do() {
    local out rc
    out=$(swaymsg "$@" 2>&1); rc=$?
    if [ "$DEBUG" -eq 1 ]; then
        local detail
        detail=$(printf '%s' "$out" | jq -r '
            if type == "array" and length > 0 then
                "success=" + ([.[].success] | all | tostring)
                + ([.[] | select(.error) | .error] | if length > 0 then " error=" + join("; ") else "" end)
            else "reply=" + (tostring | .[0:160]) end' 2>/dev/null) \
            || detail="reply=$(printf '%s' "$out" | tr -d '\n' | head -c 160)"
        log CMD "swaymsg $* -> rc=$rc $detail"
    fi
    return $rc
}

# ---------------------------------------------------------------------------
# Wait for a window to appear after launch
# ---------------------------------------------------------------------------
wait_for_window() {
    local max_iterations=50 iteration=0 count
    while [ "$iteration" -lt "$max_iterations" ]; do
        count=$(swaymsg -t get_tree 2>/dev/null | jq --arg pat "$JQ_PATTERN" --arg mode "$MATCH_MODE" '
            [ recurse(.nodes[]?, .floating_nodes[]?)
              | select(.type == "con" or .type == "floating_con")
              | select(
                  if $mode == "title" then
                      ((.name // "") | test($pat; "i"))
                  else
                      ((.app_id // "") | ascii_downcase == $pat) or
                      ((.window_properties.class // "") | ascii_downcase == $pat)
                  end
                ) ] | length' 2>/dev/null)
        if [ "${count:-0}" -gt 0 ]; then
            log INFO "window appeared after ${iteration} poll(s) (~$((iteration * 100))ms)"
            return 0
        fi
        sleep 0.1
        iteration=$((iteration + 1))
    done
    warn "no window matching [$PATTERN] appeared within 5s"
    return 1
}

# ---------------------------------------------------------------------------
# Post-launch floating/sticky rules
# ---------------------------------------------------------------------------
apply_window_properties() {
    case "${1,,}" in
        "alacritty")
            sway_do '[app_id="Alacritty"] floating enable, sticky enable' ||
            sway_do '[app_id="alacritty"] floating enable, sticky enable' ;;
        "spotify")
            sway_do '[class="Spotify"] floating enable, sticky enable' ||
            sway_do '[app_id="spotify"] floating enable, sticky enable' ;;
        "org.gnome.calculator")
            sway_do '[app_id="org.gnome.Calculator"] floating enable, sticky enable' ;;
        *) return 0 ;;
    esac
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

    if [ -z "$resolved" ]; then
        if [[ "$APP_ID" =~ ^(org|com|io|net|de|app)\. ]] && flatpak info "$APP_ID" >/dev/null 2>&1; then
            log INFO "launch: flatpak run $APP_ID"
            if command -v setsid >/dev/null 2>&1; then
                setsid flatpak run "$APP_ID" >/dev/null 2>&1 9>&- &
            else
                flatpak run "$APP_ID" >/dev/null 2>&1 9>&- &
            fi
            return 0
        fi
        warn "launch failed: '$bin' not found in PATH, nix profile, or flatpak"
        return 1
    fi

    run[0]="$resolved"
    log INFO "launch: ${run[*]}"
    if command -v setsid >/dev/null 2>&1; then
        setsid "${run[@]}" >/dev/null 2>&1 9>&- &
    else
        "${run[@]}" >/dev/null 2>&1 9>&- &
    fi
    return 0
}

if [ "${ACTUAL_COUNT:-0}" -eq 0 ]; then
    log INFO "decision=LAUNCH (no matching windows)"
    launch || finish 1
    if wait_for_window; then
        apply_window_properties "$APP_ID"
        finish 0
    fi
    finish 1   # launched but nothing showed up -- surface it instead of pretending success
fi

# ---------------------------------------------------------------------------
# TOGGLE (windows exist)
# ---------------------------------------------------------------------------
IS_FOCUSED=$(printf '%s' "$PARSED" | jq -r --arg f "$FOCUSED_ID" \
    '[ .windows[].id | tostring ] | index($f) != null')

if [ "$IS_FOCUSED" = "true" ] && [ "$ACTUAL_COUNT" -eq 1 ]; then
    # --- HIDE (focused -> scratchpad) ---
    IFS=$'\t' read -r ORIG_FLOAT WIDTH HEIGHT <<<"$(printf '%s' "$PARSED" | jq -r --arg id "$FOCUSED_ID" '
        .windows[] | select(.id == ($id | tonumber)) | "\(.floating)\t\(.w)\t\(.h)"')"

    ORIG_FLOAT="${ORIG_FLOAT:-true}"   # unknown -> treat as floating (no geometry surgery)
    WIDTH=${WIDTH:-0}
    HEIGHT=${HEIGHT:-0}
    log INFO "decision=HIDE id=$FOCUSED_ID was_floating=$ORIG_FLOAT geom=${WIDTH}x${HEIGHT}"

    # Every command is scoped to con_id. A bare `move scratchpad` acts on
    # whatever is focused *now*; with `focus_follows_mouse yes` a cursor nudge
    # between the tree read and this call sent the WRONG window to scratchpad.
    if [ "$ORIG_FLOAT" = "false" ] && [ "$WIDTH" -gt 0 ] && [ "$HEIGHT" -gt 0 ]; then
        if sway_do "[con_id=$FOCUSED_ID] floating enable, resize set $WIDTH $HEIGHT, move scratchpad"; then
            printf 'false\n' >"$(state_file "$FOCUSED_ID")"
            log INFO "saved state id=$FOCUSED_ID floating=false"
        else
            warn "hide failed for con_id=$FOCUSED_ID"
        fi
    else
        sway_do "[con_id=$FOCUSED_ID] move scratchpad" || warn "hide failed for con_id=$FOCUSED_ID"
    fi

elif [ "$IS_FOCUSED" = "true" ]; then
    # --- CYCLE (2+ windows, one of ours focused) ---
    NEXT_ID=$(printf '%s' "$PARSED" | jq -r --arg focus "$FOCUSED_ID" '
        [ .windows[].id ] as $ids
        | ($ids | index($focus | tonumber)) as $idx
        | if $idx then $ids[($idx + 1) % ($ids | length)] else $ids[0] end')
    log INFO "decision=CYCLE from=$FOCUSED_ID to=$NEXT_ID of=$ACTUAL_COUNT"
    sway_do "[con_id=$NEXT_ID] focus" || warn "focus failed for con_id=$NEXT_ID"

else
    # --- SHOW (scratchpad/unfocused -> focus) ---
    # Prefer a window that is actually hidden; otherwise the first match.
    # Target selection is driven by the live tree, never by the presence of a
    # state file -- that indirection is what let stale files hijack windows.
    TARGET_ID=$(printf '%s' "$PARSED" | jq -r '
        ( [ .windows[] | select(.hidden) ] + .windows ) | .[0].id')
    TMP_FILE="$(state_file "$TARGET_ID")"

    if [ -f "$TMP_FILE" ]; then
        ORIG_FLOAT=$(cat "$TMP_FILE" 2>/dev/null || echo "")
        rm -f "$TMP_FILE"
        log INFO "decision=SHOW id=$TARGET_ID restore_floating=$ORIG_FLOAT (state consumed)"
        if [ "$ORIG_FLOAT" = "false" ]; then
            sway_do "[con_id=$TARGET_ID] focus, floating disable" || warn "show failed for con_id=$TARGET_ID"
        else
            sway_do "[con_id=$TARGET_ID] focus, floating enable" || warn "show failed for con_id=$TARGET_ID"
        fi
    else
        # No recorded state: focus only. Never force a floating change here --
        # guessing is how untouched windows used to get silently re-floated.
        log INFO "decision=SHOW id=$TARGET_ID (no saved state, focus only)"
        sway_do "[con_id=$TARGET_ID] focus" || warn "show failed for con_id=$TARGET_ID"
    fi
fi

finish 0
