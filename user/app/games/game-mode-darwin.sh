#!/usr/bin/env bash
# Toggles gaming mode: pauses Spotlight indexing and Time Machine during gaming
# Usage: game-mode [on|off]

case "${1:-on}" in
  on)
    sudo mdutil -i off /          # Pause Spotlight indexing
    sudo tmutil disable           # Pause Time Machine
    echo "Gaming mode ON - Spotlight/TimeMachine paused"
    ;;
  off)
    sudo mdutil -i on /
    sudo tmutil enable
    echo "Gaming mode OFF - Spotlight/TimeMachine resumed"
    ;;
  *)
    echo "Usage: game-mode [on|off]"
    exit 1
    ;;
esac
