#!/usr/bin/env bash
# Usage: app-toggle.sh <app_id|class> <launch_command...>
# Example: app-toggle.sh cursor cursor --flags

APP_ID=$1
shift
CMD="$@"

[ -n "$APP_ID" ] && [ -n "$CMD" ] || { echo "Usage: $0 <app_id|class> <command...>"; exit 1; }

NORMALIZED_APP="${APP_ID,,}"

# === SINGLE tree fetch + combined parse ===
TREE=$(swaymsg -t get_tree 2>/dev/null)
PARSED=$(printf '%s' "$TREE" | jq --arg norm_app "$NORMALIZED_APP" '{
  focused_id: ([recurse(.nodes[]?, .floating_nodes[]?) | select(.focused == true) | .id] | .[0] // null),
  windows: [
    recurse(.nodes[]?, .floating_nodes[]?)
    | select(.type=="con" or .type=="floating_con")
    | select(
        ((.app_id // "") | ascii_downcase == $norm_app) or
        ((.window_properties.class // "") | ascii_downcase == $norm_app)
    )
    | { id, floating: (.floating == "user_on" or .floating == "auto_on"), w: .rect.width, h: .rect.height }
  ]
}' 2>/dev/null)

ACTUAL_COUNT=$(printf '%s' "$PARSED" | jq '.windows | length')
FOCUSED_ID=$(printf '%s' "$PARSED" | jq -r '.focused_id // "none"')

# Function to wait for window to appear after launch
wait_for_window() {
    local norm_app="${1,,}"
    local max_iterations=50
    local iteration=0

    while [ "$iteration" -lt "$max_iterations" ]; do
        local count=$(swaymsg -t get_tree 2>/dev/null | jq --arg n "$norm_app" '
            [recurse(.nodes[]?, .floating_nodes[]?)
             | select(.type=="con" or .type=="floating_con")
             | select(
                 ((.app_id // "") | ascii_downcase == $n) or
                 ((.window_properties.class // "") | ascii_downcase == $n)
             )] | length' 2>/dev/null)

        [ "${count:-0}" -gt 0 ] && return 0
        sleep 0.1
        iteration=$((iteration + 1))
    done
    return 1
}

# Function to apply sticky/floating based on APP_ID
apply_window_properties() {
    case "${1,,}" in
        "alacritty")
            swaymsg '[app_id="Alacritty"] floating enable, sticky enable' 2>/dev/null || \
            swaymsg '[app_id="alacritty"] floating enable, sticky enable' 2>/dev/null ;;
        "spotify")
            swaymsg '[class="Spotify"] floating enable, sticky enable' 2>/dev/null || \
            swaymsg '[app_id="spotify"] floating enable, sticky enable' 2>/dev/null ;;
        "org.gnome.calculator")
            swaymsg '[app_id="org.gnome.Calculator"] floating enable, sticky enable' 2>/dev/null ;;
        *) return 0 ;;
    esac
}

# === LAUNCH if no windows ===
if [ "${ACTUAL_COUNT:-0}" -eq 0 ]; then
    CMD_FIRST="${CMD%% *}"
    LAUNCHED=false

    if command -v "$CMD_FIRST" &>/dev/null; then
        $CMD >/dev/null 2>&1 &
        LAUNCHED=true
    else
        # Nix path fallbacks
        for p in "$HOME/.nix-profile/bin/$CMD_FIRST" "/run/current-system/sw/bin/$CMD_FIRST"; do
            if [ -x "$p" ]; then
                CMD_ARGS="${CMD#"$CMD_FIRST"}"
                "$p" $CMD_ARGS >/dev/null 2>&1 &
                LAUNCHED=true
                break
            fi
        done
    fi

    # Last resort: flatpak (only for reverse-domain IDs, only if nothing else worked)
    if [ "$LAUNCHED" = "false" ]; then
        if [[ "$APP_ID" =~ ^(org\.|com\.|io\.|net\.|de\.|app\.) ]] && flatpak info "$APP_ID" &>/dev/null 2>&1; then
            flatpak run "$APP_ID" >/dev/null 2>&1 &
        else
            $CMD >/dev/null 2>&1 &
        fi
    fi

    wait_for_window "$APP_ID" && apply_window_properties "$APP_ID"
    exit 0
fi

# === TOGGLE (windows exist) ===
ID_LIST=$(printf '%s' "$PARSED" | jq -r '.windows[].id')

IS_FOCUSED=false
while IFS= read -r id; do
    [ "$id" = "$FOCUSED_ID" ] && IS_FOCUSED=true && break
done <<< "$ID_LIST"

if [ "$IS_FOCUSED" = "true" ]; then
    # --- HIDE (Focused -> Scratchpad) ---
    if [ "$ACTUAL_COUNT" -eq 1 ]; then
        # Extract geometry from cached parse
        IFS=$'\t' read -r ORIG_FLOAT WIDTH HEIGHT <<< "$(printf '%s' "$PARSED" | jq -r --arg id "$FOCUSED_ID" '
            .windows[] | select(.id == ($id | tonumber)) | "\(.floating)\t\(.w)\t\(.h)"' 2>/dev/null)"

        echo "$ORIG_FLOAT" > "/tmp/sway-window-state-${FOCUSED_ID}"

        WIDTH=${WIDTH:-0}
        HEIGHT=${HEIGHT:-0}

        if [ "$ORIG_FLOAT" = "false" ] && [ "$WIDTH" -gt 0 ] && [ "$HEIGHT" -gt 0 ]; then
            swaymsg "[con_id=$FOCUSED_ID] floating enable, resize set $WIDTH $HEIGHT, move scratchpad" 2>/dev/null
        else
            swaymsg "move scratchpad" 2>/dev/null
        fi
    elif [ "$ACTUAL_COUNT" -gt 1 ]; then
        # Cycle through windows
        NEXT_ID=$(printf '%s' "$PARSED" | jq -r --arg focus "$FOCUSED_ID" '
            .windows | [.[].id] | . as $ids |
            ($ids | index($focus | tonumber)) as $idx |
            if $idx then $ids[($idx + 1) % length] else $ids[0] end')
        swaymsg "[con_id=$NEXT_ID] focus" 2>/dev/null
    fi
else
    # --- SHOW (Scratchpad/Unfocused -> Focus) ---
    TARGET_ID=""
    while IFS= read -r id; do
        [ -f "/tmp/sway-window-state-${id}" ] && TARGET_ID="$id" && break
    done <<< "$ID_LIST"
    TARGET_ID="${TARGET_ID:-${ID_LIST%%$'\n'*}}"

    TMP_FILE="/tmp/sway-window-state-${TARGET_ID}"

    if [ -f "$TMP_FILE" ]; then
        ORIG_FLOAT=$(cat "$TMP_FILE" 2>/dev/null || echo "false")
        rm -f "$TMP_FILE"
        # Combined focus + float restore in single IPC call (no sleep needed)
        if [ "$ORIG_FLOAT" = "true" ]; then
            swaymsg "[con_id=$TARGET_ID] focus, floating enable" 2>/dev/null
        else
            swaymsg "[con_id=$TARGET_ID] focus, floating disable" 2>/dev/null
        fi
    else
        swaymsg "[con_id=$TARGET_ID] focus" 2>/dev/null
    fi
fi
