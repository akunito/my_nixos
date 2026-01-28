#!/bin/bash
# SwayFX Feature Testing Script
# Run this script after logging into Sway session to verify all features

set -e

echo "=========================================="
echo "SwayFX Feature Testing Checklist"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"

# Test counter
PASSED=0
FAILED=0
WARNINGS=0

test_check() {
    local name="$1"
    local command="$2"
    local expected="$3"
    
    echo -n "Testing: $name... "
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${PASS} PASSED"
        ((PASSED++))
        return 0
    else
        echo -e "${FAIL} FAILED"
        ((FAILED++))
        return 1
    fi
}

test_warn() {
    local name="$1"
    local message="$2"
    
    echo -e "${WARN} $name: $message"
    ((WARNINGS++))
}

echo "=== 1. Basic System Checks ==="
echo ""

# Check if we're in Sway
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$SWAYSOCK" ]; then
    echo -e "${FAIL} Not running in Sway session"
    echo "   Please run this script from within a Sway session"
    exit 1
fi

test_check "Sway session active" "[ -n \"\$SWAYSOCK\" ]" "SWAYSOCK set"

# Check if swaymsg works
test_check "swaymsg accessible" "swaymsg -t get_version" "swaymsg responds"

echo ""
echo "=== 2. Daemon Checks ==="
echo ""

test_check "Waybar running" "pgrep -x waybar" "waybar process"
test_check "swaync running" "pgrep -x swaync" "swaync process"
test_check "nm-applet running" "pgrep -x nm-applet" "nm-applet process"
test_check "blueman-applet running" "pgrep -x blueman-applet" "blueman-applet process"
test_check "nwg-dock running" "pgrep -x nwg-dock" "nwg-dock process"
test_check "libinput-gestures running" "pgrep -x libinput-gestures" "libinput-gestures process"
test_check "clipman running" "pgrep -x clipman" "clipman process"

# Check swayidle
if systemctl --user is-active --quiet swayidle.service; then
    echo -e "${PASS} swayidle service: ACTIVE"
    ((PASSED++))
else
    echo -e "${FAIL} swayidle service: INACTIVE"
    ((FAILED++))
fi

# Check polkit (should NOT be in Sway startup, only systemd)
if pgrep -x polkit-gnome-authentication-agent-1 > /dev/null; then
    POLKIT_COUNT=$(pgrep -x polkit-gnome-authentication-agent-1 | wc -l)
    if [ "$POLKIT_COUNT" -gt 1 ]; then
        echo -e "${WARN} polkit-gnome: Multiple instances detected (possible duplication)"
        ((WARNINGS++))
    else
        echo -e "${PASS} polkit-gnome: Running (single instance)"
        ((PASSED++))
    fi
else
    echo -e "${WARN} polkit-gnome: Not running (may be normal if not needed)"
    ((WARNINGS++))
fi

echo ""
echo "=== 3. Package Availability ==="
echo ""

test_check "swaybg installed" "command -v swaybg" "swaybg command"
test_check "btop installed" "command -v btop" "btop command"
test_check "grim installed" "command -v grim" "grim command"
test_check "slurp installed" "command -v slurp" "slurp command"
test_check "swappy installed" "command -v swappy" "swappy command"
test_check "rofi installed" "command -v rofi" "rofi command"
test_check "jq installed" "command -v jq" "jq command"
test_check "wl-clipboard installed" "command -v wl-copy" "wl-copy command"

echo ""
echo "=== 4. Configuration File Checks ==="
echo ""

test_check "Sway config exists" "[ -f ~/.config/sway/config ]" "config file"
test_check "Screenshot script exists" "[ -f ~/.config/sway/scripts/screenshot.sh ]" "screenshot.sh"
test_check "Screenshot script executable" "[ -x ~/.config/sway/scripts/screenshot.sh ]" "executable"
test_check "App-toggle script exists" "[ -f ~/.config/sway/scripts/app-toggle.sh ]" "app-toggle.sh"
test_check "App-toggle script executable" "[ -x ~/.config/sway/scripts/app-toggle.sh ]" "executable"
test_check "SSH-smart script exists" "[ -f ~/.config/sway/scripts/ssh-smart.sh ]" "ssh-smart.sh"
test_check "SSH-smart script executable" "[ -x ~/.config/sway/scripts/ssh-smart.sh ]" "executable"
test_check "libinput-gestures config exists" "[ -f ~/.config/libinput-gestures.conf ]" "libinput-gestures.conf"
test_check "Dock CSS exists" "[ -f ~/.config/nwg-dock/style.css ]" "nwg-dock style.css"

echo ""
echo "=== 5. Sway Configuration Verification ==="
echo ""

# Check if floating_modifier is set correctly
if swaymsg -t get_config | grep -q "floating_modifier.*mod.*normal"; then
    echo -e "${PASS} floating_modifier: Set to \$mod normal (Alt key freed)"
    ((PASSED++))
else
    echo -e "${FAIL} floating_modifier: Not set correctly"
    ((FAILED++))
fi

# Check if nwg-dock is in startup
if swaymsg -t get_config | grep -q "nwg-dock"; then
    echo -e "${PASS} nwg-dock: Found in startup commands"
    ((PASSED++))
else
    echo -e "${FAIL} nwg-dock: Not found in startup"
    ((FAILED++))
fi

# Check if wallpaper command exists (if Stylix enabled)
if swaymsg -t get_config | grep -q "swaybg"; then
    echo -e "${PASS} swaybg: Found in startup commands"
    ((PASSED++))
else
    test_warn "swaybg" "Not found (may be disabled if Stylix not enabled)"
fi

echo ""
echo "=== 6. Manual Testing Checklist ==="
echo ""
echo "Please manually test the following features:"
echo ""
echo "  [ ] Wallpaper is displayed (not grey screen)"
echo "  [ ] Waybar shows at top with all modules"
echo "  [ ] Dock appears at bottom when mouse moves there (autohide works)"
echo "  [ ] Dock shows running applications (open an app, see icon in dock)"
echo "  [ ] Alt+Arrow works in Tmux (does NOT move terminal window)"
echo "  [ ] Hyper+Space opens Rofi launcher"
echo "  [ ] Hyper+BackSpace opens Rofi launcher (alternative)"
echo "  [ ] Hyper+Tab opens Rofi window overview"
echo "  [ ] Super+Tab switches to previous workspace"
echo "  [ ] Hyper+Shift+F takes full screenshot"
echo "  [ ] Hyper+Shift+C takes area screenshot"
echo "  [ ] Screenshot opens in Swappy editor"
echo "  [ ] Workspace navigation works (Hyper+Q/W, Hyper+1-0)"
echo "  [ ] Clipboard history works (test: copy text, check history)"
echo "  [ ] Touchpad gestures work (3-finger swipe left/right)"
echo "  [ ] Lock screen works (swaylock-effects with blur)"
echo "  [ ] All application shortcuts work (Hyper+L, E, T, D, V, G, Y, S, P, C, M, B)"
echo ""

echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All automated tests passed!${NC}"
    echo "Please complete the manual testing checklist above."
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    exit 1
fi

