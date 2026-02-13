#!/usr/bin/env bash
# Swaylock wrapper with 4-second grace period
# If user provides input (mouse/keyboard) during the grace period, lock is cancelled.
# Uses a background swayidle instance to detect when idle ends (user becomes active).

set -euo pipefail

GRACE_PERIOD=4

# Show notification that lock is coming
notify-send -u normal -t 5000 "Screen Locking" "Locking in ${GRACE_PERIOD} seconds... (move mouse to cancel)" -h string:x-canonical-private-synchronous:screenlock

# Create a temp file that the background swayidle will touch when user becomes active.
CANCEL_FLAG=$(mktemp /tmp/swaylock-grace.XXXXXX)
rm -f "$CANCEL_FLAG"

# Spawn a short-lived swayidle that fires a 1-second timeout.
# When user provides input, swayidle's resume command creates the cancel flag.
# The trick: set timeout=1 so it fires almost immediately (we're already idle),
# then the resume command (triggered by any user input) sets the cancel flag.
swayidle -w timeout 1 "touch ${CANCEL_FLAG}.armed" resume "touch ${CANCEL_FLAG}" &
IDLE_PID=$!

# Wait for the grace period, checking for cancellation
ELAPSED=0
while (( $(echo "$ELAPSED < $GRACE_PERIOD" | bc -l) )); do
  sleep 0.5
  ELAPSED=$(echo "$ELAPSED + 0.5" | bc -l)

  if [ -f "$CANCEL_FLAG" ]; then
    notify-send -u normal -t 2000 "Lock Cancelled" "User activity detected" -h string:x-canonical-private-synchronous:screenlock
    kill "$IDLE_PID" 2>/dev/null || true
    wait "$IDLE_PID" 2>/dev/null || true
    rm -f "$CANCEL_FLAG" "${CANCEL_FLAG}.armed"
    exit 0
  fi
done

# Clean up the background swayidle
kill "$IDLE_PID" 2>/dev/null || true
wait "$IDLE_PID" 2>/dev/null || true
rm -f "$CANCEL_FLAG" "${CANCEL_FLAG}.armed"

# No input detected during grace period - proceed with lock
# --daemonize: fork so swayidle's -w flag doesn't block subsequent timeouts (monitor off, suspend)
exec swaylock --daemonize --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033 --font 'JetBrainsMono Nerd Font Mono'
