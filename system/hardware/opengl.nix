{ pkgs, systemSettings, lib, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # OpenGL (renamed to graphics)
  hardware.graphics.extraPackages = with pkgs; [
    rocmPackages.clr.icd
  ];

  # LACT - Linux AMDGPU Controller #AMDGPU
  environment.systemPackages = with pkgs; lib.mkIf (systemSettings.amdLACTdriverEnable == true) [ lact ];
  systemd.packages = with pkgs;  lib.mkIf (systemSettings.amdLACTdriverEnable == true) [ lact ];
  systemd.services.lactd.wantedBy =  lib.mkIf (systemSettings.amdLACTdriverEnable == true) ["multi-user.target"];


}
