{ config, pkgs, userSettings, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = userSettings.username;
  home.homeDirectory = "/home/"+userSettings.username;

  programs.home-manager.enable = true;

  imports = [ ../work/home.nix # Personal is essentially work system + games
              # ../../user/app/games/games.nix # Various videogame apps
            ];

  home.stateVersion = "23.11"; # Please read the comment before changing.

  home.packages = with pkgs; [
    zsh
  ];

  # Run a Shell script to:
  # - Create needed directories
  home.activation = {
    runShellPreparationScript = ''
      #!/bin/sh
      echo -e "\nCreating my directories..."  
      # mkdir -p "$HOME/Syncthing"
      # mkdir -p "$HOME/Syncthing/git_repos"
      # mkdir -p "$HOME/Syncthing/My_Notes"
      # mkdir -p "$HOME/Syncthing/myLibrary"
      # mkdir -p "$HOME/Syncthing/Sync_Everywhere"
      mkdir -p "$HOME/myScripts"
    '';
  };
  # xdg.enable = true;
  # xdg.userDirs = {
  #   extraConfig = {
  #     XDG_GAME_DIR = "${config.home.homeDirectory}/Media/Games";
  #     XDG_GAME_SAVE_DIR = "${config.home.homeDirectory}/Media/Game Saves";
  #   };
  # };
}
