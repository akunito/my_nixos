#!/bin/sh

# Script to import all Plasma's dotfiles under $HOME to the current directory

# Destination directory is current directory
DEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create the destination directory if it does not exist
mkdir -p "$DEST_DIR"

# List of files and directories to copy
files=(
    "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" # Desktop widgets and panels config
    "$HOME/.config/kdeglobals" # General KDE settings
    "$HOME/.config/kwinrc" # KWin window manager settings
    "$HOME/.config/krunnerrc" # KRunner settings // not found
    "$HOME/.config/khotkeysrc" # Custom keybindings
    "$HOME/.config/kscreenlockerrc" # Screen locker settings
    "$HOME/.config/kwalletrc" # Kwallet settings
    "$HOME/.config/kcminputrc" # Input settings
    "$HOME/.config/ksmserverrc" # Session management settings
    "$HOME/.config/dolphinrc" # Dolphin file manager settings
    "$HOME/.config/konsolerc" # Konsole terminal settings
    "$HOME/.config/autostart" # Applications that start with Plasma
    "$HOME/.config/plasma-workspace/env" # Env scripts run at the start of a Plasma session
    "$HOME/.config/kglobalshortcutsrc" # Global shortcuts
    "$HOME/.local/share/plasma/desktoptheme" # Custom Plasma themes
    "$HOME/.local/share/plasma/look-and-feel" # Look an dfeel packages
    "$HOME/.local/share/aurorae/themes" # Window decoration themes
    "$HOME/.local/share/color-schemes" # Color schemes
)

# Copy each file/directory to the destination
for item in "${files[@]}"; do
    if [ -e "$item" ]; then
        # # Preserve the directory structure ? DISABLED
        # dest_path="$DEST_DIR${item/$HOME/}"
        # mkdir -p "$(dirname "$dest_path")"
        # cp -r "$item" "$dest_path"

        echo "Copied $item to $dest_path"
    else
        echo "Warning: $item does not exist and will not be copied."
    fi
done

echo "All specified dotfiles and directories have been copied to $DEST_DIR"
