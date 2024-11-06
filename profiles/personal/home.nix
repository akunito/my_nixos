{ config, pkgs, userSettings, systemSettings, lib, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = userSettings.username;
  home.homeDirectory = "/home/"+userSettings.username;

  programs.home-manager.enable = true;

  imports = [ ../work/home.nix # Personal is essentially work system + games
              # ../../user/app/games/games.nix # Various videogame apps
            ];

  home.stateVersion = userSettings.homeStateVersion; # Please read the comment before changing.

  home.packages = userSettings.homePackages;

  # Auto Upgrade Home Manager
  services.home-manager.autoUpgrade = lib.mkIf (systemSettings.HomeAutoUpdate == true) { 
    enable = true;
    frequency = systemSettings.HomeAutoUpdate_frecuency; 
  };

  # xdg.enable = true;
  # xdg.userDirs = {
  #   extraConfig = {
  #     XDG_GAME_DIR = "${config.home.homeDirectory}/Media/Games";
  #     XDG_GAME_SAVE_DIR = "${config.home.homeDirectory}/Media/Game Saves";
  #   };
  # };
}
