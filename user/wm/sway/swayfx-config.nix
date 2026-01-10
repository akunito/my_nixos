{ config, pkgs, lib, userSettings, systemSettings, ... }:

let
  # Hyper key combination (Super+Ctrl+Alt)
  hyper = "Mod4+Control+Mod1";
  mainMon = "Samsung Electric Company Odyssey G70NC H1AK500000";

  useSystemdSessionDaemons = config.user.wm.sway.useSystemdSessionDaemons;

  # Pull script derivations from the submodules that own them (session-env/startup-apps).
  scripts = config.user.wm.sway._internal.scripts;
  set-sway-theme-vars = scripts.setSwayThemeVars;
  set-sway-systemd-session-vars = scripts.setSwaySystemdSessionVars;
  write-sway-portal-env = scripts.writeSwayPortalEnv;
  sway-session-start = scripts.swaySessionStart;
  sway-start-plasma-kwallet-pam = scripts.swayStartPlasmaKwalletPam;
  restore-qt5ct-files = scripts.restoreQt5ctFiles;
  desk-startup-apps-init = scripts.deskStartupAppsInit;

  # Focus the primary output and warp the cursor onto it at Sway session start.
  # This avoids "focus_follows_mouse" pulling focus to an off/unused monitor if the cursor last lived there.
  sway-focus-primary-output = pkgs.writeShellApplication {
    name = "sway-focus-primary-output";
    runtimeInputs = with pkgs; [
      sway
      jq
    ];
    text = ''
      #!/bin/bash
      set -euo pipefail

      PRIMARY="${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else ""}"
      if [ -z "$PRIMARY" ]; then
        exit 0
      fi

      # Focus the intended output first.
      swaymsg focus output "$PRIMARY" >/dev/null 2>&1 || true

      # Warp cursor to the center of the primary output so focus_follows_mouse can't "steal" focus.
      SEAT="$(swaymsg -t get_seats 2>/dev/null | jq -r '.[0].name // "seat0"' 2>/dev/null || echo "seat0")"
      read -r X Y W H < <(
        swaymsg -t get_outputs 2>/dev/null | jq -r --arg name "$PRIMARY" '
          .[]
          | select(.name == $name)
          | .rect
          | "\(.x) \(.y) \(.width) \(.height)"
        ' 2>/dev/null | head -n1
      )

      if [ -n "''${X:-}" ] && [ -n "''${W:-}" ]; then
        CX=$((X + W / 2))
        CY=$((Y + H / 2))
        swaymsg "seat $SEAT cursor set $CX $CY" >/dev/null 2>&1 || true
      fi

      exit 0
    '';
  };
