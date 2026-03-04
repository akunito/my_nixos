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
        supertux
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

    # RetroArch autoconfig for joycond combined Joy-Cons (udev driver)
    # Created by combining L+R Joy-Cons via joycond (press L on Left + R on Right)
    # Device: vendor 057e, product 2008 — distinct from Pro Controller (2009)
    home.file.".config/retroarch/autoconfig/udev/Nintendo Switch Combined Joy-Cons.cfg".text = ''
      input_driver = "udev"
      input_device = "Nintendo Switch Combined Joy-Cons"
      input_vendor_id = "1406"
      input_product_id = "8200"
      input_b_btn = "0"
      input_y_btn = "3"
      input_select_btn = "9"
      input_start_btn = "10"
      input_up_btn = "h0up"
      input_down_btn = "h0down"
      input_left_btn = "h0left"
      input_right_btn = "h0right"
      input_a_btn = "1"
      input_x_btn = "2"
      input_l_btn = "5"
      input_r_btn = "6"
      input_l2_btn = "7"
      input_r2_btn = "8"
      input_l3_btn = "12"
      input_r3_btn = "13"
      input_l_x_plus_axis = "+0"
      input_l_x_minus_axis = "-0"
      input_l_y_plus_axis = "+1"
      input_l_y_minus_axis = "-1"
      input_r_x_plus_axis = "+2"
      input_r_x_minus_axis = "-2"
      input_r_y_plus_axis = "+3"
      input_r_y_minus_axis = "-3"
      input_menu_toggle_btn = "11"
      input_screenshot_btn = "4"
      input_b_btn_label = "B"
      input_y_btn_label = "Y"
      input_select_btn_label = "Minus"
      input_start_btn_label = "Plus"
      input_up_btn_label = "D-Pad Up"
      input_down_btn_label = "D-Pad Down"
      input_left_btn_label = "D-Pad Left"
      input_right_btn_label = "D-Pad Right"
      input_a_btn_label = "A"
      input_x_btn_label = "X"
      input_l_btn_label = "L"
      input_r_btn_label = "R"
      input_l2_btn_label = "ZL"
      input_r2_btn_label = "ZR"
      input_l3_btn_label = "Left Stick Press"
      input_r3_btn_label = "Right Stick Press"
      input_l_x_plus_axis_label = "Left Analog X+ (Right)"
      input_l_x_minus_axis_label = "Left Analog X- (Left)"
      input_l_y_plus_axis_label = "Left Analog Y+ (Down)"
      input_l_y_minus_axis_label = "Left Analog Y- (Up)"
      input_r_x_plus_axis_label = "Right Analog X+ (Right)"
      input_r_x_minus_axis_label = "Right Analog X- (Left)"
      input_r_y_plus_axis_label = "Right Analog Y+ (Down)"
      input_r_y_minus_axis_label = "Right Analog Y- (Up)"
      input_menu_toggle_btn_label = "Home"
      input_screenshot_btn_label = "Screenshot"
    '';
  };
}
