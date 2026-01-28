{
  pkgs,
  systemSettings,
  lib,
  ...
}:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # OpenGL (renamed to graphics)
  # AMD-specific: ROCm OpenCL runtime for compute workloads
  hardware.graphics.extraPackages = lib.mkIf (systemSettings.gpuType == "amd") (with pkgs; [
    rocmPackages.clr.icd
  ]);

  hardware.graphics.extraPackages32 = with pkgs; [
  ];

  # LACT - Linux AMDGPU Controller #AMDGPU
  environment.systemPackages =
    with pkgs;
    lib.mkIf (systemSettings.amdLACTdriverEnable == true) [ lact ];
  systemd.packages = with pkgs; lib.mkIf (systemSettings.amdLACTdriverEnable == true) [ lact ];
  systemd.services.lactd.wantedBy = lib.mkIf (systemSettings.amdLACTdriverEnable == true) [
    "multi-user.target"
  ];

}
