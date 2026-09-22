{
  pkgs,
  userSettings,
  systemSettings,
  lib,
  ...
}:

{
  # Import full shell configuration (sh.nix) for better UX
  # Provides: bat, eza, bottom, fd, direnv, and colored aliases
  # All packages have zero idle overhead (only consume resources when actively used)
  imports = [
    ../../user/shell/sh.nix
  ];

  home.username = userSettings.username;
  home.homeDirectory = "/home/" + userSettings.username;

  programs.home-manager.enable = true;

  # Atuin shell history - override sh.nix config to ensure it works in LXC
  # Note: sh.nix already includes atuin package in home.packages
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    settings = {
      auto_sync = false;  # Disable cloud sync for LXC containers
      sync_frequency = "5m";
      sync_address = "https://api.atuin.sh";
      enter_accept = true;
      records = true;
    };
  };

  # Git without libsecret (SSH key auth only, avoids dbus/gnome-keyring deps)
  programs.git = {
    enable = true;
    settings = {
      user.name = userSettings.gitUser;
      user.email = userSettings.gitEmail;
      init.defaultBranch = "main";
      pull.rebase = true;
      color.ui = "auto";
      # install.sh's harden.sh chowns ~/.dotfiles to root:root for the whole
      # nixos-rebuild (install.sh:1213 -> soften at 1374). Without this, a
      # concurrent `git fetch` as the user dies with "dubious ownership" and
      # the deploy's `&&` chain stops — bit VPS_PROD on 2026-09-22 when two
      # sessions deployed at once. user/app/git/git.nix has the same list,
      # which is why the desktops never see this race.
      safe.directory = [
        ("/home/" + userSettings.username + "/.dotfiles")
        ("/home/" + userSettings.username + "/.dotfiles/.git")
      ];
    };
  };

  # Note: zsh, bash, and shell packages (bat, eza, etc.) are configured by sh.nix
  # atuin package comes from sh.nix, but we configure it here to ensure proper integration

  home.stateVersion = userSettings.homeStateVersion;
  home.packages = userSettings.homePackages;  # Merged with sh.nix packages
}
