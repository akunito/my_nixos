#!/usr/bin/env bash
# Swaylock wrapper with 4-second grace period
# If user provides input (mouse/keyboard) during the grace period, lock is cancelled.
# Uses a background swayidle instance to detect when idle ends (user becomes active).

set -euo pipefail

# Single-instance guard: prevent concurrent wrapper invocations and double-locks.
# If another wrapper holds the lock, OR a swaylock is already running, exit silently.
# Fixes a black-screen lockout where two swaylock daemons were spawned at once and
# fought for the same lock surfaces, leaving the compositor unable to render either.
LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/swaylock-with-grace.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  exit 0
fi
if pgrep -x swaylock >/dev/null 2>&1; then
  exit 0
fi

GRACE_PERIOD=4

# Show notification that lock is coming
notify-send -u normal -t 5000 "Screen Locking" "Locking in ${GRACE_PERIOD} seconds... (move mouse to cancel)" -h string:x-canonical-private-synchronous:screenlock

# Create a temp file that the background swayidle will touch when user becomes active.
CANCEL_FLAG=$(mktemp /tmp/swaylock-grace.XXXXXX)
rm -f "$CANCEL_FLAG"

# Spawn a short-lived swayidle to detect user activity during the grace period.
# When user provides input, swayidle's resume command creates the cancel flag.
swayidle -w timeout 1 "true" resume "touch ${CANCEL_FLAG}" &
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
    rm -f "$CANCEL_FLAG"
    exit 0
  fi
done

# Clean up the background swayidle
kill "$IDLE_PID" 2>/dev/null || true
wait "$IDLE_PID" 2>/dev/null || true
rm -f "$CANCEL_FLAG"

# Defensive: ensure all monitors are powered on before swaylock initializes its surfaces.
# Mitigates Samsung Odyssey G70NC DPMS-wake quirks that can leave outputs in a half-asleep
# state, causing the lock surfaces to be invisible after a monitor wake.
swaymsg 'output * power on' 2>/dev/null || true
sleep 0.2

# No input detected during grace period - proceed with lock
# --daemonize: fork so swayidle's -w flag doesn't block subsequent timeouts (monitor off, suspend)
# --color 000000 (NOT --screenshots): screencopy can fail when monitors are mid-DPMS-cycle or
# powered off, leaving the lock surfaces in a broken state that the compositor cannot recover
# from after monitor wake. Solid color guarantees a clean repaint. Mirrors the same fix already
# applied to services.swayidle.events.before-sleep in swayfx-config.nix.
exec swaylock --daemonize --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033 --font 'JetBrainsMono Nerd Font Mono' --color 000000
