{ config, lib, pkgs, inputs, userSettings, systemSettings, ... }:

let
  themePath = "../../../themes"+("/"+userSettings.theme+"/"+userSettings.theme)+".yaml";
  themePolarity = lib.removeSuffix "\n" (builtins.readFile (./. + "../../../themes"+("/"+userSettings.theme)+"/polarity.txt"));
  # CRITICAL: Remove trailing newline from URL and SHA256 to prevent malformed URLs
  backgroundUrl = lib.removeSuffix "\n" (builtins.readFile (./. + "../../../themes"+("/"+userSettings.theme)+"/backgroundurl.txt"));
  backgroundSha256 = lib.removeSuffix "\n" (builtins.readFile (./. + "../../../themes/"+("/"+userSettings.theme)+"/backgroundsha256.txt"));
  # CRITICAL: Stylix is enabled unconditionally when stylixEnable == true
  # We use "containment" approach: force unset global environment variables to prevent leakage into Plasma 6
  # Variables are re-injected only for Sway sessions via extraSessionCommands
in
if systemSettings.stylixEnable == true then {
  # imports must be at the top level
  imports = [ inputs.stylix.homeModules.stylix ];
  
  # DEBUG: Log Stylix configuration state
  # CRITICAL: Use lib.mkMerge to merge all home.file definitions
  # This prevents "attribute 'home.file' already defined" errors
  # #region agent log - Check lib.mkMerge evaluation
  # Note: This will be evaluated at build time, so we can't log runtime values here
  # But we can verify the structure is correct
  # #endregion
  home.file = lib.mkMerge [
    {
      # Unconditional individual file definitions
      ".stylix-debug.log".text = ''
        stylixEnabled: ${toString systemSettings.stylixEnable}
        userSettings.wm: ${userSettings.wm}
        systemSettings.enableSwayForDESK: ${toString systemSettings.enableSwayForDESK}
        stylix.targets.qt.enable: ${toString (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)}
        stylix.targets.gtk.enable: true
      '';
      ".local/share/pixmaps/nixos-snowflake-stylix.svg".source = 
        config.lib.stylix.colors {
          template = builtins.readFile ../../user/pkgs/nixos-snowflake-stylix.svg.mustache;
          extension = "svg";
        };
      ".currenttheme".text = userSettings.theme;
      ".fehbg-stylix".text = ''
        #!/bin/sh
        feh --no-fehbg --bg-fill ''+config.stylix.image+'';
      '';
      ".fehbg-stylix".executable = true;
      ".config/hypr/hyprpaper.conf".text = ''
        preload = ''+config.stylix.image+''

        wallpaper = ,''+config.stylix.image+''

      '';
    }
    # CRITICAL: Only create Trolltech.conf and kdeglobals when NOT in Plasma 6
    # Plasma 6 must own these files to manage its Qt theming system
    # Sway doesn't need these files because it uses qt5ct.conf (via environment variable injection)
    (lib.mkIf (userSettings.wm != "plasma6") {
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
    })
  ];
  stylix.autoEnable = false;
  stylix.polarity = themePolarity;
  stylix.image = pkgs.fetchurl {
    url = backgroundUrl;
    sha256 = backgroundSha256;
  };
  stylix.base16Scheme = ./. + themePath;

  stylix.fonts = {
    monospace = {
      # Use JetBrainsMono Nerd Font instead of userSettings.font (Intel One Mono) which is not available
      # This matches the fix we applied to Alacritty and Rofi
      name = "JetBrainsMono Nerd Font";
      package = pkgs.nerd-fonts.jetbrains-mono;
    };
    serif = {
      # Use JetBrainsMono Nerd Font instead of userSettings.font (Intel One Mono) which is not available
      name = "JetBrainsMono Nerd Font";
      package = pkgs.nerd-fonts.jetbrains-mono;
    };
    sansSerif = {
      # Use JetBrainsMono Nerd Font instead of userSettings.font (Intel One Mono) which is not available
      # This is used by Waybar and other applications
      name = "JetBrainsMono Nerd Font";
      package = pkgs.nerd-fonts.jetbrains-mono;
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
  stylix.targets.kde.enable = false;  # CRITICAL: Disable KDE target - Plasma 6 has its own theming system
  stylix.targets.kitty.enable = true;
  # CRITICAL: Keep GTK target enabled to generate config files for Sway
  # Note: This creates read-only symlinks that Plasma can't modify, so GTK apps in Plasma will use Adwaita-Dark
  # This is acceptable as it fixes the light mode issue
  stylix.targets.gtk.enable = true;
  # CRITICAL: Only enable QT target when NOT in Plasma 6 (or when Sway is enabled for DESK)
  # Plasma 6 has its own Qt theming system and qt5ct config files interfere with Dolphin and other KDE apps
  # Sway needs qt5ct config files for Qt theming, so enable when Sway is available
  stylix.targets.qt.enable = userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true;
  stylix.targets.qt.platform = "qtct";  # Use qtct for custom Stylix colors (Stylix generates qt5ct config automatically)
  stylix.targets.rofi.enable = if (userSettings.wmType == "x11") then true else false;
  
  # CRITICAL: Stylix creates CSS files but doesn't set gtk-theme-name automatically
  # We need to set it manually to ensure dark mode. Stylix's CSS will still be loaded
  # via gtk.css which imports colors.css.
  # CRITICAL: GTK module generates read-only symlinks for settings.ini
  # In Plasma 6, this means GTK apps will use Adwaita-Dark (Stylix theme) instead of Breeze
  # This is acceptable as it fixes the light mode issue
  # Only enable GTK module when NOT in Plasma 6 to avoid unnecessary config generation
  gtk = lib.mkIf (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == false) {
    enable = true;
    gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
    gtk3.extraConfig = {
      gtk-theme-name = if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita";
      gtk-application-prefer-dark-theme = 1;
    };
    gtk4.extraConfig = {
      gtk-theme-name = if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita";
      # REMOVED: gtk-application-prefer-dark-theme = 1;  # Deprecated for libadwaita - use dconf.settings instead
    };
  };
  
  # CRITICAL: Force unset global environment variables to prevent leakage into Plasma 6
  # Stylix may set these via targets, but we override to empty string to prevent leakage
  # An empty string effectively unsets the variable in the generated shell script
  # Note: Home Manager doesn't support null for sessionVariables, so we use empty strings
  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = lib.mkForce "";
    GTK_THEME = lib.mkForce "";
    GTK_APPLICATION_PREFER_DARK_THEME = lib.mkForce "";
    QT_STYLE_OVERRIDE = lib.mkForce "";  # Also unset if Stylix sets it
  };
  
  # CRITICAL: Set gsettings for GTK4/LibAdwaita apps (Chromium, Blueman, etc.)
  # Home Manager's gtk module sets config files but doesn't set gsettings via dconf
  # NOTE: This is only applied when NOT in Plasma 6 to prevent locking Plasma settings
  # Plasma 6 has its own theming system and doesn't use Stylix
  dconf.settings = lib.mkIf (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == false) {
    "org/gnome/desktop/interface" = {
      color-scheme = if config.stylix.polarity == "dark" then "prefer-dark" else "default";
      gtk-theme = if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita";
    };
  };
  
  stylix.targets.feh.enable = if (userSettings.wmType == "x11") then true else false;
  programs.feh.enable = true;
  # Qt styling - works on both X11 and Wayland
  # Note: Removed breeze-icons to avoid conflict with papirus-icon-theme
  # Papirus icon theme is set in profiles/work/home.nix and includes some breeze icons
  # Stylix generates qt5ct config automatically when stylix.targets.qt.enable = true
  # CRITICAL: Only enable qt module when NOT in Plasma 6
  # Plasma 6 has its own Qt theming system and the qt module may conflict with it
  # Sway doesn't need the qt module because it uses qt5ct.conf (generated by Stylix QT target) via environment variable injection
  # CRITICAL: Only install qt5ct package when Qt target is enabled (not in Plasma 6)
  # This prevents unnecessary package installation and potential conflicts
  home.packages = with pkgs; [
    pkgs.noto-fonts-monochrome-emoji
  ] ++ lib.optional (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true) libsForQt5.qt5ct;
  qt = lib.mkIf (userSettings.wm != "plasma6") {
    enable = true;
    # style.package and style.name are optional - qt5ct can work without them
    # If breeze package becomes available, uncomment these lines:
    # style.package = pkgs.libsForQt5.breeze;
    # style.name = "breeze-dark";
    # NOTE: Do NOT set platformTheme.name here - it causes Home Manager to set QT_QPA_PLATFORMTHEME = "kde"
    # QT_QPA_PLATFORMTHEME is set in Sway startup commands (user/wm/sway/default.nix) to prevent Plasma leakage
    # CRITICAL: Qt target is now conditionally enabled, so qt5ct config is only generated for Sway, not Plasma 6
  };
  fonts.fontconfig.defaultFonts = {
    # Use JetBrainsMono Nerd Font instead of userSettings.font (Intel One Mono) which is not available
    monospace = [ "JetBrainsMono Nerd Font" ];
    sansSerif = [ "JetBrainsMono Nerd Font" ];
    serif = [ "JetBrainsMono Nerd Font" ];
  };
} else {
  # Return empty configuration when Stylix is disabled (Plasma 6 or stylixEnable == false)
  # This prevents Home Manager from trying to evaluate Stylix options that don't exist
}
