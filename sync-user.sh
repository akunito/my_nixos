#!/bin/sh

# Script to synchronize user (home-manager) configuration

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Read active profile
if [ -f "$SCRIPT_DIR/.active-profile" ]; then
    ACTIVE_PROFILE=$(cat "$SCRIPT_DIR/.active-profile")
else
    echo "Error: .active-profile not found. Run install.sh first."
    exit 1
fi

# Install and build home-manager configuration
# --impure: same reason as install.sh — a profile may read machine-local files kept
# out of the repo (LAPTOP_A's Plane MCP credentials), and pure mode makes those
# silently evaluate to empty.
home-manager switch --flake $SCRIPT_DIR#$ACTIVE_PROFILE --show-trace --impure;

$SCRIPT_DIR/sync-posthook.sh
