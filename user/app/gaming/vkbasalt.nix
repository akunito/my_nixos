{
  lib,
  pkgs,
  userSettings,
  ...
}:

let
  cfgEnable = (userSettings.vkbasaltEnable or false);
in
{
  home.packages = lib.mkIf cfgEnable [ pkgs.vkbasalt ];

  # vkBasalt is an *opt-in* Vulkan layer: its manifest declares
  # `enable_environment = { ENABLE_VKBASALT = "1"; }`, so it stays inert for every
  # Vulkan app that does not explicitly ask for it. Scope it per game via Steam
  # launch options (same philosophy as MangoHud/RADV_PERFTEST in games-heavy.nix):
  #   ENABLE_VKBASALT=1 %command%
  #
  # The package is also added to programs.steam.extraPackages (system/app/steam.nix)
  # so the layer manifest is visible inside Steam's FHS environment.
  home.file.".config/vkBasalt/vkBasalt.conf" = lib.mkIf cfgEnable {
    text = ''
      # vkBasalt — Vulkan post-processing
      # Enable per game: ENABLE_VKBASALT=1 in Steam launch options
      # Toggle in-game: Home

      # Built-in effects only (cas, dls, fxaa, smaa, lut).
      # ReShade .fx shaders are NOT bundled with the nixpkgs package, so
      # reshadeTexturePath/reshadeIncludePath are intentionally left unset.
      effects = cas

      # Contrast Adaptive Sharpening. Kept below the upstream default (0.4)
      # because FSR/FSR4 upscaling already applies its own sharpening pass.
      casSharpness = 0.35

      toggleKey = Home
      enableOnLaunch = True
      depthCapture = off
    '';
  };
}
