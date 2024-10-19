#!/bin/sh

# Script to update my flake without
# synchronizing configuration

echo "uupdate.sh > Updating flake..."

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Update flake
sudo nix flake update $SCRIPT_DIR;
