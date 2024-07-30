#!/bin/sh

# Script to check if the needed directories are existing, and create them if not.

# Array of directories to check
DIRECTORIES=(
    "$HOME/.config/autostart"
    "$HOME/.local/share/plasma/desktoptheme"
    "$HOME/.config/plasma-workspace/env"
)

# Loop through each directory in the array
for DIRECTORY in "${DIRECTORIES[@]}"; do
    if [ -d "$DIRECTORY" ]; then
        echo "Directory $DIRECTORY already exists."
    else
        echo "Directory $DIRECTORY does not exist. Creating now."
        mkdir -p "$DIRECTORY"
        echo "Directory $DIRECTORY created."
    fi
done
