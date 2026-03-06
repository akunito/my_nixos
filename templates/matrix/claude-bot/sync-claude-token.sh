#!/bin/bash
# Sync Claude Code OAuth credentials from local machine to VPS
# for the Matrix Claude Bot. Runs as systemd user timer.
set -euo pipefail

CRED_FILE="$HOME/.claude/.credentials.json"
VPS_HOST="100.64.0.6"  # VPS Tailscale IP
VPS_PORT="56777"
VPS_USER="akunito"
VPS_DEST="$VPS_USER@$VPS_HOST:.claude/.credentials.json"

if [ ! -f "$CRED_FILE" ]; then
    echo "No credentials file found at $CRED_FILE"
    exit 1
fi

# Only sync if credentials file was modified in the last 24h (recently refreshed)
if [ "$(find "$CRED_FILE" -mtime -1 2>/dev/null)" ]; then
    scp -P "$VPS_PORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
        "$CRED_FILE" "$VPS_DEST"
    echo "Synced credentials to VPS at $(date)"
else
    echo "Credentials not recently modified, skipping sync"
fi
