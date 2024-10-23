#!/bin/sh

# Commit GIT before running this if you made changes on these local files

# Automated script to install my dotfiles

# if given parameters ($1 = local repo path, $2 = PROFILE on flake.PROFILE.nix)
# Clone dotfiles & assign the right flake.nix based on the given parameter
if [ $# -gt 0 ]; then
    SCRIPT_DIR=$1
    rm $1/flake.nix.bak && mv $1/flake.nix $1/flake.nix.bak
    cp $1/flake.$2.nix $1/flake.nix
else
    SCRIPT_DIR=~/.dotfiles
fi

# DISABLED TO AVOID OVERWRITE FOR TESTING
# nix-shell -p git --command "git clone https://gitlab.com/akunito/nixos-config $SCRIPT_DIR"

# Ask user if they want to update the flake.nix
echo ""
read -p "Do you want to update the flake.nix ? (y/N) " yn
case $yn in
    [Yy]|[Yy][Ee][Ss])
        $SCRIPT_DIR/update.sh
        ;;
esac
echo ""

# Generate hardware config for new system
echo "Generating hardware config for new system"
sudo nixos-generate-config --show-hardware-config > $SCRIPT_DIR/system/hardware-configuration.nix

# Create SSH directory for SSH on BOOT
sudo mkdir -p /etc/secrets/initrd/

# Check if UEFI or BIOS
if [ -d /sys/firmware/efi/efivars ]; then
    sed -i "0,/bootMode.*=.*\".*\";/s//bootMode = \"uefi\";/" $SCRIPT_DIR/flake.nix
else
    sed -i "0,/bootMode.*=.*\".*\";/s//bootMode = \"bios\";/" $SCRIPT_DIR/flake.nix
    grubDevice=$(findmnt / | awk -F' ' '{ print $2 }' | sed 's/\[.*\]//g' | tail -n 1 | lsblk -no pkname | tail -n 1)
    sed -i "0,/grubDevice.*=.*\".*\";/s//grubDevice = \"\/dev\/$grubDevice\";/" $SCRIPT_DIR/flake.nix
fi

# Ask user if they want to replace user and email with the current user's
echo ""
read -p "Do you want to replace user and mail by the current user on flake.nix ? (y/N) " yn
case $yn in
    [Yy]|[Yy][Ee][Ss])
        # Patch flake.nix with different username/name and remove email by default
        sed -i "s/akunito\([^@]\)/$(whoami)\1/" $SCRIPT_DIR/flake.nix
        sed -i "s/akunito\([^@]\)/$(getent passwd $(whoami) | cut -d ':' -f 5 | cut -d ',' -f 1)\1/" $SCRIPT_DIR/flake.nix
        sed -i "s/diego88aku@gmail.com//" $SCRIPT_DIR/flake.nix
        sed -i "s+~/.dotfiles+$SCRIPT_DIR+g" $SCRIPT_DIR/flake.nix
        ;;
esac
echo ""

# Ask user if they want to generate SSH keys for SSH on BOOT
echo ""
echo "Only for new installations with formatted drives: "
read -p "Do you want to generate SSH keys for SSH on BOOT ? (y/N) " yn
case $yn in
    [Yy]|[Yy][Ee][Ss])
        # Generate SSH keys
        sudo ssh-keygen -t rsa -N "" -f /etc/secrets/initrd/ssh_host_rsa_key
        ;;
esac
echo ""

# # Open up editor to manually edit flake.nix before install
# if [ -z "$EDITOR" ]; then
#     EDITOR=code;
# fi
# $EDITOR $SCRIPT_DIR/flake.nix; DISABLED
# code $SCRIPT_DIR/flake.nix;

# Permissions for files that should be owned by root
echo "Hardening files..."
sudo $SCRIPT_DIR/harden.sh $SCRIPT_DIR

# Ask user if they want to clean iptables rules
echo ""
read -p "Do you want to clean iptables rules ? (y/N) " yn
case $yn in
    [Yy]|[Yy][Ee][Ss])
        $SCRIPT_DIR/cleaniptables.sh $SCRIPT_DIR
        ;;
esac
echo ""

# Rebuild system
echo ""
echo "Rebuilding system with flake..."
sudo nixos-rebuild switch --flake $SCRIPT_DIR#system --show-trace

# TEMPORARY FOR EDITION
echo ""
echo "Softening files..."
sudo $SCRIPT_DIR/soften.sh $SCRIPT_DIR
echo "---"
echo "when you finish editing, remember to remove the soften command, or exec harden.sh"
echo ""

# Install and build home-manager configuration
echo "Installing and building home-manager"
nix run home-manager/master --extra-experimental-features nix-command --extra-experimental-features flakes -- switch --flake $SCRIPT_DIR#user --show-trace

# Ask user if they want to run the maintenance script
echo ""
read -p "Do you want to run the maintenance script ? (y/N) " yn
case $yn in
    [Yy]|[Yy][Ee][Ss])
        $SCRIPT_DIR/maintenance.sh
        ;;
esac
echo ""