!/bin/bash

# This script will remove the Plasma's dotfiles

# List of files and directories to remove
files=(
    "$HOME/.config/autostart" # Applications that start with Plasma

    "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" # Desktop widgets and panels config
    "$HOME/.config/kdeglobals" # General KDE settings
    "$HOME/.config/kwinrc" # KWin window manager settings
    "$HOME/.config/krunnerrc" # KRunner settings
    "$HOME/.config/khotkeysrc" # Custom keybindings
    "$HOME/.config/kscreenlockerrc" # Screen locker settings
    "$HOME/.config/kcminputrc" # Input settings
    "$HOME/.config/ksmserverrc" # Session management settings
    "$HOME/.config/dolphinrc" # Dolphin file manager settings
    "$HOME/.config/konsolerc" # Konsole terminal settings
    "$HOME/.config/autostart" # Applications that start with Plasma
    "$HOME/.config/kglobalshortcutsrc" # Global shortcuts
    "$HOME/.local/share/aurorae/themes" # Window decoration themes
    "$HOME/.local/share/color-schemes" # Color schemes

    "$HOME/.config/kde.org" # directory. Stores settings for applications related to the KDE project under the domain kde.org. This includes a variety of modern KDE applications.
    "$HOME/.config/kwin" # directory. Stores configurations for KWin, the window manager for Plasma. This includes window rules, shortcuts, and effects
    "$HOME/.config/plasma-workspace" # directory. Contains various configuration files related to the Plasma workspace, including desktop layout, panels, and widgets
    "$HOME/.local/share/kded6" # directory. 
    "$HOME/.local/share/plasma" # directory. 
    "$HOME/.local/share/plasmashell" # directory. 
    "$HOME/.local/share/systemsettings" # directory. 

    "$HOME/.config/kactivitymanagerd-pluginsrc" # Configuration for plugins used by the KDE activity manager
    "$HOME/.config/kactivitymanagerd-statsrc" # Stores statistical data and settings related to KDE activities
    "$HOME/.config/kactivitymanagerd-switcher" # Configuration for the activity switcher, which lets you switch between different activities
    "$HOME/.config/kactivitymanagerdrc" # General configuration for the KDE activity manager
    "$HOME/.config/kcmfonts" # Stores font settings from the KDE control module
    "$HOME/.config/kded5rc" # Configuration for the KDE Daemon (kded5), which handles various background tasks in KDE
    "$HOME/.config/kded6rc" # Configuration file for kded6, the upcoming version of KDE Daemon, used in Plasma 6 or newer.
    "$HOME/.config/kfontinstuirc" # Stores settings for the KDE font installer interface.
    "$HOME/.config/kwinrulesrc" # Stores custom window rules in KWin.
    "$HOME/.config/plasma-localerc" # Stores locale settings for the Plasma desktop
    "$HOME/.config/plasmanotifyrc" # Configuration for Plasma notifications
    "$HOME/.config/plasmarc" # Stores general settings for the Plasma desktop
    "$HOME/.config/plasmashellrc" # Configuration file for the Plasma shell, which manages the desktop, panels, and widgets. Wallpapers.
    "$HOME/.config/plasmawindowed-appletsrc" # Stores configurations for applets run in a standalone window.
    "$HOME/.config/plasmawindowedrc" # General configuration for Plasma applets in windows
    "$HOME/.config/powerdevilrc" # Configuration for PowerDevil, KDE's power management service
    "$HOME/.config/powermanagementprofilesrc" # Stores power management profiles for different scenarios (e.g., battery, plugged in).
    "$HOME/.config/spectaclerc" # Configuration file for Spectacle, KDE's screenshot tool.
    "$HOME/.config/systemsettingsrc" # Stores settings for KDE's system settings application.
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
