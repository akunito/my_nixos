#!/bin/sh

# Commit GIT before running this if you made changes on these local files

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

# Create SSH directory for SSH on BOOT
sudo mkdir -p /etc/secrets/initrd/

# Check if uefi or bios
if [ -d /sys/firmware/efi/efivars ]; then
    sed -i "0,/bootMode.*=.*\".*\";/s//bootMode = \"uefi\";/" $SCRIPT_DIR/flake.nix
else
    sed -i "0,/bootMode.*=.*\".*\";/s//bootMode = \"bios\";/" $SCRIPT_DIR/flake.nix
    grubDevice=$(findmnt / | awk -F' ' '{ print $2 }' | sed 's/\[.*\]//g' | tail -n 1 | lsblk -no pkname | tail -n 1 )
    sed -i "0,/grubDevice.*=.*\".*\";/s//grubDevice = \"\/dev\/$grubDevice\";/" $SCRIPT_DIR/flake.nix
fi

# ask user if wants to replace user and mail by the current user
read -p "Do you want to replace user and mail by the current user on flake.nix ? (Y/n) " yn
case $yn in
    [Yy]|[Yy][Ee][Ss])
        # Patch flake.nix with different username/name and remove email by default
        # if the user string is followed by @, it will be ignored. eg: akunito@ will not be replaced.
        sed -i "s/akunito\([^@]\)/$(whoami)\1/" $SCRIPT_DIR/flake.nix
        sed -i "s/akunito\([^@]\)/$(getent passwd $(whoami) | cut -d ':' -f 5 | cut -d ',' -f 1)\1/" $SCRIPT_DIR/flake.nix
        sed -i "s/diego88aku@gmail.com//" $SCRIPT_DIR/flake.nix
        sed -i "s+~/.dotfiles+$SCRIPT_DIR+g" $SCRIPT_DIR/flake.nix
        ;;
esac

# ask user if wants to generate ssh keys for SSH on BOOT
read -p "Do you want to generate ssh keys for SSH on BOOT ? (Y/n) " yn
case $yn in
    [Yy]|[Yy][Ee][Ss])
        # Generate ssh keys
        sudo ssh-keygen -t rsa -N "" -f /etc/secrets/initrd/ssh_host_rsa_key
        ;;
esac

# Open up editor to manually edit flake.nix before install
if [ -z "$EDITOR" ]; then
    EDITOR=code;
fi
# $EDITOR $SCRIPT_DIR/flake.nix; DISABLED
#code $SCRIPT_DIR/flake.nix;

# Permissions for files that should be owned by root
echo "Hardening files..."
sudo $SCRIPT_DIR/harden.sh $SCRIPT_DIR;

# # CLEAR all previous IPTABLES RULES | In case you use custom IPTABLES rules
# sudo iptables -P INPUT ACCEPT
# sudo iptables -P FORWARD ACCEPT
# sudo iptables -P OUTPUT ACCEPT
# sudo iptables -t nat -F
# sudo iptables -t mangle -F
# sudo iptables -F
# sudo iptables -X

# # CLEAR all previous IP6TABLES RULES | In case you use custom IPTABLES rules
# sudo ip6tables -P INPUT ACCEPT
# sudo ip6tables -P FORWARD ACCEPT
# sudo ip6tables -P OUTPUT ACCEPT
# sudo ip6tables -t nat -F
# sudo ip6tables -t mangle -F
# sudo ip6tables -F
# sudo ip6tables -X

# Rebuild system
echo "Rebuilding system with flake... running command as 'doas' instead of 'sudo' cause a bug in nixos-rebuild"
doas nixos-rebuild switch --flake $SCRIPT_DIR#system --show-trace;

# Install and build home-manager configuration
# This runs home-manager on GIT, so you have to commit your changes first !!
echo "Installing and building home-manager"
nix run home-manager/master --extra-experimental-features nix-command --extra-experimental-features flakes -- switch --flake $SCRIPT_DIR#user --show-trace;

# TEMPORARY FOR EDITION <<<<<<<<<<<<<<<<<<<<<<< !!!!
echo "Softening files..."
sudo $SCRIPT_DIR/soften.sh $SCRIPT_DIR;
echo "---"
echo "when you finish edtion, remember to remove the soften command, or exec harden.sh"
