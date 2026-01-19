{ config, pkgs, userSettings, lib, ... }:

{
  # File manager configuration module
  # Handles both Ranger and Dolphin, setting the default based on userSettings.fileManager
  # 
  # This module:
  #   - Enables XDG MIME configuration for proper file manager associations
  #   - Sets the default file manager for directories (inode/directory MIME type)
  #   - Automatically installs Dolphin if selected (Ranger is installed via user/app/ranger/ranger.nix)
  #
  # Usage:
  #   To switch file managers, override userSettings.fileManager in your profile config file
  #   (e.g., profiles/PROFILE-config.nix or in flake.PROFILE.nix):
  #
  #   userSettings = {
  #     fileManager = "dolphin";  # or "ranger" (default)
  #   };
  #
  #   Default is "ranger" (defined in lib/defaults.nix)
  #
  #   After changing, rebuild with: ./sync-user.sh

  # Enable XDG MIME configuration
  xdg.mime.enable = true;
  xdg.mimeApps.enable = true;

  # Set default file manager for directories based on userSettings.fileManager
  xdg.mimeApps.defaultApplications = 
    if userSettings.fileManager == "dolphin" then {
      "inode/directory" = "org.kde.dolphin.desktop";
    } else {
      # Default to ranger
      "inode/directory" = "ranger.desktop";
    };

  # Automatically add Dolphin to packages if it's selected as the file manager
  # Ranger is already included via user/app/ranger/ranger.nix
  home.packages = lib.optional (userSettings.fileManager == "dolphin") pkgs.kdePackages.dolphin;
}
