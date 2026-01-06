#!/usr/bin/env bash
# Usage: app-toggle.sh <app_id|class> <launch_command...>
# Example: app-toggle.sh cursor cursor --flags --more-flags

APP_ID=$1
shift # Shift arguments so $@ becomes the command (e.g., "cursor --flags")
CMD="$@"

if [ -z "$APP_ID" ] || [ -z "$CMD" ]; then
    echo "Usage: $0 <app_id|class> <command...>"
    exit 1
fi

# 1. Get all windows for this app (Wayland app_id OR XWayland class)
# Include ALL windows (visible, scratchpad, etc.)
# IMPROVEMENT: Case-Insensitive Matching to ensure windows are found across all workspaces.
# We search recursively for nodes and floating_nodes.
# NOTE: We do NOT match by .name (window title) as it causes false positives.
WINDOW_JSON=$(swaymsg -t get_tree 2>/dev/null | jq --arg app "$APP_ID" '
    [
        recurse(.nodes[]?, .floating_nodes[]?) 
        | select(.type=="con" or .type=="floating_con")
        | select(
            ((.app_id // "") | ascii_downcase == ($app | ascii_downcase)) or 
            ((.window_properties.class // "") | ascii_downcase == ($app | ascii_downcase))
        )
    ]
' 2>/dev/null)

# 2. IF NOT RUNNING -> LAUNCH
# Safety check for empty JSON or empty array
if [ -z "$WINDOW_JSON" ] || [ "$WINDOW_JSON" = "[]" ]; then
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
FOCUSED_ID=$(swaymsg -t get_tree 2>/dev/null | jq -r '.. | select(.focused? == true) | .id' 2>/dev/null || echo "none")
ID_LIST=$(echo "$WINDOW_JSON" | jq -r '.[].id' 2>/dev/null || echo "")
COUNT=$(echo "$WINDOW_JSON" | jq 'length' 2>/dev/null || echo "0")

# Check if the currently focused window belongs to this app
IS_FOCUSED=$(echo "$ID_LIST" | grep -q "^$FOCUSED_ID$" && echo "yes" || echo "no")

if [ "$IS_FOCUSED" = "yes" ]; then
    # --- APP IS FOCUSED ---
    
    if [ "$COUNT" -gt 1 ]; then
        # MULTIPLE WINDOWS: Cycle to next
        # CRITICAL FIX: Use proper rotation logic to cycle through ALL windows
        # Rotate the list so the FOCUSED_ID is at the end, then pick the first element.
        # This ensures true A -> B -> C -> A cycling (not ping-pong between first two).
        NEXT_ID=$(echo "$WINDOW_JSON" | jq -r --arg focus "$FOCUSED_ID" '
            [.[].id] | . as $ids | ($ids | index($focus | tonumber)) as $idx | 
            if $idx then $ids[($idx + 1) % length] else $ids[0] end')
        
        # CRITICAL: Check if next window is in scratchpad
        IS_SCRATCHPAD=$(echo "$WINDOW_JSON" | jq -r --arg id "$NEXT_ID" '.[] | select(.id == ($id|tonumber)) | .scratchpad_state' 2>/dev/null || echo "error")
        
        if [ "$IS_SCRATCHPAD" != "none" ] && [ "$IS_SCRATCHPAD" != "null" ] && [ "$IS_SCRATCHPAD" != "error" ]; then
            swaymsg "[con_id=$NEXT_ID] scratchpad show" 2>/dev/null
        else
            swaymsg "[con_id=$NEXT_ID] focus" 2>/dev/null
        fi
    else
        # SINGLE WINDOW: Toggle Hide (Move to Scratchpad)
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
        swaymsg "[con_id=$TARGET_ID] scratchpad show" 2>/dev/null
    else
        # Window is visible - just focus it
        swaymsg "[con_id=$TARGET_ID] focus" 2>/dev/null
    fi
fi
