{ config, lib, pkgs, systemSettings, ... }:

lib.mkIf systemSettings.goaCalendarEnable {
  services.gnome.gnome-online-accounts.enable = true;
  services.gnome.evolution-data-server.enable = true;

  environment.systemPackages = with pkgs; [
    gnome-online-accounts
    evolution-data-server
  ];
}
