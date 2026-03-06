#!/bin/bash
# OpenClaw Matrix Fallback Monitor Setup Script
#
# Run on VPS_PROD to install the Telegram fallback notification service.
#
# Prerequisites:
# 1. Python 3.11+ (via NixOS profile)
# 2. Matrix server running (synapse container)
# 3. Fallback bot user created in Matrix (@fallbackbot:akunito.com)
# 4. Access token saved to ~/.homelab/openclaw/matrix-token-fallback
# 5. Telegram bot token saved to ~/.homelab/openclaw/telegram-bot-token

set -e

FALLBACK_DIR="$HOME/.openclaw-matrix-fallback"
TEMPLATES_DIR="$HOME/.dotfiles/templates/openclaw-matrix-fallback"

echo "=== OpenClaw Matrix Fallback Monitor Setup ==="

# Create directory
echo "Creating directories..."
mkdir -p "$FALLBACK_DIR/store"

# Copy files
echo "Copying files..."
cp "$TEMPLATES_DIR/fallback-monitor.py" "$FALLBACK_DIR/"
cp "$TEMPLATES_DIR/requirements.txt" "$FALLBACK_DIR/"

# Copy config if not exists
if [ ! -f "$FALLBACK_DIR/config.yaml" ]; then
    echo "Copying config template..."
    cp "$TEMPLATES_DIR/config.yaml" "$FALLBACK_DIR/"
    echo "IMPORTANT: Edit $FALLBACK_DIR/config.yaml with room IDs and Telegram group IDs!"
fi

# Create virtual environment
echo "Creating Python virtual environment..."
python3 -m venv "$FALLBACK_DIR/venv"

# Install dependencies
echo "Installing Python dependencies (via nix-shell for build tools)..."
OLM_STORE_PATH="$(readlink -f /run/current-system/sw/lib/libolm.so | sed 's|/lib/libolm.so||')"
nix-shell -p gnumake gcc cmake pkg-config --run "
  export C_INCLUDE_PATH='${OLM_STORE_PATH}/include'
  export LIBRARY_PATH='/run/current-system/sw/lib'
  export CMAKE_POLICY_VERSION_MINIMUM=3.5
  '$FALLBACK_DIR/venv/bin/pip' install --upgrade pip
  '$FALLBACK_DIR/venv/bin/pip' install -r '$FALLBACK_DIR/requirements.txt'
"

# Install systemd user service
echo "Installing systemd user service..."
mkdir -p "$HOME/.config/systemd/user"
cp "$TEMPLATES_DIR/openclaw-matrix-fallback.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo ""
echo "1. Create fallback bot user in Matrix (if not done):"
echo "   docker exec synapse register_new_matrix_user \\"
echo "     -c /data/homeserver.yaml \\"
echo "     -u fallbackbot \\"
echo "     -p '<STRONG_PASSWORD>' \\"
echo "     http://localhost:8008"
echo ""
echo "2. Get access token:"
echo "   TOKEN=\$(curl -s -X POST 'http://127.0.0.1:8008/_matrix/client/v3/login' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"fallbackbot\"},\"password\":\"<PASSWORD>\",\"device_id\":\"OPENCLAW_FALLBACK\"}' \\"
echo "     | jq -r '.access_token')"
echo "   echo \"\$TOKEN\" > ~/.homelab/openclaw/matrix-token-fallback"
echo "   chmod 600 ~/.homelab/openclaw/matrix-token-fallback"
echo ""
echo "3. Save Telegram bot token (reuse existing OpenClaw bot token):"
echo "   echo '<TELEGRAM_BOT_TOKEN>' > ~/.homelab/openclaw/telegram-bot-token"
echo "   chmod 600 ~/.homelab/openclaw/telegram-bot-token"
echo ""
echo "4. Invite @fallbackbot:akunito.com to all 3 agent rooms in Element"
echo ""
echo "5. Edit config with room IDs and Telegram group IDs:"
echo "   nano $FALLBACK_DIR/config.yaml"
echo ""
echo "6. Start the service:"
echo "   systemctl --user enable openclaw-matrix-fallback"
echo "   systemctl --user start openclaw-matrix-fallback"
echo ""
echo "7. View logs:"
echo "   journalctl --user -u openclaw-matrix-fallback -f"
