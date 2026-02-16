#!/usr/bin/env bash
# Gamescope wrapper that ensures all child processes (Wine, Proton, wineserver,
# winedevice, gamescopereaper) are cleaned up when the game exits.
#
# Usage in Steam launch options:
#   ~/.config/sway/scripts/gamescope-wrapper.sh [gamescope args] -- %command%
#
# How it works:
# 1. Starts gamescope in a new process group (setsid)
# 2. Traps EXIT to kill the entire process group
# 3. Also cleans up stale lock files and wineserver

set -euo pipefail

# Store the process group ID so we can kill everything on exit
cleanup() {
    local pgid="${GAMESCOPE_PGID:-}"
    if [[ -n "$pgid" ]]; then
        # Kill entire process group
        kill -TERM -"$pgid" 2>/dev/null || true
        sleep 1
        # Force kill any survivors
        kill -9 -"$pgid" 2>/dev/null || true
    fi

    # Clean up stale gamescope lock files
    rm -f /run/user/"$(id -u)"/gamescope-*.lock 2>/dev/null || true
}

trap cleanup EXIT

# Launch gamescope in a new session/process group
setsid gamescope "$@" &
GAMESCOPE_PID=$!
GAMESCOPE_PGID=$GAMESCOPE_PID

# Wait for gamescope to exit
wait "$GAMESCOPE_PID" 2>/dev/null || true
