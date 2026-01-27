{
  pkgs,
  userSettings,
  systemSettings,
  lib,
  ...
}:

{
  home.username = userSettings.username;
  home.homeDirectory = "/home/" + userSettings.username;

  programs.home-manager.enable = true;

  imports = [
    ../../user/shell/sh.nix
    ../../user/app/ranger/ranger.nix
    ../../user/app/git/git.nix
  ];

  home.stateVersion = userSettings.homeStateVersion;
  home.packages = userSettings.homePackages;
}
