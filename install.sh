#!/bin/sh

# Commit GIT before running this if you made changes on these local files

# Automated script to install my dotfiles

# Check for silent mode
SILENT_MODE=false
for arg in "$@"; do
    if [ "$arg" = "-s" ] || [ "$arg" = "--silent" ]; then
        SILENT_MODE=true
        break
    fi
done

# if given parameters ($1 = local repo path, $2 = PROFILE on flake.PROFILE.nix)
if [ $# -gt 0 ]; then
    SCRIPT_DIR=$1
    rm $1/flake.nix.bak && mv $1/flake.nix $1/flake.nix.bak
    cp $1/flake.$2.nix $1/flake.nix
else
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
fi

# DISABLED TO AVOID OVERWRITE FOR TESTING
# nix-shell -p git --command "git clone https://gitlab.com/akunito/nixos-config $SCRIPT_DIR"

# Ask user if they want to update the flake.nix
if [ "$SILENT_MODE" = false ]; then
    echo ""
    read -p "Do you want to update the flake.nix ? (y/N) " yn
else
    yn="y"
fi
case $yn in
    [Yy]|[Yy][Ee][Ss])
        $SCRIPT_DIR/update.sh
        ;;
esac
echo ""

# Call the Docker handling script
$SCRIPT_DIR/handle_docker.sh "$SILENT_MODE"
# Check if the Docker handling script was stopped by the user
if [ $? -ne 0 ]; then
    echo "Main script stopped due to user decision in Docker handling script."
    exit 1
fi
echo ""

# Generate hardware config for new system
echo "Generating hardware config for new system"
sudo nixos-generate-config --show-hardware-config > $SCRIPT_DIR/system/hardware-configuration.nix

# Ask user if they want to open hardware-configuration.nix
if [ "$SILENT_MODE" = false ]; then
    echo ""
    read -p "Do you want to open hardware-configuration.nix ? (y/N) " yn
else
    yn="n"
fi
case $yn in
    [Yy]|[Yy][Ee][Ss])
        sudo nano $SCRIPT_DIR/system/hardware-configuration.nix
        ;;
esac
echo ""

# Check if UEFI or BIOS
if [ -d /sys/firmware/efi/efivars ]; then
    sed -i "0,/bootMode.*=.*\".*\";/s//bootMode = \"uefi\";/" $SCRIPT_DIR/flake.nix
else
    sed -i "0,/bootMode.*=.*\".*\";/s//bootMode = \"bios\";/" $SCRIPT_DIR/flake.nix
    grubDevice=$(findmnt / | awk -F' ' '{ print $2 }' | sed 's/\[.*\]//g' | tail -n 1 | lsblk -no pkname | tail -n 1)
    sed -i "0,/grubDevice.*=.*\".*\";/s//grubDevice = \"\/dev\/$grubDevice\";/" $SCRIPT_DIR/flake.nix
fi

# Ask user if they want to replace user and email with the current user's
if [ "$SILENT_MODE" = false ]; then
    echo ""
    read -p "Do you want to replace user and mail by the current user on flake.nix ? (y/N) " yn
else
    yn="n"
fi
case $yn in
    [Yy]|[Yy][Ee][Ss])
        sed -i "s/akunito\([^@]\)/$(whoami)\1/" $SCRIPT_DIR/flake.nix
        sed -i "s/akunito\([^@]\)/$(getent passwd $(whoami) | cut -d ':' -f 5 | cut -d ',' -f 1)\1/" $SCRIPT_DIR/flake.nix
        sed -i "s/diego88aku@gmail.com//" $SCRIPT_DIR/flake.nix
        sed -i "s+~/.dotfiles+$SCRIPT_DIR+g" $SCRIPT_DIR/flake.nix
        ;;
esac
echo ""

# Create SSH directory for SSH on BOOT
sudo mkdir -p /etc/secrets/initrd/
# Ask user if they want to generate SSH keys for SSH on BOOT
if [ "$SILENT_MODE" = false ]; then
    echo ""
    echo "Only for new installations with formatted drives: "
    read -p "Do you want to generate SSH keys for SSH on BOOT ? (y/N) " yn
else
    yn="n"
fi
case $yn in
    [Yy]|[Yy][Ee][Ss])
        sudo ssh-keygen -t rsa -N "" -f /etc/secrets/initrd/ssh_host_rsa_key
        ;;
esac
echo ""

# Permissions for files that should be owned by root
echo "Hardening files..."
sudo $SCRIPT_DIR/harden.sh $SCRIPT_DIR

# Ask user if they want to clean iptables rules
if [ "$SILENT_MODE" = false ]; then
    echo ""
    read -p "Do you want to clean iptables rules ? (y/N) " yn
else
    yn="n"
fi
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

# Temporarily soften files for Home-Manager
echo ""
echo "Softening files for Home-Manager..."
sudo $SCRIPT_DIR/soften.sh $SCRIPT_DIR
echo ""

# Install and build home-manager configuration
echo "Installing and building home-manager"
nix run home-manager/master --extra-experimental-features nix-command --extra-experimental-features flakes -- switch --flake $SCRIPT_DIR#user --show-trace

# Ask user if they want to run the maintenance script
if [ "$SILENT_MODE" = false ]; then
    echo ""
    read -p "Do you want to run the maintenance script ? (y/N) " yn
else
    yn="n"
fi

if [ "$SILENT_MODE" = true ]; then
    $SCRIPT_DIR/maintenance.sh -s
elif [ "$yn" = "y" ]; then
    $SCRIPT_DIR/maintenance.sh
else
    echo "Skipping maintenance script"
fi
echo ""
