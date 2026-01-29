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

  # Override: Skip disfetch on shell startup for faster SSH logins
  # Keep the custom prompt from userSettings.zshinitContent
  programs.zsh.initContent = lib.mkForce userSettings.zshinitContent;

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

  # Note: atuin, zsh, bash are configured by sh.nix
  # atuinAutoSync defaults to false (from lib/defaults.nix) so no cloud sync in LXC

  home.stateVersion = userSettings.homeStateVersion;
  home.packages = userSettings.homePackages;  # sh.nix already includes atuin
}
