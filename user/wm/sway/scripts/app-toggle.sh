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

# 1. Get all windows (Case-Insensitive, Recursive)
# Finds all windows for the app, regardless of workspace or scratchpad state.
WINDOW_JSON=$(swaymsg -t get_tree 2>/dev/null | jq -r --arg app "$APP_ID" '
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

# Re-verify count to prevent race conditions (Fixes Issue 2)
ACTUAL_COUNT=$(echo "$WINDOW_JSON" | jq 'length' 2>/dev/null || echo "0")

# Check if app is currently focused
if echo "$ID_LIST" | grep -q "^$FOCUSED_ID$"; then
    # --- APP IS FOCUSED ---
    
    if [ "$ACTUAL_COUNT" -eq 1 ]; then
        # SINGLE WINDOW -> Toggle Hide
        swaymsg "move scratchpad" 2>/dev/null
    elif [ "$ACTUAL_COUNT" -gt 1 ]; then
        # MULTIPLE WINDOWS -> Cycle (Always use FOCUS)
        NEXT_ID=$(echo "$WINDOW_JSON" | jq -r --arg focus "$FOCUSED_ID" '
            [.[].id] | . as $ids | ($ids | index($focus | tonumber)) as $idx | 
            if $idx then $ids[($idx + 1) % length] else $ids[0] end')
        
        swaymsg "[con_id=$NEXT_ID] focus" 2>/dev/null
    else
        # Count is 0 or invalid (Safety fallback)
        $CMD &
    fi
else
    # --- APP IS NOT FOCUSED (ACTIVATE FIRST) ---
    # Just pick the first window in the list.
    TARGET_ID=$(echo "$ID_LIST" | head -n 1)
    
    # Always use FOCUS. 
    # If visible elsewhere -> Switches Workspace.
    # If hidden -> Shows it.
    swaymsg "[con_id=$TARGET_ID] focus" 2>/dev/null
fi
