{
  pkgs,
  pkgs-unstable,
  pkgs-stable,
  userSettings,
  systemSettings,
  lib,
  inputs,
  ...
}:
let
  myRetroarch = pkgs.retroarch.withCores (
    cores: with pkgs.libretro; [
      vba-m
      (desmume.overrideAttrs (oldAttrs: {
        preConfigure = ''
          sed -i 's/0009BF123456/0022AA067857/g' desmume/src/firmware.cpp;
          sed -i 's/outConfig.MACAddress\[0\] = 0x00/outConfig.MACAddress[0] = 0x00/g' desmume/src/firmware.cpp;
          sed -i 's/outConfig.MACAddress\[1\] = 0x09/outConfig.MACAddress[1] = 0x22/g' desmume/src/firmware.cpp;
          sed -i 's/outConfig.MACAddress\[2\] = 0xBF/outConfig.MACAddress[2] = 0xAA/g' desmume/src/firmware.cpp;
          sed -i 's/outConfig.MACAddress\[3\] = 0x12/outConfig.MACAddress[3] = 0x06/g' desmume/src/firmware.cpp;
          sed -i 's/outConfig.MACAddress\[4\] = 0x34/outConfig.MACAddress[4] = 0x78/g' desmume/src/firmware.cpp;
          sed -i 's/outConfig.MACAddress\[5\] = 0x56/outConfig.MACAddress[5] = 0x57/g' desmume/src/firmware.cpp;
          sed -i 's/0x00, 0x09, 0xBF, 0x12, 0x34, 0x56/0x00, 0x22, 0xAA, 0x06, 0x78, 0x57/g' desmume/src/wifi.cpp;
        '';
      }))
      genesis-plus-gx
    ]
  );

  # Conditional wrapper arguments for AMD GPUs to fix Vulkan driver discovery
  # Conditional wrapper arguments for AMD GPUs to fix Vulkan driver discovery
  amdWrapperArgs =
    if (systemSettings.gpuType or "") == "amd" then
      ''--run 'mkdir -p $HOME/.local/state' --run 'echo "--- Lutris Wrapper $(date) ---" >> $HOME/.local/state/lutris-wrapper.log' --run 'echo "NODEVICE_SELECT=$NODEVICE_SELECT" >> $HOME/.local/state/lutris-wrapper.log' --run 'echo "VK_ICD_FILENAMES=$VK_ICD_FILENAMES" >> $HOME/.local/state/lutris-wrapper.log' --set NODEVICE_SELECT "1" --set VK_ICD_FILENAMES "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json:/run/opengl-driver-32/share/vulkan/icd.d/radeon_icd.i686.json" --prefix XDG_DATA_DIRS : "/run/opengl-driver/share:/run/opengl-driver-32/share"''
    else
      "";

in
{
  home.packages =
    (with pkgs; [
      # Games
      pegasus-frontend
      myRetroarch
      libfaketime
      airshipper
      qjoypad
      superTux
      superTuxKart
      gamepad-tool
      antimicrox
    ])
    ++ (with pkgs-stable; [
      pokefinder
    ])
    ++ (lib.optionals (userSettings.protongamesEnable == true) [
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
      pkgs.wineWowPackages.stagingFull # Wine with 32/64-bit support + wine-mono
      pkgs.winetricks # Wine helper tool
      pkgs.vulkan-tools # Provides vulkaninfo, vkcube
      pkgs.mesa-demos # OpenGL debugging (glxinfo, eglinfo)
    ])
    ++ (lib.optionals (userSettings.GOGlauncherEnable == true) [
      pkgs-unstable.heroic
    ])
    ++ (lib.optionals (userSettings.dolphinEmulatorPrimehackEnable == true) [
      pkgs-unstable.dolphin-emu-primehack
    ])
    ++ (lib.optionals (userSettings.starcitizenEnable == true) [
      inputs.nix-citizen.packages.${pkgs.stdenv.hostPlatform.system}.rsi-launcher
    ])
    ++ (lib.optionals (userSettings.rpcs3Enable == true) [
      pkgs-unstable.rpcs3
    ]);

  # Session variable to suppress Bottles warning (User Session Scope)
  # Also adding Gaming Optimizations for AMD
  home.sessionVariables = lib.mkIf (userSettings.protongamesEnable == true) {
    BOTTLES_IGNORE_SANDBOX = "1";
    # AMD RDNA 4 Optimizations (9700XT)
    RADV_PERFTEST = "gpl"; # Graphics Pipeline Library - reduces stuttering
    AMD_VULKAN_ICD = "radv"; # Ensure Mesa driver is used over AMDVLK
    NODEVICE_SELECT = "1"; # Fix crash on RDNA 4 (disable VK_LAYER_MESA_device_select)
  };

  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = (_: true);
  };

  # The following 2 declarations allow retroarch to be imported into gamehub
  # Set retroarch core directory to ~/.local/bin/libretro
  # and retroarch core info directory to ~/.local/share/libretro/info
  home.file.".local/bin/libretro".source = "${myRetroarch}/lib/retroarch/cores";
  home.file.".local/bin/libretro-shaders".source = "${myRetroarch}/lib/retroarch/cores";
  home.file.".local/share/libretro/info".source = fetchTarball {
    url = "https://github.com/libretro/libretro-core-info/archive/refs/tags/v1.15.0.tar.gz";
    sha256 = "004kgbsgbk7hn1v01jg3vj4b6dfb2cp3kcp5hgjyl030wqg1r22q";
  };

}
