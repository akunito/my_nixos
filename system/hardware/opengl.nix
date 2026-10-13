{
  pkgs,
  pkgs-unstable,
  systemSettings,
  lib,
  ...
}:

let
  # Unstable's Mesa recipe evaluated with THIS package set (callPackage from
  # `p`), so the drivers link the same glibc/LLVM/libstdc++ as every app that
  # dlopens them. Only libdrm (Mesa 26.2 needs 2.4.134 symbols) and DirectX-Headers come along.
  # mesa-libclc 22.x refuses LLVM < 22 at configure time; LLVM 21's libclc is
  # what stable's own Mesa 25.2 builds with. Keep the expression identical for
  # 64 and 32 bit (pkgsi686Linux) so both come from one evaluation.
  mesaUnstableRecipe =
    p:
    let
      u = pkgs-unstable.path;
      libdrm = p.callPackage "${u}/pkgs/by-name/li/libdrm/package.nix" { };
      # Mesa 26.2 wants DirectX-Headers >= 1.619.1 (stable: 1.618.2), header-only
      directx-headers = p.callPackage "${u}/pkgs/by-name/di/directx-headers/package.nix" { };
    in
    p.callPackage "${u}/pkgs/development/libraries/mesa" {
      inherit libdrm directx-headers;
      mesa-libclc = p.llvmPackages_21.libclc;
      llvmPackages = p.llvmPackages_21;
    };
  mesaFromUnstable = systemSettings.mesaUnstableRecipeEnable or false;
in
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    package = lib.mkIf mesaFromUnstable (mesaUnstableRecipe pkgs);
    package32 = lib.mkIf mesaFromUnstable (mesaUnstableRecipe pkgs.pkgsi686Linux);
  };

  # OpenGL (renamed to graphics)
  # AMD-specific: ROCm OpenCL runtime for compute workloads
  hardware.graphics.extraPackages = lib.mkIf (systemSettings.gpuType == "amd") (with pkgs; [
    rocmPackages.clr.icd    # ROCm OpenCL runtime
    libva                    # VA-API library (hardware video decode)
    libva-vdpau-driver       # VDPAU backend for VA-API
    libvdpau-va-gl           # OpenGL-based VDPAU fallback
  ]);

  hardware.graphics.extraPackages32 = with pkgs; [
  ];

  # LACT - Linux AMDGPU Controller #AMDGPU
  environment.systemPackages =
    with pkgs;
    lib.mkIf (systemSettings.amdLACTdriverEnable == true) [ lact ];
  systemd.packages = with pkgs; lib.mkIf (systemSettings.amdLACTdriverEnable == true) [ lact ];
  # Guard the WHOLE lactd service under the flag. Setting only `.wantedBy` via
  # mkIf still instantiates `systemd.services.lactd`, which — when the flag is
  # false (no `lact` in systemd.packages to supply [Service]/ExecStart) — emits
  # an empty, invalid unit ("bad unit file setting", degraded systemd). Guarding
  # the service itself means it simply doesn't exist when LACT is disabled.
  systemd.services.lactd = lib.mkIf (systemSettings.amdLACTdriverEnable == true) {
    wantedBy = [ "multi-user.target" ];
  };

}
