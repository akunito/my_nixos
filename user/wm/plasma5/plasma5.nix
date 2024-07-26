{ config, pkgs, ... }:

{

  imports = [ ../../app/terminal/alacritty.nix
              ../../app/terminal/kitty.nix
            ];

  home.packages = with pkgs; [
    flameshot
  ];

  # Source them
  # home.file.".config/autostart/" = {
  #   source = ./autostart;
  #   recursive = true;
  # };
  # home.file.".local/share/plasma/desktoptheme" = { # Custom Plasma themes
  #   source = ./desktoptheme;
  #   recursive = true;
  # };
  # home.file.".config/plasma-workspace/env" = { # Env scripts run at the start of a Plasma session
  #   source = ./env;
  #   recursive = true;
  # };

  home.file.".config/zzzz".source = ./test; # test

  # # # Plasma config > Directories symlinks
  # home.file.".config/autostart".source = ./autostart; # Applications that start with Plasma
  # home.file.".local/share/plasma/desktoptheme".source = ./desktoptheme; # Custom Plasma themes
  # home.file.".config/plasma-workspace/env".source = ./env; # Env scripts run at the start of a Plasma session

  # # Plasma config > Files symlinks
  home.file.".config/plasma-org.kde.plasma.desktop-appletsrc".source = ./plasma-org.kde.plasma.desktop-appletsrc; # Desktop widgets and panels config
  home.file.".config/kdeglobals".source = ./kdeglobals; # General KDE settings
  home.file.".config/kwinrc".source = ./kwinrc; # KWin window manager settings
  home.file.".config/krunnerrc".source = ./krunnerrc; # KRunner settings // not found
  home.file.".config/khotkeysrc".source = ./khotkeysrc; # Custom keybindings
  home.file.".config/kscreenlockerrc".source = ./kscreenlockerrc; # Screen locker settings
  home.file.".config/kwalletrc".source = ./kwalletrc; # Kwallet settings
  home.file.".config/kcminputrc".source = ./kcminputrc; # Input settings
  home.file.".config/ksmserverrc".source = ./ksmserverrc; # Session management settings
  home.file.".config/dolphinrc".source = ./dolphinrc; # Dolphin file manager settings
  home.file.".config/konsolerc".source = ./konsolerc; # Konsole terminal settings
  home.file.".config/kglobalshortcutsrc".source = ./kglobalshortcutsrc; # Global shortcuts
  home.file.".local/share/plasma/look-and-feel".source = ./look-and-feel; # Look an dfeel packages
  home.file.".local/share/aurorae/themes".source = ./themes; # Window decoration themes
  home.file.".local/share/color-schemes".source = ./color-schemes; # Color schemes

}
