#!/usr/bin/env bash
# Usage: app-toggle.sh <app_id|class> <launch_command...>
# Example: app-toggle.sh cursor cursor --flags --more-flags

LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"
TIMESTAMP=$(date +%s)

# Safe logging function that writes directly to file
log_json() {
  echo "{\"id\":\"log_${TIMESTAMP}_$(date +%N)\",\"timestamp\":$(date +%s)000,\"location\":\"app-toggle.sh:$1\",\"message\":\"$2\",\"data\":$3,\"sessionId\":\"sway-debug\",\"runId\":\"app-toggle\",\"hypothesisId\":\"$4\"}" >> "$LOG_FILE" 2>/dev/null
}

# #region agent log - Script entry
log_json "ENTRY" "Script started" "{\"APP_ID\":\"$1\",\"ALL_ARGS\":\"$@\"}" "A"
# #endregion

APP_ID=$1
shift # Shift arguments so $@ becomes the command (e.g., "cursor --flags")
CMD="$@"

# #region agent log - After shift
log_json "AFTER_SHIFT" "Arguments processed" "{\"APP_ID\":\"$APP_ID\",\"CMD\":\"$CMD\"}" "A"
# #endregion

if [ -z "$APP_ID" ] || [ -z "$CMD" ]; then
    log_json "ERROR" "Missing arguments" "{\"APP_ID\":\"$APP_ID\",\"CMD\":\"$CMD\"}" "A"
    echo "Usage: $0 <app_id|class> <command...>"
    exit 1
fi

# 1. Get all windows for this app (Wayland app_id OR XWayland class)
# Include ALL windows (visible, scratchpad, etc.)
# #region agent log - Before query
log_json "BEFORE_QUERY" "About to run window detection query" "{\"APP_ID\":\"$APP_ID\"}" "B"
# #endregion

