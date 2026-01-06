#!/bin/sh
# Smart application toggle/cycle/launch script
# Usage: app-toggle.sh <app_name>
#
# Logic:
# - If app is not open -> Launch it
# - If app is open and focused -> Move to Scratchpad (Hide)
# - If app is open but not focused -> Focus it
# - If multiple windows exist -> Cycle focus

APP_NAME="$1"

if [ -z "$APP_NAME" ]; then
    echo "Usage: app-toggle.sh <app_name>"
    exit 1
fi

# Get list of windows matching the app (check both app_id for Wayland and class for XWayland)
# Handle special cases for apps with multiple possible app_id values
case "$APP_NAME" in
    telegram-desktop)
        WINDOWS=$(swaymsg -t get_tree | jq -r "
            recurse(.nodes[]?, .floating_nodes[]?)
            | select(.type == \"con\")
            | select(.app_id == \"org.telegram.desktop\" or .app_id == \"telegram-desktop\")
            | .id
        ")
        ;;
    dolphin)
        WINDOWS=$(swaymsg -t get_tree | jq -r "
            recurse(.nodes[]?, .floating_nodes[]?)
            | select(.type == \"con\")
            | select(.app_id == \"org.kde.dolphin\" or .window_properties.class == \"Dolphin\" or .window_properties.class == \"dolphin\")
            | .id
        ")
        ;;
    bitwarden-desktop)
        WINDOWS=$(swaymsg -t get_tree | jq -r "
            recurse(.nodes[]?, .floating_nodes[]?)
            | select(.type == \"con\")
            | select(.app_id == \"bitwarden\" or .app_id == \"bitwarden-desktop\")
            | .id
        ")
        ;;
    *)
        WINDOWS=$(swaymsg -t get_tree | jq -r "
            recurse(.nodes[]?, .floating_nodes[]?)
            | select(.type == \"con\")
            | select(.app_id == \"$APP_NAME\" or .window_properties.class == \"$APP_NAME\")
            | .id
        ")
        ;;
esac

if [ -z "$WINDOWS" ]; then
    # App is not open, launch it
    case "$APP_NAME" in
        telegram-desktop)
            telegram-desktop &
            ;;
        dolphin)
            dolphin &
            ;;
        kitty)
            kitty &
            ;;
        obsidian)
            obsidian --no-sandbox --ozone-platform=wayland --ozone-platform-hint=auto --enable-features=UseOzonePlatform,WaylandWindowDecorations &
            ;;
        vivaldi)
            vivaldi &
            ;;
        chromium)
            chromium &
            ;;
        spotify)
            spotify --enable-features=UseOzonePlatform --ozone-platform=wayland &
            ;;
        nwg-look)
            nwg-look &
            ;;
        bitwarden-desktop)
            bitwarden &
            ;;
        code)
            code --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform-hint=auto --unity-launch &
            ;;
        cursor)
            cursor --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform-hint=auto --unity-launch &
            ;;
        mission-center)
            mission-center &
            ;;
        bottles)
            bottles &
            ;;
        *)
            # Try to launch as-is
            $APP_NAME &
            ;;
    esac
else
    # App is open, check if focused
    FOCUSED_WINDOW=$(swaymsg -t get_tree | jq -r '.. | select(.type? == "con" and .focused? == true) | .id')
    
    # Count number of windows
    WINDOW_COUNT=$(echo "$WINDOWS" | wc -l)
    
    if [ "$WINDOW_COUNT" -eq 1 ]; then
        # Single window
        WINDOW_ID=$(echo "$WINDOWS" | head -n1)
        
        if [ "$FOCUSED_WINDOW" = "$WINDOW_ID" ]; then
            # Window is focused, move to scratchpad
            swaymsg "[id=$WINDOW_ID] move scratchpad"
        else
            # Window is not focused, focus it
            swaymsg "[id=$WINDOW_ID] focus"
        fi
    else
        # Multiple windows, cycle focus
        # Get currently focused window ID
        if echo "$WINDOWS" | grep -q "^$FOCUSED_WINDOW$"; then
            # Currently focused window is in the list, focus next
            NEXT_WINDOW=$(echo "$WINDOWS" | grep -A1 "^$FOCUSED_WINDOW$" | tail -n1)
            if [ -z "$NEXT_WINDOW" ]; then
                # Wrap around to first
                NEXT_WINDOW=$(echo "$WINDOWS" | head -n1)
            fi
            swaymsg "[id=$NEXT_WINDOW] focus"
        else
            # No window from this app is focused, focus first
            FIRST_WINDOW=$(echo "$WINDOWS" | head -n1)
            swaymsg "[id=$FIRST_WINDOW] focus"
        fi
    fi
fi

