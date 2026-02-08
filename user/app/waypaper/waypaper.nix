{
  config,
  pkgs,
  lib,
  systemSettings,
  ...
}:

let
  # Waypaper wrapper script for Sway session restoration
  # Runs `waypaper --restore` only when swww daemon is active
  waypaper-restore-wrapper = pkgs.writeShellApplication {
    name = "waypaper-restore-wrapper";
    runtimeInputs = with pkgs; [
      waypaper
      systemd
    ];
    text = ''
      #!/bin/bash
      set -euo pipefail

      # Only restore if swww daemon is running
      if systemctl --user is-active swww-daemon.service >/dev/null 2>&1; then
        waypaper --restore
      fi
    '';
  };
in
{
  config = lib.mkIf (systemSettings.waypaperEnable or false) {
    # Install Waypaper GUI package
    home.packages = with pkgs; [
      waypaper # GUI frontend for swww/swaybg wallpaper backends
    ];

    # Desktop entry for application launcher
    xdg.desktopEntries.waypaper = {
      name = "Waypaper";
      genericName = "Wallpaper Manager";
      comment = "GUI wallpaper manager for Wayland compositors (swww/swaybg)";
      exec = "waypaper";
      terminal = false;
      categories = [ "Settings" "DesktopSettings" "Utility" ];
      icon = "preferences-desktop-wallpaper";
    };

    # Systemd service for wallpaper restoration
    # Runs after swww-daemon.service to restore wallpapers on login
    systemd.user.services.waypaper-restore = {
      Unit = {
        Description = "Waypaper Wallpaper Restoration";
        After = [ "swww-daemon.service" ];
        PartOf = [ "sway-session.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };

      Service = {
        Type = "oneshot";
        RemainAfterExit = false;
        ExecStart = "${waypaper-restore-wrapper}/bin/waypaper-restore-wrapper";
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };

    # Home-Manager activation hook to restore wallpaper after HM rebuild
    # This ensures wallpapers are restored even after home-manager switch
    home.activation.waypaperRestore = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if systemctl --user is-active sway-session.target >/dev/null 2>&1; then
        run ${waypaper-restore-wrapper}/bin/waypaper-restore-wrapper
      fi
    '';
  };
}
