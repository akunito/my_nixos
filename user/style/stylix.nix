{ config, lib, pkgs, inputs, userSettings, systemSettings, ... }:

let
  themePath = "../../../themes"+("/"+userSettings.theme+"/"+userSettings.theme)+".yaml";
  themePolarity = lib.removeSuffix "\n" (builtins.readFile (./. + "../../../themes"+("/"+userSettings.theme)+"/polarity.txt"));
  # CRITICAL: Remove trailing newline from URL and SHA256 to prevent malformed URLs
  backgroundUrl = lib.removeSuffix "\n" (builtins.readFile (./. + "../../../themes"+("/"+userSettings.theme)+"/backgroundurl.txt"));
  backgroundSha256 = lib.removeSuffix "\n" (builtins.readFile (./. + "../../../themes/"+("/"+userSettings.theme)+"/backgroundsha256.txt"));
  # CRITICAL: Stylix should NOT be used with Plasma 6 (unless SwayFX is enabled)
  # Plasma 6 has its own theming system and Stylix conflicts with it
  # However, if SwayFX is enabled via enableSwayForDESK, Stylix should be enabled for SwayFX
  stylixEnabled = systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true);
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
  stylix.targets.qt.enable = true;
  stylix.targets.qt.platform = "qtct";  # Use qtct for custom Stylix colors (Stylix generates qt5ct config automatically)
  stylix.targets.rofi.enable = if (userSettings.wmType == "x11") then true else false;
  
  # CRITICAL: Stylix creates CSS files but doesn't set gtk-theme-name automatically
  # We need to set it manually to ensure dark mode. Stylix's CSS will still be loaded
  # via gtk.css which imports colors.css.
  gtk = {
    enable = true;
    gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
    gtk3.extraConfig = {
      gtk-theme-name = if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita";
      gtk-application-prefer-dark-theme = 1;
    };
    gtk4.extraConfig = {
      gtk-theme-name = if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita";
      gtk-application-prefer-dark-theme = 1;
    };
  };
  
  # CRITICAL: Set environment variables system-wide for dark mode
  # Note: QT_QPA_PLATFORMTHEME is set by Stylix when stylix.targets.qt.enable = true
  # Use lib.mkForce to override Home Manager's qt module which sets it to "kde" when qt.platformTheme.name = "kde"
  home.sessionVariables = {
    GTK_THEME = if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita";
    GTK_APPLICATION_PREFER_DARK_THEME = "1";
    QT_QPA_PLATFORMTHEME = lib.mkForce "qt5ct";  # Force qt5ct for Stylix (overrides qt module's "kde" setting)
  };
  
  # CRITICAL: Set gsettings for GTK4/LibAdwaita apps (Chromium, Blueman, etc.)
  # Home Manager's gtk module sets config files but doesn't set gsettings via dconf
  # NOTE: This is only applied when Stylix is enabled (not for Plasma 6)
  # Plasma 6 has its own theming system and doesn't use Stylix
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = if config.stylix.polarity == "dark" then "prefer-dark" else "default";
      gtk-theme = if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita";
    };
  };
  
  stylix.targets.feh.enable = if (userSettings.wmType == "x11") then true else false;
  programs.feh.enable = true;
  home.file.".fehbg-stylix".text = ''
    #!/bin/sh
    feh --no-fehbg --bg-fill ''+config.stylix.image+'';
  '';
  home.file.".fehbg-stylix".executable = true;
  # CRITICAL: Do NOT manually create qt5ct config files - Stylix generates them declaratively
  # when stylix.targets.qt.enable = true. Manual file creation conflicts with Stylix.
  # Stylix automatically generates:
  # - .config/qt5ct/colors/oomox-current.conf
  # - .config/qt5ct/qt5ct.conf
  # - .config/Trolltech.conf
  # - .config/kdeglobals
  home.file = {
    ".config/Trolltech.conf" = {
      source = config.lib.stylix.colors {
        template = builtins.readFile ./Trolltech.conf.mustache;
        extension = ".conf";
      };
      force = true;  # CRITICAL: Allow overwriting existing file (managed by Stylix)
    };
    ".config/kdeglobals" = {
      source = config.lib.stylix.colors {
        template = builtins.readFile ./Trolltech.conf.mustache;
        extension = "";
      };
      force = true;  # CRITICAL: Allow overwriting existing file (managed by Stylix)
    };
  };
  home.file.".config/hypr/hyprpaper.conf".text = ''
    preload = ''+config.stylix.image+''

    wallpaper = ,''+config.stylix.image+''

  '';
  # Qt styling - works on both X11 and Wayland
  # Note: Removed breeze-icons to avoid conflict with papirus-icon-theme
  # Papirus icon theme is set in profiles/work/home.nix and includes some breeze icons
  # Stylix generates qt5ct config automatically when stylix.targets.qt.enable = true
  # NOTE: This is only applied when Stylix is enabled (not for Plasma 6)
  # Plasma 6 has its own Qt theming system and doesn't use Stylix/qt5ct
  home.packages = with pkgs; [
    libsForQt5.qt5ct  # qt5ct is needed for QT5/QT6 theming (Stylix uses it)
    pkgs.noto-fonts-monochrome-emoji
  ];
  qt = {
    enable = true;
    # style.package and style.name are optional - qt5ct can work without them
    # If breeze package becomes available, uncomment these lines:
    # style.package = pkgs.libsForQt5.breeze;
    # style.name = "breeze-dark";
    # NOTE: Do NOT set platformTheme.name here - it causes Home Manager to set QT_QPA_PLATFORMTHEME = "kde"
    # We want QT_QPA_PLATFORMTHEME = "qt5ct" instead, which is set via home.sessionVariables above
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
