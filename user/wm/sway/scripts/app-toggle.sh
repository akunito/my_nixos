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
    local max_iterations=50  # 50 * 0.1s = 5 seconds maximum
    local poll_interval=0.1  # Poll every 0.1 seconds
    local iteration=0
    local norm_app=$(echo "$app_id" | tr '[:upper:]' '[:lower:]')
    
    while [ "$iteration" -lt "$max_iterations" ]; do
        # Check if window exists (case-insensitive, normalized)
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
            return 0  # Window found
        fi
        
        sleep "$poll_interval"
        iteration=$((iteration + 1))
    done
    
    return 1  # Timeout
}

# Function to apply sticky/floating based on APP_ID
apply_window_properties() {
    local app_id="$1"
    
    # Normalize APP_ID to lowercase for comparison
    local app_lower=$(echo "$app_id" | tr '[:upper:]' '[:lower:]')
    
    # Check if this app needs sticky/floating
    case "$app_lower" in
        "alacritty")
            # Try both case variations
            swaymsg '[app_id="Alacritty"] floating enable, sticky enable' 2>/dev/null || \
            swaymsg '[app_id="alacritty"] floating enable, sticky enable' 2>/dev/null
            ;;
        "spotify")
            # Try both XWayland (class) and Wayland (app_id)
            swaymsg '[class="Spotify"] floating enable, sticky enable' 2>/dev/null || \
            swaymsg '[app_id="spotify"] floating enable, sticky enable' 2>/dev/null
            ;;
        *)
            # No special handling needed for other apps
            return 0
            ;;
    esac
}

# 1. Get all windows (Case-Insensitive, Recursive)
# Finds all windows for the app, regardless of workspace or scratchpad state.
# Normalize APP_ID to lowercase for consistent matching
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
    
    # Wait for window to appear and apply sticky/floating properties
    # This fixes race condition where window appears before Sway applies window rules
    if wait_for_window "$APP_ID"; then
        apply_window_properties "$APP_ID"
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
        # Store the original floating state before moving to scratchpad
        ORIGINAL_FLOATING=$(swaymsg -t get_tree 2>/dev/null | jq -r --arg id "$FOCUSED_ID" '
            recurse(.nodes[]?, .floating_nodes[]?) 
            | select(.id == ($id | tonumber))
            | if .floating == "user_on" or .floating == "auto_on" then "true" else "false" end
        ' 2>/dev/null || echo "false")
        
        # Store the floating state in a temporary file (using window ID as identifier)
        TMP_FILE="/tmp/sway-window-state-${FOCUSED_ID}"
        echo "$ORIGINAL_FLOATING" > "$TMP_FILE"
        
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
    
    # 1. Smart-select the target window
    # Iterate through all IDs for this app and check if any have a saved state file.
    # This ensures we restore the specific window we hid, not a secondary/helper window.
    TARGET_ID=""
    for id in $ID_LIST; do
        if [ -f "/tmp/sway-window-state-${id}" ]; then
            TARGET_ID="$id"
            break
        fi
    done

    # Fallback: If no state file found, just pick the first one (e.g. freshly launched or manually hidden)
    if [ -z "$TARGET_ID" ]; then
        TARGET_ID=$(echo "$ID_LIST" | head -n 1)
    fi
    
    # Check if this window was previously hidden (has a state file)
    TMP_FILE="/tmp/sway-window-state-${TARGET_ID}"
    
    if [ -f "$TMP_FILE" ]; then
        # Restore the original floating state
        ORIGINAL_FLOATING=$(cat "$TMP_FILE" 2>/dev/null || echo "false")
        
        # Focus the window first (brings it from scratchpad)
        swaymsg "[con_id=$TARGET_ID] focus" 2>/dev/null
        
        # Slightly increased delay to ensure Sway processes the focus event
        sleep 0.2
        
        # Restore floating state based on what it was before
        if [ "$ORIGINAL_FLOATING" = "true" ]; then
            swaymsg "[con_id=$TARGET_ID] floating enable" 2>/dev/null
        else
            swaymsg "[con_id=$TARGET_ID] floating disable" 2>/dev/null
        fi
        
        # Clean up the temporary file
        rm -f "$TMP_FILE" 2>/dev/null
    else
        # No state file found. 
        # This implies the window was hidden manually (Mod+Minus) or is a fresh instance.
        # We simply focus it. It will likely appear Floating (Sway default for scratchpad).
        swaymsg "[con_id=$TARGET_ID] focus" 2>/dev/null
    fi
fi
