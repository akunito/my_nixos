#!/bin/bash
# Sync Claude Code OAuth credentials from local machine to VPS
# for the Matrix Claude Bot. Runs as systemd user timer.
#
# Usage:
#   sync-claude-token.sh           # sync if modified in last 48h
#   sync-claude-token.sh --force   # always sync (bypass freshness check)
set -euo pipefail

CRED_FILE="$HOME/.claude/.credentials.json"
VPS_HOST="100.64.0.6"  # VPS Tailscale IP
VPS_PORT="56777"
VPS_USER="akunito"
VPS_DEST="$VPS_USER@$VPS_HOST:.claude/.credentials.json"
FORCE=false

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

if [ ! -f "$CRED_FILE" ]; then
    echo "No credentials file found at $CRED_FILE"
    exit 1
fi

# Validate file size (reject if < 50 bytes — likely corrupt or empty)
FILE_SIZE=$(stat --format=%s "$CRED_FILE" 2>/dev/null || stat -f%z "$CRED_FILE" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 50 ]; then
    echo "Credentials file too small (${FILE_SIZE} bytes), likely corrupt — skipping sync"
    exit 1
fi

# Only sync if credentials file was modified in the last 48h (recently refreshed)
# or if --force is specified
if [ "$FORCE" = true ] || [ "$(find "$CRED_FILE" -mtime -2 2>/dev/null)" ]; then
    scp -P "$VPS_PORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
        "$CRED_FILE" "$VPS_DEST"
    echo "Synced credentials to VPS at $(date) (force=$FORCE, size=${FILE_SIZE}B)"
else
    echo "Credentials not recently modified (>48h), skipping sync (use --force to override)"
fi
