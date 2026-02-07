#!/usr/bin/env bash
# Swaylock wrapper with 4-second grace period
# If user provides input (mouse/keyboard) during the grace period, lock is cancelled

set -euo pipefail

GRACE_PERIOD=4

# Show notification that lock is coming
# Use -u normal (not critical) so the timeout actually works in swaync
# Critical notifications ignore timeout and stay until dismissed
notify-send -u normal -t 5000 "Screen Locking" "Locking in ${GRACE_PERIOD} seconds... (move mouse to cancel)" -h string:x-canonical-private-synchronous:screenlock

# Get initial idle time (in milliseconds) from Sway
get_idle_time() {
  swaymsg -t get_seats -r 2>/dev/null | jq -r '.[0].idle_time // 0' 2>/dev/null || echo 0
}

INITIAL_IDLE=$(get_idle_time)

# Monitor for input during grace period (check every 0.5 seconds)
ELAPSED=0
CHECK_INTERVAL=0.5

while (( $(echo "$ELAPSED < $GRACE_PERIOD" | bc -l) )); do
  sleep "$CHECK_INTERVAL"
  ELAPSED=$(echo "$ELAPSED + $CHECK_INTERVAL" | bc -l)
  
  CURRENT_IDLE=$(get_idle_time)
  
  # If idle time decreased (user provided input), cancel lock
  if (( CURRENT_IDLE < INITIAL_IDLE )); then
    notify-send -u normal -t 2000 "Lock Cancelled" "User activity detected" -h string:x-canonical-private-synchronous:screenlock
    exit 0
  fi
done

# No input detected during grace period - proceed with lock
exec swaylock --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033
