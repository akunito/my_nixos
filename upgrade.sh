#!/bin/sh

# Script to update system and sync
# Does not pull changes from git

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

# Call the Docker handling script
$SCRIPT_DIR/handle_docker.sh "$SILENT_MODE"
# Check if the Docker handling script was stopped by the user
if [ $? -ne 0 ]; then
    echo "Main script stopped due to user decision in Docker handling script."
    exit 1
fi
echo ""

# ===================================== Start the update script
# Update flake
$SCRIPT_DIR/update.sh;

# Synchronize system
$SCRIPT_DIR/sync.sh;


# Ask user if they want to run the maintenance script
if [ "$SILENT_MODE" = false ]; then
    echo ""
    read -p "Do you want to run the maintenance script ? (y/N) " yn
else
    yn="n"
fi

# ===================================== Run the maintenance script
if [ "$SILENT_MODE" = true ]; then
    $SCRIPT_DIR/maintenance.sh -s
elif [ "$yn" = "y" ]; then
    $SCRIPT_DIR/maintenance.sh
else
    echo "Skipping maintenance script"
fi
echo ""
