{ config, pkgs, lib, systemSettings, userSettings, ... }:

{
  programs.waybar = {
    enable = true;
    # CRITICAL: Disable systemd service - waybar is managed by daemon-manager via Sway startup
    # This prevents systemd and daemon-manager from both trying to start waybar
    systemd.enable = false;
    # CRITICAL: settings must be a List of attribute sets when defining multiple bars
    settings = [
      {
        # Main Top Bar (first element)
        layer = "top";
        position = "top";
        height = 30;
        spacing = 4;
        
        modules-left = [ "sway/workspaces" "sway/window" ];
        modules-center = [ "clock" ];
        modules-right = [ "tray" "pulseaudio" "network" "battery" "bluetooth" ];
        
        "sway/workspaces" = {
          disable-scroll = true;
          all-outputs = false;  # Only show workspaces for the current monitor
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
        
        "sway/window" = {
          format = "{}";
          max-length = 50;
        };
        
        clock = {
          format = "{:%H:%M}";
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
        
        tray = {
          icon-spacing = 10;
          tooltip = true;
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
          on-click = "pavucontrol";
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
      }
      {
        # New Dock Bar (second element)
        layer = "top";
        position = "bottom";
        height = 44;
        spacing = 4;
        mode = "dock";  # Exclusive zone mode
        modules-center = [ "wlr/taskbar" ];
        
        "wlr/taskbar" = {
          icon-size = 24;
          format = "{icon}";
          on-click = "activate";
          tooltip-format = "{title}";
          ignore-list = [ "nwg-dock" ];  # Ignore old dock if still running
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
        background-color: #${config.lib.stylix.colors.base00}B3;
        border: 1px solid #${config.lib.stylix.colors.base02}4D;
        border-radius: 16px;
        margin: 8px 12px;
        padding: 0;
        color: #${config.lib.stylix.colors.base07};
        backdrop-filter: blur(20px);
        -webkit-backdrop-filter: blur(20px);
        box-shadow: 0 4px 16px rgba(0, 0, 0, 0.3);
        transition-property: background-color;
        transition-duration: .3s;
      }
      
      window#waybar:last-child {
        background-color: #${config.lib.stylix.colors.base00}B3;
        border: 1px solid #${config.lib.stylix.colors.base02}4D;
        border-radius: 20px;
        margin: 0 12px 10px 12px;
        padding: 8px;
        box-shadow: 0 4px 16px rgba(0, 0, 0, 0.3);
      }
      
      #taskbar {
        border-radius: 12px;
        padding: 4px;
      }
      
      #taskbar button {
        border-radius: 8px;
        padding: 4px 8px;
        margin: 0 2px;
      }
      
      #taskbar button:hover {
        background-color: #${config.lib.stylix.colors.base0D}33;
      }
      
      window#waybar.hidden {
        opacity: 0.2;
      }
      
      #workspaces {
        margin: 4px 8px;
        padding: 0;
        border-radius: 12px;
        background-color: #${config.lib.stylix.colors.base01}66;
      }
      
      #workspaces button {
        padding: 4px 12px;
        margin: 2px;
        border-radius: 10px;
        background-color: transparent;
        color: #${config.lib.stylix.colors.base05};
        transition: all 0.2s ease;
      }
      
      #workspaces button:hover {
        background-color: #${config.lib.stylix.colors.base02}66;
        color: #${config.lib.stylix.colors.base07};
      }
      
      #workspaces button.focused {
        background-color: #${config.lib.stylix.colors.base0D}4D;
        color: #${config.lib.stylix.colors.base0D};
        box-shadow: 0 2px 8px #${config.lib.stylix.colors.base0D}4D;
      }
      
      #workspaces button.urgent {
        background-color: #${config.lib.stylix.colors.base08}80;
        color: #${config.lib.stylix.colors.base07};
        animation: urgent-pulse 2s ease-in-out infinite;
      }
      
      @keyframes urgent-pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.7; }
      }
      
      #window {
        margin: 4px 8px;
        padding: 4px 12px;
        border-radius: 10px;
        background-color: #${config.lib.stylix.colors.base01}66;
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
      #bluetooth {
        margin: 4px 4px;
        padding: 4px 12px;
        border-radius: 10px;
        background-color: #${config.lib.stylix.colors.base01}66;
        color: #${config.lib.stylix.colors.base07};
        transition: all 0.2s ease;
      }
      
      #clock:hover,
      #battery:hover,
      #network:hover,
      #pulseaudio:hover,
      #bluetooth:hover {
        background-color: #${config.lib.stylix.colors.base02}80;
      }
      
      #clock {
        font-weight: 600;
      }
      
      #battery {
        color: #${config.lib.stylix.colors.base07};
      }
      
      #battery.charging, #battery.plugged {
        color: #${config.lib.stylix.colors.base0B};
        background-color: #${config.lib.stylix.colors.base0B}33;
      }
      
      @keyframes blink {
        to {
          background-color: #${config.lib.stylix.colors.base08};
          color: #${config.lib.stylix.colors.base07};
        }
      }
      
      #battery.critical:not(.charging) {
        background-color: #${config.lib.stylix.colors.base08}99;
        color: #${config.lib.stylix.colors.base07};
        animation-name: blink;
        animation-duration: 0.5s;
        animation-timing-function: linear;
        animation-iteration-count: infinite;
        animation-direction: alternate;
      }
      
      label:focus {
        background-color: #${config.lib.stylix.colors.base02}80;
      }
      
      #pulseaudio {
        color: #${config.lib.stylix.colors.base07};
      }
      
      #pulseaudio.muted {
        color: #${config.lib.stylix.colors.base04};
        background-color: #${config.lib.stylix.colors.base04}33;
      }
      
      #network {
        color: #${config.lib.stylix.colors.base07};
      }
      
      #network.disconnected {
        color: #${config.lib.stylix.colors.base08};
        background-color: #${config.lib.stylix.colors.base08}33;
      }
      
      #bluetooth {
        color: #${config.lib.stylix.colors.base07};
      }
      
      #bluetooth.disabled {
        color: #${config.lib.stylix.colors.base04};
        background-color: #${config.lib.stylix.colors.base04}33;
      }
      
      #tray {
        margin: 4px 4px;
        padding: 4px 8px;
        border-radius: 10px;
        background-color: #${config.lib.stylix.colors.base01}66;
      }
      
      #tray > .passive {
        -gtk-icon-effect: dim;
      }
      
      #tray > .needs-attention {
        -gtk-icon-effect: highlight;
        background-color: #${config.lib.stylix.colors.base08}66;
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
        background-color: rgba(0, 0, 0, 0.8);
        border-bottom: 1px solid rgba(255, 255, 255, 0.1);
        color: #ffffff;
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
      #bluetooth {
        padding: 0 10px;
        color: #ffffff;
      }
    '';
  };
}

