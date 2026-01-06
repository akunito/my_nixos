{ config, pkgs, lib, userSettings, systemSettings, ... }:

let
  # Hyper key combination (Super+Ctrl+Alt)
  hyper = "Mod4+Control+Mod1";
  
  # Daemon definitions - shared by all generated scripts (DRY principle)
  daemons = [
    {
      name = "waybar";
      command = "${pkgs.waybar}/bin/waybar";
      pattern = "waybar";
      match_type = "exact";  # Use pgrep -x for exact match (safer)
      reload = "${pkgs.procps}/bin/pkill -SIGUSR2 waybar";  # Hot reload CSS/config
      requires_sway = true;
    }
    {
      name = "nwg-dock";
      command = "${pkgs.nwg-dock}/bin/nwg-dock -d -l bottom -p bottom -i 48 -w 5 -mb 10 -hd 0 -c \"rofi -show drun\"";
      pattern = "nwg-dock";
      match_type = "exact";  # Use pgrep -x for exact match
      reload = "";  # No reload support
      requires_sway = true;
    }
    {
      name = "swaync";
      command = "${pkgs.swaynotificationcenter}/bin/swaync";
      pattern = "swaync";
      match_type = "exact";  # Use pgrep -x for exact match
      reload = "${pkgs.swaynotificationcenter}/bin/swaync-client -R";
      requires_sway = true;
    }
    {
      name = "nm-applet";
      command = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
      pattern = "nm-applet";
      match_type = "exact";  # Use pgrep -x for exact match
      reload = "";
      requires_sway = false;
    }
    {
      name = "blueman-applet";
      command = "${pkgs.blueman}/bin/blueman-applet";
      pattern = "blueman-applet";
      match_type = "exact";  # Use pgrep -x for exact match
      reload = "";
      requires_sway = false;
    }
    {
      name = "cliphist";
      command = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
      pattern = "wl-paste.*cliphist";  # Regex pattern for full command match
      match_type = "full";  # Use pgrep -f for full command match (needed for complex commands)
      reload = "";
      requires_sway = true;
    }
    {
      name = "kwalletd6";
      command = "${pkgs.kdePackages.kwallet}/bin/kwalletd6";
      pattern = "kwalletd6";
      match_type = "exact";  # Use pgrep -x for exact match
      reload = "";
      requires_sway = false;
    }
    {
      name = "libinput-gestures";
      command = "${pkgs.libinput-gestures}/bin/libinput-gestures";
      pattern = "libinput-gestures";
      match_type = "exact";  # Use pgrep -x for exact match
      reload = "";
      requires_sway = false;
    }
  ] ++ lib.optional (systemSettings.stylixEnable == true) {
    name = "swaybg";
    command = "${pkgs.swaybg}/bin/swaybg -i ${config.stylix.image} -m fill";
    pattern = "swaybg";
    match_type = "exact";  # Use pgrep -x for exact match
    reload = "";
    requires_sway = true;
  };
  
  # Generate daemon-manager script
  daemon-manager = pkgs.writeShellScriptBin "daemon-manager" ''
    #!/bin/sh
    # Unified daemon manager for SwayFX
    # Usage: daemon-manager [PATTERN] [MATCH_TYPE] [COMMAND] [RELOAD_CMD] [REQUIRES_SWAY]
    
    PATTERN="$1"
    MATCH_TYPE="$2"
    COMMAND="$3"
    RELOAD_CMD="$4"
    REQUIRES_SWAY="$5"
    
    # Determine pgrep/pkill flags based on match_type
    if [ "$MATCH_TYPE" = "exact" ]; then
      PGREP_FLAG="-x"
      PKILL_FLAG="-x"
    else
      PGREP_FLAG="-f"
      PKILL_FLAG="-f"
    fi
    
    # Logging function using systemd-cat
    # systemd-cat is a standard system utility available in PATH
    log() {
      echo "$1" | systemd-cat -t sway-daemon-mgr -p "$2"
    }
    
    # Check if process is running
    if ${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" > /dev/null 2>&1; then
      if [ -n "$RELOAD_CMD" ]; then
        # Process running and supports reload
        eval "$RELOAD_CMD"
        log "Reload signal sent to daemon: $PATTERN" "info"
        exit 0
      else
        # Process running but no reload support
        log "Daemon already running: $PATTERN" "info"
        exit 0
      fi
    fi
    
    # Process not running - start it
    if [ "$REQUIRES_SWAY" = "true" ]; then
      # Wait for SwayFX IPC to be ready (max 10 seconds)
      SWAY_READY=false
      for i in $(seq 1 10); do
        if ${pkgs.swayfx}/bin/swaymsg -t get_outputs > /dev/null 2>&1; then
          SWAY_READY=true
          break
        fi
        sleep 1
      done
      if [ "$SWAY_READY" = "false" ]; then
        log "WARNING: SwayFX not ready after 10 seconds, starting daemon anyway: $PATTERN" "warning"
      fi
    fi
    
    # Kill any stale processes
    ${pkgs.procps}/bin/pkill $PKILL_FLAG "$PATTERN" 2>/dev/null
    sleep 0.5
    
    # Start daemon with systemd logging
    nohup sh -c "$COMMAND" 2>&1 | systemd-cat -t "sway-daemon-''${PATTERN}" &
    DAEMON_PID=$!
    
    # Verify it started
    sleep 1
    if ${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" > /dev/null 2>&1; then
      log "Daemon started successfully: $PATTERN (PID: $DAEMON_PID)" "info"
      exit 0
    else
      log "ERROR: Failed to start daemon: $PATTERN" "err"
      exit 1
    fi
  '';
  
  # Generate startup script (iterates daemon list)
  start-sway-daemons = pkgs.writeShellScriptBin "start-sway-daemons" ''
    #!/bin/sh
    # Auto-generated script - starts all SwayFX daemons
    # Do not edit manually - generated from daemon list in default.nix
    
    ${lib.concatMapStringsSep "\n" (daemon: ''
      ${daemon-manager}/bin/daemon-manager \
        ${lib.strings.escapeShellArg daemon.pattern} \
        ${lib.strings.escapeShellArg daemon.match_type} \
        ${lib.strings.escapeShellArg daemon.command} \
        ${lib.strings.escapeShellArg (if daemon.reload != "" then daemon.reload else "")} \
        ${if daemon.requires_sway then "true" else "false"} &
    '') daemons}
    wait
  '';
  
  # Generate sanity check script (uses same daemon list)
  daemon-sanity-check = pkgs.writeShellScriptBin "daemon-sanity-check" ''
    #!/bin/sh
    # Auto-generated script - checks status of all SwayFX daemons
    # Do not edit manually - generated from daemon list in default.nix
    
    FIX_MODE=false
    if [ "$1" = "--fix" ]; then
      FIX_MODE=true
    fi
    
    ALL_RUNNING=true
    ${lib.concatMapStringsSep "\n" (daemon: ''
      MATCH_TYPE=${lib.strings.escapeShellArg daemon.match_type}
      if [ "$MATCH_TYPE" = "exact" ]; then
        PGREP_FLAG="-x"
      else
        PGREP_FLAG="-f"
      fi
      
      if ${pkgs.procps}/bin/pgrep $PGREP_FLAG ${lib.strings.escapeShellArg daemon.pattern} > /dev/null 2>&1; then
        echo "✓ ${daemon.name} is running" | systemd-cat -t sway-daemon-check -p info
      else
        echo "✗ ${daemon.name} is NOT running" | systemd-cat -t sway-daemon-check -p warning
        ALL_RUNNING=false
        if [ "$FIX_MODE" = "true" ]; then
          ${daemon-manager}/bin/daemon-manager \
            ${lib.strings.escapeShellArg daemon.pattern} \
            ${lib.strings.escapeShellArg daemon.match_type} \
            ${lib.strings.escapeShellArg daemon.command} \
            ${lib.strings.escapeShellArg (if daemon.reload != "" then daemon.reload else "")} \
            ${if daemon.requires_sway then "true" else "false"}
        fi
      fi
    '') daemons}
    
    if [ "$ALL_RUNNING" = "true" ]; then
      exit 0
    else
      exit 1
    fi
  '';
in {

  imports = [
    ../../app/terminal/alacritty.nix
    ../../app/terminal/kitty.nix
    ../../app/terminal/tmux.nix
    ../../app/gaming/mangohud.nix
    ../../app/ai/aichat.nix
    ../../shell/sh.nix
  ];

  # CRITICAL: Portal configuration to avoid conflicts with KDE
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
    ];
    config = {
      sway = {
        default = [ "wlr" "gtk" ];
      };
    };
  };

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

  # Clipboard history is now handled via cliphist in startup commands

  # SwayFX configuration
  wayland.windowManager.sway = {
    enable = true;
    package = pkgs.swayfx;  # Use SwayFX instead of standard sway
    checkConfig = false;  # Disable config check (fails in build sandbox without DRM FD)
    
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
          
          # Rofi Universal Launcher
          "${hyper}+space" = "exec rofi -show combi -combi-modi 'drun,run,window' -show-icons";
          "${hyper}+BackSpace" = "exec rofi -show combi -combi-modi 'drun,run,window' -show-icons";
          # Note: Removed "${hyper}+d" to avoid conflict with application bindings
          # Use "${hyper}+space" or "${hyper}+BackSpace" for rofi launcher
          
          # Window Overview (Mission Control-like)
          "${hyper}+Tab" = "exec rofi -show window -theme-str 'listview { columns: 2; lines: 10; }' -show-icons";
          
          # Workspace toggle (back and forth)
          "Mod4+Tab" = "workspace back_and_forth";
          
          # Screenshot workflow
          "${hyper}+Shift+x" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh full";
          "${hyper}+Shift+c" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh area";
          "Print" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh area";
          
          # Application keybindings (using app-toggle.sh script)
          # Note: Using different keys to avoid conflicts with window management bindings
          # Format: app-toggle.sh <app_id|class> <launch_command...>
          "${hyper}+T" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh kitty kitty";
          "${hyper}+L" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh org.telegram.desktop Telegram";
          "${hyper}+E" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh org.kde.dolphin dolphin";
          "${hyper}+D" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh obsidian obsidian --no-sandbox --ozone-platform=wayland --ozone-platform-hint=auto --enable-features=UseOzonePlatform,WaylandWindowDecorations";
          "${hyper}+V" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh com.vivaldi.Vivaldi vivaldi";
          "${hyper}+G" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh chromium-browser chromium";
          "${hyper}+Y" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh spotify spotify --enable-features=UseOzonePlatform --ozone-platform=wayland";
          "${hyper}+N" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh nwg-look nwg-look";
          "${hyper}+P" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh Bitwarden bitwarden";
          "${hyper}+C" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh cursor cursor --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform-hint=auto --unity-launch";
          "${hyper}+M" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh mission-center mission-center";
          "${hyper}+B" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh com.usebottles.bottles bottles";
          
          # Workspace navigation (using Sway native commands for local cycling)
          "${hyper}+Q" = "workspace prev_on_output";  # LOCAL navigation (within current monitor only)
          "${hyper}+W" = "workspace next_on_output";  # LOCAL navigation (within current monitor only)
          "${hyper}+Shift+Q" = "move container to workspace prev_on_output";  # Move window to previous workspace on current monitor (LOCAL)
          "${hyper}+Shift+W" = "move container to workspace next_on_output";  # Move window to next workspace on current monitor (LOCAL)
          
          # Direct workspace bindings (using swaysome)
          "${hyper}+1" = "exec swaysome focus 1";
          "${hyper}+2" = "exec swaysome focus 2";
          "${hyper}+3" = "exec swaysome focus 3";
          "${hyper}+4" = "exec swaysome focus 4";
          "${hyper}+5" = "exec swaysome focus 5";
          "${hyper}+6" = "exec swaysome focus 6";
          "${hyper}+7" = "exec swaysome focus 7";
          "${hyper}+8" = "exec swaysome focus 8";
          "${hyper}+9" = "exec swaysome focus 9";
          "${hyper}+0" = "exec swaysome focus 10";
          
          # Move window to workspace 1-10 (using swaysome)
          "${hyper}+Shift+1" = "exec swaysome move 1";
          "${hyper}+Shift+2" = "exec swaysome move 2";
          "${hyper}+Shift+3" = "exec swaysome move 3";
          "${hyper}+Shift+4" = "exec swaysome move 4";
          "${hyper}+Shift+5" = "exec swaysome move 5";
          "${hyper}+Shift+6" = "exec swaysome move 6";
          "${hyper}+Shift+7" = "exec swaysome move 7";
          "${hyper}+Shift+8" = "exec swaysome move 8";
          "${hyper}+Shift+9" = "exec swaysome move 9";
          "${hyper}+Shift+0" = "exec swaysome move 10";
          
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
          # Note: Removed "${hyper}+s" to avoid conflict with layout bindings
          # Note: Removed "${hyper}+w" to avoid conflict with "${hyper}+W" (workspace next)
          # Note: Removed "${hyper}+e" to avoid conflict with "${hyper}+E" (dolphin)
          
          # Window movement (conditional - floating vs tiled)
          "${hyper}+Shift+j" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh left";
          "${hyper}+colon" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh right";
          "${hyper}+Shift+k" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh down";
          "${hyper}+Shift+l" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh up";
          
          # Window focus navigation
          "${hyper}+Shift+comma" = "focus left";  # Changed from Shift+m to avoid conflict with mission-center
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
          "${hyper}+Shift+d" = "sticky toggle";
          "${hyper}+Shift+g" = "fullscreen toggle";
          
          # Scratchpad
          "${hyper}+minus" = "scratchpad show";
          "${hyper}+Shift+minus" = "move scratchpad";
          
          # Clipboard history
          "${hyper}+Shift+v" = "exec sh -c '${pkgs.cliphist}/bin/cliphist list | ${pkgs.rofi}/bin/rofi -dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy'";
          
          # Power menu
          "${hyper}+Shift+BackSpace" = "exec ${config.home.homeDirectory}/.config/sway/scripts/power-menu.sh";
          
          # Exit Sway
          "${hyper}+Shift+e" = "exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit Sway? This will end your Wayland session.' -b 'Yes, exit Sway' 'swaymsg exit'";
        }
      ];

      # Startup commands (daemons)
      startup = [
        # Initialize swaysome and assign workspace groups to monitors
        # No 'always = true' - runs only on initial startup, not on config reload
        # This prevents jumping back to empty workspaces when editing config
        {
          command = "${config.home.homeDirectory}/.config/sway/scripts/swaysome-init.sh";
        }
        # CRITICAL: Set dark mode environment variables for XWayland apps
        {
          command = "bash -c 'export GTK_APPLICATION_PREFER_DARK_THEME=1; export GTK_THEME=Adwaita-dark; dbus-update-activation-environment --systemd GTK_APPLICATION_PREFER_DARK_THEME GTK_THEME'";
          always = true;
        }
        # Note: Wallpaper (swaybg) is now handled by the unified daemon manager
        {
          command = "bash ${config.home.homeDirectory}/.config/sway/scripts/debug-startup.sh";
          always = true;
        }
        # Unified daemon management - starts all daemons with smart reload support
        {
          command = "${start-sway-daemons}/bin/start-sway-daemons";
          always = true;
        }
        # Optional: Sanity check after startup (can be removed if not needed)
        # {
        #   command = "${daemon-sanity-check}/bin/daemon-sanity-check --fix";
        #   always = false;  # Only run on initial startup, not on reload
        # }
      ];

      # Window rules
      window = {
        commands = [
          # Wayland apps (use app_id)
          { criteria = { app_id = "rofi"; }; command = "floating enable"; }
          { criteria = { app_id = "nwg-dock"; }; command = "floating enable"; }
          { criteria = { app_id = "kitty"; }; command = "floating enable"; }
          { criteria = { app_id = "org.telegram.desktop"; }; command = "floating enable"; }
          { criteria = { app_id = "telegram-desktop"; }; command = "floating enable"; }
          { criteria = { app_id = "bitwarden"; }; command = "floating enable"; }
          { criteria = { app_id = "bitwarden-desktop"; }; command = "floating enable"; }
          { criteria = { app_id = "Bitwarden"; }; command = "floating enable"; }
          { criteria = { app_id = "com.usebottles.bottles"; }; command = "floating enable"; }
          { criteria = { app_id = "swayfx-settings"; }; command = "floating enable"; }
          
          # XWayland apps (use class)
          { criteria = { class = "Spotify"; }; command = "floating enable"; }
          { criteria = { class = "Dolphin"; }; command = "floating enable"; }
          { criteria = { class = "dolphin"; }; command = "floating enable"; }
          
          # Dolphin on Wayland (use app_id)
          { criteria = { app_id = "org.kde.dolphin"; }; command = "floating enable"; }
        ];
      };
    };

    extraConfig = ''
      # Window border settings
      default_border pixel 2
      
      # CRITICAL: Alt key for Plasma-like window manipulation
      # Alt+drag moves windows, Alt+right-drag resizes windows
      floating_modifier Mod1
      
      # Monitor configuration with scaling and positioning
      # DP-1: Samsung Odyssey G70NC (4K: 3840x2160) - Primary monitor
      # DP-2: NSL RGB-27QHDS (2K: 2560x1440) - Secondary monitor (portrait, right side)
      # Calculations:
      # - DP-1: 3840x2160 @ scale 1.6 = logical 2400x1350
      # - DP-2: 2560x1440 rotated 90° = 1440x2560 @ scale 1.15 = logical 1252x2226
      # - To align bottoms: DP-1 bottom at y=1350, DP-2 bottom should be at y=1350
      # - DP-2 top at y=1350-2226=-876 (extends above DP-1, which is fine)
      # - DP-2 x position: right of DP-1 = 2400
      output "DP-1" {
          scale 1.6
          position 0,0
      }
      output "DP-2" {
          mode 2560x1440@144.000Hz
          scale 1.25
          transform 90
          position 2400,-876
      }
      
      # DP-3 (BenQ): Position left of DP-1
      # Position: negative x to place it left of DP-1
      output "DP-3" {
          position -1920,0
      }
      
      # HDMI-A-1 (Philips): Position right of DP-2
      # DP-2 logical width: 1252, so HDMI-A-1 x = 2400 + 1252 = 3652
      # Align vertically with DP-2 (y = -876 or adjust for alignment)
      output "HDMI-A-1" {
          position 3652,-876
      }
      
      # Workspace-to-monitor assignments with fallbacks
      # DP-1 (Samsung 4K): Workspaces 1-10
      workspace 1 output DP-1
      workspace 2 output DP-1
      workspace 3 output DP-1
      workspace 4 output DP-1
      workspace 5 output DP-1
      workspace 6 output DP-1
      workspace 7 output DP-1
      workspace 8 output DP-1
      workspace 9 output DP-1
      workspace 10 output DP-1
      
      # DP-2 (NSL 2K): Workspaces 11-15 (fallback to DP-1 if DP-2 disconnected)
      workspace 11 output DP-2 DP-1
      workspace 12 output DP-2 DP-1
      workspace 13 output DP-2 DP-1
      workspace 14 output DP-2 DP-1
      workspace 15 output DP-2 DP-1
      
      # DP-3 (BenQ): Workspace 21 (fallback to DP-1 if DP-3 disconnected)
      workspace 21 output DP-3 DP-1
      
      # HDMI-A-1 (Philips): Workspace 31 (fallback to DP-1 if HDMI-A-1 disconnected)
      workspace 31 output HDMI-A-1 DP-1
      
      # Workspace configuration
      workspace_auto_back_and_forth yes
      
      # SwayFX visual settings (blur, shadows, rounded corners)
      corner_radius 6
      blur enable
      blur_passes 2
      blur_radius 4
      shadows enable
      
      # NOTE: layer_effects command removed - causes segfault in SwayFX 0.5.3
      # Blur will still work for windows, but not specifically for layer surfaces
      # If needed, can be re-enabled after SwayFX update or syntax fix
      # layer_effects waybar blur
      # layer_effects nwg-dock-hyprland blur
      # layer_effects rofi blur
      
      # Keyboard input configuration for polyglot typing (English/Spanish)
      input "type:keyboard" {
        xkb_layout "us"
        xkb_variant "altgr-intl"
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
      for_window [class="Spotify"] floating enable
      for_window [app_id="rofi"] floating enable
      for_window [app_id="nwg-dock"] floating enable
      for_window [app_id="swayfx-settings"] floating enable
      
      # Additional floating window rules
      for_window [app_id="pavucontrol"] floating enable
      for_window [app_id="nm-connection-editor"] floating enable
      for_window [app_id="blueman-manager"] floating enable
      for_window [app_id="swappy"] floating enable
      for_window [app_id="swaync"] floating enable
      
      # Focus follows mouse
      focus_follows_mouse yes
      
      # Mouse warping
      mouse_warping output
    '';
  };

  # Btop theme configuration (Stylix colors)
  home.file.".config/btop/btop.conf" = lib.mkIf (systemSettings.stylixEnable == true) {
    text = ''
      # Btop Configuration
      # Theme matching Stylix colors
      
      theme_background = "#${config.lib.stylix.colors.base00}"
      theme_text = "#${config.lib.stylix.colors.base07}"
      theme_title = "#${config.lib.stylix.colors.base0D}"
      theme_hi_fg = "#${config.lib.stylix.colors.base0A}"
      theme_selected_bg = "#${config.lib.stylix.colors.base0D}"
      theme_selected_fg = "#${config.lib.stylix.colors.base07}"
      theme_cpu_box = "#${config.lib.stylix.colors.base0B}"
      theme_mem_box = "#${config.lib.stylix.colors.base0E}"
      theme_net_box = "#${config.lib.stylix.colors.base0C}"
      theme_proc_box = "#${config.lib.stylix.colors.base09}"
    '';
  };

  # Libinput-gestures configuration
  home.file.".config/libinput-gestures.conf".text = ''
    # Libinput-gestures configuration
    # 3-finger swipe for workspace navigation
    
    gesture swipe left 3 ${pkgs.sway}/bin/swaymsg workspace next
    gesture swipe right 3 ${pkgs.sway}/bin/swaymsg workspace prev
  '';

  # Install scripts to .config/sway/scripts/
  home.file.".config/sway/scripts/screenshot.sh" = {
    source = ./scripts/screenshot.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/ssh-smart.sh" = {
    source = ./scripts/ssh-smart.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/app-toggle.sh" = {
    source = ./scripts/app-toggle.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/window-move.sh" = {
    source = ./scripts/window-move.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/power-menu.sh" = {
    source = ./scripts/power-menu.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/debug-startup.sh" = {
    source = ./scripts/debug-startup.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/swaysome-init.sh" = {
    source = ./scripts/swaysome-init.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/waybar-startup.sh" = {
    source = ./scripts/waybar-startup.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/dock-diagnostic.sh" = {
    source = ./scripts/dock-diagnostic.sh;
    executable = true;
  };
  
  # Add generated daemon management scripts to PATH
  home.packages = [
    daemon-manager
    start-sway-daemons
    daemon-sanity-check
  ] ++ (with pkgs; [
    # SwayFX and related
    swayfx
    swaylock-effects
    swayidle
    swaynotificationcenter
    waybar  # Waybar status bar (also configured via programs.waybar)
    nwg-dock  # Sway-compatible dock (Python version, NOT nwg-dock-hyprland)
    swaysome  # Workspace namespace per monitor
    
    # Screenshot workflow
    grim
    slurp
    swappy
    swaybg  # Wallpaper manager
    
    # Universal launcher
    rofi  # rofi-wayland has been merged into rofi (as of 2025-09-06)
    
    # Gaming tools
    gamescope
    mangohud
    
    # AI workflow (aichat is installed via module)
    
    # Terminal and tools
    jq  # CRITICAL: Required for screenshot script
    wl-clipboard
    cliphist  # Clipboard history manager for Wayland
    
    # Touchpad gestures
    libinput-gestures
    
    # System tools
    networkmanagerapplet
    blueman
    polkit_gnome
    
    # System monitoring
    # btop is installed by system/hardware/gpu-monitoring.nix module
    # AMD profiles get btop-rocm, Intel/others get standard btop
  ]);
}

