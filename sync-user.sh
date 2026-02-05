#!/bin/sh

# Script to synchronize system state
# with configuration files for nixos system
# and home-manager

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Sync flake.nix with active profile
if [ -f "$SCRIPT_DIR/.active-profile" ]; then
    ACTIVE_PROFILE=$(cat "$SCRIPT_DIR/.active-profile")
    if [ -f "$SCRIPT_DIR/flake.$ACTIVE_PROFILE.nix" ]; then
        cp "$SCRIPT_DIR/flake.$ACTIVE_PROFILE.nix" "$SCRIPT_DIR/flake.nix"
    fi
fi

# Install and build home-manager configuration
home-manager switch --flake $SCRIPT_DIR#user --show-trace;

$SCRIPT_DIR/sync-posthook.sh
