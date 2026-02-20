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

  # Atuin shell history
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    settings = {
      auto_sync = false;  # Disable cloud sync for VPS
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
    };
  };

  home.stateVersion = userSettings.homeStateVersion;
  home.packages = userSettings.homePackages;
}
