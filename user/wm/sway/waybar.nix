{ config, pkgs, lib, systemSettings, ... }:

{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        spacing = 4;
        
        modules-left = [ "sway/workspaces" "sway/window" ];
        modules-center = [ "clock" ];
        modules-right = [ "tray" "pulseaudio" "network" "battery" "bluetooth" ];
        
        "sway/workspaces" = {
          disable-scroll = true;
          all-outputs = true;
          persistent_workspaces = {
            "*" = [ "1" "2" "3" "4" "5" "6" "7" "8" "9" "10" ];
          };
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
      };
    };
    
    style = if systemSettings.stylixEnable == true then ''
      * {
        border: none;
        border-radius: 0;
        font-family: ${config.stylix.fonts.sansSerif.name}, Font Awesome, sans-serif;
        font-size: 13px;
        min-height: 0;
      }
      
      window#waybar {
        background-color: rgba(${config.lib.stylix.colors.base00}, 0.8);
        border-bottom: 1px solid rgba(${config.lib.stylix.colors.base02}, 0.5);
        color: #${config.lib.stylix.colors.base07};
        transition-property: background-color;
        transition-duration: .5s;
      }
      
      window#waybar.hidden {
        opacity: 0.2;
      }
      
      #workspaces button {
        padding: 0 5px;
        background-color: transparent;
        color: #${config.lib.stylix.colors.base05};
      }
      
      #workspaces button:hover {
        background: rgba(${config.lib.stylix.colors.base02}, 0.2);
      }
      
      #workspaces button.focused {
        color: #${config.lib.stylix.colors.base0D};
      }
      
      #workspaces button.urgent {
        background-color: #${config.lib.stylix.colors.base08};
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
        padding: 0 10px;
        color: #${config.lib.stylix.colors.base07};
      }
      
      #window {
        color: #${config.lib.stylix.colors.base07};
      }
      
      #clock {
        background-color: transparent;
      }
      
      #battery {
        background-color: transparent;
        color: #${config.lib.stylix.colors.base07};
      }
      
      #battery.charging, #battery.plugged {
        color: #${config.lib.stylix.colors.base0B};
      }
      
      @keyframes blink {
        to {
          background-color: #${config.lib.stylix.colors.base07};
          color: #${config.lib.stylix.colors.base00};
        }
      }
      
      #battery.critical:not(.charging) {
        background-color: #${config.lib.stylix.colors.base08};
        color: #${config.lib.stylix.colors.base07};
        animation-name: blink;
        animation-duration: 0.5s;
        animation-timing-function: linear;
        animation-iteration-count: infinite;
        animation-direction: alternate;
      }
      
      label:focus {
        background-color: #${config.lib.stylix.colors.base02};
      }
      
      #pulseaudio {
        background-color: transparent;
        color: #${config.lib.stylix.colors.base07};
      }
      
      #pulseaudio.muted {
        background-color: transparent;
        color: #${config.lib.stylix.colors.base04};
      }
      
      #network {
        background-color: transparent;
        color: #${config.lib.stylix.colors.base07};
      }
      
      #network.disconnected {
        background-color: transparent;
        color: #${config.lib.stylix.colors.base08};
      }
      
      #bluetooth {
        background-color: transparent;
        color: #${config.lib.stylix.colors.base07};
      }
      
      #bluetooth.disabled {
        background-color: transparent;
        color: #${config.lib.stylix.colors.base04};
      }
      
      #tray {
        background-color: transparent;
      }
      
      #tray > .passive {
        -gtk-icon-effect: dim;
      }
      
      #tray > .needs-attention {
        -gtk-icon-effect: highlight;
        background-color: #${config.lib.stylix.colors.base08};
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

