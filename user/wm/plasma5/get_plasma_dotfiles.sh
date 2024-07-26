#!/bin/sh

# script to get all dotfiles for plasma5 under $HOME to current directory

#!/bin/bash

# Destination directory is current directory
DEST_DIR="$(pwd)"

# Create the destination directory if it does not exist
mkdir -p "$DEST_DIR"

# List of files and directories to copy
files=(
    "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    "$HOME/.config/kdeglobals"
    "$HOME/.config/kwinrc"
    "$HOME/.config/krunnerrc"
    "$HOME/.config/khotkeysrc"
    "$HOME/.config/kscreenlockerrc"
    "$HOME/.config/kwalletrc"
    "$HOME/.config/kcminputrc"
    "$HOME/.config/ksmserverrc"
    "$HOME/.local/share/plasma/desktoptheme"
    "$HOME/.local/share/plasma/look-and-feel"
    "$HOME/.local/share/aurorae/themes"
    "$HOME/.local/share/color-schemes"
    "$HOME/.config/autostart"
    "$HOME/.config/plasma-workspace/env"
    "$HOME/.config/kglobalshortcutsrc"
    "$HOME/.config/khotkeysrc" # Duplicate entry, but kept for completeness
    "$HOME/.config/dolphinrc"
    "$HOME/.config/konsole"
)

# Copy each file/directory to the destination
for item in "${files[@]}"; do
    if [ -e "$item" ]; then
        # Preserve the directory structure
        dest_path="$DEST_DIR${item/$HOME/}"
        mkdir -p "$(dirname "$dest_path")"
        cp -r "$item" "$dest_path"
        echo "Copied $item to $dest_path"
    else
        echo "Warning: $item does not exist and will not be copied."
    fi
done

echo "All specified dotfiles and directories have been copied to $DEST_DIR"
