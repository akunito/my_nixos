{ config, lib, pkgs, systemSettings, ... }:

let
  swaybgplusPkg = pkgs.callPackage ../../pkgs/swaybgplus.nix { };
in
{
  home.packages = lib.mkIf (systemSettings.swaybgPlusEnable or false) [
    swaybgplusPkg
    pkgs.swaybg
  ];

  # Make it easy to launch from rofi/fuzzel/drun
  xdg.desktopEntries.swaybgplus = lib.mkIf (systemSettings.swaybgPlusEnable or false) {
    name = "SwayBG+";
    comment = "Advanced multi-monitor wallpaper manager for Sway (GUI)";
    exec = "${swaybgplusPkg}/bin/swaybgplus-gui";
    terminal = false;
    categories = [ "Settings" ];
  };

  # Restore saved wallpaper configuration when a Sway session starts.
  # This is inert outside Sway because it only binds to sway-session.target.
  systemd.user.services.swaybgplus-restore = lib.mkIf (systemSettings.swaybgPlusEnable or false) {
    Unit = {
      Description = "SwayBG+ restore wallpapers";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${swaybgplusPkg}/bin/swaybgplus --restore";
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
}


