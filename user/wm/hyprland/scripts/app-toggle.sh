#!/usr/bin/env bash
# Application Toggle Script
# Toggle application: launch if not running, focus/hide if running
# Usage: app-toggle.sh <app_class> <launch_command...>
#   app_class: Window class to search for (e.g., "kitty", "chromium-browser")
#   launch_command: Command to launch if not running

set -euo pipefail

APP_CLASS="$1"
shift
LAUNCH_CMD="$@"

if [ -z "$APP_CLASS" ] || [ -z "$LAUNCH_CMD" ]; then
    echo "Usage: $0 <app_class> <launch_command...>" >&2
    exit 1
fi

# Function to wait for window to appear after launch
wait_for_window() {
    local app_class="$1"
    local max_iterations=50  # 50 * 0.1s = 5 seconds maximum
    local poll_interval=0.1  # Poll every 0.1 seconds
    local iteration=0
    
    while [ "$iteration" -lt "$max_iterations" ]; do
        # Check if window exists (case-insensitive)
        local window_exists=$(hyprctl clients -j 2>/dev/null | jq -r --arg app "$app_class" '
            [
                .[] 
                | select(
                    ((.class // "") | ascii_downcase == ($app | ascii_downcase)) or 
                    ((.initialClass // "") | ascii_downcase == ($app | ascii_downcase))
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

# Function to check if Flatpak app is installed
is_flatpak_installed() {
    local APP_ID="$1"
    if flatpak list --app --columns=application 2>/dev/null | grep -q "^${APP_ID}$"; then
        return 0
    elif [[ "$APP_ID" =~ ^(org\.|com\.|io\.|net\.|de\.|app\.) ]]; then
        # APP_ID matches Flatpak pattern - verify it's actually installed
        if flatpak info "$APP_ID" &>/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Get all windows matching the app class (case-insensitive)
WINDOW_JSON=$(hyprctl clients -j 2>/dev/null | jq -r --arg app "$APP_CLASS" '
    [
        .[] 
        | select(
            ((.class // "") | ascii_downcase == ($app | ascii_downcase)) or 
            ((.initialClass // "") | ascii_downcase == ($app | ascii_downcase))
        )
    ]
' 2>/dev/null)

# Check if app is running
if [ -z "$WINDOW_JSON" ] || [ "$WINDOW_JSON" == "[]" ]; then
    # --- APP IS NOT RUNNING -> LAUNCH ---
    
    # Check if this is a Flatpak app
    IS_FLATPAK=false
    if is_flatpak_installed "$APP_CLASS"; then
        IS_FLATPAK=true
    elif [[ "$APP_CLASS" =~ ^(org\.|com\.|io\.|net\.|de\.|app\.) ]]; then
        # APP_CLASS matches Flatpak pattern - verify it's actually installed
        if flatpak info "$APP_CLASS" &>/dev/null 2>&1; then
            IS_FLATPAK=true
        fi
    fi
    
    if [ "$IS_FLATPAK" = "true" ]; then
        # Launch via Flatpak - redirect output to prevent EPIPE errors
        flatpak run "$APP_CLASS" >/dev/null 2>&1 &
    else
        # Launch normally (use the provided command)
        # Extract first word of command to check if it exists
        CMD_FIRST=$(echo "$LAUNCH_CMD" | cut -d' ' -f1)
        
        # Check if command exists in PATH
        if command -v "$CMD_FIRST" &>/dev/null; then
            # Command exists in PATH - use it with output redirection
            $LAUNCH_CMD >/dev/null 2>&1 &
        else
            # Command not in PATH - try Nix profile locations
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
                if [ -d "$HOME/.nix-profile/bin" ]; then
                    FOUND_BIN=$(find "$HOME/.nix-profile/bin" -maxdepth 1 -iname "$CMD_FIRST" -type f -executable 2>/dev/null | head -1)
                fi
                if [ -z "$FOUND_BIN" ] && [ -d "/run/current-system/sw/bin" ]; then
                    FOUND_BIN=$(find "/run/current-system/sw/bin" -maxdepth 1 -iname "$CMD_FIRST" -type f -executable 2>/dev/null | head -1)
                fi
            fi
            
            if [ -n "$FOUND_BIN" ]; then
                # Found binary - use full path
                CMD_ARGS=$(echo "$LAUNCH_CMD" | cut -d' ' -f2-)
                if [ -n "$CMD_ARGS" ]; then
                    "$FOUND_BIN" $CMD_ARGS >/dev/null 2>&1 &
                else
                    "$FOUND_BIN" >/dev/null 2>&1 &
                fi
            elif [[ "$APP_CLASS" =~ ^(org\.|com\.|io\.|net\.|de\.|app\.) ]]; then
                # Command not found but APP_CLASS looks like Flatpak - try flatpak run as fallback
                flatpak run "$APP_CLASS" >/dev/null 2>&1 &
            else
                # Last resort - try the command anyway
                $LAUNCH_CMD >/dev/null 2>&1 &
            fi
        fi
    fi
    
    # Wait for window to appear
    if wait_for_window "$APP_CLASS"; then
        exit 0
    fi
    
    exit 0
fi

# --- APP IS RUNNING ---

# Get focused window address
FOCUSED_ADDRESS=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')

# Get all matching window addresses and workspace info
WINDOW_LIST=$(echo "$WINDOW_JSON" | jq -r '.[] | "\(.address)|\(.workspace.id)|\(.workspace.name)"')

# Count windows
WINDOW_COUNT=$(echo "$WINDOW_JSON" | jq 'length')

# Check if any window is focused
FOCUSED_WINDOW=""
while IFS='|' read -r addr workspace_id workspace_name; do
    if [ "$addr" == "$FOCUSED_ADDRESS" ]; then
        FOCUSED_WINDOW="$addr|$workspace_id|$workspace_name"
        break
    fi
done <<< "$WINDOW_LIST"

if [ -n "$FOCUSED_WINDOW" ]; then
    # --- APP IS FOCUSED ---
    
    if [ "$WINDOW_COUNT" -eq 1 ]; then
        # SINGLE WINDOW -> Hide to scratchpad
        # Use app-specific namespace (e.g., scratch_term for kitty)
        # Extract app name from class for namespace
        APP_NAME=$(echo "$APP_CLASS" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g')
        SCRATCH_NAMESPACE="scratch_${APP_NAME}"
        
        hyprctl dispatch movetoworkspacesilent "special:${SCRATCH_NAMESPACE}"
    else
        # MULTIPLE WINDOWS -> Cycle to next window
        # Get current focused window index
        CURRENT_INDEX=0
        INDEX=0
        while IFS='|' read -r addr workspace_id workspace_name; do
            if [ "$addr" == "$FOCUSED_ADDRESS" ]; then
                CURRENT_INDEX=$INDEX
                break
            fi
            INDEX=$((INDEX + 1))
        done <<< "$WINDOW_LIST"
        
        # Calculate next index (wrap around)
        NEXT_INDEX=$(((CURRENT_INDEX + 1) % WINDOW_COUNT))
        
        # Get next window address
        NEXT_ADDRESS=$(echo "$WINDOW_LIST" | sed -n "$((NEXT_INDEX + 1))p" | cut -d'|' -f1)
        
        hyprctl dispatch focuswindow "address:${NEXT_ADDRESS}"
    fi
else
    # --- APP IS NOT FOCUSED ---
    
    # Get first window info
    FIRST_WINDOW=$(echo "$WINDOW_LIST" | head -n 1)
    FIRST_ADDRESS=$(echo "$FIRST_WINDOW" | cut -d'|' -f1)
    FIRST_WORKSPACE_NAME=$(echo "$FIRST_WINDOW" | cut -d'|' -f3)
    
    # Check if window is in special workspace
    if [[ "$FIRST_WORKSPACE_NAME" =~ ^special: ]]; then
        # Window is in special workspace -> Toggle special workspace and focus
        SCRATCH_NAMESPACE=$(echo "$FIRST_WORKSPACE_NAME" | sed 's/^special://')
        
        # Toggle special workspace (shows it if hidden)
        hyprctl dispatch togglespecialworkspace "$SCRATCH_NAMESPACE"
        
        # Small delay to ensure workspace is toggled
        sleep 0.1
        
        # Focus the window
        hyprctl dispatch focuswindow "address:${FIRST_ADDRESS}"
    else
        # Window is visible on normal workspace -> Just focus it
        # CRITICAL: Do NOT toggle special workspace, or it might hide the window
        hyprctl dispatch focuswindow "address:${FIRST_ADDRESS}"
    fi
fi

exit 0

