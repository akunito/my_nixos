#!/bin/sh

# Automated script to install my dotfiles

# ======================================== Variables ======================================== #
# Check if silent mode is enabled by -s or --silent
SILENT_MODE=false
for arg in "$@"; do
    if [ "$arg" = "-s" ] || [ "$arg" = "--silent" ]; then
        SILENT_MODE=true
        break
    fi
done

# Set SCRIPT_DIR based on first parameter or current directory
if [ $# -gt 0 ]; then
    SCRIPT_DIR=$1
else
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
fi

# If SCRIPT_DIR was provided, check for PROFILE parameter
if [ "$1" != "" ]; then
    if [ "$2" = "" ]; then
        echo -e "\nError: PROFILE parameter is required when providing a path"
        echo "Usage: $0 <path> <profile>"
        echo "Example: $0 /path/to/repo HOME"
        echo "Where HOME indicates the right flake to use, in this case: flake.HOME.nix"
        exit 1
    fi
    
    # Backup and replace flake.nix with the selected profile
    rm "$SCRIPT_DIR/flake.nix.bak" 2>/dev/null
    mv "$SCRIPT_DIR/flake.nix" "$SCRIPT_DIR/flake.nix.bak"
    cp "$SCRIPT_DIR/flake.$2.nix" "$SCRIPT_DIR/flake.nix"
fi

# Define sudo command based on mode
# Usage: $0 [path] [profile] <sudo_password>
if [ -n "$3" ]; then
    SUDO_PASS="$3"
    sudo_exec() {
        echo "$SUDO_PASS" | sudo -S "$@" 2>/dev/null
    }
    SUDO_CMD="sudo_exec"
else
    sudo_exec() {
        sudo "$@"
    }
    SUDO_CMD="sudo_exec"
fi

# ======================================== Functions ======================================== #
wait_for_user_input() {
    read -n 1 -s -r -p "Press any key to continue..."
}

# ======================================== Execution ======================================== #
$SUDO_CMD echo -e "\nActivating sudo password for this session"

# Overwrite $SCRIPT_DIR with the last commit of the remote repo
echo -e "\nOverwriting $SCRIPT_DIR with the last commit of the remote repo in 8 seconds: (Ctrl+C to cancel)"
read -t 8 -n 1 -s key
if [ -z "$key" ]; then
    # Fetch the latest changes from the remote repository
    git -C $SCRIPT_DIR fetch origin
    # Reset the local branch to match the remote repository
    git -C $SCRIPT_DIR reset --hard origin/main
fi

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

# Call the Docker handling script
$SCRIPT_DIR/handle_docker.sh "$SILENT_MODE"
# Check if the Docker handling script was stopped by the user
if [ $? -ne 0 ]; then
    echo "Main script stopped due to user decision in Docker handling script."
    exit 1
fi

# Generate hardware config for new system
echo -e "\nGenerating hardware config for new system"
$SUDO_CMD nixos-generate-config --show-hardware-config > $SCRIPT_DIR/system/hardware-configuration.nix

# Ask user if they want to open hardware-configuration.nix
if [ "$SILENT_MODE" = false ]; then
    echo ""
    read -p "Do you want to open hardware-configuration.nix ? (y/N) " yn
else
    yn="n"
fi
case $yn in
    [Yy]|[Yy][Ee][Ss])
        $SUDO_CMD nano $SCRIPT_DIR/system/hardware-configuration.nix
        ;;
esac

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

# Create SSH directory for SSH on BOOT
$SUDO_CMD mkdir -p /etc/secrets/initrd/
# Ask user if they want to generate SSH keys for SSH on BOOT
if [ "$SILENT_MODE" = false ]; then
    echo -e "\nOnly if didn't generate it previously on /etc/secrets/initrd"
    read -p "Do you want to generate SSH keys for SSH on BOOT ? (y/N) " yn
else
    yn="n"
fi
case $yn in
    [Yy]|[Yy][Ee][Ss])
        $SUDO_CMD ssh-keygen -t rsa -N "" -f /etc/secrets/initrd/ssh_host_rsa_key
        ;;
esac

# Permissions for files that should be owned by root
echo -e "\nHardening files..."
$SUDO_CMD $SCRIPT_DIR/harden.sh $SCRIPT_DIR

# Ask user if they want to clean iptables rules
if [ "$SILENT_MODE" = false ]; then
    echo ""
    read -p "Do you want to clean iptables rules ? (y/N) " yn
else
    yn="n"
fi
case $yn in
    [Yy]|[Yy][Ee][Ss])
        $SUDO_CMD $SCRIPT_DIR/cleaniptables.sh $SCRIPT_DIR
        ;;
esac

# Rebuild system
echo -e "\nRebuilding system with flake..."
$SUDO_CMD nixos-rebuild switch --flake $SCRIPT_DIR#system --show-trace

# Temporarily soften files for Home-Manager
echo -e "\nSoftening files for Home-Manager..."
$SUDO_CMD $SCRIPT_DIR/soften.sh $SCRIPT_DIR

# Install and build home-manager configuration
echo -e "\nInstalling and building home-manager"
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