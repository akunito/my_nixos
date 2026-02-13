{
  config,
  pkgs,
  lib,
  userSettings,
  systemSettings,
  ...
}:

let
  # Hyper key combination (Super+Ctrl+Alt)
  hyper = "Mod4+Control+Mod1";
  mainMon = "Samsung Electric Company Odyssey G70NC H1AK500000";

  # Pull script derivations from the submodules that own them (session-env/startup-apps).
  scripts = config.user.wm.sway._internal.scripts;
  set-sway-theme-vars = scripts.setSwayThemeVars;
  set-sway-systemd-session-vars = scripts.setSwaySystemdSessionVars;
  write-sway-portal-env = scripts.writeSwayPortalEnv;
  sway-session-start = scripts.swaySessionStart;
  sway-session-refresh-env = scripts.swaySessionRefreshEnv;
  sway-start-plasma-kwallet-pam = scripts.swayStartPlasmaKwalletPam;
  restore-qt5ct-files = scripts.restoreQt5ctFiles;
  desk-startup-apps-init = scripts.deskStartupAppsInit;
  rebuild-ksycoca = scripts.rebuildKsycoCa;

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

      PRIMARY="${
        if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else ""
      }"
      if [ -z "$PRIMARY" ]; then
        exit 0
      fi

      # Focus the intended output first.
      swaymsg focus output "$PRIMARY" >/dev/null 2>&1 || true

      # Warp cursor to the center of the primary output so focus_follows_mouse can't "steal" focus.
      SEAT="$(swaymsg -t get_seats 2>/dev/null | jq -r '.[0].name // "seat0"' 2>/dev/null || echo "seat0")"
      read -r X Y W H < <(
        swaymsg -t get_outputs 2>/dev/null | jq -r --arg primary "$PRIMARY" '
          .[]
          | select(
              (.name == $primary)
              or ((.make + " " + .model + " " + .serial) == $primary)
            )
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

  # Parse keyboard layouts and variants from systemSettings.swayKeyboardLayouts
  # Input format: [ "us(altgr-intl)" "es" "pl" ]
  # Output: { layouts = "us,es,pl"; variants = "altgr-intl,,"; }
  parseLayout =
    entry:
    let
      parts = lib.splitString "(" entry;
    in
    if lib.length parts > 1 then
      {
        layout = lib.head parts;
        variant = lib.removeSuffix ")" (lib.elemAt parts 1);
      }
    else
      {
        layout = entry;
        variant = "";
      };

  parsedLayouts = map parseLayout systemSettings.swayKeyboardLayouts;
  xkbLayouts = lib.concatStringsSep "," (map (x: x.layout) parsedLayouts);
  xkbVariants = lib.concatStringsSep "," (map (x: x.variant) parsedLayouts);

  # Swaylock wrapper with 4-second grace period
  # Shows warning notification and cancels lock if user provides input during grace period
  swaylock-with-grace = pkgs.writeShellApplication {
    name = "swaylock-with-grace";
    runtimeInputs = with pkgs; [
      coreutils
      sway
      swayidle
      jq
      libnotify
      swaylock-effects
      bc
    ];
    text = builtins.readFile ./scripts/swaylock-with-grace.sh;
  };

  # Resume monitors and restore wallpaper (wraps multi-command sequence for swayidle)
  sway-resume-monitors = pkgs.writeShellScript "sway-resume-monitors" ''
    ${pkgs.sway}/bin/swaymsg 'output * power on'
    ${if (systemSettings.waypaperEnable or false)
      then "${pkgs.systemd}/bin/systemctl --user start waypaper-restore.service"
      else "${pkgs.systemd}/bin/systemctl --user start swww-restore.service"}
  '';

  # Smart lid handler: context-aware lid close behavior
  # External monitor(s) present → disable internal display only
  # No external monitors + on battery → suspend
  # No external monitors + on AC → do nothing (safety: never black out the only display)
  sway-lid-handler = pkgs.writeShellScript "sway-lid-handler" ''
    EXT_COUNT=$(${pkgs.sway}/bin/swaymsg -t get_outputs -r | \
      ${pkgs.jq}/bin/jq '[.[] | select(.name != "eDP-1" and .active == true)] | length')

    if [ "$EXT_COUNT" -gt 0 ]; then
      # External monitor(s) connected: safe to disable internal display
      ${pkgs.sway}/bin/swaymsg output eDP-1 disable
    else
      # No external monitors: only suspend if on battery
      BAT_STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Full")
      if [ "$BAT_STATUS" = "Discharging" ]; then
        ${if (systemSettings.hibernateEnable or false)
          then "${pkgs.systemd}/bin/systemctl suspend-then-hibernate"
          else "${pkgs.systemd}/bin/systemctl suspend"}
      fi
      # On AC with no external monitors: do nothing (lid close ignored)
    fi
  '';

  # Idle action scripts (used by power-aware swayidle wrapper)
  sway-idle-dim = pkgs.writeShellScript "sway-idle-dim" ''
    # Save current brightness and dim to configured percentage
    ${pkgs.brightnessctl}/bin/brightnessctl -s set ${toString (systemSettings.swayIdleDimPercent or 30)}%
  '';

  sway-idle-undim = pkgs.writeShellScript "sway-idle-undim" ''
    # Restore previous brightness
    ${pkgs.brightnessctl}/bin/brightnessctl -r
  '';

  sway-idle-monitor-off = pkgs.writeShellScript "sway-idle-monitor-off" ''
    ${pkgs.sway}/bin/swaymsg 'output * power off'
  '';

  sway-idle-suspend = pkgs.writeShellScript "sway-idle-suspend" ''
    ${if (systemSettings.hibernateEnable or false) then ''
      BAT_STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Full")
      if [ "$BAT_STATUS" = "Discharging" ]; then
        ${pkgs.systemd}/bin/systemctl suspend-then-hibernate
      else
        ${pkgs.systemd}/bin/systemctl suspend
      fi
    '' else ''
      ${pkgs.systemd}/bin/systemctl suspend
    ''}
  '';

  sway-idle-before-sleep = pkgs.writeShellScript "sway-idle-before-sleep" ''
    ${pkgs.swaylock-effects}/bin/swaylock --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033 --font 'JetBrainsMono Nerd Font Mono' --color 000000
  '';

  # Power-aware swayidle launcher: selects timeouts based on AC/battery state
  sway-power-swayidle = pkgs.writeShellScript "sway-power-swayidle" ''
    BAT_STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Full")

    if [ "$BAT_STATUS" = "Discharging" ]; then
      DIM_TIMEOUT=${toString (systemSettings.swayIdleDimTimeoutBat or 60)}
      LOCK_TIMEOUT=${toString (systemSettings.swayIdleLockTimeoutBat or 180)}
      MONITOR_OFF_TIMEOUT=${toString (systemSettings.swayIdleMonitorOffTimeoutBat or 210)}
      SUSPEND_TIMEOUT=${toString (systemSettings.swayIdleSuspendTimeoutBat or 480)}
      ON_BATTERY=true
    else
      DIM_TIMEOUT=0
      LOCK_TIMEOUT=${toString systemSettings.swayIdleLockTimeout}
      MONITOR_OFF_TIMEOUT=${toString systemSettings.swayIdleMonitorOffTimeout}
      SUSPEND_TIMEOUT=${toString systemSettings.swayIdleSuspendTimeout}
      ON_BATTERY=false
    fi

    ARGS=(-w)
    # Dim screen on battery before lock (restore on activity)
    if [ "$ON_BATTERY" = true ] && [ "$DIM_TIMEOUT" -gt 0 ]; then
      ARGS+=(timeout "$DIM_TIMEOUT" '${sway-idle-dim}')
      ARGS+=(resume '${sway-idle-undim}')
    fi
    ARGS+=(timeout "$LOCK_TIMEOUT" '${swaylock-with-grace}/bin/swaylock-with-grace')
    ${lib.optionalString (systemSettings.swayIdleDisableMonitorPowerOff != true) ''
    ARGS+=(timeout "$MONITOR_OFF_TIMEOUT" '${sway-idle-monitor-off}')
    ARGS+=(resume '${sway-resume-monitors}')
    ''}
    ARGS+=(timeout "$SUSPEND_TIMEOUT" '${sway-idle-suspend}')
    ARGS+=(before-sleep '${sway-idle-before-sleep}')
    ARGS+=(after-resume '${sway-resume-monitors}')

    exec ${pkgs.swayidle}/bin/swayidle "''${ARGS[@]}"
  '';

  # Power state monitor: restarts swayidle when AC/battery state changes
  sway-power-monitor = pkgs.writeShellScript "sway-power-monitor" ''
    ${lib.optionalString (systemSettings.swayBatteryReduceEffects or false) ''
    # Set initial SwayFX effects based on current power state
    INIT_BAT=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Full")
    if [ "$INIT_BAT" = "Discharging" ]; then
      ${pkgs.sway}/bin/swaymsg blur disable 2>/dev/null || true
      ${pkgs.sway}/bin/swaymsg shadows disable 2>/dev/null || true
      ${pkgs.sway}/bin/swaymsg default_dim_inactive 0.0 2>/dev/null || true
    fi
    ''}
    LAST_STATE=""
    while true; do
      BAT_STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Full")
      if [ "$BAT_STATUS" = "Discharging" ]; then
        CURRENT="battery"
      else
        CURRENT="ac"
      fi
      if [ -n "$LAST_STATE" ] && [ "$CURRENT" != "$LAST_STATE" ]; then
        ${pkgs.systemd}/bin/systemctl --user restart swayidle.service
        if [ "$CURRENT" = "ac" ]; then
          # Restore brightness in case screen was dimmed on battery
          ${pkgs.brightnessctl}/bin/brightnessctl -r 2>/dev/null || true
          ${pkgs.libnotify}/bin/notify-send -t 3000 "Power" "AC connected - extended idle timeouts" -h string:x-canonical-private-synchronous:power-state
        else
          ${pkgs.libnotify}/bin/notify-send -t 3000 "Power" "On battery - shorter idle timeouts" -h string:x-canonical-private-synchronous:power-state
        fi
        ${lib.optionalString (systemSettings.swayBatteryReduceEffects or false) ''
        # Toggle SwayFX effects based on power state
        if [ "$CURRENT" = "ac" ]; then
          ${pkgs.sway}/bin/swaymsg blur enable 2>/dev/null || true
          ${pkgs.sway}/bin/swaymsg shadows enable 2>/dev/null || true
          ${pkgs.sway}/bin/swaymsg default_dim_inactive 0.1 2>/dev/null || true
        else
          ${pkgs.sway}/bin/swaymsg blur disable 2>/dev/null || true
          ${pkgs.sway}/bin/swaymsg shadows disable 2>/dev/null || true
          ${pkgs.sway}/bin/swaymsg default_dim_inactive 0.0 2>/dev/null || true
        fi
        ''}
      fi
      LAST_STATE="$CURRENT"
      sleep 5
    done
  '';

  # Keyboard layout switching script
  keyboard-layout-switch = pkgs.writeShellApplication {
    name = "keyboard-layout-switch";
    runtimeInputs = with pkgs; [
      sway
      jq
      libnotify
    ];
    text = ''
      #!/bin/bash
      set -euo pipefail

      # Switch to next layout
      swaymsg input type:keyboard xkb_switch_layout next

      # Wait for state update
      sleep 0.1

      # Query current layout name
      CURRENT_LAYOUT=$(swaymsg -t get_inputs --raw | \
        jq -r '.[] | select(.type == "keyboard") | .xkb_active_layout_name' | \
        head -n1)

      # Send notification
      notify-send -t 2000 "Keyboard Layout" "$CURRENT_LAYOUT"
    '';
  };
in
{
  # Set XDG_MENU_PREFIX for KDE applications (Okular, Ark, etc. menu database)
  # Using home.sessionVariables (safe method that doesn't break DBus/networking)
  home.sessionVariables = {
    XDG_MENU_PREFIX = "plasma-";
  };

  # CRITICAL: Idle daemon with swaylock-effects
  # Timeouts are ABSOLUTE from last user activity, not incremental
  # When power-aware mode is enabled (laptops), this is disabled and replaced by custom systemd services
  services.swayidle = {
    enable = !(systemSettings.swayIdlePowerAwareEnable or false);
    timeouts =
      [
        {
          timeout = systemSettings.swayIdleLockTimeout; # Lock screen (with 4-second grace period)
          command = "${swaylock-with-grace}/bin/swaylock-with-grace";
        }
      ]
      ++ lib.optionals (systemSettings.swayIdleDisableMonitorPowerOff != true) [
        {
          timeout = systemSettings.swayIdleMonitorOffTimeout; # Turn off displays
          command = "${pkgs.sway}/bin/swaymsg 'output * power off'";
          # Restore outputs AND wallpaper when monitors wake from power-off
          resumeCommand = "${sway-resume-monitors}";
        }
      ]
      ++ [
        {
          timeout = systemSettings.swayIdleSuspendTimeout; # Suspend system
          command = "${pkgs.systemd}/bin/systemctl suspend";
        }
      ];
    events = {
      # Use --color instead of --screenshots for before-sleep: monitors may be powered off,
      # causing screencopy to fail and leaving the session unlocked after resume.
      before-sleep = "${pkgs.swaylock-effects}/bin/swaylock --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033 --font 'JetBrainsMono Nerd Font Mono' --color 000000";
      # Ensure monitors are powered on after resume (safety net — timeout resumeCommand may not fire)
      after-resume = "${sway-resume-monitors}";
    };
  };

  # Power-aware swayidle: custom systemd services (replaces HM swayidle when enabled)
  # Detects AC/battery state and uses different idle timeouts accordingly
  systemd.user.services.swayidle = lib.mkIf (systemSettings.swayIdlePowerAwareEnable or false) {
    Unit = {
      Description = "Power-aware idle manager for Wayland";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${sway-power-swayidle}";
      Restart = "on-failure";
      RestartSec = "2";
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  # Monitors power state changes and restarts swayidle with correct timeouts
  systemd.user.services.swayidle-power-monitor = lib.mkIf (systemSettings.swayIdlePowerAwareEnable or false) {
    Unit = {
      Description = "Monitor AC/battery state and restart swayidle on change";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${sway-power-monitor}";
      Restart = "on-failure";
      RestartSec = "5";
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
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
    extraSessionCommands = lib.mkMerge [
      # Always set CUPS_SERVER for printer access in Sway
      # CRITICAL: Add OpenGL driver paths to XDG_DATA_DIRS for Vulkan ICD discovery
      # Without this, Lutris/Wine can't find Vulkan drivers when launched from Rofi/D-Bus
      # VK_ICD_FILENAMES explicitly points to RADV drivers (fixes Lutris "Found no drivers" error)
      ''
        export CUPS_SERVER=localhost:631
        export XDG_DATA_DIRS="/run/opengl-driver/share:/run/opengl-driver-32/share:$XDG_DATA_DIRS"
        export VK_ICD_FILENAMES="/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json:/run/opengl-driver-32/share/vulkan/icd.d/radeon_icd.i686.json"
        export NODEVICE_SELECT="1"
        export BOTTLES_IGNORE_SANDBOX="1"
      ''
      # Conditionally set theme variables if Stylix is enabled
      (lib.mkIf (systemSettings.stylixEnable == true) ''
        # Inject variables that we force-unset globally to prevent Plasma 6 leakage
        export QT_QPA_PLATFORMTHEME=qt6ct
        export GTK_THEME=${if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita"}
        export GTK_APPLICATION_PREFER_DARK_THEME=1
        # Fix for Java apps if needed
        export _JAVA_AWT_WM_NONREPARENTING=1
      '')
    ];

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

          # Keyboard layout switching (English/Spanish/Polish)
          "${hyper}+Return" = "exec ${keyboard-layout-switch}/bin/keyboard-layout-switch";

          # Manual startup apps launcher
          "${hyper}+Shift+Return" =
            "exec ${config.home.homeDirectory}/.nix-profile/bin/desk-startup-apps-launcher";

          # Rofi Universal Launcher
          # Use rofi's configured combi-modi (includes apps/run/window/filebrowser/calc/emoji/power)
          "${hyper}+space" = "exec rofi -show combi -show-icons";
          # Note: Removed "${hyper}+d" to avoid conflict with application bindings
          # Use "${hyper}+space" for rofi launcher

          # GNOME Calculator (replaces rofi calculator)
          "${hyper}+x" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh org.gnome.Calculator gnome-calculator";

          # Rofi Emoji Picker
          "${hyper}+period" = "exec rofi -show emoji";

          # Rofi File Browser (separate from combi mode)
          "${hyper}+slash" = "exec rofi -show filebrowser";

          # Window Overview (Mission Control-like)
          # Using Rofi in window mode with grid layout for stable workspace overview
          # Grid layout: 3 columns, large icons (48px), vertical orientation
          # Rofi inherits Stylix colors automatically via existing rofi.nix configuration
          # Default: grouped app -> window picker (less noisy when apps have multiple windows)
          "${hyper}+Tab" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/window-overview-grouped.sh";

          # Workspace toggle (back and forth)
          "Mod4+Tab" = "workspace back_and_forth";

          # Lock screen (Meta/Super + l)
          "Mod4+l" =
            "exec ${pkgs.swaylock-effects}/bin/swaylock --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033 --font 'JetBrainsMono Nerd Font Mono'";

          # Media keys (volume)
          # Uses swayosd-client to both adjust volume and show an on-screen display.
          "XF86AudioLowerVolume" = "exec ${pkgs.swayosd}/bin/swayosd-client --output-volume lower";
          "XF86AudioRaiseVolume" = "exec ${pkgs.swayosd}/bin/swayosd-client --output-volume raise";
          "XF86AudioMute" = "exec ${pkgs.swayosd}/bin/swayosd-client --output-volume mute-toggle";
          "XF86AudioMicMute" = "exec ${pkgs.swayosd}/bin/swayosd-client --input-volume mute-toggle";
          # Keyd virtual keyboard emits a quick mute down/up; bind the combo to avoid clobbering real mute.
          "${hyper}+XF86AudioMute" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/idle-inhibit-toggle.sh";

          # Media keys (brightness)
          "XF86MonBrightnessDown" = "exec ${pkgs.swayosd}/bin/swayosd-client --brightness lower";
          "XF86MonBrightnessUp" = "exec ${pkgs.swayosd}/bin/swayosd-client --brightness raise";

          # Media keys (player control via MPRIS)
          "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
          "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
          "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
          "XF86AudioStop" = "exec ${pkgs.playerctl}/bin/playerctl stop";

          # Screenshot workflow
          "${hyper}+Shift+x" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh full";
          "${hyper}+Shift+c" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh area";
          "Print" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh area";
          "Shift+Print" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh clipboard";
          # Copy last screenshot path to clipboard (for pasting into Claude Code)
          "Ctrl+Alt+c" = "exec sh -c 'cat /tmp/last-screenshot-path 2>/dev/null | ${pkgs.wl-clipboard}/bin/wl-copy --type text/plain'";

          # Application keybindings (using app-toggle.sh script)
          # Note: Using different keys to avoid conflicts with window management bindings
          # Format: app-toggle.sh <app_id|class> <launch_command...>
          "${hyper}+T" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh kitty kitty";
          "${hyper}+R" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh Alacritty alacritty";
          "${hyper}+L" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh org.telegram.desktop Telegram";
          "${hyper}+e" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh kitty-ranger 'kitty --class kitty-ranger ranger'";
          "${hyper}+U" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh io.dbeaver.DBeaverCommunity dbeaver";
          "${hyper}+A" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh .blueman-manager-wrapped blueman-manager";
          "${hyper}+D" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh obsidian obsidian --no-sandbox --ozone-platform=wayland --ozone-platform-hint=auto --enable-features=UseOzonePlatform,WaylandWindowDecorations";
          "${hyper}+V" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh vivaldi-stable vivaldi";
          "${hyper}+G" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh chromium-browser chromium";
          "${hyper}+Y" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh spotify spotify --enable-features=UseOzonePlatform --ozone-platform=wayland";
          "${hyper}+N" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh nwg-look nwg-look";
          "${hyper}+P" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh Bitwarden bitwarden";
          "${hyper}+C" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh cursor cursor --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform-hint=auto --unity-launch";
          # Mission Center (app_id is io.missioncenter.MissionCenter, binary is missioncenter)
          "${hyper}+m" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh io.missioncenter.MissionCenter missioncenter";
          "${hyper}+B" =
            "exec env ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh com.usebottles.bottles bottles";
          # Control Panel (NixOS Infrastructure Management) - hyper+S
          "${hyper}+s" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh control-panel control-panel";
          # Pavucontrol (Audio mixer) - hyper+Shift+a (A for Audio)
          "${hyper}+Shift+a" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh org.pulseaudio.pavucontrol pavucontrol";
          # Waypaper (wallpaper GUI) - Hyper+Shift+b (b for background)
          "${hyper}+Shift+b" = lib.mkIf (systemSettings.waypaperEnable or false) "exec waypaper";

          # Workspace navigation with auto-creation and wrapping (Option B)
          # Hyper+Q/W: Navigate between workspaces in current group, wrap at boundaries
          # Hyper+Shift+Q/W: Move window to workspace in current group, wrap at boundaries
          "${hyper}+q" = "exec ${config.home.homeDirectory}/.config/sway/scripts/workspace-nav-prev.sh";
          "${hyper}+w" = "exec ${config.home.homeDirectory}/.config/sway/scripts/workspace-nav-next.sh";
          "${hyper}+Shift+q" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/workspace-move-prev.sh";
          "${hyper}+Shift+w" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/workspace-move-next.sh";

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
          # Note: "${hyper}+s" is used for control-panel (see application bindings above)
          # Note: "${hyper}+w" is used for workspace next_on_output (see Workspace navigation above)
          # Note: Removed "${hyper}+e" layout toggle (now used for ranger file manager)
          # Note: Removed "${hyper}+a" to avoid conflict with "${hyper}+A" (blueman-manager)
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
          "${hyper}+Shift+v" =
            "exec sh -c '${pkgs.cliphist}/bin/cliphist list | ${pkgs.rofi}/bin/rofi -dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy'";

          # Power menu
          "${hyper}+Shift+BackSpace" = "exec rofi -show power -show-icons";

          # Monitor management GUIs (when enabled)
          # nwg-displays: Visual monitor layout, position, scale, resolution
          "${hyper}+Shift+d" = "exec nwg-displays";
          # workspace-groups-gui: Assign swaysome workspace groups to monitors
          "${hyper}+grave" = "exec workspace-groups-gui";

          # Trayscale: Tailscale GUI manager
          "${hyper}+Shift+t" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh dev.deedles.Trayscale trayscale";

          # Toggle SwayFX default bar (swaybar) - disabled by default, can be toggled manually
          "${hyper}+Shift+Home" = "exec ${config.home.homeDirectory}/.config/sway/scripts/swaybar-toggle.sh";

          # Dolphin file manager (KDE, tabs restore)
          "${hyper}+Shift+e" =
            "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh org.kde.dolphin dolphin";

          # Hide window (move to scratchpad) - Previously: hyper+Shift+e
          # Commented out to avoid conflict with Dolphin keybinding above
          # To manually move windows to scratchpad, use: hyper+Shift+minus
          # "${hyper}+Shift+e" = "move scratchpad";

          # Exit Sway
          "${hyper}+Shift+End" =
            "exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit Sway? This will end your Wayland session.' -b 'Yes, exit Sway' 'swaymsg exit'";
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
      startup = [
        # CRITICAL: Import environment variables EARLY, before any DBus-activated services start
        # xdg-desktop-portal is DBus-activated when apps request screen sharing
        # If these variables aren't in systemd BEFORE activation, portal fails and no picker appears
        # XDG_DATA_DIRS and VK_ICD_FILENAMES are critical for Vulkan ICD discovery (Lutris, Wine, games)
        {
          command = "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP SWAYSOCK XDG_DATA_DIRS VK_ICD_FILENAMES NODEVICE_SELECT BOTTLES_IGNORE_SANDBOX";
          always = true;
        }
        {
          command = "${pkgs.systemd}/bin/systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP SWAYSOCK XDG_DATA_DIRS VK_ICD_FILENAMES NODEVICE_SELECT BOTTLES_IGNORE_SANDBOX";
          always = true;
        }
        # Startup logging for workspace assignment debugging
        {
          command = "/home/akunito/.dotfiles/user/wm/sway/scripts/workspace-startup-logger.sh";
          always = false; # Only run on initial startup, not on config reload
        }
        # DESK-only: focus the primary output and warp cursor onto it early
        {
          command = "${sway-focus-primary-output}/bin/sway-focus-primary-output";
          always = false; # Only run on initial startup, not on config reload
        }
        # Rebuild KDE menu database for KDE apps (must run after XDG_MENU_PREFIX is set via home.sessionVariables)
        {
          command = "${rebuild-ksycoca}/bin/rebuild-ksycoca";
          always = false; # Run only on initial login, not on reload
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
        # Portal env must exist before portals restart during fast relog; it is only consumed by portal units via drop-in.
        {
          command = "${write-sway-portal-env}/bin/write-sway-portal-env";
          always = true;
        }
        # Start the Sway session target; services are ordered and restarted by systemd
        # CRITICAL: always = false prevents target restart on config reload (fixes duplicate waybar)
        {
          command = "${sway-session-start}/bin/sway-session-start";
          always = false;
        }
        # Refresh session env on reload (safe: only updates env file, no target restart)
        {
          command = "${sway-session-refresh-env}/bin/sway-session-refresh-env";
          always = true;
        }
      ]
      ++ lib.optionals (systemSettings.enableSwayForDESK == true) [
        # DESK-only: ensure monitor configurations are reapplied BEFORE workspace assignment on reload
        # This prevents workspaces from being assigned to monitors with wrong/default configurations
        {
          command = "/run/current-system/sw/bin/systemctl --user restart kanshi.service";
          always = true; # Run on every config reload to fix monitor settings first
        }
        # Note: Workspace-to-output assignments are now handled declaratively in extraConfig
        # swaysome init 1 is handled by kanshi profiles
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
          {
            criteria = {
              app_id = "rofi";
            };
            command = "floating enable";
          }
          {
            criteria = {
              app_id = "kitty";
            };
            command = "floating enable";
          }
          {
            criteria = {
              app_id = "kitty-ranger";
            };
            command = "floating enable";
          }
          {
            criteria = {
              app_id = "SwayBG+";
            };
            command = "floating enable";
          }
          {
            criteria = {
              title = "SwayBG+";
            };
            command = "floating enable";
          }
          {
            criteria = {
              app_id = "org.telegram.desktop";
            };
            command = "floating enable";
          }
          {
            criteria = {
              app_id = "telegram-desktop";
            };
            command = "floating enable";
          }
          {
            criteria = {
              app_id = "bitwarden";
            };
            command = "floating enable";
          }
          {
            criteria = {
              app_id = "bitwarden-desktop";
            };
            command = "floating enable";
          }
          {
            criteria = {
              app_id = "Bitwarden";
            };
            command = "floating enable";
          }
          {
            criteria = {
              app_id = "com.usebottles.bottles";
            };
            command = "floating enable";
          }
          {
            criteria = {
              app_id = "swayfx-settings";
            };
            command = "floating enable";
          }
          {
            criteria = {
              app_id = "io.missioncenter.MissionCenter";
            };
            command = "floating enable, sticky enable, resize set 800 600";
          }
          # LACT (Linux AMDGPU Controller): often XWayland; keep explicit app_id match for Wayland variants too.
          {
            criteria = {
              app_id = "lact";
            };
            command = "floating enable, sticky enable";
          }
          {
            criteria = {
              title = "LACT";
            };
            command = "floating enable, sticky enable";
          }

          # KDE Discover: floating + sticky (Wayland app_id + common fallbacks)
          {
            criteria = {
              app_id = "org.kde.discover";
            };
            command = "floating enable, sticky enable";
          }
          {
            criteria = {
              app_id = "plasma-discover";
            };
            command = "floating enable, sticky enable";
          }
          {
            criteria = {
              app_id = "discover";
            };
            command = "floating enable, sticky enable";
          }
          {
            criteria = {
              title = "Discover";
            };
            command = "floating enable, sticky enable";
          }

          # Pavucontrol: floating + sticky (correct app_id)
          {
            criteria = {
              app_id = "org.pulseaudio.pavucontrol";
            };
            command = "floating enable, sticky enable";
          }

          # Dolphin: floating + sticky (KDE file manager)
          {
            criteria = {
              app_id = "org.kde.dolphin";
            };
            command = "floating enable, sticky enable";
          }

          # Blueman-manager: floating + sticky (Bluetooth Manager - NixOS wrapped)
          {
            criteria = {
              app_id = ".blueman-manager-wrapped";
            };
            command = "floating enable, sticky enable";
          }

          # GNOME Calculator: floating + sticky
          {
            criteria = {
              app_id = "org.gnome.Calculator";
            };
            command = "floating enable, sticky enable";
          }

          # nwg-displays: Monitor management GUI - floating + sticky
          {
            criteria = {
              app_id = "nwg-displays";
            };
            command = "floating enable, sticky enable";
          }

          # Trayscale: Tailscale GUI - floating + sticky
          {
            criteria = {
              app_id = "dev.deedles.Trayscale";
            };
            command = "floating enable, sticky enable";
          }

          # Waypaper: Wallpaper GUI - floating, centered, sized
          {
            criteria = {
              app_id = "waypaper";
            };
            command = "floating enable, resize set 1200 800";
          }

          # XWayland apps (use class)
          {
            criteria = {
              class = "SwayBG+";
            };
            command = "floating enable";
          }
          {
            criteria = {
              class = "Spotify";
            };
            command = "floating enable";
          }
          {
            criteria = {
              class = "lact";
            };
            command = "floating enable, sticky enable";
          }
          {
            criteria = {
              class = "LACT";
            };
            command = "floating enable, sticky enable";
          }
          {
            criteria = {
              class = "discover";
            };
            command = "floating enable, sticky enable";
          }
          {
            criteria = {
              class = "Discover";
            };
            command = "floating enable, sticky enable";
          }
          {
            criteria = {
              class = "plasma-discover";
            };
            command = "floating enable, sticky enable";
          }


          # Sticky windows - visible on all workspaces of their monitor
          {
            criteria = {
              app_id = "kitty";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "kitty-ranger";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "Alacritty";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "SwayBG+";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              title = "SwayBG+";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "org.telegram.desktop";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "telegram-desktop";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "bitwarden";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "bitwarden-desktop";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "Bitwarden";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              class = "SwayBG+";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              class = "Spotify";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "io.missioncenter.MissionCenter";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "lact";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              title = "LACT";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              class = "lact";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              class = "LACT";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "org.kde.discover";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "plasma-discover";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "discover";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              title = "Discover";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              class = "discover";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              class = "Discover";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              class = "plasma-discover";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "org.pulseaudio.pavucontrol";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "org.kde.kcalc";
            };
            command = "sticky enable";
          }
          {
            criteria = {
              app_id = "kcalc";
            };
            command = "sticky enable";
          }
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

      # Include user-managed output configuration (from nwg-displays)
      # These files are optional - Sway continues if they don't exist
      include ~/.config/sway/outputs
      include ~/.config/sway/workspaces

      # Output layout is managed dynamically by kanshi (official wlroots/Sway output profile manager).
      # This avoids phantom pointer/workspace regions on monitors that are usually OFF.
      #
      # IMPORTANT: Do NOT include swaybgplus output geometry here; it can re-enable "usually OFF" outputs.

      # Workspace placement is managed by swaysome (per-output groups) and kanshi (outputs).
      # Do not hardcode connector-based workspace->output mappings here (anti-drift).

      # Workspace configuration
      workspace_auto_back_and_forth yes

      # Workspace-to-Output assignments (hardware ID-based, declarative)
      # Sway supports hardware IDs directly - no need for connector names or scripts
      ${lib.concatStringsSep "\n" (
        let
          samsung = "Samsung Electric Company Odyssey G70NC H1AK500000";
          nsl = "NSL RGB-27QHDS    Unknown";
          philips = "Philips Consumer Electronics Company PHILIPS FTV 0x01010101";
          bnq = "BNQ ZOWIE XL LCD 7CK03588SL0";
        in
        (map (i: "workspace ${toString i} output \"${samsung}\"") (lib.range 11 20))
        ++ (map (i: "workspace ${toString i} output \"${nsl}\"") (lib.range 21 30))
        ++ (map (i: "workspace ${toString i} output \"${philips}\"") (lib.range 31 40))
        ++ (map (i: "workspace ${toString i} output \"${bnq}\"") (lib.range 41 50))
      )}

      # DESK startup apps - assign to specific workspaces
      # Using 'assign' instead of 'for_window' prevents flickering on wrong workspace
      # Vivaldi - using pkgs version (keeping flatpak assignments for compatibility)
      assign [app_id="Vivaldi-flatpak"] workspace number 11
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

      # Keyboard input configuration for multi-language support (English/Spanish/Polish)
      input type:keyboard {
        xkb_layout "${xkbLayouts}"
        xkb_variant "${xkbVariants}"
        xkb_numlock enabled
      }

      # Touchpad configuration
      input "type:touchpad" {
        dwt enabled
        tap enabled
        natural_scroll enabled
        middle_emulation enabled
        accel_profile adaptive
        pointer_accel 0.5
      }

      # Additional SwayFX configuration
      # Floating window rules (duplicate from config.window.commands for reliability)
      for_window [app_id="kitty"] floating enable
      for_window [app_id="kitty-ranger"] floating enable, sticky enable
      for_window [app_id="org.telegram.desktop"] floating enable
      for_window [app_id="telegram-desktop"] floating enable
      for_window [app_id="bitwarden"] floating enable
      for_window [app_id="bitwarden-desktop"] floating enable
      for_window [app_id="Bitwarden"] floating enable
      for_window [app_id="com.usebottles.bottles"] floating enable
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
      # Pavucontrol: floating + sticky (correct app_id)
      for_window [app_id="org.pulseaudio.pavucontrol"] floating enable, sticky enable
      # Dolphin: floating + sticky (KDE file manager)
      for_window [app_id="org.kde.dolphin"] floating enable, sticky enable
      # GNOME Calculator: floating + sticky
      for_window [app_id="org.gnome.Calculator"] floating enable, sticky enable
      # nwg-displays: Monitor management GUI - floating + sticky
      for_window [app_id="nwg-displays"] floating enable, sticky enable
      # Trayscale: Tailscale GUI - floating + sticky
      for_window [app_id="dev.deedles.Trayscale"] floating enable, sticky enable
      # Waypaper: Wallpaper GUI - floating, centered, sized
      for_window [app_id="waypaper"] floating enable, resize set 1200 800
      for_window [app_id="nm-connection-editor"] floating enable
      for_window [app_id=".blueman-manager-wrapped"] floating enable, sticky enable
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

      # Gamescope: always fullscreen, inhibit idle, no border
      for_window [app_id="gamescope"] fullscreen enable, inhibit_idle fullscreen
      no_focus [app_id="mako"]
      no_focus [app_id="swaync"]
      no_focus [app_id="dunst"]

      # Steam/Proton games: inhibit idle, fullscreen (XWayland class="steam_app_*")
      for_window [class="^steam_app_"] inhibit_idle focus, fullscreen enable
      # ModOrganizer2 (Wildlander/Wabbajack modlists): float so it's usable
      for_window [class="ModOrganizer"] floating enable
      for_window [title="Mod Organizer"] floating enable

      # Mission Center - Floating, Sticky, Resized
      for_window [app_id="io.missioncenter.MissionCenter"] floating enable, sticky enable, resize set 800 600

      # Control Panel (NixOS Infrastructure Management) - Floating, Sticky
      for_window [app_id="control-panel"] floating enable, sticky enable
      for_window [title="NixOS Control Panel"] floating enable, sticky enable

      # KWallet - Force to Primary Monitor, Workspace 1 (Floating, Sticky)
      # Multiple rules to catch all KWallet variants (kwalletd5, kwalletd6, kwallet-query, etc.)
      # Note: Sway doesn't support regex in for_window criteria, so we use explicit string matching
      # Note: Use Nix string interpolation for PRIMARY_OUTPUT variable
      # CRITICAL: Primary app_id is org.kde.ksecretd (captured from actual KWallet window)
      # CRITICAL: Actual window name is "KDE Wallet Service" (captured from actual window)

      # App ID-based matching (Wayland native) - PRIMARY
      for_window [app_id="org.kde.ksecretd"] move to output "${
        if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"
      }", move to workspace number 1, floating enable, sticky enable
      # Fallback variants (in case different KWallet windows use these)
      for_window [app_id="org.kde.kwalletd5"] move to output "${
        if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"
      }", move to workspace number 1, floating enable, sticky enable
      for_window [app_id="org.kde.kwalletd6"] move to output "${
        if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"
      }", move to workspace number 1, floating enable, sticky enable
      for_window [app_id="kwallet-query"] move to output "${
        if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"
      }", move to workspace number 1, floating enable, sticky enable

      # Title-based matching (fallback) - PRIMARY
      for_window [title="KDE Wallet Service"] move to output "${
        if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"
      }", move to workspace number 1, floating enable, sticky enable
      for_window [title="KWallet"] move to output "${
        if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"
      }", move to workspace number 1, floating enable, sticky enable
      for_window [title="kwallet"] move to output "${
        if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"
      }", move to workspace number 1, floating enable, sticky enable

      # Class-based matching (X11/XWayland) - fallback
      for_window [class="kwalletmanager5"] move to output "${
        if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"
      }", move to workspace number 1, floating enable, sticky enable
      for_window [class="kwalletmanager6"] move to output "${
        if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"
      }", move to workspace number 1, floating enable, sticky enable
      for_window [class="KWalletManager"] move to output "${
        if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"
      }", move to workspace number 1, floating enable, sticky enable

      # Focus follows mouse
      focus_follows_mouse yes

      # Mouse warping
      mouse_warping output
    ''
    + lib.optionalString (systemSettings.swaySmartLidEnable or false) ''

      # Smart lid handler: suspend if no external monitor, disable internal display if docked
      bindswitch --reload --locked lid:on exec ${sway-lid-handler}
      bindswitch --reload --locked lid:off exec ${pkgs.sway}/bin/swaymsg output eDP-1 enable
    '';
  };

  # Gamemode hooks: disable swayidle when gamemode is active
  xdg.configFile."gamemode.ini" = lib.mkIf (systemSettings.gamemodeEnable == true) {
    text = ''
      [custom]
      start=${pkgs.systemd}/bin/systemctl --user stop swayidle.service
      end=${pkgs.systemd}/bin/systemctl --user start swayidle.service
    '';
  };
}
