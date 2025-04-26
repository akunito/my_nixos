{ pkgs, ... }:

{
  # OpenGL (renamed to graphics)
  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [
    rocmPackages.clr.icd
  ];

  # For 32 bit applications #AMDGPU
  hardware.graphics.extraPackages32 = with pkgs; [
    driversi686Linux.amdvlk
  ];

  # LACT - Linux AMDGPU Controller #AMDGPU
  environment.systemPackages = with pkgs; [ lact ];
  systemd.packages = with pkgs; [ lact ];
  systemd.services.lactd.wantedBy = ["multi-user.target"];

}
