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
    }
    # When the local LLM is enabled, lock it out for the duration of a game so
    # inference never competes with the game for the GPU (see llama-server.nix).
    // lib.optionalAttrs (systemSettings.llamaServerEnable or false) {
      custom = {
        start = "${pkgs.coreutils}/bin/touch /run/llama-gaming/lock";
        end = "${pkgs.coreutils}/bin/rm -f /run/llama-gaming/lock";
      };
    };
  };

  # AMD GPU gaming optimizations
  boot.kernelParams = lib.mkIf (systemSettings.gpuType == "amd") [
    "split_lock_detect=off"  # Prevent kernel from penalizing Wine/Proton split-lock instructions (RDNA 4)
  ];
}
