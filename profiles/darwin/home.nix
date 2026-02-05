# Darwin (macOS) Home Manager Configuration
# This is the base Home Manager configuration for macOS profiles
# Profile-specific configs (MACBOOK-KOMI, etc.) will import and extend this

{ config, pkgs, lib, systemSettings, userSettings, ... }:

{
  # Home Manager needs information about you and the paths it should manage
  home.username = userSettings.username;
  home.homeDirectory = "/Users/${userSettings.username}";

  programs.home-manager.enable = true;

  imports = [
    # === Shell & Terminal (Portable) ===
    ../../user/shell/sh.nix
    ../../user/app/terminal/tmux.nix
    ../../user/app/terminal/kitty.nix

    # === Development & Editors (Portable) ===
    ../../user/app/git/git.nix

    # === CLI Tools (Portable) ===
    ../../user/shell/cli-collection.nix
  ]
  # === Conditional Imports ===
  ++ lib.optional (userSettings.starshipEnable == true) ../../user/shell/starship.nix
  ++ lib.optional (systemSettings.nixvimEnabled == true) ../../user/app/nixvim/nixvim.nix
  ++ lib.optional (systemSettings.aichatEnable == true) ../../user/app/ai/aichat.nix
  ++ lib.optional (userSettings.hammerspoonEnable == true) ../../user/app/hammerspoon/hammerspoon.nix
  ;

  # Home packages from profile config
  home.packages = userSettings.homePackages;

  home.stateVersion = userSettings.homeStateVersion;

  # XDG directories for macOS
  xdg.enable = true;
}
