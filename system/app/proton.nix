{ pkgs, pkgs-unstable, systemSettings, lib, ... }:

{
  environment.systemPackages = lib.mkIf (systemSettings.protongamesEnable == true) [ 
    (pkgs-unstable.bottles.override { removeWarningPopup = true; })
    pkgs-unstable.lutris
    pkgs-unstable.heroic
    pkgs-unstable.protonup-qt
    pkgs-unstable.dolphin-emu-primehack
  ];


  environment.variables = lib.mkIf (systemSettings.protongamesEnable == true) {
    BOTTLES_IGNORE_SANDBOX = "1"; # Disable unsupported environment warning
  };
}
