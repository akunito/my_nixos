{ config, pkgs, lib, systemSettings, userSettings, ... }:

let
  # Helper function to convert hex color + alpha to rgba()
  # hex: 6-digit hex color (e.g., "0d1001")
  # alphaHex: 2-digit hex alpha (e.g., "B3" = 179/255 = 0.702)
  # Uses manual hex conversion since Nix doesn't have built-in hex parsing
  # CRITICAL: Waybar's CSS parser does NOT support 8-digit hex colors (#RRGGBBAA)
  # Must use rgba() format instead
  hexToRgba = hex: alphaHex:
    let
      # Convert single hex digit to decimal
      hexDigitToDec = d:
        if d == "0" then 0
        else if d == "1" then 1
        else if d == "2" then 2
        else if d == "3" then 3
        else if d == "4" then 4
        else if d == "5" then 5
        else if d == "6" then 6
        else if d == "7" then 7
        else if d == "8" then 8
        else if d == "9" then 9
        else if d == "a" || d == "A" then 10
        else if d == "b" || d == "B" then 11
        else if d == "c" || d == "C" then 12
        else if d == "d" || d == "D" then 13
        else if d == "e" || d == "E" then 14
        else if d == "f" || d == "F" then 15
        else 0;
      # Convert 2-digit hex to decimal
      hexToDec = hexStr:
        let
          d1 = builtins.substring 0 1 hexStr;
          d2 = builtins.substring 1 1 hexStr;
        in
          hexDigitToDec d1 * 16 + hexDigitToDec d2;
      r = hexToDec (builtins.substring 0 2 hex);
      g = hexToDec (builtins.substring 2 2 hex);
      b = hexToDec (builtins.substring 4 2 hex);
      alpha = (hexToDec alphaHex) / 255.0;
      # Format alpha to 3 decimal places
      alphaStr = builtins.substring 0 5 (toString alpha);
    in
      "rgba(${toString r}, ${toString g}, ${toString b}, ${alphaStr})";
  
  # Shared module configurations (DRY principle)
  sharedModules = {
        clock = {
          format = "{:%d/%m/%Y %H:%M}";
          format-alt = "{:%A, %B %d, %Y (%R)}";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
          calendar = {
            mode = "year";
            mode-mon-col = 3;
            weeks-pos = "right";
            on-scroll = 1;
            on-click-right = "mode";
            first-day-of-week = 1;  # Start week on Monday (0 = Sunday, 1 = Monday)
            format = {
              months = "<span color='#ffead3'><b>{}</b></span>";
              days = "<span color='#ecc6d9'>{}</span>";
              weeks = "<span color='#99ffdd'><b>W{}</b></span>";
              weekdays = "<span color='#ffcc66'><b>{}</b></span>";
              today = "<span color='#ff6699'><b><u>{}</u></b></span>";
            };
          };
          actions = {
            on-click-right = "mode";
            on-click-forward = "tz_up";
            on-click-backward = "tz_down";
            on-scroll-up = "shift_up";
            on-scroll-down = "shift_down";
          };
        };
        
        pulseaudio = {
          format = "{icon} {volume}%";
          format-bluetooth = "{icon} {volume}% {format_source}";
          format-bluetooth-muted = "󰂲 {format_source}";
          format-muted = "󰝟";
          format-source = "{volume}% 󰍬";
          format-source-muted = "󰍭";
          format-icons = {
            headphone = "󰋋";
            hands-free = "󰋎";
            headset = "󰋎";
            phone = "󰄜";
            portable = "󰓃";
            car = "󰄋";
            default = [ "󰕿" "󰖀" "󰕾" ];
          };
          # Use absolute store path so it works reliably under systemd (no PATH assumptions)
          on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
          on-click-right = "pactl set-sink-mute @DEFAULT_SINK@ toggle";
        };
        
        network = {
          format-wifi = "󰤨 {signalStrength}%";
          format-ethernet = "󰈀 Connected";
          format-linked = "󰈀 {ifname} (No IP)";
          format-disconnected = "󰤭 Disconnected";
          format-alt = "{ifname}: {ipaddr}/{cidr}";
          tooltip-format = "{ifname} via {gwaddr}";
        };
        
        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-plugged = "󰂄 {capacity}%";
          format-alt = "{icon} {time}";
          format-icons = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
        };
        
        bluetooth = {
          format = "󰂯";
          format-disabled = "󰂲";
          format-off = "󰂲";
          format-on = "󰂯";
          format-connected = "󰂱 {num_connections}";
          tooltip-format = "{controller_alias}\t{controller_address}\n\n{num_connections} connections";
          tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{num_connections} connections\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
        };
    
    tray = {
      icon-spacing = 48;
      tooltip = true;
    };
    
    # "sway/window" removed (active window title not shown in bar)
  };
  
  # Workspace configuration for primary monitor (all workspaces grouped)
  primaryWorkspaces = {
    disable-scroll = true;
    all-outputs = true;  # Show all workspaces from all monitors
    format = "{name}: {icon}";  # Note: {output} token not supported by sway/workspaces module
    format-icons = {
      "1" = "一";
      "2" = "二";
      "3" = "三";
      "4" = "四";
      "5" = "五";
      "6" = "六";
      "7" = "七";
      "8" = "八";
      "9" = "九";
      "10" = "十";
      urgent = "";
      focused = "";
      default = "";
    };
  };
  
  # Workspace configuration for secondary monitors (per-monitor workspaces)
  secondaryWorkspaces = {
    disable-scroll = true;
    all-outputs = false;  # Only show workspaces for current monitor
    format = "{name}: {icon}";
    format-icons = {
      "1" = "一";
      "2" = "二";
      "3" = "三";
      "4" = "四";
      "5" = "五";
      "6" = "六";
      "7" = "七";
      "8" = "八";
      "9" = "九";
      "10" = "十";
      urgent = "";
      focused = "";
      default = "";
    };
  };
  
  # Safe extraction: check if swayPrimaryMonitor exists and is not empty
  primaryMonitor = if (systemSettings ? swayPrimaryMonitor && systemSettings.swayPrimaryMonitor != "") 
                   then systemSettings.swayPrimaryMonitor 
                   else null;
  hasPrimaryMonitor = primaryMonitor != null;