# Try multiple detection strategies for Electron-wrapped apps
WINDOW_JSON=$(swaymsg -t get_tree 2>/dev/null | jq --arg app "$APP_ID" '
    [
        recurse(.nodes[]?, .floating_nodes[]?) 
        | select(.type=="con" or .type=="floating_con")
        | select(
            (.app_id == $app) or 
            (.window_properties.class == $app) or
            ((.app_id // "") | ascii_downcase == ($app | ascii_downcase)) or
            ((.window_properties.class // "") | ascii_downcase == ($app | ascii_downcase)) or
            ((.name // "") | ascii_downcase | contains($app | ascii_downcase))
        )
    ]
' 2>/dev/null)

WINDOW_COUNT=$(echo "$WINDOW_JSON" | jq 'length' 2>/dev/null || echo "error")
# Ensure WINDOW_COUNT is a valid number (handle empty string case)
if [ -z "$WINDOW_COUNT" ] || [ "$WINDOW_COUNT" = "error" ]; then
    WINDOW_COUNT="0"
fi

# #region agent log - After query
JSON_LENGTH=${#WINDOW_JSON}
JSON_PREVIEW=$(echo "$WINDOW_JSON" | head -c 200 | tr '\n' ' ' | sed 's/"/\\"/g')
# Also log actual app_id/class found for debugging
FOUND_APP_IDS=$(echo "$WINDOW_JSON" | jq -r '.[] | .app_id // "null"' 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//' || echo "")
FOUND_CLASSES=$(echo "$WINDOW_JSON" | jq -r '.[] | .window_properties.class // "null"' 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//' || echo "")
log_json "AFTER_QUERY" "Query completed" "{\"COUNT\":\"$WINDOW_COUNT\",\"FOUND_APP_IDS\":\"$FOUND_APP_IDS\",\"FOUND_CLASSES\":\"$FOUND_CLASSES\",\"JSON_PREVIEW\":\"$JSON_PREVIEW\"}" "B"
# #endregion

# 2. IF NOT RUNNING -> LAUNCH
WINDOW_JSON_NORMALIZED=$(echo "$WINDOW_JSON" | jq -c '.' 2>/dev/null || echo "")
if [ -z "$WINDOW_JSON" ] || [ "$WINDOW_JSON_NORMALIZED" = "[]" ] || [ "$WINDOW_COUNT" = "0" ] || [ "$WINDOW_COUNT" = "error" ]; then
    # Check if this is a Flatpak app
    # Method 1: Check if APP_ID exists in flatpak list (most reliable)
    # Method 2: Check if APP_ID matches common Flatpak app ID patterns and verify with flatpak info
    IS_FLATPAK=false
    if flatpak list --app --columns=application 2>/dev/null | grep -q "^${APP_ID}$"; then
        IS_FLATPAK=true
    elif [[ "$APP_ID" =~ ^(org\.|com\.|io\.|net\.|de\.|app\.) ]]; then
        # APP_ID matches Flatpak pattern - verify it's actually installed
        if flatpak info "$APP_ID" &>/dev/null 2>&1; then
            IS_FLATPAK=true
        fi
    fi
    
    if [ "$IS_FLATPAK" = "true" ]; then
        # Launch via Flatpak - redirect output to prevent EPIPE errors
        flatpak run "$APP_ID" >/dev/null 2>&1 &
    else
        # Launch normally (use the provided command)
        # Extract first word of command to check if it exists
        CMD_FIRST=$(echo "$CMD" | cut -d' ' -f1)
        
        # Check if command exists in PATH
        if command -v "$CMD_FIRST" &>/dev/null; then
            # Command exists in PATH - use it with output redirection
            # Redirect stdout/stderr to prevent EPIPE errors with Electron apps
            $CMD >/dev/null 2>&1 &
        else
            # Command not in PATH - check Nix profile locations
            # Try exact name first, then try common variations (case-insensitive search)
            NIX_PROFILE_BIN="$HOME/.nix-profile/bin/$CMD_FIRST"
            SYSTEM_BIN="/run/current-system/sw/bin/$CMD_FIRST"
            FOUND_BIN=""
            
            # Check exact match first
            if [ -f "$NIX_PROFILE_BIN" ] && [ -x "$NIX_PROFILE_BIN" ]; then
                FOUND_BIN="$NIX_PROFILE_BIN"
            elif [ -f "$SYSTEM_BIN" ] && [ -x "$SYSTEM_BIN" ]; then
                FOUND_BIN="$SYSTEM_BIN"
            else
                # Try case-insensitive search in Nix profile bin directories
                # Some Nix packages use different casing (e.g., Telegram vs telegram-desktop)
                if [ -d "$HOME/.nix-profile/bin" ]; then
                    FOUND_BIN=$(find "$HOME/.nix-profile/bin" -maxdepth 1 -iname "$CMD_FIRST" -type f -executable 2>/dev/null | head -1)
                fi
                if [ -z "$FOUND_BIN" ] && [ -d "/run/current-system/sw/bin" ]; then
                    FOUND_BIN=$(find "/run/current-system/sw/bin" -maxdepth 1 -iname "$CMD_FIRST" -type f -executable 2>/dev/null | head -1)
                fi
            fi
            
            if [ -n "$FOUND_BIN" ]; then
                # Found binary - use full path
                # Redirect output to prevent EPIPE errors with Electron apps
                CMD_ARGS=$(echo "$CMD" | cut -d' ' -f2-)
                if [ -n "$CMD_ARGS" ]; then
                    "$FOUND_BIN" $CMD_ARGS >/dev/null 2>&1 &
                else
                    "$FOUND_BIN" >/dev/null 2>&1 &
                fi
            elif [[ "$APP_ID" =~ ^(org\.|com\.|io\.|net\.|de\.|app\.) ]]; then
                # Command not found but APP_ID looks like Flatpak - try flatpak run as fallback
                # Redirect output to prevent EPIPE errors
                flatpak run "$APP_ID" >/dev/null 2>&1 &
            else
                # Last resort - try the command anyway (might work with full PATH from Sway)
                # Redirect output to prevent EPIPE errors
                $CMD >/dev/null 2>&1 &
            fi
        fi
    fi
    exit 0
fi

# 3. IDENTIFY STATE
# #region agent log - Before state identification
log_json "BEFORE_STATE_ID" "Identifying state" "{}" "D"
# #endregion

FOCUSED_ID=$(swaymsg -t get_tree 2>/dev/null | jq -r '.. | select(.focused? == true) | .id' 2>/dev/null || echo "none")
ID_LIST=$(echo "$WINDOW_JSON" | jq -r '.[].id' 2>/dev/null || echo "")
# Use WINDOW_COUNT consistently (already calculated and validated above)
COUNT="$WINDOW_COUNT"

# #region agent log - State identification result
log_json "STATE_ID" "State identified" "{\"FOCUSED_ID\":\"$FOCUSED_ID\",\"ID_LIST\":\"$ID_LIST\",\"COUNT\":\"$COUNT\"}" "D"
# #endregion

# Check if the currently focused window belongs to this app
IS_FOCUSED=$(echo "$ID_LIST" | grep -q "^$FOCUSED_ID$" && echo "yes" || echo "no")

# #region agent log - Focus check
log_json "FOCUS_CHECK" "Checking if app is focused" "{\"IS_FOCUSED\":\"$IS_FOCUSED\",\"FOCUSED_ID\":\"$FOCUSED_ID\",\"ID_LIST\":\"$ID_LIST\",\"COUNT\":\"$COUNT\"}" "D"
# #endregion

if [ "$IS_FOCUSED" = "yes" ]; then
    # --- APP IS FOCUSED ---
    
    if [ "$COUNT" -gt 1 ]; then
        # MULTIPLE WINDOWS: Cycle to next
        # Calculate next window ID (A → B → C → A)
        NEXT_ID=$(echo "$WINDOW_JSON" | jq -r --arg focus "$FOCUSED_ID" '
            [.[].id] | . as $ids | ($ids | index($focus | tonumber)) as $idx | 
            if $idx then $ids[($idx + 1) % length] else $ids[0] end')
        
        # CRITICAL FIX: Always use 'focus' for multiple windows, even if in scratchpad
        # 'focus' will show scratchpad windows naturally without moving them to mouse position
        # 'scratchpad show' would move the window to mouse position (unwanted behavior)
        swaymsg "[con_id=$NEXT_ID] focus" 2>/dev/null
    else
        # SINGLE WINDOW: Toggle Hide (Move to Scratchpad)
        # #region agent log - Hide single window
        log_json "ACTION" "Hiding single window (move to scratchpad)" "{\"COUNT\":\"$COUNT\",\"FOCUSED_ID\":\"$FOCUSED_ID\"}" "E"
        # #endregion
        swaymsg "move scratchpad" 2>/dev/null
    fi

else
    # --- APP IS RUNNING BUT NOT FOCUSED ---
    
    # Prioritize scratchpad windows - show hidden windows first
    TARGET_ID=$(echo "$WINDOW_JSON" | jq -r '
        .[] | select(.scratchpad_state != "none" and .scratchpad_state != null) | .id
    ' 2>/dev/null | head -n 1)
    
    if [ -z "$TARGET_ID" ] || [ "$TARGET_ID" = "" ]; then
        # No scratchpad window found, pick first visible window
        TARGET_ID=$(echo "$ID_LIST" | head -n 1)
    fi
    
    # Check if target is in scratchpad
    IS_SCRATCHPAD=$(echo "$WINDOW_JSON" | jq -r --arg id "$TARGET_ID" '.[] | select(.id == ($id|tonumber)) | .scratchpad_state' 2>/dev/null || echo "error")

    if [ "$IS_SCRATCHPAD" != "none" ] && [ "$IS_SCRATCHPAD" != "null" ] && [ "$IS_SCRATCHPAD" != "error" ]; then
        # Window is hidden in scratchpad - use 'scratchpad show' to show it
        # This is OK for "not focused" case as we're bringing the app to front
        # #region agent log - Show from scratchpad
        log_json "ACTION" "Showing window from scratchpad" "{\"TARGET_ID\":\"$TARGET_ID\",\"IS_SCRATCHPAD\":\"$IS_SCRATCHPAD\"}" "F"
        # #endregion
        # Check floating state before showing
        FLOATING_BEFORE=$(swaymsg -t get_tree 2>/dev/null | jq -r --arg id "$TARGET_ID" '.. | select(.id == ($id|tonumber)) | .floating' 2>/dev/null || echo "unknown")
        log_json "BEFORE_SCRATCHPAD_SHOW" "Floating state before scratchpad show" "{\"TARGET_ID\":\"$TARGET_ID\",\"FLOATING_BEFORE\":\"$FLOATING_BEFORE\"}" "F"
        swaymsg "[con_id=$TARGET_ID] scratchpad show" 2>/dev/null
        sleep 0.1
        # Check floating state after showing
        FLOATING_AFTER=$(swaymsg -t get_tree 2>/dev/null | jq -r --arg id "$TARGET_ID" '.. | select(.id == ($id|tonumber)) | .floating' 2>/dev/null || echo "unknown")
        log_json "AFTER_SCRATCHPAD_SHOW" "Floating state after scratchpad show" "{\"TARGET_ID\":\"$TARGET_ID\",\"FLOATING_BEFORE\":\"$FLOATING_BEFORE\",\"FLOATING_AFTER\":\"$FLOATING_AFTER\"}" "F"
        # If window became floating but shouldn't be, disable floating
        if [ "$FLOATING_AFTER" = "floating" ] && [ "$FLOATING_BEFORE" != "floating" ]; then
            log_json "FIX_FLOATING" "Window became floating after scratchpad show, disabling" "{\"TARGET_ID\":\"$TARGET_ID\"}" "F"
            swaymsg "[con_id=$TARGET_ID] floating disable" 2>/dev/null
        fi
    else
        # Window is visible - just focus it
        log_json "ACTION" "Focusing visible window" "{\"TARGET_ID\":\"$TARGET_ID\"}" "F"
        swaymsg "[con_id=$TARGET_ID] focus" 2>/dev/null
    fi
fi
