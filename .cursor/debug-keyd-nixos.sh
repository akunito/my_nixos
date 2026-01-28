#!/usr/bin/env bash
# Comprehensive keyd debugging script for NixOS
# This script helps debug keyboard remapping issues with keyd

echo "=========================================="
echo "keyd Debugging Script for NixOS"
echo "=========================================="
echo ""

KEYD_BIN="/nix/store/820fi6f0wylfjsl08r2hrjhw3ws7ddxc-keyd-2.6.0/bin/keyd"

# Step 1: Check keyd service status
echo "[STEP 1] Checking keyd service status..."

if systemctl is-active --quiet keyd; then
  echo "✓ keyd service is ACTIVE"
  SERVICE_STATUS="active"
else
  echo "✗ keyd service is NOT ACTIVE"
  SERVICE_STATUS="inactive"
fi

# Step 2: Check keyd configuration
echo ""
echo "[STEP 2] Checking keyd configuration..."

if [ -f /etc/keyd/default.conf ]; then
  echo "✓ Configuration file exists: /etc/keyd/default.conf"
  echo "  Contents:"
  cat /etc/keyd/default.conf | sed 's/^/    /'
  
  # Check for capslock remapping
  if grep -q "capslock" /etc/keyd/default.conf; then
    CAPSLOCK_CONFIG=$(grep "capslock" /etc/keyd/default.conf)
    echo "  Found capslock config: $CAPSLOCK_CONFIG"
  else
    echo "  ✗ WARNING: No capslock configuration found!"
  fi
else
  echo "✗ Configuration file NOT found!"
fi

# Step 3: Validate configuration syntax
echo ""
echo "[STEP 3] Validating configuration syntax..."

if [ -f "$KEYD_BIN" ]; then
  VALIDATION_OUTPUT=$($KEYD_BIN check /etc/keyd/default.conf 2>&1)
  VALIDATION_EXIT=$?
  
  if [ $VALIDATION_EXIT -eq 0 ]; then
    echo "✓ Configuration syntax is VALID"
  else
    echo "✗ Configuration syntax has ERRORS:"
    echo "$VALIDATION_OUTPUT" | sed 's/^/    /'
  fi
else
  echo "✗ keyd binary not found at $KEYD_BIN"
fi

# Step 4: Check keyd logs for device matching
echo ""
echo "[STEP 4] Checking keyd logs for device matching..."

RECENT_LOGS=$(journalctl -u keyd --since "10 minutes ago" --no-pager 2>&1 | tail -30)
if echo "$RECENT_LOGS" | grep -q "046d:4075"; then
  echo "✓ Logitech keyboard (046d:4075) found in keyd logs"
  MATCHED_DEVICES=$(echo "$RECENT_LOGS" | grep "046d:4075" | tail -3)
  echo "  Recent matches:"
  echo "$MATCHED_DEVICES" | sed 's/^/    /'
else
  echo "✗ Logitech keyboard (046d:4075) NOT found in recent logs"
fi

# Step 5: Use keyd monitor to see what keyd is actually processing
echo ""
echo "[STEP 5] Using keyd monitor to see real-time key events..."
echo "  This will show what keyd sees when you press keys."
echo "  Press Caps Lock on the keyboard, then press Ctrl+C to stop."
echo ""

if [ -f "$KEYD_BIN" ]; then
  echo "Running: sudo $KEYD_BIN monitor"
  echo ""
  sudo "$KEYD_BIN" monitor 2>&1 | while IFS= read -r line; do
    echo "[MONITOR] $line"
    
    # Check if Caps Lock is being remapped
    if echo "$line" | grep -qi "caps\|lock"; then
      echo "  → CAPS LOCK DETECTED!"
    fi
    
    # Check if C-A-M is being sent
    if echo "$line" | grep -qiE "control.*alt.*meta|C-A-M|ctrl.*alt.*super"; then
      echo "  → C-A-M COMBINATION DETECTED!"
    fi
  done
else
  echo "✗ keyd binary not found, cannot run monitor"
fi

echo ""
echo "=========================================="
echo "Debugging Complete"
echo "=========================================="