in
{
  # CRITICAL: Idle daemon with swaylock-effects
  services.swayidle = {
    enable = true;
    timeouts = [
      {
        timeout = 600; # 10 minutes
        command = "${pkgs.swaylock-effects}/bin/swaylock --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033";
      }
      {
        timeout = 900; # 15 minutes
        command = "${pkgs.sway}/bin/swaymsg 'output * dpms off'";
        resumeCommand = "${pkgs.sway}/bin/swaymsg 'output * dpms on'";
      }
    ];
    # New syntax: events is now an attrset keyed by event name, value is the command string
    events = {
      "before-sleep" = "${pkgs.swaylock-effects}/bin/swaylock --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033";
    };
  };

  # SwayFX configuration
  wayland.windowManager.sway = {
    enable = true;
    package = pkgs.swayfx; # Use SwayFX instead of standard sway
    checkConfig = false; # Disable config check (fails in build sandbox without DRM FD)

    # CRITICAL: Inject theme variables that we force-unset globally
    # This runs early in the Sway startup sequence, ensuring the environment is set before any apps launch
    # Variables are set ONLY for Sway sessions, not affecting Plasma 6
    extraSessionCommands = lib.mkIf (systemSettings.stylixEnable == true) ''
      # Inject variables that we force-unset globally to prevent Plasma 6 leakage
      export QT_QPA_PLATFORMTHEME=qt5ct
      export GTK_THEME=${if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita"}
      export GTK_APPLICATION_PREFER_DARK_THEME=1
      # Fix for Java apps if needed
      export _JAVA_AWT_WM_NONREPARENTING=1
    '';

    config = {
      # Hyper key definition (Ctrl+Alt+Super)
      modifier = "Mod4"; # Super key
      # Note: Hyper key combinations are defined directly in keybindings
      # $hyper = Mod4+Control+Mod1 (used in keybindings)

      # Standard Sway settings (border, gaps, and workspace settings moved to extraConfig)
      gaps = {
        inner = 8;
      };

      # Keybindings
      keybindings = lib.mkMerge [
        {
          # Reload SwayFX configuration
          "${hyper}+Shift+r" = "reload";

          # Manual startup apps launcher
          "${hyper}+Shift+Return" = "exec ${config.home.homeDirectory}/.nix-profile/bin/desk-startup-apps-launcher";

          # Rofi Universal Launcher
          # Use rofi's configured combi-modi (includes apps/run/window/filebrowser/calc/emoji/power)
          "${hyper}+space" = "exec rofi -show combi -show-icons";
          # Note: Removed "${hyper}+d" to avoid conflict with application bindings
          # Use "${hyper}+space" for rofi launcher

          # Rofi Calculator (with -no-show-match -no-sort for better UX)
          "${hyper}+x" = "exec rofi -show calc -modi calc -no-show-match -no-sort";

          # Rofi Emoji Picker
          "${hyper}+period" = "exec rofi -show emoji";

          # Rofi File Browser (separate from combi mode)
          "${hyper}+slash" = "exec rofi -show filebrowser";

          # Window Overview (Mission Control-like)
          # Using Rofi in window mode with grid layout for stable workspace overview
          # Grid layout: 3 columns, large icons (48px), vertical orientation
          # Rofi inherits Stylix colors automatically via existing rofi.nix configuration
          # Default: grouped app -> window picker (less noisy when apps have multiple windows)
          "${hyper}+Tab" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-overview-grouped.sh";

          # Workspace toggle (back and forth)
          "Mod4+Tab" = "workspace back_and_forth";

          # Lock screen (Meta/Super + l)
          "Mod4+l" = "exec ${pkgs.swaylock-effects}/bin/swaylock --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033";

          # Media keys (volume)
          # Uses swayosd-client to both adjust volume and show an on-screen display.
          "XF86AudioLowerVolume" = "exec ${pkgs.swayosd}/bin/swayosd-client --output-volume lower";
          "XF86AudioRaiseVolume" = "exec ${pkgs.swayosd}/bin/swayosd-client --output-volume raise";
          "XF86AudioMute" = "exec ${pkgs.swayosd}/bin/swayosd-client --output-volume mute-toggle";
          # Keyd virtual keyboard emits a quick mute down/up; bind the combo to avoid clobbering real mute.
          "${hyper}+XF86AudioMute" = "exec ${config.home.homeDirectory}/.config/sway/scripts/idle-inhibit-toggle.sh";

          # Screenshot workflow
          "${hyper}+Shift+x" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh full";
          "${hyper}+Shift+c" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh area";
          "Print" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh area";
          "Shift+Print" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh clipboard";

          # Application keybindings (using app-toggle.sh script)
          # Note: Using different keys to avoid conflicts with window management bindings
          # Format: app-toggle.sh <app_id|class> <launch_command...>
          "${hyper}+T" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh kitty kitty";
          "${hyper}+R" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh Alacritty alacritty";
          "${hyper}+L" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh org.telegram.desktop Telegram";
          "${hyper}+E" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh org.kde.dolphin dolphin";
          "${hyper}+U" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh io.dbeaver.DBeaverCommunity dbeaver";
          "${hyper}+A" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh pavucontrol pavucontrol";
          "${hyper}+D" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh obsidian obsidian --no-sandbox --ozone-platform=wayland --ozone-platform-hint=auto --enable-features=UseOzonePlatform,WaylandWindowDecorations";
          "${hyper}+V" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh com.vivaldi.Vivaldi vivaldi";
          "${hyper}+G" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh chromium-browser chromium";
          "${hyper}+Y" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh spotify spotify --enable-features=UseOzonePlatform --ozone-platform=wayland";
          "${hyper}+N" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh nwg-look nwg-look";
          "${hyper}+P" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh Bitwarden bitwarden";
          "${hyper}+C" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh cursor cursor --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform-hint=auto --unity-launch";
          # Mission Center (app_id is io.missioncenter.MissionCenter, binary is missioncenter)
          "${hyper}+m" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh io.missioncenter.MissionCenter missioncenter";
          "${hyper}+B" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh com.usebottles.bottles bottles";
          # SwayBG+ (wallpaper UI)
          "${hyper}+s" = "exec swaybgplus-gui";

          # Workspace navigation (using Sway native commands for local cycling)
          #
          # NOTE: Use lowercase keysyms; adding Q/W variants causes Sway to warn about duplicate binds
          # (it normalizes the combo and overwrites the earlier binding).
          "${hyper}+q" = "workspace prev_on_output"; # LOCAL navigation (within current monitor only)
          "${hyper}+w" = "workspace next_on_output"; # LOCAL navigation (within current monitor only)
          "${hyper}+Shift+q" = "move container to workspace prev_on_output"; # Move window to previous workspace on current monitor (LOCAL)
          "${hyper}+Shift+w" = "move container to workspace next_on_output"; # Move window to next workspace on current monitor (LOCAL)

          # Direct workspace bindings (using swaysome)
          #
          # NOTE: The 1..0 and Shift+1..0 bindings are defined in the override block below
          # to implement the absolute-to-Samsung workflow. Do not define them here as well,
          # or Home Manager will throw a conflicting-definition error.

          # Move window between monitors
          "${hyper}+Shift+Left" = "move container to output left";
          "${hyper}+Shift+Right" = "move container to output right";

          # Output focus bindings (required since F-keys are removed)
          "${hyper}+Left" = "focus output left";
          "${hyper}+Right" = "focus output right";
          "${hyper}+Up" = "focus output up";
          "${hyper}+Down" = "focus output down";

          # Window management (basic - keeping for compatibility)
          "${hyper}+h" = "focus left";
          "${hyper}+j" = "focus down";
          "${hyper}+k" = "focus up";
          # Note: Removed "${hyper}+l" to avoid conflict with "${hyper}+L" (telegram)
          "${hyper}+f" = "fullscreen toggle";
          "${hyper}+Shift+space" = "floating toggle";
          # Note: "${hyper}+s" is reserved for SwayBG+ (see application bindings above)
          # Note: "${hyper}+w" is used for workspace next_on_output (see Workspace navigation above)
          # Note: Removed "${hyper}+e" to avoid conflict with "${hyper}+E" (dolphin file explorer)
          # Note: Removed "${hyper}+a" to avoid conflict with "${hyper}+A" (pavucontrol)
          # Note: Removed "${hyper}+u" to avoid conflict with "${hyper}+U" (dbeaver)

          # Window movement (conditional - floating vs tiled)
          "${hyper}+Shift+j" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh left";
          "${hyper}+colon" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh right";
          "${hyper}+Shift+k" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh down";
          "${hyper}+Shift+l" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh up";

          # Window focus navigation
          "${hyper}+Shift+comma" = "focus left"; # Changed from Shift+m to avoid conflict with mission-center
          "${hyper}+question" = "focus right";
          "${hyper}+less" = "focus down";
          "${hyper}+greater" = "focus up";

          # Window resizing
          "${hyper}+Shift+u" = "resize shrink width 5 ppt";
          "${hyper}+Shift+p" = "resize grow width 5 ppt";
          "${hyper}+Shift+i" = "resize grow height 5 ppt";
          "${hyper}+Shift+o" = "resize shrink height 5 ppt";

          # Window management toggles
          "${hyper}+Escape" = "kill";
          "${hyper}+Shift+f" = "floating toggle";
          "${hyper}+Shift+s" = "sticky toggle";
          "${hyper}+Shift+g" = "fullscreen toggle";

          # Scratchpad
          "${hyper}+minus" = "scratchpad show";
          "${hyper}+Shift+minus" = "move scratchpad";

          # Clipboard history
          "${hyper}+Shift+v" = "exec sh -c '${pkgs.cliphist}/bin/cliphist list | ${pkgs.rofi}/bin/rofi -dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy'";

          # Power menu
          "${hyper}+Shift+BackSpace" = "exec rofi -show power -show-icons";

          # Toggle SwayFX default bar (swaybar) - disabled by default, can be toggled manually
          "${hyper}+Shift+Home" = "exec ${config.home.homeDirectory}/.config/sway/scripts/swaybar-toggle.sh";

          # Hide window (move to scratchpad)
          "${hyper}+Shift+e" = "move scratchpad";

          # Exit Sway
          "${hyper}+Shift+End" = "exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit Sway? This will end your Wayland session.' -b 'Yes, exit Sway' 'swaymsg exit'";
        }
        # Overrides (must win without breaking the rest of the keymap)
        {
          # Relative workspace navigation (standard swaysome behavior):
          # - It uses the CURRENT output's workspace group and maps index -> workspace number block.
          "${hyper}+1" = "exec ${pkgs.swaysome}/bin/swaysome focus 1";
          "${hyper}+2" = "exec ${pkgs.swaysome}/bin/swaysome focus 2";
          "${hyper}+3" = "exec ${pkgs.swaysome}/bin/swaysome focus 3";
          "${hyper}+4" = "exec ${pkgs.swaysome}/bin/swaysome focus 4";
          "${hyper}+5" = "exec ${pkgs.swaysome}/bin/swaysome focus 5";
          "${hyper}+6" = "exec ${pkgs.swaysome}/bin/swaysome focus 6";
          "${hyper}+7" = "exec ${pkgs.swaysome}/bin/swaysome focus 7";
          "${hyper}+8" = "exec ${pkgs.swaysome}/bin/swaysome focus 8";
          "${hyper}+9" = "exec ${pkgs.swaysome}/bin/swaysome focus 9";
          # IMPORTANT: swaysome expects index 10 for the \"0\" key.
          "${hyper}+0" = "exec ${pkgs.swaysome}/bin/swaysome focus 10";

          # Relative move (same group as current output)
          "${hyper}+Shift+1" = "exec ${pkgs.swaysome}/bin/swaysome move 1";
          "${hyper}+Shift+2" = "exec ${pkgs.swaysome}/bin/swaysome move 2";
          "${hyper}+Shift+3" = "exec ${pkgs.swaysome}/bin/swaysome move 3";
          "${hyper}+Shift+4" = "exec ${pkgs.swaysome}/bin/swaysome move 4";
          "${hyper}+Shift+5" = "exec ${pkgs.swaysome}/bin/swaysome move 5";
          "${hyper}+Shift+6" = "exec ${pkgs.swaysome}/bin/swaysome move 6";
          "${hyper}+Shift+7" = "exec ${pkgs.swaysome}/bin/swaysome move 7";
          "${hyper}+Shift+8" = "exec ${pkgs.swaysome}/bin/swaysome move 8";
          "${hyper}+Shift+9" = "exec ${pkgs.swaysome}/bin/swaysome move 9";
          "${hyper}+Shift+0" = "exec ${pkgs.swaysome}/bin/swaysome move 10";
        }
      ];

      # Startup commands
      startup =
        [
          # DESK-only: focus the primary output and warp cursor onto it early
          {
            command = "${sway-focus-primary-output}/bin/sway-focus-primary-output";
            always = false; # Only run on initial startup, not on config reload
          }
          # Initialize swaysome and assign workspace groups to monitors
          # No 'always = true' - runs only on initial startup, not on config reload
          # This prevents jumping back to empty workspaces when editing config
          # Workspace grouping is triggered by kanshi profiles (after outputs are configured),
          # to avoid assigning workspaces to phantom/"usually OFF" outputs.
          {
            command = "${config.home.homeDirectory}/.config/sway/scripts/swaysome-init.sh";
          }
          # NOTE: Theme variables are now set via extraSessionCommands (cleaner, native Home Manager option)
          # This script syncs them with D-Bus activation environment to ensure GUI applications launched via D-Bus inherit the variables
          {
            command = "${set-sway-theme-vars}/bin/set-sway-theme-vars";
            always = true;
          }
          # Make core Wayland session vars available to systemd --user (needed for DBus-activated services like xdg-desktop-portal)
          {
            command = "${set-sway-systemd-session-vars}/bin/set-sway-systemd-session-vars";
            always = true;
          }
          # Apply PAM-provided credentials to KWallet in Sway sessions (non-Plasma).
          # Must run AFTER set-sway-systemd-session-vars so systemd --user has WAYLAND_DISPLAY/SWAYSOCK.
          {
            command = "${sway-start-plasma-kwallet-pam}/bin/sway-start-plasma-kwallet-pam";
            always = false; # Only run on initial startup, not on config reload
          }
          # CRITICAL: Restore qt5ct files before daemons start to ensure correct Qt theming
          # Plasma 6 might modify qt5ct files even though it shouldn't use them
          {
            command = "${restore-qt5ct-files}/bin/restore-qt5ct-files";
            always = false; # Only run on initial startup, not on reload
          }
        ]
        ++ lib.optionals useSystemdSessionDaemons [
          # Portal env must exist before portals restart during fast relog; it is only consumed by portal units via drop-in.
          {
            command = "${write-sway-portal-env}/bin/write-sway-portal-env";
            always = true;
          }
          # Start the Sway session target; services are ordered and restarted by systemd
          {
            command = "${sway-session-start}/bin/sway-session-start";
            always = true;
          }
        ]
        ++ [
          # DESK-only startup apps (runs after daemons are ready)
          {
            command = "${desk-startup-apps-init}/bin/desk-startup-apps-init";
            always = false; # Only run on initial startup, not on config reload
          }
        ];

      # Window rules
      window = {
        commands = [
          # Wayland apps (use app_id)
          { criteria = { app_id = "rofi"; }; command = "floating enable"; }
          { criteria = { app_id = "kitty"; }; command = "floating enable"; }
          { criteria = { app_id = "SwayBG+"; }; command = "floating enable"; }
          { criteria = { title = "SwayBG+"; }; command = "floating enable"; }
          { criteria = { app_id = "org.telegram.desktop"; }; command = "floating enable"; }
          { criteria = { app_id = "telegram-desktop"; }; command = "floating enable"; }
          { criteria = { app_id = "bitwarden"; }; command = "floating enable"; }
          { criteria = { app_id = "bitwarden-desktop"; }; command = "floating enable"; }
          { criteria = { app_id = "Bitwarden"; }; command = "floating enable"; }
          { criteria = { app_id = "com.usebottles.bottles"; }; command = "floating enable"; }
          { criteria = { app_id = "swayfx-settings"; }; command = "floating enable"; }
          { criteria = { app_id = "io.missioncenter.MissionCenter"; }; command = "floating enable, sticky enable, resize set 800 600"; }
          # LACT (Linux AMDGPU Controller): often XWayland; keep explicit app_id match for Wayland variants too.
          { criteria = { app_id = "lact"; }; command = "floating enable, sticky enable"; }
          { criteria = { title = "LACT"; }; command = "floating enable, sticky enable"; }

          # KDE Discover: floating + sticky (Wayland app_id + common fallbacks)
          { criteria = { app_id = "org.kde.discover"; }; command = "floating enable, sticky enable"; }
          { criteria = { app_id = "plasma-discover"; }; command = "floating enable, sticky enable"; }
          { criteria = { app_id = "discover"; }; command = "floating enable, sticky enable"; }
          { criteria = { title = "Discover"; }; command = "floating enable, sticky enable"; }

          # XWayland apps (use class)
          { criteria = { class = "SwayBG+"; }; command = "floating enable"; }
          { criteria = { class = "Spotify"; }; command = "floating enable"; }
          { criteria = { class = "Dolphin"; }; command = "floating enable"; }
          { criteria = { class = "dolphin"; }; command = "floating enable"; }
          { criteria = { class = "lact"; }; command = "floating enable, sticky enable"; }
          { criteria = { class = "LACT"; }; command = "floating enable, sticky enable"; }
          { criteria = { class = "discover"; }; command = "floating enable, sticky enable"; }
          { criteria = { class = "Discover"; }; command = "floating enable, sticky enable"; }
          { criteria = { class = "plasma-discover"; }; command = "floating enable, sticky enable"; }

          # Dolphin on Wayland (use app_id)
          { criteria = { app_id = "org.kde.dolphin"; }; command = "floating enable"; }

          # Sticky windows - visible on all workspaces of their monitor
          { criteria = { app_id = "kitty"; }; command = "sticky enable"; }
          { criteria = { app_id = "Alacritty"; }; command = "sticky enable"; }
          { criteria = { app_id = "SwayBG+"; }; command = "sticky enable"; }
          { criteria = { title = "SwayBG+"; }; command = "sticky enable"; }
          { criteria = { app_id = "org.telegram.desktop"; }; command = "sticky enable"; }
          { criteria = { app_id = "telegram-desktop"; }; command = "sticky enable"; }
          { criteria = { app_id = "bitwarden"; }; command = "sticky enable"; }
          { criteria = { app_id = "bitwarden-desktop"; }; command = "sticky enable"; }
          { criteria = { app_id = "Bitwarden"; }; command = "sticky enable"; }
          { criteria = { app_id = "org.kde.dolphin"; }; command = "sticky enable"; }
          { criteria = { class = "SwayBG+"; }; command = "sticky enable"; }
          { criteria = { class = "Dolphin"; }; command = "sticky enable"; }
          { criteria = { class = "dolphin"; }; command = "sticky enable"; }
          { criteria = { class = "Spotify"; }; command = "sticky enable"; }
          { criteria = { app_id = "io.missioncenter.MissionCenter"; }; command = "sticky enable"; }
          { criteria = { app_id = "lact"; }; command = "sticky enable"; }
          { criteria = { title = "LACT"; }; command = "sticky enable"; }
          { criteria = { class = "lact"; }; command = "sticky enable"; }
          { criteria = { class = "LACT"; }; command = "sticky enable"; }
          { criteria = { app_id = "org.kde.discover"; }; command = "sticky enable"; }
          { criteria = { app_id = "plasma-discover"; }; command = "sticky enable"; }
          { criteria = { app_id = "discover"; }; command = "sticky enable"; }
          { criteria = { title = "Discover"; }; command = "sticky enable"; }
          { criteria = { class = "discover"; }; command = "sticky enable"; }
          { criteria = { class = "Discover"; }; command = "sticky enable"; }
          { criteria = { class = "plasma-discover"; }; command = "sticky enable"; }
        ];
      };
    };

    extraConfig = ''
      # Window border settings
      default_border pixel 2

      # Disable SwayFX's default internal bar (swaybar) by default
      # Can be toggled manually via ${hyper}+Shift+Home keybinding or: swaymsg bar mode dock/invisible
      bar {
        mode invisible
        hidden_state hide
        position bottom
      }

      # CRITICAL: Alt key for Plasma-like window manipulation
      # Alt+drag moves windows, Alt+right-drag resizes windows
      floating_modifier Mod1

      # Output layout is managed dynamically by kanshi (official wlroots/Sway output profile manager).
      # This avoids phantom pointer/workspace regions on monitors that are usually OFF.
      #
      # IMPORTANT: Do NOT include swaybgplus output geometry here; it can re-enable "usually OFF" outputs.

      # Workspace placement is managed by swaysome (per-output groups) and kanshi (outputs).
      # Do not hardcode connector-based workspace->output mappings here (anti-drift).

      # Workspace configuration
      workspace_auto_back_and_forth yes

      # DESK startup apps - assign to specific workspaces
      # Using 'assign' instead of 'for_window' prevents flickering on wrong workspace
      # Vivaldi - support both Flatpak and native versions
      assign [app_id="com.vivaldi.Vivaldi"] workspace number 11
      assign [app_id="vivaldi"] workspace number 11
      assign [app_id="vivaldi-stable"] workspace number 11

      # Cursor - support both Flatpak and native versions
      assign [app_id="cursor"] workspace number 12
      assign [app_id="com.todesktop.230313mzl4w4u92"] workspace number 12

      # Obsidian - support both Flatpak and native versions
      assign [app_id="obsidian"] workspace number 21
      assign [app_id="md.obsidian.Obsidian"] workspace number 21

      # Chromium - support both Flatpak and native versions
      assign [app_id="chromium"] workspace number 22
      assign [app_id="org.chromium.Chromium"] workspace number 22
      assign [class="chromium-browser"] workspace number 22

      # Disable SwayFX's default internal bar (swaybar) by default
      # Can be toggled manually via swaybar-toggle.sh script or keybinding
      bar bar-0 {
        mode invisible
        hidden_state hide
      }

      # SwayFX visual settings matching Khanelinix aesthetic (blur, shadows, rounded corners)
      corner_radius 12
      blur enable
      blur_xray disable
      blur_passes 3
      blur_radius 5
      shadows enable
      shadow_blur_radius 20
      shadow_color #00000070

      # Dim inactive windows slightly for focus
      default_dim_inactive 0.1

      # Layer effects (Waybar)
      # Keep the bar surface fully transparent (no glass blur); only individual widget pills have backgrounds (Waybar CSS).
      # If `layer_effects` isn't supported in your SwayFX build, these lines are ignored and won't break startup.
      layer_effects "waybar" blur disable
      layer_effects "waybar" corner_radius 0

      # NumLock (config-only; cannot be toggled via `swaymsg` at runtime)
      #
      # IMPORTANT: Use the official Sway form (`type:keyboard`) rather than `*`.
      # In Sway, `input` matching supports `type:keyboard` and concrete identifiers.
      input type:keyboard xkb_numlock enabled

      # Keyboard input configuration for polyglot typing (English/Spanish)
      input type:keyboard {
        xkb_layout "us"
        xkb_variant "altgr-intl"
        xkb_numlock enabled
      }

      # Touchpad configuration
      input "type:touchpad" {
        dwt enabled
        tap enabled
        natural_scroll enabled
        middle_emulation enabled
      }

      # Additional SwayFX configuration
      # Floating window rules (duplicate from config.window.commands for reliability)
      for_window [app_id="kitty"] floating enable
      for_window [app_id="org.telegram.desktop"] floating enable
      for_window [app_id="telegram-desktop"] floating enable
      for_window [app_id="bitwarden"] floating enable
      for_window [app_id="bitwarden-desktop"] floating enable
      for_window [app_id="Bitwarden"] floating enable
      for_window [app_id="com.usebottles.bottles"] floating enable
      for_window [app_id="org.kde.dolphin"] floating enable
      for_window [class="Dolphin"] floating enable
      for_window [class="dolphin"] floating enable
      for_window [app_id="rofi"] floating enable
      for_window [app_id="swayfx-settings"] floating enable

      # SwayBG+ (wallpaper UI): always floating and sticky (Wayland + XWayland)
      for_window [app_id="SwayBG+"] floating enable, sticky enable
      for_window [class="SwayBG+"] floating enable, sticky enable
      for_window [title="SwayBG+"] floating enable, sticky enable

      # Alacritty: floating and sticky (case variations)
      for_window [app_id="Alacritty"] floating enable, sticky enable
      for_window [app_id="alacritty"] floating enable, sticky enable

      # Spotify: floating and sticky (both XWayland and Wayland)
      for_window [class="Spotify"] floating enable, sticky enable
      for_window [app_id="spotify"] floating enable, sticky enable

      # Additional floating window rules
      for_window [app_id="pavucontrol"] floating enable
      for_window [app_id="nm-connection-editor"] floating enable
      for_window [app_id="blueman-manager"] floating enable
      for_window [app_id="swappy"] floating enable, sticky enable
      for_window [app_id="swaync"] floating enable
      # LACT (Linux AMDGPU Controller): ensure floating+sticky (Wayland app_id + XWayland class)
      for_window [app_id="lact"] floating enable, sticky enable
      for_window [title="LACT"] floating enable, sticky enable
      for_window [class="lact"] floating enable, sticky enable
      for_window [class="LACT"] floating enable, sticky enable

      # KDE Discover: ensure floating+sticky (Wayland app_id + XWayland class/title fallbacks)
      for_window [app_id="org.kde.discover"] floating enable, sticky enable
      for_window [app_id="plasma-discover"] floating enable, sticky enable
      for_window [app_id="discover"] floating enable, sticky enable
      for_window [class="plasma-discover"] floating enable, sticky enable
      for_window [class="discover"] floating enable, sticky enable
      for_window [class="Discover"] floating enable, sticky enable
      for_window [title="Discover"] floating enable, sticky enable

      # Mission Center - Floating, Sticky, Resized
      for_window [app_id="io.missioncenter.MissionCenter"] floating enable, sticky enable, resize set 800 600

      # KWallet - Force to Primary Monitor, Workspace 1 (Floating, Sticky)
      # Multiple rules to catch all KWallet variants (kwalletd5, kwalletd6, kwallet-query, etc.)
      # Note: Sway doesn't support regex in for_window criteria, so we use explicit string matching
      # Note: Use Nix string interpolation for PRIMARY_OUTPUT variable
      # CRITICAL: Primary app_id is org.kde.ksecretd (captured from actual KWallet window)
      # CRITICAL: Actual window name is "KDE Wallet Service" (captured from actual window)

      # App ID-based matching (Wayland native) - PRIMARY
      for_window [app_id="org.kde.ksecretd"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      # Fallback variants (in case different KWallet windows use these)
      for_window [app_id="org.kde.kwalletd5"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      for_window [app_id="org.kde.kwalletd6"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      for_window [app_id="kwallet-query"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable

      # Title-based matching (fallback) - PRIMARY
      for_window [title="KDE Wallet Service"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      for_window [title="KWallet"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      for_window [title="kwallet"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable

      # Class-based matching (X11/XWayland) - fallback
      for_window [class="kwalletmanager5"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      for_window [class="kwalletmanager6"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      for_window [class="KWalletManager"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable

      # Focus follows mouse
      focus_follows_mouse yes

      # Mouse warping
      mouse_warping output
    '';
  };
}


