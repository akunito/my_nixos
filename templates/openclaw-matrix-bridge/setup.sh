#!/bin/bash
# OpenClaw Matrix Bridge Setup Script
#
# Run on VPS_PROD to install and configure the Matrix bridge for OpenClaw agents.
#
# Prerequisites:
# 1. Python 3.11+ (via NixOS profile)
# 2. Matrix server running (synapse container)
# 3. Bot users created in Matrix (alfredbot, vaultkeeperbot, scoutbot)
# 4. Access tokens saved to ~/.homelab/openclaw/matrix-token-{alfred,vaultkeeper,scout}

set -e

BRIDGE_DIR="$HOME/.openclaw-matrix-bridge"
TEMPLATES_DIR="$HOME/.dotfiles/templates/openclaw-matrix-bridge"

echo "=== OpenClaw Matrix Bridge Setup ==="

# Create bridge directory and agent subdirectories
echo "Creating directories..."
mkdir -p "$BRIDGE_DIR"
for agent in alfred vaultkeeper scout; do
    mkdir -p "$BRIDGE_DIR/$agent/store"
done

# Copy bridge files
echo "Copying bridge files..."
cp "$TEMPLATES_DIR/bridge.py" "$BRIDGE_DIR/"
cp "$TEMPLATES_DIR/requirements.txt" "$BRIDGE_DIR/"

# Copy config if not exists
if [ ! -f "$BRIDGE_DIR/config.yaml" ]; then
    echo "Copying config template..."
    cp "$TEMPLATES_DIR/config.yaml" "$BRIDGE_DIR/"
    echo "IMPORTANT: Edit $BRIDGE_DIR/config.yaml with your room IDs!"
fi

# Create virtual environment
echo "Creating Python virtual environment..."
python3 -m venv "$BRIDGE_DIR/venv"

# Install dependencies (with libolm build paths for E2E encryption)
echo "Installing Python dependencies (via nix-shell for build tools)..."
OLM_STORE_PATH="$(readlink -f /run/current-system/sw/lib/libolm.so | sed 's|/lib/libolm.so||')"
nix-shell -p gnumake gcc cmake pkg-config --run "
  export C_INCLUDE_PATH='${OLM_STORE_PATH}/include'
  export LIBRARY_PATH='/run/current-system/sw/lib'
  export CMAKE_POLICY_VERSION_MINIMUM=3.5
  '$BRIDGE_DIR/venv/bin/pip' install --upgrade pip
  '$BRIDGE_DIR/venv/bin/pip' install -r '$BRIDGE_DIR/requirements.txt'
"

# Install systemd user service
echo "Installing systemd user service..."
mkdir -p "$HOME/.config/systemd/user"
cp "$TEMPLATES_DIR/openclaw-matrix-bridge.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo ""
echo "1. Create bot users in Matrix (if not already done):"
echo "   for bot in alfred vaultkeeper scout; do"
echo "     docker exec synapse register_new_matrix_user \\"
echo "       -c /data/homeserver.yaml \\"
echo "       -u \"\${bot}bot\" \\"
echo "       -p '<STRONG_PASSWORD>' \\"
echo "       http://localhost:8008"
echo "   done"
echo ""
echo "2. Get access tokens:"
echo "   for bot in alfred vaultkeeper scout; do"
echo "     TOKEN=\$(curl -s -X POST 'http://127.0.0.1:8008/_matrix/client/v3/login' \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d \"{\\\"type\\\":\\\"m.login.password\\\",\\\"identifier\\\":{\\\"type\\\":\\\"m.id.user\\\",\\\"user\\\":\\\"\${bot}bot\\\"},\\\"password\\\":\\\"<PASSWORD>\\\",\\\"device_id\\\":\\\"OPENCLAW_\${bot^^}\\\"}\" \\"
echo "       | jq -r '.access_token')"
echo "     echo \"\$TOKEN\" > ~/.homelab/openclaw/matrix-token-\$bot"
echo "     chmod 600 ~/.homelab/openclaw/matrix-token-\$bot"
echo "   done"
echo ""
echo "3. Create E2E-encrypted rooms in Element:"
echo "   - Create private room 'Alfred' -> enable E2E -> invite @alfredbot:akunito.com"
echo "   - Create private room 'Vaultkeeper' -> enable E2E -> invite @vaultkeeperbot:akunito.com"
echo "   - Create private room 'Scout' -> enable E2E -> invite @scoutbot:akunito.com"
echo "   - Copy room IDs from room settings (Advanced tab)"
echo ""
echo "4. Edit config with room IDs:"
echo "   nano $BRIDGE_DIR/config.yaml"
echo ""
echo "5. Start the service:"
echo "   systemctl --user enable openclaw-matrix-bridge"
echo "   systemctl --user start openclaw-matrix-bridge"
echo ""
echo "6. View logs:"
echo "   journalctl --user -u openclaw-matrix-bridge -f"
