{ config, pkgs, lib, systemSettings, ... }:

{
  config = lib.mkIf systemSettings.goaCalendarEnable {
    home.packages = with pkgs; [
      gnome-calendar
      gnome-control-center
    ];

    home.file.".config/sway/scripts/waybar-gcal.sh" = {
      source = ../../wm/sway/scripts/waybar-gcal.sh;
      executable = true;
    };

    home.file.".config/sway/scripts/waybar-gcal-open.sh" = {
      source = ../../wm/sway/scripts/waybar-gcal-open.sh;
      executable = true;
    };
  };
}
