#!/bin/sh

# $1 = flake.nix's directory
# $2 = username

# Script triggered by SystemD service, set on autoUpgrade.sh

# Update flake.nix
echo "updating flake.nix on $1"
$which nix flake update $1

# Rebuild system
echo "Rebuilding system with flake... on $1"
$which nixos-rebuild switch --flake $1#system --show-trace

# Install and build home-manager configuration
$which home-manager switch --flake $1#user --show-trace