in {
  # Official NixOS Waybar Setup for SwayFX
  # Reference: https://wiki.nixos.org/wiki/Waybar
  # Official Waybar Documentation: https://github.com/Alexays/Waybar
  # 
  # Best Practices:
  # 1. Use programs.waybar.enable = true (Home Manager module)
  # 2. Disable systemd service when managing manually (systemd.enable = false)
  # 3. Official way to start: exec waybar in Sway config
  #    We use daemon-manager instead for better process management and crash recovery
  # 4. Config files are auto-generated by Home Manager in ~/.config/waybar/
  # 5. Waybar works with SwayFX the same as with Sway (no special configuration needed)
  programs.waybar = {
    enable = true;
    # CRITICAL: Enable systemd service - waybar lifecycle is managed by systemd --user
    # We bind waybar to Sway via sway-session.target (configured in user/wm/sway/default.nix)
    # so it starts/stops cleanly with Sway and does not leak into Plasma 6 sessions.
    #
    # NOTE: Some Home Manager versions don't support programs.waybar.systemd.target,
    # so we keep target-binding logic in default.nix via systemd.user.services.waybar.
    systemd.enable = true;
    # CRITICAL: settings must be a List of attribute sets when defining multiple bars
    settings = 
      if hasPrimaryMonitor then
        # Primary monitor setup: single bar on primary, all workspaces grouped
        [
          {
            # Primary monitor top bar
            output = primaryMonitor;  # Bind to primary monitor only
            layer = "top";
            position = "top";
            height = 30;
            spacing = 4;
            
            modules-left = [ "sway/workspaces" ];
            modules-center = [ "clock" ];
            modules-right = [ "custom/notifications" "tray" "pulseaudio" "battery" "custom/perf" "custom/flatpak-updates" ];
            
            "sway/workspaces" = primaryWorkspaces;
            # Use shared modules
            clock = sharedModules.clock;
            pulseaudio = sharedModules.pulseaudio;
            network = sharedModules.network;
            battery = sharedModules.battery;
            bluetooth = sharedModules.bluetooth;
            tray = sharedModules.tray;
            # "sway/window" removed

            "custom/perf" = {
              return-type = "json";
              interval = 2;
              # Run explicitly with Nix bash. Waybar is a systemd user service and may not have `bash` on PATH,
              # so `/usr/bin/env bash` scripts can fail silently.
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-perf.sh";
              on-click = "${pkgs.kitty}/bin/kitty --title 'btop++ (System Monitor)' -e /run/current-system/sw/bin/btop";
              tooltip = true;
            };

            # Notifications history (Sway Notification Center)
            # `swaync-client -swb` streams JSON updates (waybar format) when notifications change.
            "custom/notifications" = {
              return-type = "json";
              exec = "${pkgs.swaynotificationcenter}/bin/swaync-client -swb";
              on-click = "${pkgs.swaynotificationcenter}/bin/swaync-client -t";
              on-click-right = "${pkgs.swaynotificationcenter}/bin/swaync-client -C";
              tooltip = true;
            };

            # Flatpak updates indicator (read-only)
            "custom/flatpak-updates" = {
              return-type = "json";
              interval = 1800; # 30min
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-flatpak-updates.sh ${pkgs.flatpak}/bin/flatpak";
              tooltip = true;
            };
          }
          # Dock bar removed: wlr/taskbar requires foreign-toplevel-manager protocol
          # which is often disabled or flaky in SwayFX. Rofi remains the primary
          # application switcher. Dock can be re-enabled when SwayFX protocol support improves.
          # {
          #   # Primary monitor dock (hidden by default, hover to show)
          #   name = "dock";
          #   output = primaryMonitor;
          #   layer = "top";
          #   position = "bottom";
          #   height = 44;
          #   spacing = 4;
          #   mode = "overlay";
          #   modules-center = [ "wlr/taskbar" ];
          #   "wlr/taskbar" = {
          #     icon-size = 24;
          #     format = "{icon}";
          #     on-click = "activate";
          #     tooltip-format = "{title}";
          #     ignore-list = [ "nwg-dock" ];
          #     all-outputs = true;
          #   };
          # }
        ]
      else
        # Multi-monitor setup: bar on each monitor with per-monitor workspaces
        [
          {
            # Top bar (no output specified = shows on all monitors)
            layer = "top";
            position = "top";
            height = 30;
            spacing = 4;
            
            modules-left = [ "sway/workspaces" ];
            modules-center = [ "clock" ];
            modules-right = [ "custom/notifications" "tray" "pulseaudio" "battery" "custom/perf" "custom/flatpak-updates" ];
            
            "sway/workspaces" = secondaryWorkspaces;  # Per-monitor workspaces
            # Use shared modules
            clock = sharedModules.clock;
            pulseaudio = sharedModules.pulseaudio;
            network = sharedModules.network;
            battery = sharedModules.battery;
            bluetooth = sharedModules.bluetooth;
            tray = sharedModules.tray;
            # "sway/window" removed

            "custom/perf" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-perf.sh";
              on-click = "${pkgs.kitty}/bin/kitty --title 'btop++ (System Monitor)' -e /run/current-system/sw/bin/btop";
              tooltip = true;
            };

            "custom/notifications" = {
              return-type = "json";
              exec = "${pkgs.swaynotificationcenter}/bin/swaync-client -swb";
              on-click = "${pkgs.swaynotificationcenter}/bin/swaync-client -t";
              on-click-right = "${pkgs.swaynotificationcenter}/bin/swaync-client -C";
              tooltip = true;
            };

            "custom/flatpak-updates" = {
              return-type = "json";
              interval = 1800;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-flatpak-updates.sh ${pkgs.flatpak}/bin/flatpak";
              tooltip = true;
            };
          }
        ];
    
    # CRITICAL: Check if Stylix is actually available (not just enabled)
    # Stylix is disabled for Plasma 6 even if stylixEnable is true
    # However, if SwayFX is enabled via enableSwayForDESK, Stylix should be enabled for SwayFX
    # Use the same condition as the Stylix module to ensure consistency
    style = if (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)) then ''
      * {
        border: none;
        border-radius: 12px;
        font-family: ${config.stylix.fonts.sansSerif.name}, Font Awesome, sans-serif;
        font-size: 13px;
        min-height: 0;
      }
      
      window#waybar {
        /* Default: bar container is invisible (modules keep their own pill backgrounds) */
        background-color: transparent;
        border: 1px solid transparent;
        border-radius: 16px;
        margin: 8px 12px;
        padding: 0;
        color: #${config.lib.stylix.colors.base07};
        /* backdrop-filter not supported by waybar CSS parser - removed */
        box-shadow: none;
        /* Keep the bar container always invisible; only widgets have backgrounds */
      }
      
      /* Dock bar CSS removed: Dock bar disabled due to wlr/taskbar protocol limitations in SwayFX */
      /* Dock can be re-enabled when SwayFX foreign-toplevel-manager protocol support improves */
      
      window#waybar.hidden {
        opacity: 0.2;
      }
      
      #workspaces {
        margin: 4px 8px;
        padding: 0;
        border-radius: 12px;
        background-color: ${hexToRgba config.lib.stylix.colors.base01 "66"};
      }
      
      #workspaces button {
        min-width: 20px;  /* CRITICAL: Prevent collapse to zero width */
        padding: 0 5px;  /* Horizontal padding is critical for visibility */
        margin: 2px;
        border-radius: 10px;
        background-color: transparent;
        color: #${config.lib.stylix.colors.base05};
        transition: all 0.2s ease;
      }
      
      #workspaces button:hover {
        background-color: ${hexToRgba config.lib.stylix.colors.base02 "66"};
        color: #${config.lib.stylix.colors.base07};
      }
      
      #workspaces button.focused {
        background-color: ${hexToRgba config.lib.stylix.colors.base0D "4D"};
        color: #${config.lib.stylix.colors.base0D};
        box-shadow: 0 2px 8px ${hexToRgba config.lib.stylix.colors.base0D "4D"};
      }
      
      #workspaces button.urgent {
        background-color: ${hexToRgba config.lib.stylix.colors.base08 "80"};
        color: #${config.lib.stylix.colors.base07};
        animation: urgent-pulse 2s ease-in-out infinite;
      }
      
      @keyframes urgent-pulse {
        0% { opacity: 1; }
        50% { opacity: 0.7; }
        100% { opacity: 1; }
      }
      
      #window {
        margin: 4px 8px;
        padding: 4px 12px;
        border-radius: 10px;
        background-color: ${hexToRgba config.lib.stylix.colors.base01 "66"};
        color: #${config.lib.stylix.colors.base07};
      }
      
      #clock,
      #battery,
      #cpu,
      #memory,
      #disk,
      #temperature,
      #backlight,
      #network,
      #pulseaudio,
      #custom-media,
      #tray,
      #mode,
      #idle_inhibitor,
      #mpd,
      #bluetooth,
      #custom-perf,
      #custom-notifications,
      #custom-flatpak-updates {
        margin: 4px 4px;
        padding: 4px 12px;
        border-radius: 10px;
        background-color: ${hexToRgba config.lib.stylix.colors.base01 "66"};
        color: #${config.lib.stylix.colors.base07};
        transition: all 0.2s ease;
      }
      
      #clock:hover,
      #battery:hover,
      #network:hover,
      #pulseaudio:hover,
      #bluetooth:hover,
      #custom-perf:hover,
      #custom-notifications:hover,
      #custom-flatpak-updates:hover {
        background-color: ${hexToRgba config.lib.stylix.colors.base02 "80"};
      }
      
      #clock {
        font-weight: 600;
      }
      
      #battery {
        color: #${config.lib.stylix.colors.base07};
      }
      
      #battery.charging, #battery.plugged {
        color: #${config.lib.stylix.colors.base0B};
        background-color: ${hexToRgba config.lib.stylix.colors.base0B "33"};
      }
      
      @keyframes blink {
        to {
          background-color: #${config.lib.stylix.colors.base08};
          color: #${config.lib.stylix.colors.base07};
        }
      }
      
      #battery.critical:not(.charging) {
        background-color: ${hexToRgba config.lib.stylix.colors.base08 "99"};
        color: #${config.lib.stylix.colors.base07};
        animation-name: blink;
        animation-duration: 0.5s;
        animation-timing-function: linear;
        animation-iteration-count: infinite;
        animation-direction: alternate;
      }
      
      label:focus {
        background-color: ${hexToRgba config.lib.stylix.colors.base02 "80"};
      }
      
      #pulseaudio {
        color: #${config.lib.stylix.colors.base07};
      }
      
      #pulseaudio.muted {
        color: #${config.lib.stylix.colors.base04};
        background-color: ${hexToRgba config.lib.stylix.colors.base04 "33"};
      }
      
      #network {
        color: #${config.lib.stylix.colors.base07};
      }
      
      #network.disconnected {
        color: #${config.lib.stylix.colors.base08};
        background-color: ${hexToRgba config.lib.stylix.colors.base08 "33"};
      }
      
      #bluetooth {
        color: #${config.lib.stylix.colors.base07};
      }
      
      #bluetooth.disabled {
        color: #${config.lib.stylix.colors.base04};
        background-color: ${hexToRgba config.lib.stylix.colors.base04 "33"};
      }
      
      #tray {
        margin: 4px 4px;
        padding: 4px 8px;
        border-radius: 10px;
        background-color: ${hexToRgba config.lib.stylix.colors.base01 "66"};
      }
      
      /* Add spacing between tray icons */
      #tray > * {
        margin: 0 24px;  /* Horizontal margin between icons */
        padding: 0 4px;
      }

      /* Some Waybar builds wrap tray items in buttons/widgets; cover common cases */
      #tray button {
        margin: 0 24px;
        padding: 0 4px;
      }
      
      #tray > *:first-child {
        margin-left: 0;
      }
      
      #tray > *:last-child {
        margin-right: 0;
      }
      
      #tray > .passive {
        -gtk-icon-effect: dim;
      }
      
      #tray > .needs-attention {
        -gtk-icon-effect: highlight;
        background-color: ${hexToRgba config.lib.stylix.colors.base08 "66"};
        border-radius: 8px;
      }
    '' else ''
      * {
        border: none;
        border-radius: 0;
        font-family: sans-serif;
        font-size: 13px;
        min-height: 0;
      }
      
      window#waybar {
        background-color: transparent;
        border-bottom: 1px solid transparent;
        color: #ffffff;
        /* Keep the bar container always invisible; only widgets have backgrounds */
      }
      
      #workspaces button {
        padding: 0 5px;
        background-color: transparent;
        color: #888888;
      }
      
      #workspaces button.focused {
        color: #ffffff;
      }
      
      #clock,
      #battery,
      #network,
      #pulseaudio,
      #tray,
      #bluetooth,
      #custom-perf,
      #custom-notifications,
      #custom-flatpak-updates {
        padding: 0 10px;
        color: #ffffff;
      }
    '';
  };
}
