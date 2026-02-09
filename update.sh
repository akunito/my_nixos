#!/bin/sh

# Script to update my flake without
# synchronizing configuration

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Attempt to update using flake, suppressing error messages
if ! sudo nix flake update --flake "$SCRIPT_DIR" 2>/dev/null; then
    # If the command fails, update without --flake
    sudo nix flake update "$SCRIPT_DIR"
    #sudo nix flake update "$SCRIPT_DIR" --extra-experimental-features nix-command --extra-experimental-features flakes
fi

# if fails, try adding both flags, like follows:
# sudo nix flake update . --extra-experimental-features nix-command --extra-experimental-features flakes
