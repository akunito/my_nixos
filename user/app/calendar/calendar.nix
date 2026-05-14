{ config, pkgs, lib, systemSettings, ... }:

{
  config = lib.mkIf systemSettings.googleCalendarWidgetEnable {
    home.packages = [ pkgs.gcalcli ];

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
