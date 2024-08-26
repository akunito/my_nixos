#!/bin/sh

# Script to check if the needed directories are existing, and create them if not.

# Array of directories to check
DIRECTORIES=(
    "$HOME/.config/autostart"
    "$HOME/.local/share/plasma/desktoptheme"
    "$HOME/.config/plasma-workspace/env"
    "$HOME/.config/kde.org" # directory. Stores settings for applications related to the KDE project under the domain kde.org. This includes a variety of modern KDE applications.
    "$HOME/.config/kwin" # directory. Stores configurations for KWin, the window manager for Plasma. This includes window rules, shortcuts, and effects
    "$HOME/.config/plasma-workspace" # directory. Contains various configuration files related to the Plasma workspace, including desktop layout, panels, and widgets
    "$HOME/.local/share/kactivitymanagerd" # directory. Custom keybindings
    "$HOME/.local/share/kded6" # directory. 
    "$HOME/.local/share/plasma" # directory. 
    "$HOME/.local/share/plasmashell" # directory. 
    "$HOME/.local/share/systemsettings" # directory. 
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

echo ""
echo "it's possible that you have to run it few times if the order was not correct. Or you can fix the script to do it rightly"

