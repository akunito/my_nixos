{ pkgs, systemSettings, lib, ... }:

{
  # OpenGL (renamed to graphics)
  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [
    rocmPackages.clr.icd
  ];

  # For 32 bit applications
  hardware.graphics.enable32Bit = true; # For 32 bit applications
  hardware.graphics.extraPackages32 = with pkgs; [
    driversi686Linux.amdvlk
  ];

  # LACT - Linux AMDGPU Controller #AMDGPU
  environment.systemPackages = with pkgs; lib.mkIf (systemSettings.amdLACTdriverEnable == true) [ lact ];
  systemd.packages = with pkgs;  lib.mkIf (systemSettings.amdLACTdriverEnable == true) [ lact ];
  systemd.services.lactd.wantedBy =  lib.mkIf (systemSettings.amdLACTdriverEnable == true) ["multi-user.target"];

}
