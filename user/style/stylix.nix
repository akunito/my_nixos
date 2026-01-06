{ config, lib, pkgs, inputs, userSettings, systemSettings, ... }:

let
  themePath = "../../../themes"+("/"+userSettings.theme+"/"+userSettings.theme)+".yaml";
  themePolarity = lib.removeSuffix "\n" (builtins.readFile (./. + "../../../themes"+("/"+userSettings.theme)+"/polarity.txt"));
  backgroundUrl = builtins.readFile (./. + "../../../themes"+("/"+userSettings.theme)+"/backgroundurl.txt");
  backgroundSha256 = builtins.readFile (./. + "../../../themes/"+("/"+userSettings.theme)+"/backgroundsha256.txt");
  # CRITICAL: Stylix should NOT be used with Plasma 6
  # Plasma 6 has its own theming system and Stylix conflicts with it
  stylixEnabled = systemSettings.stylixEnable == true && userSettings.wm != "plasma6";
in
if stylixEnabled then {
  # imports must be at the top level
  imports = [ inputs.stylix.homeModules.stylix ];

  home.file.".local/share/pixmaps/nixos-snowflake-stylix.svg".source = 
    config.lib.stylix.colors {
      template = builtins.readFile ../../user/pkgs/nixos-snowflake-stylix.svg.mustache;
      extension = "svg";
    };

  home.file.".currenttheme".text = userSettings.theme;
  stylix.autoEnable = false;
  stylix.polarity = themePolarity;
  stylix.image = pkgs.fetchurl {
    url = backgroundUrl;
    sha256 = backgroundSha256;
  };
  stylix.base16Scheme = ./. + themePath;

  stylix.fonts = {
    monospace = {
      name = userSettings.font;
      package = userSettings.fontPkg;
    };
    serif = {
      name = userSettings.font;
      package = userSettings.fontPkg;
    };
    sansSerif = {
      name = userSettings.font;
      package = userSettings.fontPkg;
    };
    emoji = {
      name = "Noto Emoji";
      package = pkgs.noto-fonts-monochrome-emoji;
    };
    sizes = {
      terminal = 18;
      applications = 12;
      popups = 12;
      desktop = 12;
    };
  };

  stylix.targets.alacritty.enable = false;  # CRITICAL: Disable - colors are handled in user/app/terminal/alacritty.nix
  stylix.targets.waybar.enable = false;  # CRITICAL: Disable to prevent overwriting custom waybar config
  # Note: stylix.targets.rofi.enable is defined conditionally below (line 90) based on wmType
  # For Wayland (SwayFX): false (uses custom config)
  # For X11: true (uses Stylix config)
  # CRITICAL: Do NOT define programs.alacritty.settings here - it's already handled in user/app/terminal/alacritty.nix
  # with proper conditional logic based on systemSettings.stylixEnable
  # CRITICAL: Disable KDE target - Plasma 6 has its own theming system
  # This module should not be loaded for Plasma 6, but disable KDE target as a safety measure
  stylix.targets.kde.enable = false;
  stylix.targets.kitty.enable = true;
  stylix.targets.gtk.enable = true;
  stylix.targets.rofi.enable = if (userSettings.wmType == "x11") then true else false;
  stylix.targets.feh.enable = if (userSettings.wmType == "x11") then true else false;
  programs.feh.enable = true;
  home.file.".fehbg-stylix".text = ''
    #!/bin/sh
    feh --no-fehbg --bg-fill ''+config.stylix.image+'';
  '';
  home.file.".fehbg-stylix".executable = true;
  home.file = {
    ".config/qt5ct/colors/oomox-current.conf".source = config.lib.stylix.colors {
      template = builtins.readFile ./oomox-current.conf.mustache;
      extension = ".conf";
    };
    ".config/Trolltech.conf".source = config.lib.stylix.colors {
      template = builtins.readFile ./Trolltech.conf.mustache;
      extension = ".conf";
    };
    ".config/kdeglobals".source = config.lib.stylix.colors {
      template = builtins.readFile ./Trolltech.conf.mustache;
      extension = "";
    };
    ".config/qt5ct/qt5ct.conf".text = pkgs.lib.mkBefore (builtins.readFile ./qt5ct.conf);
  };
  home.file.".config/hypr/hyprpaper.conf".text = ''
    preload = ''+config.stylix.image+''

    wallpaper = ,''+config.stylix.image+''

  '';
  # Qt5 styling - only for X11 (not needed for Wayland/SwayFX)
  # Note: breeze package may not be available in all nixpkgs versions
  home.packages = with pkgs; [
     libsForQt5.qt5ct libsForQt5.breeze-icons pkgs.noto-fonts-monochrome-emoji
  ] ++ lib.optionals (userSettings.wmType == "x11") [
     # Only include breeze if available and needed for X11
     # If breeze is not available, qt5ct will use built-in styles
  ];
  qt = lib.mkIf (userSettings.wmType == "x11") {
    enable = true;
    # style.package and style.name are optional - qt5ct can work without them
    # If breeze package becomes available, uncomment these lines:
    # style.package = pkgs.libsForQt5.breeze;
    # style.name = "breeze-dark";
    platformTheme.name = "kde";
  };
  fonts.fontconfig.defaultFonts = {
    monospace = [ userSettings.font ];
    sansSerif = [ userSettings.font ];
    serif = [ userSettings.font ];
  };
} else {
  # Return empty configuration when Stylix is disabled (Plasma 6 or stylixEnable == false)
  # This prevents Home Manager from trying to evaluate Stylix options that don't exist
}
