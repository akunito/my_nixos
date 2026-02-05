# Darwin (macOS) Home Manager Configuration
# This is the base Home Manager configuration for macOS profiles
# Profile-specific configs (MACBOOK-KOMI, etc.) will import and extend this
#
# Terminal Setup (matching DESK profile):
# - sh.nix: zsh/bash config, direnv, atuin, starship (conditional via starshipEnable)
# - tmux.nix: tmux with session persistence (uses pbcopy on macOS)
# - kitty.nix: kitty terminal with tmux auto-start
# - alacritty.nix: alacritty terminal with tmux auto-start
# - cli-collection.nix: fd, bat, eza, bottom, ripgrep, fzf, etc.

{ config, pkgs, lib, systemSettings, userSettings, ... }:

{
  # Home Manager needs information about you and the paths it should manage
  home.username = userSettings.username;
  home.homeDirectory = "/Users/${userSettings.username}";

  programs.home-manager.enable = true;

  imports = [
    # === Shell & Terminal (Portable) ===
    # sh.nix includes: zsh, bash, direnv, atuin, and conditionally imports starship.nix
    ../../user/shell/sh.nix
    ../../user/app/terminal/tmux.nix
    ../../user/app/terminal/kitty.nix
    ../../user/app/terminal/alacritty.nix

    # === Development & Editors (Portable) ===
    ../../user/app/git/git.nix

    # === CLI Tools (Portable) ===
    ../../user/shell/cli-collection.nix

    # === File Manager (Portable) ===
    ../../user/app/ranger/ranger.nix

    # === Keyboard Remapping (macOS only) ===
    ../../user/app/karabiner/karabiner.nix
  ]
  # === Conditional Imports ===
  # Note: starship is already conditionally imported by sh.nix based on userSettings.starshipEnable
  ++ lib.optional (systemSettings.nixvimEnabled == true) ../../user/app/nixvim/nixvim.nix
  ++ lib.optional (systemSettings.aichatEnable == true) ../../user/app/ai/aichat.nix
  ++ lib.optional (userSettings.hammerspoonEnable == true) ../../user/app/hammerspoon/hammerspoon.nix
  ;

  # Home packages from profile config
  home.packages = userSettings.homePackages;

  home.stateVersion = userSettings.homeStateVersion;

  # XDG directories for macOS
  xdg.enable = true;

  # Session variables (matching work/home.nix)
  # Note: TERM should NOT be set here - let the terminal emulator set it
  home.sessionVariables = {
    EDITOR = userSettings.editor;
    BROWSER = userSettings.browser;
  };
}
