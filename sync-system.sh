#!/bin/sh

# Script to synchronize system (NixOS) configuration

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Read active profile
if [ -f "$SCRIPT_DIR/.active-profile" ]; then
    ACTIVE_PROFILE=$(cat "$SCRIPT_DIR/.active-profile")
else
    echo "Error: .active-profile not found. Run install.sh first."
    exit 1
fi

# Rebuild system
sudo nixos-rebuild switch --flake $SCRIPT_DIR#$ACTIVE_PROFILE --show-trace;
