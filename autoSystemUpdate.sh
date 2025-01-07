#!/bin/sh

# Script triggered by SystemD to update System and cleanup
# Must run as root

# Set SCRIPT_DIR based on first parameter or current directory
if [ $# -gt 0 ]; then
    SCRIPT_DIR=$1
else
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
fi

# echo -e "Stopping Services/etc"
# $SCRIPT_DIR/stop_external_drives.sh

echo -e "Updating flake.lock"
$SCRIPT_DIR/update.sh

echo -e "Rebuilding system"
nixos-rebuild switch --flake $SCRIPT_DIR#system --show-trace --impure

# echo -e "Starting Services/etc"
# $SCRIPT_DIR/startup_services.sh

echo -e "Running Maintenance script"
$SCRIPT_DIR/maintenance.sh -s