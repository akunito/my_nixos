{ config, pkgs, userSettings, systemSettings, lib, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = userSettings.username;
  home.homeDirectory = "/home/"+userSettings.username;

  programs.home-manager.enable = true;

  imports = [ ../work/home.nix # Personal is essentially work system + games
              ../../user/packages/user-basic-pkgs.nix # Basic user packages (browsers, office, communication, etc.)
              ../../user/packages/user-ai-pkgs.nix # AI & ML packages (lmstudio, ollama-rocm)
              ../../user/app/games/games.nix # Various videogame apps
              ../../user/app/development/development.nix # Development tools (IDEs, cloud CLI)
            ]
            #++ lib.optional systemSettings.starCitizenModules ../../user/app/games/starcitizen.nix # Star Citizen support
            ;

  home.stateVersion = userSettings.homeStateVersion; # Please read the comment before changing.

  home.packages = userSettings.homePackages;

  # xdg.enable = true;
  # xdg.userDirs = {
  #   extraConfig = {
  #     XDG_GAME_DIR = "${config.home.homeDirectory}/Media/Games";
  #     XDG_GAME_SAVE_DIR = "${config.home.homeDirectory}/Media/Game Saves";
  #   };
  # };
}
