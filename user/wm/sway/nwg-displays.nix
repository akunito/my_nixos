{ config, lib, pkgs, systemSettings, ... }:

let
  enabled = systemSettings.nwgDisplaysEnable or false;
in
{
  config = lib.mkIf enabled {
    home.packages = with pkgs; [
      nwg-displays
      wlr-randr
    ];
  };
}
