#!/bin/bash
# Claude Matrix Bot Setup Script
#
# Run on LXC_matrix to install and configure the Claude Matrix bot.
#
# Prerequisites:
# 1. Python 3.11+ installed (via NixOS profile)
# 2. Claude Code CLI installed (via NixOS profile)
# 3. Matrix server running (synapse container)
# 4. Bot user created in Matrix

set -e

BOT_DIR="$HOME/.claude-matrix-bot"
TEMPLATES_DIR="$HOME/.dotfiles/templates/matrix/claude-bot"

echo "=== Claude Matrix Bot Setup ==="

# Create bot directory
echo "Creating bot directory..."
mkdir -p "$BOT_DIR"

# Copy bot files
echo "Copying bot files..."
cp "$TEMPLATES_DIR/bot.py" "$BOT_DIR/"
cp "$TEMPLATES_DIR/claude_cli.py" "$BOT_DIR/"
cp "$TEMPLATES_DIR/session_manager.py" "$BOT_DIR/"
cp "$TEMPLATES_DIR/requirements.txt" "$BOT_DIR/"

# Copy config if not exists
if [ ! -f "$BOT_DIR/config.yaml" ]; then
    echo "Copying config template..."
    cp "$TEMPLATES_DIR/config.yaml" "$BOT_DIR/"
    echo "IMPORTANT: Edit $BOT_DIR/config.yaml with your settings!"
fi

# Create virtual environment
echo "Creating Python virtual environment..."
python3 -m venv "$BOT_DIR/venv"

# Install dependencies
echo "Installing Python dependencies..."
"$BOT_DIR/venv/bin/pip" install --upgrade pip
"$BOT_DIR/venv/bin/pip" install -r "$BOT_DIR/requirements.txt"

# Create store directory for Matrix client
mkdir -p "$BOT_DIR/store"

# Install systemd service
echo "Installing systemd user service..."
mkdir -p "$HOME/.config/systemd/user"
cp "$TEMPLATES_DIR/claude-matrix-bot.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Create bot user in Matrix:"
echo "   docker exec synapse register_new_matrix_user \\"
echo "     -c /data/homeserver.yaml \\"
echo "     -u claudebot \\"
echo "     -p <password> \\"
echo "     http://localhost:8008"
echo ""
echo "2. Get access token:"
echo "   curl -X POST 'https://matrix.local.akunito.com/_matrix/client/v3/login' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"type\":\"m.login.password\",\"user\":\"claudebot\",\"password\":\"<password>\"}'"
echo ""
echo "3. Save access token:"
echo "   echo '<access_token>' > $BOT_DIR/access_token"
echo "   chmod 600 $BOT_DIR/access_token"
echo ""
echo "4. Edit configuration:"
echo "   nano $BOT_DIR/config.yaml"
echo ""
echo "5. Start the service:"
echo "   systemctl --user enable claude-matrix-bot"
echo "   systemctl --user start claude-matrix-bot"
echo ""
echo "6. View logs:"
echo "   journalctl --user -u claude-matrix-bot -f"
