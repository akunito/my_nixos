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
  home.file.".local/share/plasma/desktoptheme/" = { # Custom Plasma themes
    source = ./source/desktoptheme;
    recursive = true;
  };
  home.file.".config/plasma-workspace/env/" = { # Env scripts run at the start of a Plasma session
    source = ./source/env;
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

  home.file.".local/share/plasma/look-and-feel".source = ./source/look-and-feel; # Look an dfeel packages
  home.file.".local/share/aurorae/themes".source = ./source/themes; # Window decoration themes
  home.file.".local/share/color-schemes".source = ./source/color-schemes; # Color schemes

}
