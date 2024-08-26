{ config, pkgs, ... }:

{

  imports = [ ../../app/terminal/alacritty.nix
              ../../app/terminal/kitty.nix
            ];

  home.packages = with pkgs; [
    flameshot
  ];

  # Plasma config > Directory symlinks
  home.file.".config/autostart/" = {
    source = ./source/autostart;
    recursive = true;
  };
  home.file.".config/kde.org/" = { # directory. Stores settings for applications related to the KDE project under the domain kde.org. This includes a variety of modern KDE applications.
    source = ./source/kde.org;
    recursive = true;
  };
  home.file.".config/kwin/" = { # directory. Stores configurations for KWin, the window manager for Plasma. This includes window rules, shortcuts, and effects
    source = ./source/kwin;
    recursive = true;
  };
  home.file.".config/plasma-workspace/" = { # directory. Contains various configuration files related to the Plasma workspace, including desktop layout, panels, and widgets
    source = ./source/plasma-workspace;
    recursive = true;
  };
  home.file.".local/share/kactivitymanagerd/" = { # directory. Custom keybindings
    source = ./source/kactivitymanagerd;
    recursive = true;
  };
  home.file.".local/share/kded6/" = { # directory.
    source = ./source/kded6;
    recursive = true;
  };
  home.file.".local/share/plasma/" = { # directory.
    source = ./source/plasma;
    recursive = true;
  };  
  home.file.".local/share/plasmashell/" = { # directory.
    source = ./source/plasmashell;
    recursive = true;
  };
  home.file.".local/share/systemsettings/" = { # directory.
    source = ./source/systemsettings;
    recursive = true;
  };

  # Plasma config > Files symlinks
  home.file.".config/plasma-org.kde.plasma.desktop-appletsrc".source = ./source/plasma-org.kde.plasma.desktop-appletsrc; # Desktop widgets and panels config
  home.file.".config/kdeglobals".source = ./source/kdeglobals; # General KDE settings
  home.file.".config/kwinrc".source = ./source/kwinrc; # KWin window manager settings
  home.file.".config/krunnerrc".source = ./source/krunnerrc; # KRunner settings // not found
  home.file.".config/khotkeysrc".source = ./source/khotkeysrc; # Custom keybindings
  home.file.".config/kscreenlockerrc".source = ./source/kscreenlockerrc; # Screen locker settings
  home.file.".config/kwalletrc".source = ./source/kwalletrc; # Kwallet settings
  home.file.".config/kcminputrc".source = ./source/kcminputrc; # Input settings
  home.file.".config/ksmserverrc".source = ./source/ksmserverrc; # Session management settings
  home.file.".config/dolphinrc".source = ./source/dolphinrc; # Dolphin file manager settings
  home.file.".config/konsolerc".source = ./source/konsolerc; # Konsole terminal settings
  home.file.".config/kglobalshortcutsrc".source = ./source/kglobalshortcutsrc; # Global shortcuts

  home.file.".config/kactivitymanagerd-pluginsrc".source = ./source/kactivitymanagerd-pluginsrc; # Configuration for plugins used by the KDE activity manager
  home.file.".config/kactivitymanagerd-statsrc".source = ./source/kactivitymanagerd-statsrc; # Stores statistical data and settings related to KDE activities
  home.file.".config/kactivitymanagerd-switcher".source = ./source/kactivitymanagerd-switcher; # Configuration for the activity switcher, which lets you switch between different activities
  home.file.".config/kactivitymanagerdrc".source = ./source/kactivitymanagerdrc; # General configuration for the KDE activity manager
  home.file.".config/kcmfonts".source = ./source/kcmfonts; # Stores font settings from the KDE control module
  home.file.".config/kded5rc".source = ./source/kded5rc; # Configuration for the KDE Daemon (kded5), which handles various background tasks in KDE
  home.file.".config/kded6rc".source = ./source/kded6rc; # Configuration file for kded6, the upcoming version of KDE Daemon, used in Plasma 6 or newer.
  home.file.".config/kfontinstuirc".source = ./source/kfontinstuirc; # Stores settings for the KDE font installer interface.
  home.file.".config/kwinrulesrc".source = ./source/kwinrulesrc; # Stores custom window rules in KWin.
  home.file.".config/plasma-localerc".source = ./source/plasma-localerc; # Stores locale settings for the Plasma desktop
  home.file.".config/plasmanotifyrc".source = ./source/plasmanotifyrc; # Configuration for Plasma notifications
  home.file.".config/plasmarc".source = ./source/plasmarc; # Stores general settings for the Plasma desktop
  home.file.".config/plasmashellrc".source = ./source/plasmashellrc; # Configuration file for the Plasma shell, which manages the desktop, panels, and widgets. Wallpapers.
  home.file.".config/plasmawindowed-appletsrc".source = ./source/plasmawindowed-appletsrc; # Configuration for Plasma applets in windows
  home.file.".config/plasmawindowedrc".source = ./source/plasmawindowedrc; # Configuration for Plasma windows
  home.file.".config/powerdevilrc".source = ./source/powerdevilrc; # Configuration for Powerdevil
  home.file.".config/powermanagementprofilesrc".source = ./source/powermanagementprofilesrc; # Configuration for Power Management Profiles
  home.file.".config/spectaclerc".source = ./source/spectaclerc; # Configuration for Spectacle
  home.file.".config/systemsettingsrc".source = ./source/systemsettingsrc; # Configuration for System Settings

  home.file.".local/share/aurorae/themes".source = ./source/themes; # Window decoration themes
  home.file.".local/share/color-schemes".source = ./source/color-schemes; # Color schemes
}
