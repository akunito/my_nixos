#!/usr/bin/env bash
# Usage: app-toggle.sh <app_id|class> <launch_command...>
# Example: app-toggle.sh cursor cursor --flags

APP_ID=$1
shift
CMD="$@"

if [ -z "$APP_ID" ] || [ -z "$CMD" ]; then
    echo "Usage: $0 <app_id|class> <command...>"
    exit 1
fi

# Function to wait for window to appear after launch
wait_for_window() {
    local app_id="$1"
    local max_iterations=50  # 5 seconds max
    local poll_interval=0.1
    local iteration=0
    local norm_app=$(echo "$app_id" | tr '[:upper:]' '[:lower:]')
    
    while [ "$iteration" -lt "$max_iterations" ]; do
        local window_exists=$(swaymsg -t get_tree 2>/dev/null | jq -r --arg norm_app "$norm_app" '
            [
                recurse(.nodes[]?, .floating_nodes[]?) 
                | select(.type=="con" or .type=="floating_con")
                | select(
                    ((.app_id // "") | ascii_downcase == $norm_app) or 
                    ((.window_properties.class // "") | ascii_downcase == $norm_app)
                )
            ] | length
        ' 2>/dev/null || echo "0")
        
        if [ "$window_exists" != "0" ] && [ "$window_exists" != "" ]; then
            return 0
        fi
        
        sleep "$poll_interval"
        iteration=$((iteration + 1))
    done
    return 1
}

# Function to apply sticky/floating based on APP_ID
apply_window_properties() {
    local app_id="$1"
    local app_lower=$(echo "$app_id" | tr '[:upper:]' '[:lower:]')
    
    case "$app_lower" in
        "alacritty")
            swaymsg '[app_id="Alacritty"] floating enable, sticky enable' 2>/dev/null || \
            swaymsg '[app_id="alacritty"] floating enable, sticky enable' 2>/dev/null ;;
        "spotify")
            swaymsg '[class="Spotify"] floating enable, sticky enable' 2>/dev/null || \
            swaymsg '[app_id="spotify"] floating enable, sticky enable' 2>/dev/null ;;
        *) return 0 ;;
    esac
}

# 1. FIND WINDOWS
NORMALIZED_APP=$(echo "$APP_ID" | tr '[:upper:]' '[:lower:]')
WINDOW_JSON=$(swaymsg -t get_tree 2>/dev/null | jq -r --arg app "$APP_ID" --arg norm_app "$NORMALIZED_APP" '
    [
        recurse(.nodes[]?, .floating_nodes[]?) 
        | select(.type=="con" or .type=="floating_con")
        | select(
            ((.app_id // "") | ascii_downcase == $norm_app) or 
            ((.window_properties.class // "") | ascii_downcase == $norm_app)
        )
    ]
' 2>/dev/null)

# 2. LAUNCH IF NOT RUNNING
if [ -z "$WINDOW_JSON" ] || [ "$WINDOW_JSON" = "[]" ]; then
    IS_FLATPAK=false
    if flatpak list --app --columns=application 2>/dev/null | grep -q "^${APP_ID}$"; then
        IS_FLATPAK=true
    elif [[ "$APP_ID" =~ ^(org\.|com\.|io\.|net\.|de\.|app\.) ]]; then
        if flatpak info "$APP_ID" &>/dev/null 2>&1; then IS_FLATPAK=true; fi
    fi
    
    if [ "$IS_FLATPAK" = "true" ]; then
        flatpak run "$APP_ID" >/dev/null 2>&1 &
    else
        CMD_FIRST=$(echo "$CMD" | cut -d' ' -f1)
        if command -v "$CMD_FIRST" &>/dev/null; then
            $CMD >/dev/null 2>&1 &
        else
            # NixOS/Nix Profile Fallbacks
            NIX_PROFILE_BIN="$HOME/.nix-profile/bin/$CMD_FIRST"
            SYSTEM_BIN="/run/current-system/sw/bin/$CMD_FIRST"
            FOUND_BIN=""
            
            if [ -x "$NIX_PROFILE_BIN" ]; then FOUND_BIN="$NIX_PROFILE_BIN"
            elif [ -x "$SYSTEM_BIN" ]; then FOUND_BIN="$SYSTEM_BIN"
            else
                if [ -d "$HOME/.nix-profile/bin" ]; then
                    FOUND_BIN=$(find "$HOME/.nix-profile/bin" -maxdepth 1 -iname "$CMD_FIRST" -type f -executable 2>/dev/null | head -1)
                fi
                if [ -z "$FOUND_BIN" ] && [ -d "/run/current-system/sw/bin" ]; then
                    FOUND_BIN=$(find "/run/current-system/sw/bin" -maxdepth 1 -iname "$CMD_FIRST" -type f -executable 2>/dev/null | head -1)
                fi
            fi
            
            if [ -n "$FOUND_BIN" ]; then
                CMD_ARGS=$(echo "$CMD" | cut -d' ' -f2-)
                if [ -n "$CMD_ARGS" ]; then
                    "$FOUND_BIN" $CMD_ARGS >/dev/null 2>&1 &
                else
                    "$FOUND_BIN" >/dev/null 2>&1 &
                fi
            elif [[ "$APP_ID" =~ ^(org\.|com\.|io\.|net\.|de\.|app\.) ]]; then
                flatpak run "$APP_ID" >/dev/null 2>&1 &
            else
                $CMD >/dev/null 2>&1 &
            fi
        fi
    fi
    
    if wait_for_window "$APP_ID"; then apply_window_properties "$APP_ID"; fi
    exit 0
fi

# 3. TOGGLE STATE
FOCUSED_ID=$(swaymsg -t get_tree 2>/dev/null | jq -r '.. | select(.focused? == true) | .id' 2>/dev/null || echo "none")
ID_LIST=$(echo "$WINDOW_JSON" | jq -r '.[].id' 2>/dev/null || echo "")
ACTUAL_COUNT=$(echo "$WINDOW_JSON" | jq 'length' 2>/dev/null || echo "0")

if echo "$ID_LIST" | grep -q "^$FOCUSED_ID$"; then
    # --- HIDE (Focused -> Scratchpad) ---
    if [ "$ACTUAL_COUNT" -eq 1 ]; then
        # Capture Geometry
        eval $(swaymsg -t get_tree 2>/dev/null | jq -r --arg id "$FOCUSED_ID" '
            recurse(.nodes[]?, .floating_nodes[]?) 
            | select(.id == ($id | tonumber))
            | "ORIGINAL_FLOATING=" + (if .floating == "user_on" or .floating == "auto_on" then "true" else "false" end) + 
              "\nWIDTH=" + (.rect.width | tostring) + 
              "\nHEIGHT=" + (.rect.height | tostring)
        ' 2>/dev/null)
        
        # Save State
        TMP_FILE="/tmp/sway-window-state-${FOCUSED_ID}"
        echo "$ORIGINAL_FLOATING" > "$TMP_FILE"
        
        # Sanitize integers for arithmetic check
        WIDTH=${WIDTH:-0}
        HEIGHT=${HEIGHT:-0}

        # Hide with Geometry Freeze if Tiled
        if [ "$ORIGINAL_FLOATING" = "false" ] && [ "$WIDTH" -gt 0 ] && [ "$HEIGHT" -gt 0 ]; then
            swaymsg "[con_id=$FOCUSED_ID] floating enable, resize set $WIDTH $HEIGHT, move scratchpad" 2>/dev/null
        else
            swaymsg "move scratchpad" 2>/dev/null
        fi
    elif [ "$ACTUAL_COUNT" -gt 1 ]; then
        # Cycle through windows
        NEXT_ID=$(echo "$WINDOW_JSON" | jq -r --arg focus "$FOCUSED_ID" '
            [.[].id] | . as $ids | ($ids | index($focus | tonumber)) as $idx | 
            if $idx then $ids[($idx + 1) % length] else $ids[0] end')
        swaymsg "[con_id=$NEXT_ID] focus" 2>/dev/null
    else
        $CMD &
    fi
else
    # --- SHOW (Scratchpad/Unfocused -> Focus) ---
    TARGET_ID=""
    for id in $ID_LIST; do
        if [ -f "/tmp/sway-window-state-${id}" ]; then
            TARGET_ID="$id"
            break
        fi
    done

    if [ -z "$TARGET_ID" ]; then
        TARGET_ID=$(echo "$ID_LIST" | head -n 1)
    fi
    
    TMP_FILE="/tmp/sway-window-state-${TARGET_ID}"
    
    if [ -f "$TMP_FILE" ]; then
        ORIGINAL_FLOATING=$(cat "$TMP_FILE" 2>/dev/null || echo "false")
        
        swaymsg "[con_id=$TARGET_ID] focus" 2>/dev/null
        sleep 0.2
        
        if [ "$ORIGINAL_FLOATING" = "true" ]; then
            swaymsg "[con_id=$TARGET_ID] floating enable" 2>/dev/null
        else
            swaymsg "[con_id=$TARGET_ID] floating disable" 2>/dev/null
        fi
        rm -f "$TMP_FILE" 2>/dev/null
    else
        swaymsg "[con_id=$TARGET_ID] focus" 2>/dev/null
    fi
fi
