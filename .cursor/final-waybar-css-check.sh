#!/usr/bin/env bash
# Final comprehensive Waybar CSS error check
# This verifies the source file is correct and identifies what needs to be regenerated

SOURCE_FILE="/home/akunito/.dotfiles/user/wm/sway/waybar.nix"
CSS_FILE="$HOME/.config/waybar/config"
STYLE_FILE="$HOME/.config/waybar/style.css"

echo "=== Waybar CSS Error Check ==="
echo ""

# Check source file
echo "1. Checking SOURCE FILE ($SOURCE_FILE):"
echo "   - Unsupported properties:"
UNSUPPORTED_IN_SOURCE=$(grep -vE "(comment|/\*|CRITICAL|Removed)" "$SOURCE_FILE" 2>/dev/null | grep -E "(pointer-events|height:|display.*flex|justify-content|width:.*auto|max-width|min-width:.*[0-9]+px)" | grep -v "min-height:.*2px\|min-height:.*44px\|min-height:.*0" | wc -l)
if [ "$UNSUPPORTED_IN_SOURCE" -eq 0 ]; then
    echo "     ✓ No unsupported properties found"
else
    echo "     ✗ Found $UNSUPPORTED_IN_SOURCE unsupported properties"
    grep -vE "(comment|/\*|CRITICAL|Removed)" "$SOURCE_FILE" 2>/dev/null | grep -E "(pointer-events|height:|display.*flex|justify-content)" | head -5
fi

echo "   - 8-digit hex colors:"
HEX8_IN_SOURCE=$(grep -cE "#[0-9a-fA-F]{8}" "$SOURCE_FILE" 2>/dev/null || echo "0")
if [ "$HEX8_IN_SOURCE" -eq 0 ]; then
    echo "     ✓ No 8-digit hex colors (using rgba)"
else
    echo "     ✗ Found $HEX8_IN_SOURCE 8-digit hex colors"
fi

echo "   - rgba() usage:"
RGBA_IN_SOURCE=$(grep -c "hexToRgba\|rgba(" "$SOURCE_FILE" 2>/dev/null || echo "0")
echo "     ✓ Found $RGBA_IN_SOURCE rgba() color definitions"
echo ""

# Check generated CSS file
echo "2. Checking GENERATED CSS FILE ($STYLE_FILE):"
if [ ! -f "$STYLE_FILE" ]; then
    echo "   ✗ CSS file does not exist"
else
    echo "   - Unsupported properties:"
    UNSUPPORTED_IN_CSS=$(grep -vE "(comment|/\*)" "$STYLE_FILE" 2>/dev/null | grep -E "(pointer-events|height:)" | grep -v "min-height" | wc -l)
    if [ "$UNSUPPORTED_IN_CSS" -eq 0 ]; then
        echo "     ✓ No unsupported properties found"
    else
        echo "     ✗ Found $UNSUPPORTED_IN_CSS unsupported properties (NEEDS REBUILD):"
        grep -nE "(pointer-events|height:)" "$STYLE_FILE" 2>/dev/null | grep -v "min-height" | head -5
    fi
    
    echo "   - Flexbox properties:"
    FLEX_IN_CSS=$(grep -cE "(display.*flex|justify-content|width:.*auto|max-width:)" "$STYLE_FILE" 2>/dev/null || echo "0")
    if [ "$FLEX_IN_CSS" -eq 0 ]; then
        echo "     ✓ No flexbox properties"
    else
        echo "     ✗ Found $FLEX_IN_CSS flexbox properties (NEEDS REBUILD):"
        grep -nE "(display.*flex|justify-content|width:.*auto|max-width:)" "$STYLE_FILE" 2>/dev/null | head -5
    fi
    
    echo "   - 8-digit hex colors:"
    HEX8_IN_CSS=$(grep -cE "#[0-9a-fA-F]{8}" "$STYLE_FILE" 2>/dev/null || echo "0")
    if [ "$HEX8_IN_CSS" -eq 0 ]; then
        echo "     ✓ No 8-digit hex colors"
    else
        echo "     ✗ Found $HEX8_IN_CSS 8-digit hex colors (NEEDS REBUILD)"
    fi
fi
echo ""

# Test Waybar parsing
echo "3. Testing Waybar CSS parsing:"
WAYBAR_OUTPUT=$(waybar -c "$CSS_FILE" 2>&1)
if echo "$WAYBAR_OUTPUT" | grep -qi "error"; then
    echo "   ✗ Waybar reports CSS errors:"
    echo "$WAYBAR_OUTPUT" | grep -i "error" | head -3
else
    echo "   ✓ Waybar parses CSS without errors"
fi
echo ""

# Summary
echo "=== SUMMARY ==="
if [ "$UNSUPPORTED_IN_SOURCE" -eq 0 ] && [ "$HEX8_IN_SOURCE" -eq 0 ]; then
    echo "✓ SOURCE FILE: Correct - no errors found"
    if [ "$UNSUPPORTED_IN_CSS" -gt 0 ] || [ "$FLEX_IN_CSS" -gt 0 ] || [ "$HEX8_IN_CSS" -gt 0 ]; then
        echo "✗ GENERATED CSS: Stale - needs rebuild to regenerate"
        echo ""
        echo "ACTION REQUIRED: Run 'home-manager switch' to regenerate CSS file"
    else
        echo "✓ GENERATED CSS: Correct - no errors found"
    fi
else
    echo "✗ SOURCE FILE: Has errors - needs fixing"
fi

