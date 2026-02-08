{
  config,
  lib,
  pkgs,
  inputs,
  userSettings,
  systemSettings,
  ...
}:

let
  themePath = "../../../themes" + ("/" + userSettings.theme + "/" + userSettings.theme) + ".yaml";
  themePolarity = lib.removeSuffix "\n" (
    builtins.readFile (./. + "../../../themes" + ("/" + userSettings.theme) + "/polarity.txt")
  );
  # CRITICAL: Remove trailing newline from URL and SHA256 to prevent malformed URLs
  backgroundUrl = lib.removeSuffix "\n" (
    builtins.readFile (./. + "../../../themes" + ("/" + userSettings.theme) + "/backgroundurl.txt")
  );
  backgroundSha256 = lib.removeSuffix "\n" (
    builtins.readFile (./. + "../../../themes/" + ("/" + userSettings.theme) + "/backgroundsha256.txt")
  );
  # CRITICAL: Stylix is enabled unconditionally when stylixEnable == true
  # We use "containment" approach: force unset global environment variables to prevent leakage into Plasma 6
  # Variables are re-injected only for Sway sessions via extraSessionCommands
in
if systemSettings.stylixEnable == true then
  {
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
          stylix.targets.qt.enable: ${
            toString (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)
          }
          stylix.targets.gtk.enable: true
          qt5ctFilesRemoved: ${
            toString (userSettings.wm == "plasma6" && systemSettings.enableSwayForDESK == false)
          }
        '';
        ".local/share/pixmaps/nixos-snowflake-stylix.svg".source = config.lib.stylix.colors {
          template = builtins.readFile ../../user/pkgs/nixos-snowflake-stylix.svg.mustache;
          extension = "svg";
        };
        ".currenttheme".text = userSettings.theme;
        ".fehbg-stylix".text = ''
          #!/bin/sh
          feh --no-fehbg --bg-fill ''
        + config.stylix.image
        + ''
          ;
        '';
        ".fehbg-stylix".executable = true;
        ".config/hypr/hyprpaper.conf".text =
          "preload = "
          + config.stylix.image
          + ''

            wallpaper = ,''
          + config.stylix.image
          + ''

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
          force = true; # CRITICAL: Allow overwriting existing file (managed by Stylix)
        };
        ".config/kdeglobals" = {
          source = config.lib.stylix.colors {
            template = builtins.readFile ./Trolltech.conf.mustache;
            extension = "";
          };
          force = true; # CRITICAL: Allow overwriting existing file (managed by Stylix)
        };
      })
      # CRITICAL: Remove qt5ct config files in Plasma 6 when Sway is NOT enabled
      # When enableSwayForDESK = true, files must exist for Sway sessions, but Plasma 6 won't read them
      # because QT_QPA_PLATFORMTHEME is unset (containment approach)
      # When enableSwayForDESK = false, remove files completely to prevent any interference
      (lib.mkIf (userSettings.wm == "plasma6" && systemSettings.enableSwayForDESK == false) {
        ".config/qt5ct/qt5ct.conf".text = "";
        ".config/qt5ct/colors/oomox-current.conf".text = "";
      })

      # CRITICAL: Manually generate qt6ct configuration for Dolphin in Sway
      # Stylix doesn't auto-generate qt6ct configs yet, so we map it to use the same colors as qt5ct
      # We use the generated oomox-current.conf from qt5ct (which Stylix creates)
      (lib.mkIf (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true) {
        ".config/qt6ct/qt6ct.conf".text = ''
          [Appearance]
          color_scheme_path=${config.home.homeDirectory}/.config/qt6ct/colors/oomox-current.conf
          custom_palette=false
          standard_dialogs=default
          style=adwaita-dark
        '';

        # Symlink the generated color scheme from qt5ct to qt6ct
        # note: we can't symlink to the file content safely because we need to know the path Stylix uses
        # but since Stylix generates ~/.config/qt5ct/colors/oomox-current.conf via home.file (effectively),
        # we can try to reuse the source if we knew it foundable.
        # instead, we can just say: if Stylix generates qt5ct colors, we want them here.
        # actually, Stylix generates `.config/qt5ct/colors/oomox-current.conf` automatically.
        # Let's just symlink it using home-manager file logic?
        # No, HM doesn't like symlinking to *other* HM managed files easily if they are dynamic.
        #
        # Use source from stylix colors directly:
        ".config/qt6ct/colors/oomox-current.conf".source = config.lib.stylix.colors {
          template = builtins.readFile ./Trolltech.conf.mustache;
          extension = ".conf";
        };
      })

      # CRITICAL: Prevent theme leakage into Plasma 6
      # Since we now set QT_QPA_PLATFORMTHEME globally (to support Sway), we must explicit unset it for Plasma.
      # Plasma sources scripts in ~/.config/plasma-workspace/env/ at startup.
      {
        ".config/plasma-workspace/env/unset-qt-theme.sh".text = ''
          unset QT_QPA_PLATFORMTHEME
        '';
      }
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
        # CRITICAL: Use "JetBrainsMono Nerd Font Mono" (the Mono variant) for terminals
        # The non-Mono variant is proportional and lacks proper Nerd Font glyph support
        name = "JetBrainsMono Nerd Font Mono";
        package = pkgs.nerd-fonts.jetbrains-mono;
      };
      serif = {
        # Use JetBrainsMono Nerd Font Mono for consistency across Stylix targets
        name = "JetBrainsMono Nerd Font Mono";
        package = pkgs.nerd-fonts.jetbrains-mono;
      };
      sansSerif = {
        # Use proportional JetBrainsMono Nerd Font for Waybar and UI elements
        # The Mono variant causes icons to render smaller (fixed-width cells)
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

    stylix.targets.alacritty.enable = false; # CRITICAL: Disable - colors are handled in user/app/terminal/alacritty.nix
    stylix.targets.waybar.enable = false; # CRITICAL: Disable to prevent overwriting custom waybar config
    # Note: stylix.targets.rofi.enable is defined conditionally below (line 90) based on wmType
    # For Wayland (SwayFX): false (uses custom config)
    # For X11: true (uses Stylix config)
    # CRITICAL: Do NOT define programs.alacritty.settings here - it's already handled in user/app/terminal/alacritty.nix
    # with proper conditional logic based on systemSettings.stylixEnable
    # CRITICAL: Disable KDE target - Plasma 6 has its own theming system
    # This module should not be loaded for Plasma 6, but disable KDE target as a safety measure
    stylix.targets.kde.enable = false; # CRITICAL: Disable KDE target - Plasma 6 has its own theming system
    stylix.targets.kitty.enable = true;
    # CRITICAL: Keep GTK target enabled to generate config files for Sway
    # Note: This creates read-only symlinks that Plasma can't modify, so GTK apps in Plasma will use Adwaita-Dark
    # This is acceptable as it fixes the light mode issue
    stylix.targets.gtk.enable = true;
    # CRITICAL: Only enable QT target when NOT in Plasma 6 (or when Sway is enabled for DESK)
    # Plasma 6 has its own Qt theming system and qt5ct config files interfere with Dolphin and other KDE apps
    # Sway needs qt5ct config files for Qt theming, so enable when Sway is available
    stylix.targets.qt.enable = userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true;
    stylix.targets.qt.platform = "qtct"; # Use qtct for custom Stylix colors (Stylix generates qt5ct config automatically)
    stylix.targets.rofi.enable = if (userSettings.wmType == "x11") then true else false;

    # CRITICAL: Stylix creates CSS files but doesn't set gtk-theme-name automatically
    # We need to set it manually to ensure dark mode. Stylix's CSS will still be loaded
    # via gtk.css which imports colors.css.
    # CRITICAL: GTK module generates read-only symlinks for settings.ini
    # In Plasma 6, this means GTK apps will use Adwaita-Dark (Stylix theme) instead of Breeze
    # This is acceptable as it fixes the light mode issue
    # Only enable GTK module when NOT in Plasma 6 to avoid unnecessary config generation
    gtk = lib.mkIf (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true) {
      enable = true;
      gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
      gtk2.extraConfig = ''
        gtk-enable-animations=1
        gtk-primary-button-warps-slider=1
        gtk-toolbar-style=3
        gtk-menu-images=1
        gtk-button-images=1
        gtk-cursor-blink-time=1000
        gtk-cursor-blink=1
        gtk-cursor-theme-size=24
        gtk-cursor-theme-name="breeze_cursors"
        gtk-sound-theme-name="ocean"
        gtk-icon-theme-name="breeze-dark"
        gtk-font-name="Noto Sans 10"
      '';
      gtk3.extraConfig = {
        gtk-theme-name = if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita";
        gtk-application-prefer-dark-theme = 1;

        # CRITICAL: Force Portal for file chooser
        gtk-use-portal = 1;

        # Restore legacy settings requested by user
        gtk-button-images = 1;
        gtk-cursor-blink = 1;
        gtk-cursor-blink-time = 1000;
        gtk-cursor-theme-name = "breeze_cursors";
        gtk-cursor-theme-size = 24;
        gtk-decoration-layout = "icon:minimize,maximize,close";
        gtk-enable-animations = 1;
        gtk-font-name = "Noto Sans, 10";
        gtk-icon-theme-name = "breeze-dark";
        gtk-menu-images = 1;
        gtk-primary-button-warps-slider = 1;
        gtk-sound-theme-name = "ocean";
        gtk-toolbar-style = 3;
      };
      gtk4.extraConfig = {
        gtk-theme-name = if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita";
        # REMOVED: gtk-application-prefer-dark-theme = 1;  # Deprecated for libadwaita - use dconf.settings instead

        # Restore legacy settings requested by user
        gtk-cursor-blink = 1;
        gtk-cursor-blink-time = 1000;
        gtk-cursor-theme-name = "breeze_cursors";
        gtk-cursor-theme-size = 24;
        gtk-decoration-layout = "icon:minimize,maximize,close";
        gtk-enable-animations = 1;
        gtk-font-name = "Noto Sans, 10";
        gtk-icon-theme-name = "breeze-dark";
        gtk-primary-button-warps-slider = 1;
        gtk-sound-theme-name = "ocean";
      };
    };

    # CRITICAL: Force unset global environment variables to prevent leakage into Plasma 6
    home.sessionVariables = {
      QT_QPA_PLATFORMTHEME = lib.mkForce "qt6ct";

      # Only force empty for Plasma - Sway needs dark GTK theme
      GTK_THEME =
        if (userSettings.wm == "plasma6" && !(systemSettings.enableSwayForDESK or false)) then
          lib.mkForce ""
        else
          lib.mkForce "Adwaita-dark";

      GTK_APPLICATION_PREFER_DARK_THEME =
        if (userSettings.wm == "plasma6" && !(systemSettings.enableSwayForDESK or false)) then
          lib.mkForce ""
        else
          lib.mkForce "1";
      # Force Portal usage for GTK apps via environment variable (reinforces generated settings.ini)
      GTK_USE_PORTAL = lib.mkForce "1";
      # Only force empty for Plasma - Sway needs dark Qt style for portal
      QT_STYLE_OVERRIDE =
        if (userSettings.wm == "plasma6" && !(systemSettings.enableSwayForDESK or false)) then
          lib.mkForce ""
        else
          lib.mkDefault "adwaita-dark";
    };

    # CRITICAL: Set gsettings for GTK4/LibAdwaita apps (Chromium, Blueman, etc.)
    # Home Manager's gtk module sets config files but doesn't set gsettings via dconf
    # NOTE: This is only applied when NOT in Plasma 6 to prevent locking Plasma settings
    # Plasma 6 has its own theming system and doesn't use Stylix
    dconf.settings =
      lib.mkIf (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)
        {
          "org/gnome/desktop/interface" = {
            color-scheme = if config.stylix.polarity == "dark" then "prefer-dark" else "default";
            gtk-theme = if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita";
          };
        };

    # CRITICAL: Force GTK_THEME for xdg-desktop-portal-gtk service
    # This ensures the portal process itself knows to use dark mode, fixing light mode issues
    systemd.user.services.xdg-desktop-portal-gtk.Service.Environment = lib.mkIf (
      userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true
    ) (lib.mkForce [ "GTK_THEME=Adwaita-dark" ]);

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
    home.packages =
      with pkgs;
      [
        pkgs.noto-fonts-monochrome-emoji
      ]
      ++ lib.optionals (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true) [
        pkgs.adwaita-qt # Adwaita style for Qt5
        pkgs.adwaita-qt6 # Adwaita style for Qt6
      ];

    qt = lib.mkIf (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true) {
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
      # CRITICAL: Use "JetBrainsMono Nerd Font Mono" (the Mono variant) for terminals
      # Use proportional variant for sansSerif (Waybar icons render at natural size)
      # Add "Symbols Nerd Font Mono" as fallback for any missing glyphs
      monospace = [ "JetBrainsMono Nerd Font Mono" "Symbols Nerd Font Mono" ];
      sansSerif = [ "JetBrainsMono Nerd Font" "Symbols Nerd Font Mono" ];
      serif = [ "JetBrainsMono Nerd Font Mono" "Symbols Nerd Font Mono" ];
    };

    # CRITICAL: qt5ct/qt6ct File Management Strategy
    #
    # When enableSwayForDESK = false:
    #   - qt5ct/qt6ct files are removed via home.file above (empty text overrides Stylix-generated files)
    #   - Plasma 6 uses native Breeze theme (QT_QPA_PLATFORMTHEME is unset)
    #
    # When enableSwayForDESK = true:
    #   - qt5ct/qt6ct files are generated by Stylix (Qt target is enabled)
    #   - In Plasma 6: QT_QPA_PLATFORMTHEME is unset (containment), so Qt uses default "kde" platform theme
    #     Qt applications should NOT read qt5ct files when QT_QPA_PLATFORMTHEME is unset
    #   - In Sway: QT_QPA_PLATFORMTHEME=qt5ct is set via extraSessionCommands, so Qt uses qt5ct
    #
    # CRITICAL: Backup qt5ct/qt6ct files to allow restoration if Plasma 6 modifies them
    # This activation script runs after Stylix generates files, creating backups
    # Files are kept writable (644) to allow Dolphin to persist color scheme preferences
    # Protection against Plasma 6 modifications is provided by restoration on Sway startup
    home.activation.backupAndProtectQt5ct = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Only run when enableSwayForDESK = true (files are needed for Sway)
      if [ "${toString (systemSettings.enableSwayForDESK == true)}" = "true" ]; then
        QT5CT_DIR="$HOME/.config/qt5ct"
        QT6CT_DIR="$HOME/.config/qt6ct"
        QT5CT_BACKUP_DIR="$HOME/.config/qt5ct-backup"
        QT6CT_BACKUP_DIR="$HOME/.config/qt6ct-backup"
        
        # Ensure backup directory exists
        mkdir -p "$QT5CT_BACKUP_DIR/colors" || true
        mkdir -p "$QT6CT_BACKUP_DIR/colors" || true
        
        # Create backup of Stylix-generated qt5ct files
        # These files are generated by Stylix when stylix.targets.qt.enable = true
        if [ -f "$QT5CT_DIR/qt5ct.conf" ]; then
          cp -f "$QT5CT_DIR/qt5ct.conf" "$QT5CT_BACKUP_DIR/qt5ct.conf" || true
          echo "Backed up qt5ct.conf"
        fi
        if [ -f "$QT5CT_DIR/colors/oomox-current.conf" ]; then
          cp -f "$QT5CT_DIR/colors/oomox-current.conf" "$QT5CT_BACKUP_DIR/colors/oomox-current.conf" || true
          echo "Backed up oomox-current.conf"
        fi

        # Backup qt6ct files
        if [ -f "$QT6CT_DIR/qt6ct.conf" ]; then
          cp -f "$QT6CT_DIR/qt6ct.conf" "$QT6CT_BACKUP_DIR/qt6ct.conf" || true
          echo "Backed up qt6ct.conf"
        fi
        
        # NOTE: Files are kept writable (644) to allow Dolphin to persist color scheme preferences
        # Protection against Plasma 6 modifications is provided by restoration on Sway startup
        echo "qt5ct/qt6ct files backed up (writable to allow Dolphin preferences)"
      fi
    '';
  }
else
  {
    # Return empty configuration when Stylix is disabled (Plasma 6 or stylixEnable == false)
    # This prevents Home Manager from trying to evaluate Stylix options that don't exist
  }
