{ pkgs, userSettings, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = userSettings.username;
  home.homeDirectory = "/home/"+userSettings.username;

  programs.home-manager.enable = true;

  imports = [
              ../../user/shell/sh.nix # My zsh and bash config
              ../../user/app/ranger/ranger.nix # My ranger file manager config
              ../../user/app/git/git.nix # My git config
              ../../user/app/virtualization/virtualization.nix # Virtual machines
            ];

  home.stateVersion = "24.05"; # Please read the comment before changing.

  home.packages = userSettings.homePackages;

  # home.activation = { # FOR TEST
  #     createDirectoryMyScripts = ''
  #     #!/bin/sh
  #     echo "\nRunning home.activation script TEST <<<<<<<<<<<<<<<<<<< ..." 

  #     echo "Create symlinks to Plasma settings files on my Git repo"
  #     echo "Building paths from userSettings variables (username & dotfilesDir)"
  #     echo "Home path ----> /home/''+userSettings.username+''/..."
  #     echo "Source path --> ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/..."
  #     '';
  #   };

  home.activation = { # FOR TEST
      createDirectoryMyScripts = ''
      #!/bin/sh
      echo "\nRunning home.activation script TEST <<<<<<<<<<<<<<<<<<< ..." 

      echo "Create symlinks to Plasma settings files on my Git repo"
      echo "Building paths from userSettings variables (username & dotfilesDir)"
      echo "Home path ----> /home/''+userSettings.username+''/..."
      echo "Source path --> ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/..."

      # Directories
      ln -sf /home/''+userSettings.username+''/.config/testautostart ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/autostart
      
      # Files
      ln -sf /home/''+userSettings.username+''/.config/testkdeglobals ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kdeglobals
      '';
    };
}
