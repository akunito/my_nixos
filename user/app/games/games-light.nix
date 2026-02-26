{
  pkgs,
  pkgs-unstable,
  pkgs-stable,
  userSettings,
  lib,
  ...
}:
let
  myRetroarch = pkgs.retroarch.withCores (
    cores: with pkgs.libretro; [
      # Handheld consoles
      vba-m # Game Boy Advance
      gambatte # Game Boy / Game Boy Color
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
      })) # Nintendo DS
      beetle-ngp # Neo Geo Pocket / Neo Geo Pocket Color

      # Home consoles
      fceumm # NES / Famicom
      snes9x # Super Nintendo
      mupen64plus # Nintendo 64
      genesis-plus-gx # Genesis / Mega Drive / Master System / Game Gear / SG-1000

      # Arcade emulators
      mame # MAME - Multiple Arcade Machine Emulator
      fbneo # FinalBurn Neo - CPS1/2/3, Neo Geo, etc.

      # Atari systems
      atari800 # Atari 5200 / 800 / XL / XE
      virtualjaguar # Atari Jaguar
    ]
  );
in
{
  config = lib.mkIf (userSettings.gamesLightEnable or false) {
    home.packages =
      (with pkgs; [
        # Games & launchers
        pegasus-frontend
        myRetroarch
        libfaketime
        airshipper
        qjoypad
        supertuxkart
        gamepad-tool
        antimicrox
      ])
      ++ (with pkgs-stable; [
        pokefinder
      ])
      ++ (lib.optionals (userSettings.dolphinEmulatorPrimehackEnable == true) [
        pkgs-unstable.dolphin-emu-primehack
      ])
      ++ (lib.optionals (userSettings.rpcs3Enable == true) [
        pkgs-unstable.rpcs3
      ]);

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
  };
}
