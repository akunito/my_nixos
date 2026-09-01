{ config, pkgs, systemSettings, lib, ... }:

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
    # inference never competes with the game for the GPU.
    #
    # ‼️ This MUST test both backends. It tested only llamaServerEnable, which
    # the Ollama swap on 2026-08-21 set to false — so from that day the hook was
    # not emitted at all and the automatic lock silently did nothing. The
    # consequence showed up on 2026-09-01 as an amdgpu command-submission fault
    # that killed a running Minecraft client (see system/app/ollama-server.nix).
    //
    lib.optionalAttrs ((systemSettings.llamaServerEnable or false)
                    || (systemSettings.ollamaServerEnable or false)) {
      custom = {
        start = "${pkgs.coreutils}/bin/touch /run/llama-gaming/lock";
        end = "${pkgs.coreutils}/bin/rm -f /run/llama-gaming/lock";
      };
    };
  };

  # gamemoded reads /etc/gamemode.ini ONCE, at start. Without this the daemon
  # keeps whatever config it had when the session began, so a deploy that adds
  # or changes a hook appears to do nothing until the next reboot — and it fails
  # silently, which is how the llama-lock hook above went unnoticed. Observed
  # 2026-09-01: a daemon up since Aug 27 ignored a freshly written [custom]
  # section until it was restarted by hand.
  systemd.user.services.gamemoded.restartTriggers =
    lib.mkIf (systemSettings.gamemodeEnable == true)
      [ config.environment.etc."gamemode.ini".source ];

  # AMD GPU gaming optimizations
  boot.kernelParams = lib.mkIf (systemSettings.gpuType == "amd") [
    "split_lock_detect=off"  # Prevent kernel from penalizing Wine/Proton split-lock instructions (RDNA 4)
  ];
}
