{ config, pkgs, lib, systemSettings, userSettings, ... }:

let
  # Some GPU tooling is optional depending on hardware / nixpkgs settings.
  # Avoid hard failures during evaluation (e.g. missing pkgs.nvidia-settings on non-NVIDIA hosts).
  nvidiaSettingsBin =
    if builtins.hasAttr "nvidia-settings" pkgs
    then "${pkgs.nvidia-settings}/bin/nvidia-settings"
    else "";
  intelGpuTopBin =
    if builtins.hasAttr "intel-gpu-tools" pkgs
    then "${pkgs.intel-gpu-tools}/bin/intel_gpu_top"
    else "";
  lactBin =
    if builtins.hasAttr "lact" pkgs
    then "${pkgs.lact}/bin/lact"
    else "";

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
          # Screenshot style: percent first, icon last
          format = "{volume}% {icon}";
          format-bluetooth = "{icon} {volume}% {format_source}";
          format-bluetooth-muted = "󰂲 {format_source}";
          format-muted = "0% 󰝟";
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
          on-click-right = "${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle";
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
          # Screenshot style: percent first, icon last
          format = "{capacity}% {icon}";
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

  # Swaysome workspace groups (10s/20s/30s/40s) -> readable labels on a single bar.
  #
  # Important: `sway/workspaces` does NOT support a generic `rewrite` map.
  # Instead we encode the decoded label into `format-icons` and display `{icon}`.
  #
  # Also: `{name}` is "number stripped from workspace value" (e.g. "1: web" -> "web"),
  # so numeric-only workspaces can render empty when using `{name}`. We avoid `{name}`.
  stylixForSway =
    systemSettings.stylixEnable == true
    && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true);

  mkSwaysomeGroupIcons = group: groupIcon: groupColor:
    builtins.listToAttrs (builtins.genList (d:
      let
        digit = d; # 0..9
        ws = "${toString group}${toString digit}"; # e.g. "11", "20", "39"
        label = if digit == 0 then "10" else toString digit; # show key "0" as 10
      in
      {
        name = ws;
        value =
          if stylixForSway
          then "<span foreground='#${groupColor}'>${groupIcon}</span> ${label}"
          else "${groupIcon} ${label}";
      }
    ) 10);

  swaysomeWorkspaceIcons =
    (mkSwaysomeGroupIcons 1 "󰍹" config.lib.stylix.colors.base0C) //
    (mkSwaysomeGroupIcons 2 "󰍹" config.lib.stylix.colors.base08) //
    (mkSwaysomeGroupIcons 3 "󰍹" config.lib.stylix.colors.base0A) //
    (mkSwaysomeGroupIcons 4 "󰍹" config.lib.stylix.colors.base0E);
  
  # Workspace configuration for primary monitor (all workspaces grouped)
  primaryWorkspaces = {
    disable-scroll = true;
    all-outputs = true;  # Show all workspaces from all monitors
    format = "{icon}";
    format-icons = swaysomeWorkspaceIcons // {
      default = "";
    };
  };
  
  # Workspace configuration for secondary monitors (per-monitor workspaces)
  secondaryWorkspaces = {
    disable-scroll = true;
    all-outputs = false;  # Only show workspaces for current monitor
    format = "{icon}";
    format-icons = swaysomeWorkspaceIcons // {
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
            # Spacing affects inter-module gaps even if CSS margins are 0.
            # Set to 0 so the left cluster can truly fuse into a single pill.
            spacing = 0;
            
            modules-left = [
              "battery"
              "backlight"
              "pulseaudio"
              "custom/mic"
              "custom/cpu"
              "custom/cpu-temp"
              "custom/gpu"
              "custom/gpu-temp"
              "custom/ram"
            ];
            modules-center = [ "sway/workspaces" ];
            modules-right = [ "idle_inhibitor" "custom/nixos-update" "custom/flatpak-updates" "group/extras" "clock" "custom/power-menu" ];
            
            "sway/workspaces" = primaryWorkspaces;
            # Use shared modules
            clock = sharedModules.clock;
            pulseaudio = sharedModules.pulseaudio;
            network = sharedModules.network;
            battery = sharedModules.battery;
            bluetooth = sharedModules.bluetooth;
            tray = sharedModules.tray;
            # "sway/window" removed

            backlight = {
              # “Contrast” == brightness/backlight %
              format = "{percent}% ◐";
              scroll-step = 5;
              tooltip = false;
            };

            # Microphone widget (percent + mic icon)
            "custom/mic" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-mic.sh ${pkgs.pulseaudio}/bin/pactl";
              on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
              tooltip = true;
            };

            # Split metrics (CPU/GPU/RAM/temps); click opens btop++
            "custom/cpu" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-metrics.sh cpu";
              on-click = "${pkgs.kitty}/bin/kitty --title 'btop++ (System Monitor)' -e /run/current-system/sw/bin/btop";
              tooltip = true;
            };
            "custom/gpu" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-metrics.sh gpu";
              on-click = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-gpu-tool.sh ${systemSettings.gpuType} ${pkgs.kitty}/bin/kitty /run/current-system/sw/bin/btop ${lactBin} ${nvidiaSettingsBin} ${intelGpuTopBin}";
              tooltip = true;
            };
            "custom/ram" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-metrics.sh ram";
              on-click = "${pkgs.kitty}/bin/kitty --title 'btop++ (System Monitor)' -e /run/current-system/sw/bin/btop";
              tooltip = true;
            };
            "custom/cpu-temp" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-metrics.sh cpu-temp";
              on-click = "${pkgs.kitty}/bin/kitty --title 'btop++ (System Monitor)' -e /run/current-system/sw/bin/btop";
              tooltip = true;
            };
            "custom/gpu-temp" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-metrics.sh gpu-temp";
              on-click = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-gpu-tool.sh ${systemSettings.gpuType} ${pkgs.kitty}/bin/kitty /run/current-system/sw/bin/btop ${lactBin} ${nvidiaSettingsBin} ${intelGpuTopBin}";
              tooltip = true;
            };

            # Notifications history (Sway Notification Center)
            # Icon-only (no counter), and hidden when there are no notifications.
            "custom/notifications" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-notifications.sh ${pkgs.swaynotificationcenter}/bin/swaync-client";
              on-click = "${pkgs.swaynotificationcenter}/bin/swaync-client -t";
              on-click-right = "${pkgs.swaynotificationcenter}/bin/swaync-client -C";
              tooltip = true;
            };

            # Extras drawer (official Waybar group drawer)
            "custom/reveal" = {
              interval = 3600;
              exec = "${pkgs.coreutils}/bin/printf '⋯'";
              tooltip = true;
              tooltip-format = "Extras (click)";
            };

            "group/extras" = {
              orientation = "inherit";
              drawer = {
                transition-duration = 200;
                children-class = "drawer-hidden";
                click-to-reveal = false;
                transition-left-to-right = false;
              };
              modules = [ "custom/reveal" "custom/notifications" "custom/vpn" "tray" ];
            };

            # Flatpak updates indicator (read-only)
            "custom/flatpak-updates" = {
              return-type = "json";
              interval = 1800; # 30min
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-flatpak-updates.sh ${pkgs.flatpak}/bin/flatpak";
              on-click = "${pkgs.kitty}/bin/kitty --title 'Flatpak update' -e ${pkgs.bash}/bin/bash -lc '${pkgs.flatpak}/bin/flatpak update -y; rc=$?; if [ $rc -eq 0 ]; then echo \"All Flatpaks updated. Bye bye!\"; sleep 3; exit 0; else echo \"Flatpak update failed ($rc).\"; exec ${pkgs.bash}/bin/bash; fi'";
              tooltip = true;
            };

            # Update NixOS (runs install.sh for the active profile)
            "custom/nixos-update" = {
              return-type = "json";
              interval = 3600;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-nixos-update.sh";
              on-click = "${pkgs.kitty}/bin/kitty --title 'Update NixOS' -e ${pkgs.bash}/bin/bash -lc '${systemSettings.installCommand}; rc=$?; if [ $rc -eq 0 ]; then echo \"Update completed. Bye bye!\"; sleep 3; exit 0; else echo \"Update failed ($rc).\"; exec ${pkgs.bash}/bin/bash; fi'";
              tooltip = true;
            };

            # Coffee button: toggle idle inhibition (prevents swayidle screen blank/suspend logic that respects inhibit)
            idle_inhibitor = {
              format = "{icon}";
              tooltip = true;
              tooltip-format = "Anfetas {status}";
              # For testing/transition: clicking the built-in module toggles the same swayidle.service
              # as the custom idle toggle + keybinding.
              on-click = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/idle-inhibit-toggle.sh";
              format-icons = {
                activated = "";
                deactivated = "";
              };
            };

            # WireGuard VPN toggle (wg-quick)
            "custom/vpn" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-vpn-wg-client.sh ${pkgs.iproute2}/bin/ip";
              on-click = "${pkgs.kitty}/bin/kitty --title 'VPN toggle' -e ${pkgs.bash}/bin/bash -lc 'if ${pkgs.iproute2}/bin/ip link show wg-client >/dev/null 2>&1; then sudo ${pkgs.wireguard-tools}/bin/wg-quick down ~/.wireguard/wg-client.conf; else sudo ${pkgs.wireguard-tools}/bin/wg-quick up ~/.wireguard/wg-client.conf; fi; rc=$?; if [ $rc -eq 0 ]; then echo \"Bye bye!\"; sleep 3; exit 0; else echo \"VPN command failed ($rc).\"; exec ${pkgs.bash}/bin/bash; fi'";
              tooltip = true;
            };

            # Power menu (same as ${hyper}+Shift+BackSpace)
            "custom/power-menu" = {
              interval = 3600;
              exec = "${pkgs.coreutils}/bin/printf '⏻'";
              on-click = "${config.home.homeDirectory}/.config/sway/scripts/rofi-power-launch.sh";
              tooltip = true;
              tooltip-format = "Power menu";
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
            spacing = 0;
            
            modules-left = [
              "battery"
              "backlight"
              "pulseaudio"
              "custom/mic"
              "custom/cpu"
              "custom/cpu-temp"
              "custom/gpu"
              "custom/gpu-temp"
              "custom/ram"
            ];
            modules-center = [ "sway/workspaces" ];
            modules-right = [ "idle_inhibitor" "custom/nixos-update" "custom/flatpak-updates" "group/extras" "clock" "custom/power-menu" ];
            
            "sway/workspaces" = secondaryWorkspaces;  # Per-monitor workspaces
            # Use shared modules
            clock = sharedModules.clock;
            pulseaudio = sharedModules.pulseaudio;
            network = sharedModules.network;
            battery = sharedModules.battery;
            bluetooth = sharedModules.bluetooth;
            tray = sharedModules.tray;
            # "sway/window" removed

            backlight = {
              format = "{percent}% ◐";
              scroll-step = 5;
              tooltip = false;
            };

            "custom/mic" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-mic.sh ${pkgs.pulseaudio}/bin/pactl";
              on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
              tooltip = true;
            };

            "custom/cpu" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-metrics.sh cpu";
              on-click = "${pkgs.kitty}/bin/kitty --title 'btop++ (System Monitor)' -e /run/current-system/sw/bin/btop";
              tooltip = true;
            };
            "custom/gpu" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-metrics.sh gpu";
              on-click = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-gpu-tool.sh ${systemSettings.gpuType} ${pkgs.kitty}/bin/kitty /run/current-system/sw/bin/btop ${lactBin} ${nvidiaSettingsBin} ${intelGpuTopBin}";
              tooltip = true;
            };
            "custom/ram" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-metrics.sh ram";
              on-click = "${pkgs.kitty}/bin/kitty --title 'btop++ (System Monitor)' -e /run/current-system/sw/bin/btop";
              tooltip = true;
            };
            "custom/cpu-temp" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-metrics.sh cpu-temp";
              on-click = "${pkgs.kitty}/bin/kitty --title 'btop++ (System Monitor)' -e /run/current-system/sw/bin/btop";
              tooltip = true;
            };
            "custom/gpu-temp" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-metrics.sh gpu-temp";
              on-click = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-gpu-tool.sh ${systemSettings.gpuType} ${pkgs.kitty}/bin/kitty /run/current-system/sw/bin/btop ${lactBin} ${nvidiaSettingsBin} ${intelGpuTopBin}";
              tooltip = true;
            };

            "custom/notifications" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-notifications.sh ${pkgs.swaynotificationcenter}/bin/swaync-client";
              on-click = "${pkgs.swaynotificationcenter}/bin/swaync-client -t";
              on-click-right = "${pkgs.swaynotificationcenter}/bin/swaync-client -C";
              tooltip = true;
            };

            "custom/reveal" = {
              interval = 3600;
              exec = "${pkgs.coreutils}/bin/printf '⋯'";
              tooltip = true;
              tooltip-format = "Extras (click)";
            };

            "group/extras" = {
              orientation = "inherit";
              drawer = {
                transition-duration = 200;
                children-class = "drawer-hidden";
                click-to-reveal = false;
                transition-left-to-right = false;
                hover-timeout = 8000;
              };
              modules = [ "custom/reveal" "custom/notifications" "custom/vpn" "tray" ];
            };

            "custom/flatpak-updates" = {
              return-type = "json";
              interval = 1800;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-flatpak-updates.sh ${pkgs.flatpak}/bin/flatpak";
              on-click = "${pkgs.kitty}/bin/kitty --title 'Flatpak update' -e ${pkgs.bash}/bin/bash -lc '${pkgs.flatpak}/bin/flatpak update -y; rc=$?; if [ $rc -eq 0 ]; then echo \"All Flatpaks updated. Bye bye!\"; sleep 3; exit 0; else echo \"Flatpak update failed ($rc).\"; exec ${pkgs.bash}/bin/bash; fi'";
              tooltip = true;
            };

            "custom/nixos-update" = {
              return-type = "json";
              interval = 3600;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-nixos-update.sh";
              on-click = "${pkgs.kitty}/bin/kitty --title 'Update NixOS' -e ${pkgs.bash}/bin/bash -lc '${systemSettings.installCommand}; rc=$?; if [ $rc -eq 0 ]; then echo \"Update completed. Bye bye!\"; sleep 3; exit 0; else echo \"Update failed ($rc).\"; exec ${pkgs.bash}/bin/bash; fi'";
              tooltip = true;
            };

            idle_inhibitor = {
              format = "{icon}";
              tooltip = true;
              tooltip-format = "Anfetas {status}";
              # For testing/transition: clicking the built-in module toggles the same swayidle.service
              # as the custom idle toggle + keybinding.
              on-click = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/idle-inhibit-toggle.sh";
              format-icons = {
                activated = "";
                deactivated = "";
              };
            };

            "custom/vpn" = {
              return-type = "json";
              interval = 2;
              exec = "${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/sway/scripts/waybar-vpn-wg-client.sh ${pkgs.iproute2}/bin/ip";
              on-click = "${pkgs.kitty}/bin/kitty --title 'VPN toggle' -e ${pkgs.bash}/bin/bash -lc 'if ${pkgs.iproute2}/bin/ip link show wg-client >/dev/null 2>&1; then sudo ${pkgs.wireguard-tools}/bin/wg-quick down ~/.wireguard/wg-client.conf; else sudo ${pkgs.wireguard-tools}/bin/wg-quick up ~/.wireguard/wg-client.conf; fi; rc=$?; if [ $rc -eq 0 ]; then echo \"Bye bye!\"; sleep 3; exit 0; else echo \"VPN command failed ($rc).\"; exec ${pkgs.bash}/bin/bash; fi'";
              tooltip = true;
            };

            "custom/power-menu" = {
              interval = 3600;
              exec = "${pkgs.coreutils}/bin/printf '⏻'";
              on-click = "${config.home.homeDirectory}/.config/sway/scripts/rofi-power-launch.sh";
              tooltip = true;
              tooltip-format = "Power menu";
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
        /* NOTE: A fully transparent GTK window can be flaky for :hover selectors.
           Use an almost-transparent background to make hover detection reliable. */
        background-color: rgba(0, 0, 0, 0.001);
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

      /* Per-group workspace colors are applied via Pango markup in `format-icons`
         because Waybar's CSS selector parser rejects attribute selectors. */
      
      #workspaces button:hover {
        background-color: ${hexToRgba config.lib.stylix.colors.base02 "66"};
      }
      
      #workspaces button.focused {
        /* Keep the per-group foreground color; use same background as hover */
        background-color: ${hexToRgba config.lib.stylix.colors.base02 "66"};
        box-shadow: 0 3px 12px ${hexToRgba config.lib.stylix.colors.base03 "80"}, 0 1px 4px ${hexToRgba config.lib.stylix.colors.base00 "60"};
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
      #custom-mic,
      #custom-cpu,
      #custom-gpu,
      #custom-ram,
      #custom-cpu-temp,
      #custom-gpu-temp,
      #custom-reveal,
      #custom-notifications,
      #custom-flatpak-updates,
      #custom-vpn,
      #custom-nixos-update,
      #custom-power-menu {
        margin: 4px 4px;
        padding: 4px 12px;
        border-radius: 10px;
        background-color: ${hexToRgba config.lib.stylix.colors.base01 "66"};
        color: #${config.lib.stylix.colors.base07};
        transition: all 0.2s ease;
      }

      /* Stylix color groups (left cluster) */
      #battery,
      #backlight,
      #custom-ram {
        color: #${config.lib.stylix.colors.base08};
      }

      #clock {
        color: #${config.lib.stylix.colors.base0C};
      }

      #pulseaudio,
      #custom-mic,
      #custom-flatpak-updates {
        color: #${config.lib.stylix.colors.base0C};
      }

      #custom-cpu,
      #custom-cpu-temp,
      #custom-notifications {
        color: #${config.lib.stylix.colors.base08};
      }

      #custom-gpu,
      #custom-gpu-temp {
        color: #${config.lib.stylix.colors.base0C};
      }

      #custom-power-menu {
        color: #${config.lib.stylix.colors.base08};
      }
      
      #clock:hover,
      #battery:hover,
      #network:hover,
      #pulseaudio:hover,
      #bluetooth:hover,
      #custom-perf:hover,
      #custom-mic:hover,
      #custom-cpu:hover,
      #custom-gpu:hover,
      #custom-ram:hover,
      #custom-cpu-temp:hover,
      #custom-gpu-temp:hover,
      #custom-notifications:hover,
      #custom-flatpak-updates:hover,
      #custom-vpn:hover,
      #custom-nixos-update:hover,
      #custom-power-menu:hover {
        background-color: ${hexToRgba config.lib.stylix.colors.base02 "80"};
      }

      /* Collapse notifications module when it's hidden (no notifications) */
      #custom-notifications.hidden {
        margin: 0;
        padding: 0;
        background-color: transparent;
        border-radius: 0;
      }

      /* Extras are now handled via Waybar's official group drawer (group/extras).
         Avoid CSS hover hacks for tray/notifications which are flaky in GTK CSS. */

      /* Drawer: hidden children class (configured via drawer.children-class) */
      .drawer-hidden {
        /* IMPORTANT:
         * Do NOT force opacity=0 here.
         * Waybar's group drawer uses GTK reveal/slide logic; depending on build/theme
         * the class can remain present during reveal animations (or on wrappers),
         * which would make revealed modules stay invisible.
         */
      }

      /* Drawer leader (always visible handle) */
      #custom-reveal {
        margin: 4px 4px;
        padding: 4px 12px;
        border-radius: 10px;
        background-color: ${hexToRgba config.lib.stylix.colors.base01 "66"};
        color: #${config.lib.stylix.colors.base08};
      }

      /* (custom idle toggle removed; keeping built-in idle_inhibitor only) */

      /* VPN: always visible in drawer */

      /* Idle inhibitor should stay visible even when deactivated. */

      /* Collapse flatpak module when it's hidden (no updates) */
      #custom-flatpak-updates.hidden {
        margin: 0;
        padding: 0;
        background-color: transparent;
        border-radius: 0;
      }

      /* VPN state hint */
      #custom-vpn.on {
        color: #${config.lib.stylix.colors.base0B};
        background-color: ${hexToRgba config.lib.stylix.colors.base0B "33"};
      }
      #custom-vpn.off {
        color: #${config.lib.stylix.colors.base0C};
      }

      /* Anfetas (idle inhibitor): green when enabled, white when off */
      #idle_inhibitor {
        color: #${config.lib.stylix.colors.base0C};
        transition: all 0.2s ease;
      }

      #idle_inhibitor:hover {
        background-color: ${hexToRgba config.lib.stylix.colors.base02 "66"};
        box-shadow: 0 2px 8px ${hexToRgba config.lib.stylix.colors.base03 "4D"};
      }

      #idle_inhibitor.activated {
        color: #${config.lib.stylix.colors.base0B};
        background-color: ${hexToRgba config.lib.stylix.colors.base0B "33"};
        box-shadow: 0 2px 8px ${hexToRgba config.lib.stylix.colors.base0B "4D"};
      }

      #custom-nixos-update {
        color: #${config.lib.stylix.colors.base0D};
      }

      /* Perf turns red if CPU or GPU temp >= 80C */
      #custom-perf.hot {
        color: #${config.lib.stylix.colors.base08};
        background-color: ${hexToRgba config.lib.stylix.colors.base08 "33"};
      }
      
      #clock {
        font-weight: 600;
      }
      
      /* battery color is handled by the Stylix color-group rules above */
      
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
      
      /* pulseaudio color is handled by the Stylix color-group rules above */

      /* Left cluster: render as one shared segmented pill */
      .modules-left {
        margin: 4px 4px;
        padding: 0;
        border-radius: 10px;
        background-color: ${hexToRgba config.lib.stylix.colors.base01 "66"};
      }

      #battery,
      #backlight,
      #pulseaudio,
      #custom-mic,
      #custom-cpu,
      #custom-gpu,
      #custom-ram,
      #custom-cpu-temp,
      #custom-gpu-temp {
        margin: 0;
        border-radius: 0;
        background-color: transparent;
      }

      /* No separators: fully merged pill */
      
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
        transition: all 0.2s ease;
      }

      /* Add hover effect to tray widget */
      #tray:hover {
        background-color: ${hexToRgba config.lib.stylix.colors.base02 "66"};
        box-shadow: 0 2px 8px ${hexToRgba config.lib.stylix.colors.base03 "4D"};
      }

      /* Increase spacing between tray icons */
      #tray > * {
        margin: 0 32px;  /* Increased from 24px to 32px */
        padding: 0 6px;   /* Increased padding slightly */
      }

      /* Some Waybar builds wrap tray items in buttons/widgets; cover common cases */
      #tray button {
        margin: 0 32px;   /* Match the increased spacing */
        padding: 0 6px;
        transition: all 0.2s ease;
      }

      /* Add hover effect to individual tray buttons */
      #tray button:hover {
        background-color: ${hexToRgba config.lib.stylix.colors.base02 "4D"};
        border-radius: 6px;
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
        background-color: rgba(0, 0, 0, 0.001);
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
      #backlight,
      #network,
      #pulseaudio,
      #tray,
      #bluetooth,
      #custom-perf,
      #custom-mic,
      #custom-cpu,
      #custom-gpu,
      #custom-ram,
      #custom-cpu-temp,
      #custom-gpu-temp,
      #custom-notifications,
      #custom-flatpak-updates {
        padding: 0 10px;
        color: #ffffff;
      }

      /* Noise reduction: hide by default, show on bar hover */
      #custom-notifications,
      #tray {
        opacity: 0;
        padding: 0;
      }

      window#waybar:hover #custom-notifications,
      window#waybar:hover #tray {
        opacity: 1;
        padding: 0 10px;
      }

      /* VPN: always visible in drawer */

      /* Idle inhibitor should stay visible even when deactivated. */

      /* Left cluster: render as one shared segmented pill */
      .modules-left {
        padding: 0;
        border-radius: 10px;
      }

      #battery,
      #backlight,
      #pulseaudio,
      #custom-mic,
      #custom-cpu,
      #custom-gpu,
      #custom-ram,
      #custom-cpu-temp,
      #custom-gpu-temp {
        padding-left: 10px;
        padding-right: 10px;
        margin: 0;
      }

      #backlight,
      #pulseaudio,
      #custom-mic,
      #custom-cpu,
      #custom-gpu,
      #custom-ram,
      #custom-cpu-temp,
      #custom-gpu-temp {
        border-left: 1px solid rgba(255,255,255,0.08);
      }
    '';
  };
}
