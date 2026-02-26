{
  pkgs,
  pkgs-unstable,
  userSettings,
  systemSettings,
  lib,
  inputs,
  ...
}:
let
  # Conditional wrapper arguments for AMD GPUs to fix Vulkan driver discovery
  amdWrapperArgs =
    if (systemSettings.gpuType or "") == "amd" then
      ''--run 'mkdir -p $HOME/.local/state' --run 'echo "--- Lutris Wrapper $(date) ---" >> $HOME/.local/state/lutris-wrapper.log' --run 'echo "NODEVICE_SELECT=$NODEVICE_SELECT" >> $HOME/.local/state/lutris-wrapper.log' --run 'echo "VK_ICD_FILENAMES=$VK_ICD_FILENAMES" >> $HOME/.local/state/lutris-wrapper.log' --set NODEVICE_SELECT "1" --set VK_ICD_FILENAMES "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json:/run/opengl-driver-32/share/vulkan/icd.d/radeon_icd.i686.json" --prefix XDG_DATA_DIRS : "/run/opengl-driver/share:/run/opengl-driver-32/share"''
    else
      "";
in
{
  config = lib.mkIf (userSettings.protongamesEnable or false) {
    home.packages = [
      ((pkgs-unstable.bottles.override { removeWarningPopup = true; }).overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
        buildCommand = ''
          ${old.buildCommand}
          wrapProgram $out/bin/bottles ${amdWrapperArgs}
        '';
      }))
      # Lutris with explicit Vulkan environment wrapping to fix FHS/sandbox driver discovery
      (pkgs-unstable.lutris.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
        buildCommand = ''
          ${old.buildCommand}
          wrapProgram $out/bin/lutris ${amdWrapperArgs} \
            --set PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION "python"
        '';
      }))
      pkgs-unstable.protonup-qt
      # Wine and debugging tools
      pkgs.wineWow64Packages.stagingFull # Wine 64-bit with WoW64 32-bit support (binary cached)
      pkgs.winetricks # Wine helper tool
      pkgs.vulkan-tools # Provides vulkaninfo, vkcube
      pkgs.mesa-demos # OpenGL debugging (glxinfo, eglinfo)
    ]
    ++ (lib.optionals (userSettings.GOGlauncherEnable == true) [
      pkgs-unstable.heroic
    ])
    ++ (lib.optionals (userSettings.starcitizenEnable == true) [
      inputs.nix-citizen.packages.${pkgs.stdenv.hostPlatform.system}.rsi-launcher
    ]);

    # Session variable to suppress Bottles warning (User Session Scope)
    # Also adding Gaming Optimizations for AMD
    home.sessionVariables = {
      BOTTLES_IGNORE_SANDBOX = "1";
      # AMD RDNA 4 Optimizations (9700XT)
      # RADV_PERFTEST=gpl is scoped per-game via Steam launch options instead of session-wide
      # to avoid wasting VRAM on non-game Vulkan apps (Sway, Chromium, etc.)
      AMD_VULKAN_ICD = "radv"; # Ensure Mesa driver is used over AMDVLK
      NODEVICE_SELECT = "1"; # Fix crash on RDNA 4 (disable VK_LAYER_MESA_device_select)
      # MangoHud is scoped per-game via gamescope --mangoapp instead of session-wide
      # to avoid duplicate injection (gamescope compositor + game)
    };

    nixpkgs.config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };
}
