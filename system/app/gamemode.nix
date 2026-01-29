{ pkgs, systemSettings, lib, ... }:

{
  # Feral GameMode
  # Conditionally enable based on systemSettings.gamemodeEnable
  # Configured to avoid AMDGPU conflicts on RDNA 4 (9700XT) by disabling GPU optimizations
  # LACT handles GPU management, gamemode only handles CPU and screensaver inhibition
  environment.systemPackages = lib.mkIf (systemSettings.gamemodeEnable == true) [ pkgs.gamemode ];

  programs.gamemode = lib.mkIf (systemSettings.gamemodeEnable == true) {
    enable = true;
    settings = {
      general = {
        # Primary goal: prevent screensaver during fullscreen games
        inhibit_screensaver = 1;
      };
      gpu = {
        # CRITICAL: Completely disable GPU optimizations to avoid crashes on RDNA 4 (9700XT)
        # LACT handles GPU management, gamemode must not touch GPU
        apply_gpu_optimisations = "reject";
      };
      # CPU optimizations are kept but should be compatible with power-profiles-daemon
      # Process and I/O priority optimizations are enabled by default (safe)
    };
  };
}
