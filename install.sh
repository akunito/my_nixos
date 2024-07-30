#!/bin/sh

# FORK: I have adjusted to my basic user and mail. But I never test it.

# Automated script to install my dotfiles

# Clone dotfiles
if [ $# -gt 0 ]
  then
    SCRIPT_DIR=$1
  else
    SCRIPT_DIR=~/.dotfiles
fi

# DISABLED TO AVOID OVERWRITE FOR TESTING
# nix-shell -p git --command "git clone https://gitlab.com/akunito/nixos-config $SCRIPT_DIR"

# Generate hardware config for new system
sudo nixos-generate-config --show-hardware-config > $SCRIPT_DIR/system/hardware-configuration.nix

# Check if uefi or bios
if [ -d /sys/firmware/efi/efivars ]; then
    sed -i "0,/bootMode.*=.*\".*\";/s//bootMode = \"uefi\";/" $SCRIPT_DIR/flake.nix
else
    sed -i "0,/bootMode.*=.*\".*\";/s//bootMode = \"bios\";/" $SCRIPT_DIR/flake.nix
    grubDevice=$(findmnt / | awk -F' ' '{ print $2 }' | sed 's/\[.*\]//g' | tail -n 1 | lsblk -no pkname | tail -n 1 )
    sed -i "0,/grubDevice.*=.*\".*\";/s//grubDevice = \"\/dev\/$grubDevice\";/" $SCRIPT_DIR/flake.nix
fi

# Patch flake.nix with different username/name and remove email by default
sed -i "0,/akunito/s//$(whoami)/" $SCRIPT_DIR/flake.nix
sed -i "0,/akunito/s//$(getent passwd $(whoami) | cut -d ':' -f 5 | cut -d ',' -f 1)/" $SCRIPT_DIR/flake.nix
sed -i "s/diego88aku@gmail.com//" $SCRIPT_DIR/flake.nix
sed -i "s+~/.dotfiles+$SCRIPT_DIR+g" $SCRIPT_DIR/flake.nix

# Open up editor to manually edit flake.nix before install
if [ -z "$EDITOR" ]; then
    EDITOR=code;
fi
# $EDITOR $SCRIPT_DIR/flake.nix; DISABLED
#code $SCRIPT_DIR/flake.nix;

# Permissions for files that should be owned by root
echo "Hardening files..."
sudo $SCRIPT_DIR/harden.sh $SCRIPT_DIR;

# Rebuild system
echo "Rebuilding system with flake..."
sudo nixos-rebuild switch --flake $SCRIPT_DIR#system --show-trace;

# Install and build home-manager configuration
# This runs home-manager on GIT, so you have to commit your changes first !!
echo "Installing and building home-manager"
nix run home-manager/master --extra-experimental-features nix-command --extra-experimental-features flakes -- switch --flake $SCRIPT_DIR#user --show-trace;

# TEMPORARY FOR EDITION <<<<<<<<<<<<<<<<<<<<<<< !!!!
echo "Softening files..."
sudo $SCRIPT_DIR/soften.sh $SCRIPT_DIR;
echo "---"
echo "when you finish edtion, remember to remove the soften command, or exec harden.sh"
