#!/bin/sh

# Script to check if the needed directories are existing, and create them if not.

# Array of directories to check
DIRECTORIES=(
    "$HOME/.config/autostart"
    "$HOME/.config/kde.org"
    "$HOME/.config/kwin"
    "$HOME/.config/plasma-workspace"
    "$HOME/.local/share/kded6"
    "$HOME/.local/share/plasma"
    "$HOME/.local/share/plasmashell"
    "$HOME/.local/share/systemsettings"
)

# Function to check and create directories
check_and_create_directories() {
    local all_exist=true
    for DIRECTORY in "${DIRECTORIES[@]}"; do
        if [ -d "$DIRECTORY" ]; then
            echo "Directory $DIRECTORY already exists."
        else
            echo "Directory $DIRECTORY does not exist. Creating now."
            mkdir -p "$DIRECTORY"
            echo "Directory $DIRECTORY created."
            all_exist=false
        fi
    done
    echo $all_exist
}

# Loop until all directories are created
while [ "$(check_and_create_directories)" = "false" ]; do
    echo "Some directories were missing. Rechecking..."
done

echo "All directories are created."
