{ config, pkgs, userSettings, ... }:

{

  imports = [ ../../app/terminal/alacritty.nix
              ../../app/terminal/kitty.nix
            ];

  home.packages = with pkgs; [
    flameshot
  ];

  # Plasma config > Directory symlinks
  home.file.".config/autostart/" = {
    source = ./. + builtins.toPath ("/" + userSettings.username + "/autostart");
    recursive = true;
  };
  home.file.".config/kde.org/" = { # directory. Stores settings for applications related to the KDE project under the domain kde.org. This includes a variety of modern KDE applications.
    source = ./. + builtins.toPath ("/" + userSettings.username + "/kde.org");
    recursive = true;
  };
  home.file.".config/kwin/" = { # directory. Stores configurations for KWin, the window manager for Plasma. This includes window rules, shortcuts, and effects
    source = ./. + builtins.toPath ("/" + userSettings.username + "/kwin");
    recursive = true;
  };
  home.file.".config/plasma-workspace/" = { # directory. Contains various configuration files related to the Plasma workspace, including desktop layout, panels, and widgets
    source = ./. + builtins.toPath ("/" + userSettings.username + "/plasma-workspace");
    recursive = true;
  };
  # home.file.".local/share/kactivitymanagerd/" = { # directory. Custom keybindings
  #   source = ./. + builtins.toPath ("/" + userSettings.username + "/kactivitymanagerd;
  #   recursive = true;
  # };
  home.file.".local/share/kded6/" = { # directory.
    source = ./. + builtins.toPath ("/" + userSettings.username + "/kded6");
    recursive = true;
  };
  home.file.".local/share/plasma/" = { # directory.
    source = ./. + builtins.toPath ("/" + userSettings.username + "/plasma");
    recursive = true;
  };  
  home.file.".local/share/plasmashell/" = { # directory.
    source = ./. + builtins.toPath ("/" + userSettings.username + "/plasmashell");
    recursive = true;
  };
  home.file.".local/share/systemsettings/" = { # directory.
    source = ./. + builtins.toPath ("/" + userSettings.username + "/systemsettings");
    recursive = true;
  };

  # Plasma config > Files symlinks
  home.file.".config/plasma-org.kde.plasma.desktop-appletsrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/plasma-org.kde.plasma.desktop-appletsrc"); # Desktop widgets and panels config
  home.file.".config/kdeglobals".source = ./. + builtins.toPath ("/" + userSettings.username + "/kdeglobals"); # General KDE settings
  home.file.".config/kwinrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kwinrc"); # KWin window manager settings
  home.file.".config/krunnerrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/krunnerrc"); # KRunner settings // not found
  home.file.".config/khotkeysrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/khotkeysrc"); # Custom keybindings
  home.file.".config/kscreenlockerrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kscreenlockerrc"); # Screen locker settings
  home.file.".config/kwalletrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kwalletrc"); # Kwallet settings
  home.file.".config/kcminputrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kcminputrc"); # Input settings
  home.file.".config/ksmserverrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/ksmserverrc"); # Session management settings
  home.file.".config/dolphinrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/dolphinrc"); # Dolphin file manager settings
  home.file.".config/konsolerc".source = ./. + builtins.toPath ("/" + userSettings.username + "/konsolerc"); # Konsole terminal settings
  home.file.".config/kglobalshortcutsrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kglobalshortcutsrc"); # Global shortcuts

  home.file.".config/kactivitymanagerd-pluginsrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kactivitymanagerd-pluginsrc"); # Configuration for plugins used by the KDE activity manager
  home.file.".config/kactivitymanagerd-statsrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kactivitymanagerd-statsrc"); # Stores statistical data and settings related to KDE activities
  home.file.".config/kactivitymanagerd-switcher".source = ./. + builtins.toPath ("/" + userSettings.username + "/kactivitymanagerd-switcher"); # Configuration for the activity switcher, which lets you switch between different activities
  home.file.".config/kactivitymanagerdrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kactivitymanagerdrc"); # General configuration for the KDE activity manager
  home.file.".config/kcmfonts".source = ./. + builtins.toPath ("/" + userSettings.username + "/kcmfonts"); # Stores font settings from the KDE control module
  home.file.".config/kded5rc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kded5rc"); # Configuration for the KDE Daemon (kded5), which handles various background tasks in KDE
  home.file.".config/kded6rc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kded6rc"); # Configuration file for kded6, the upcoming version of KDE Daemon, used in Plasma 6 or newer.
  home.file.".config/kfontinstuirc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kfontinstuirc"); # Stores settings for the KDE font installer interface.
  home.file.".config/kwinrulesrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kwinrulesrc"); # Stores custom window rules in KWin.
  home.file.".config/plasma-localerc".source = ./. + builtins.toPath ("/" + userSettings.username + "/plasma-localerc"); # Stores locale settings for the Plasma desktop
  home.file.".config/plasmanotifyrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/plasmanotifyrc"); # Configuration for Plasma notifications
  home.file.".config/plasmarc".source = ./. + builtins.toPath ("/" + userSettings.username + "/plasmarc"); # Stores general settings for the Plasma desktop
  home.file.".config/plasmashellrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/plasmashellrc"); # Configuration file for the Plasma shell, which manages the desktop, panels, and widgets. Wallpapers.
  home.file.".config/plasmawindowed-appletsrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/plasmawindowed-appletsrc"); # Configuration for Plasma applets in windows
  home.file.".config/plasmawindowedrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/plasmawindowedrc"); # Configuration for Plasma windows
  home.file.".config/powerdevilrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/powerdevilrc"); # Configuration for Powerdevil
  home.file.".config/powermanagementprofilesrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/powermanagementprofilesrc"); # Configuration for Power Management Profiles
  home.file.".config/spectaclerc".source = ./. + builtins.toPath ("/" + userSettings.username + "/spectaclerc"); # Configuration for Spectacle
  home.file.".config/systemsettingsrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/systemsettingsrc"); # Configuration for System Settings

  home.file.".local/share/aurorae/themes".source = ./. + builtins.toPath ("/" + userSettings.username + "/themes"); # Window decoration themes
  home.file.".local/share/color-schemes".source = ./. + builtins.toPath ("/" + userSettings.username + "/color-schemes"); # Color schemes
}
