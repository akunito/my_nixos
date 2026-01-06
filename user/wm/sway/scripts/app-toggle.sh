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
# We recurse to find windows in tabs, stacks, floating, or scratchpad.
# CRITICAL: Use .nodes[]? and .floating_nodes[]? to handle leaf nodes safely
WINDOW_JSON=$(swaymsg -t get_tree | jq -r --arg app "$APP_ID" '
    [recurse(.nodes[]?) | select(.type=="con"), recurse(.floating_nodes[]?) | select(.type=="con")]
    | map(select((.app_id == $app) or (.window_properties.class == $app)))')

# 2. IF NOT RUNNING -> LAUNCH
if [ "$(echo "$WINDOW_JSON" | jq 'length')" -eq 0 ]; then
    $CMD &
    exit 0
fi

# 3. IDENTIFY STATE
FOCUSED_ID=$(swaymsg -t get_tree | jq -r '.. | select(.focused? == true) | .id')
ID_LIST=$(echo "$WINDOW_JSON" | jq -r '.[].id')
COUNT=$(echo "$WINDOW_JSON" | jq 'length')

# Check if the currently focused window belongs to this app
if echo "$ID_LIST" | grep -q "^$FOCUSED_ID$"; then
    # --- APP IS FOCUSED ---
    
    if [ "$COUNT" -gt 1 ]; then
        # MULTIPLE WINDOWS: Cycle to next
        # CRITICAL FIX: Use proper rotation logic to cycle through ALL windows
        # Rotate the list so the FOCUSED_ID is at the end, then pick the first element.
        # This ensures true A -> B -> C -> A cycling (not ping-pong between first two).
        NEXT_ID=$(echo "$WINDOW_JSON" | jq -r --arg focus "$FOCUSED_ID" '
            [.[].id] | . as $ids | ($ids | index($focus | tonumber)) as $idx | 
            $ids[($idx + 1) % length]')
        
        # CRITICAL: Check if next window is in scratchpad
        IS_SCRATCHPAD=$(echo "$WINDOW_JSON" | jq -r --arg id "$NEXT_ID" '.[] | select(.id == ($id|tonumber)) | .scratchpad_state')
        
        if [ "$IS_SCRATCHPAD" != "none" ] && [ "$IS_SCRATCHPAD" != "null" ]; then
            swaymsg "[con_id=$NEXT_ID] scratchpad show"
        else
            swaymsg "[con_id=$NEXT_ID] focus"
        fi
    else
        # SINGLE WINDOW: Toggle Hide (Move to Scratchpad)
        swaymsg "move scratchpad"
    fi

else
    # --- APP IS RUNNING BUT NOT FOCUSED ---
    
    # Pick the first available window to show
    TARGET_ID=$(echo "$ID_LIST" | head -n 1)
    
    # CRITICAL: Check if it is hidden in scratchpad
    IS_SCRATCHPAD=$(echo "$WINDOW_JSON" | jq -r --arg id "$TARGET_ID" '.[] | select(.id == ($id|tonumber)) | .scratchpad_state')

    if [ "$IS_SCRATCHPAD" != "none" ] && [ "$IS_SCRATCHPAD" != "null" ]; then
        # It is hidden -> Show it
        swaymsg "[con_id=$TARGET_ID] scratchpad show"
    else
        # It is visible elsewhere -> Focus it
        swaymsg "[con_id=$TARGET_ID] focus"
    fi
fi
