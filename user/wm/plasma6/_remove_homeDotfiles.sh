!/bin/bash

# This script will remove the Plasma's dotfiles

# List of files and directories to remove
files=(
    "$HOME/.config/autostart" # Applications that start with Plasma
    "$HOME/.local/share/plasma/desktoptheme" # Custom Plasma themes
    "$HOME/.config/plasma-workspace/env" # Env scripts run at the start of a Plasma session

    "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" # Desktop widgets and panels config
    "$HOME/.config/kdeglobals" # General KDE settings
    "$HOME/.config/kwinrc" # KWin window manager settings
    "$HOME/.config/krunnerrc" # KRunner settings
    "$HOME/.config/khotkeysrc" # Custom keybindings
    "$HOME/.config/kscreenlockerrc" # Screen locker settings
    "$HOME/.config/kwalletrc" # Kwallet settings
    "$HOME/.config/kcminputrc" # Input settings
    "$HOME/.config/ksmserverrc" # Session management settings
    "$HOME/.config/dolphinrc" # Dolphin file manager settings
    "$HOME/.config/konsolerc" # Konsole terminal settings
    "$HOME/.config/autostart" # Applications that start with Plasma
    "$HOME/.config/kglobalshortcutsrc" # Global shortcuts
    "$HOME/.local/share/plasma/look-and-feel" # Look and feel packages
    "$HOME/.local/share/aurorae/themes" # Window decoration themes
    "$HOME/.local/share/color-schemes" # Color schemes
)

# Loop through the files and remove them if they exist
for file in "${files[@]}"; do
    if [ -e "$file" ]; then
        echo "Removing $file..."
        rm -rf "$file"
        if [ $? -eq 0 ]; then
            echo "Successfully removed $file."
        else
            echo "Failed to remove $file."
        fi
    else
        echo "$file does not exist."
    fi
done

echo "Cleanup complete."
