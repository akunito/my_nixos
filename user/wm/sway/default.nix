{ config, pkgs, lib, userSettings, systemSettings, ... }:

let
  # Hyper key combination (Super+Ctrl+Alt)
  hyper = "Mod4+Control+Mod1";
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
          "${hyper}+L" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh telegram-desktop";
          "${hyper}+E" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh dolphin";
          "${hyper}+T" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh kitty";
          "${hyper}+O" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh obsidian";  # Changed from D to O
          "${hyper}+V" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh vivaldi";
          "${hyper}+G" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh chromium";
          "${hyper}+Y" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh spotify";
          "${hyper}+N" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh nwg-look";  # Changed from S to N
          "${hyper}+P" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh bitwarden-desktop";
          "${hyper}+C" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh cursor";
          "${hyper}+M" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh mission-center";
          "${hyper}+B" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh bottles";
          
          # Workspace navigation
          "${hyper}+Q" = "workspace prev";
          "${hyper}+W" = "workspace next";
          "${hyper}+Shift+Q" = "move container to workspace prev";
          "${hyper}+Shift+W" = "move container to workspace next";
          
          # Direct workspace bindings
          "${hyper}+1" = "workspace number 1";
          "${hyper}+2" = "workspace number 2";
          "${hyper}+3" = "workspace number 3";
          "${hyper}+4" = "workspace number 4";
          "${hyper}+5" = "workspace number 5";
          "${hyper}+6" = "workspace number 6";
          "${hyper}+7" = "workspace number 7";
          "${hyper}+8" = "workspace number 8";
          "${hyper}+9" = "workspace number 9";
          "${hyper}+0" = "workspace number 10";
          
          # Move window to workspace (already configured above, keeping for compatibility)
          
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
        # CRITICAL: Set dark mode environment variables for XWayland apps
        {
          command = "bash -c 'export GTK_APPLICATION_PREFER_DARK_THEME=1; export GTK_THEME=Adwaita-dark; dbus-update-activation-environment --systemd GTK_APPLICATION_PREFER_DARK_THEME GTK_THEME'";
          always = true;
        }
        # Wallpaper (with Stylix safety check)
        (lib.mkIf (systemSettings.stylixEnable == true) {
          command = "swaybg -i ${config.stylix.image} -m fill";
          always = true;
        })
        {
          command = "bash ${config.home.homeDirectory}/.config/sway/scripts/debug-startup.sh";
          always = true;
        }
        {
          command = "pkill waybar; sleep 0.5; ${pkgs.waybar}/bin/waybar 2>&1 | tee -a ${config.home.homeDirectory}/.dotfiles/.cursor/debug.log &";
          always = true;
        }
        {
          command = "${pkgs.swaynotificationcenter}/bin/swaync";
          always = true;
        }
        {
          command = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
          always = true;
        }
        {
          command = "${pkgs.blueman}/bin/blueman-applet";
          always = true;
        }
        {
          command = "${pkgs.nwg-dock}/bin/nwg-dock -d -r -p bottom -i 48 -w 5 -mb 10 -hd 10 -c \"rofi -show drun\"";
          always = true;
        }
        {
          command = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
          always = true;
        }
        {
          command = "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --start --components=secrets";
          always = true;
        }
        {
          command = "${pkgs.libinput-gestures}/bin/libinput-gestures";
          always = true;
        }
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
          scale 1.15
          transform 90
          position 2400,-876
      }
      
      # Workspaces 1-10 are shared across both monitors (no explicit output assignment)
      
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

  # Home Manager packages
  home.packages = with pkgs; [
    # SwayFX and related
    swayfx
    swaylock-effects
    swayidle
    swaynotificationcenter
    waybar  # Waybar status bar (also configured via programs.waybar)
    nwg-dock  # Sway-compatible dock (Python version, NOT nwg-dock-hyprland)
    
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
    btop  # Modern system monitor (replacement for htop)
  ];
}

