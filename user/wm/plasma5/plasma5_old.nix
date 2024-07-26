{ config, pkgs, ... }:

{

  imports = [ ../../app/terminal/alacritty.nix
              ../../app/terminal/kitty.nix
            ];

  home.packages = with pkgs; [
    flameshot
  ];

  # Directories that contains dotfiles to be sourced under theirs path  <<<<
  home.file."$HOME/.config/autostart".source = ./autostart # Applications that start with Plasma
  home.file."$HOME/.local/share/plasma/desktoptheme".source = ./desktoptheme # Custom Plasma themes
  home.file."$HOME/.config/plasma-workspace/env".source = ./env # Env scripts run at the start of a Plasma session

  # Set single dotfiles for plasma under .config
  home.file."$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc".source = ./plasma-org.kde.plasma.desktop-appletsrc # Desktop widgets and panels config
  home.file."$HOME/.config/kdeglobals".source = ./kdeglobals # General KDE settings
  home.file."$HOME/.config/kwinrc".source = ./kwinrc # KWin window manager settings
  home.file."$HOME/.config/krunnerrc".source = ./krunnerrc # KRunner settings // not found
  home.file."$HOME/.config/khotkeysrc".source = ./khotkeysrc # Custom keybindings
  home.file."$HOME/.config/kscreenlockerrc".source = ./kscreenlockerrc # Screen locker settings
  home.file."$HOME/.config/kwalletrc".source = ./kwalletrc # Kwallet settings
  home.file."$HOME/.config/kcminputrc".source = ./kcminputrc # Input settings
  home.file."$HOME/.config/ksmserverrc".source = ./ksmserverrc # Session management settings
  home.file."$HOME/.config/dolphinrc".source = ./dolphinrc # Dolphin file manager settings
  home.file."$HOME/.config/konsolerc".source = ./konsolerc # Konsole terminal settings
  home.file."$HOME/.config/kglobalshortcutsrc".source = ./kglobalshortcutsrc # Global shortcuts
  home.file."$HOME/.local/share/plasma/look-and-feel".source = ./look-and-feel # Look an dfeel packages
  home.file."$HOME/.local/share/aurorae/themes".source = ./themes # Window decoration themes
  home.file."$HOME/.local/share/color-schemes".source = ./color-schemes # Color schemes

}
