{
  config,
  pkgs,
  lib,
  userSettings,
  systemSettings,
  ...
}:

{
  # Btop theme configuration (Stylix colors)
  # CRITICAL: Check if Stylix is actually available (not just enabled)
  # Stylix is disabled for Plasma 6 even if stylixEnable is true
  # However, if SwayFX is enabled via enableSwayForDESK, Stylix should be enabled for SwayFX
  home.file.".config/btop/btop.conf" =
    lib.mkIf
      (
        systemSettings.stylixEnable == true
        && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)
      )
      {
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

  # Libinput-gestures configuration for SwayFX
  # 3-finger swipe for workspace navigation (matches keybindings: next_on_output/prev_on_output)
  # Uses next_on_output/prev_on_output to prevent gestures from jumping between monitors
  xdg.configFile."libinput-gestures.conf".text = ''
    # Libinput-gestures configuration for SwayFX
    # 3-finger swipe for workspace navigation (matches keybindings: next_on_output/prev_on_output)

    gesture swipe left 3 ${pkgs.swayfx}/bin/swaymsg workspace next_on_output
    gesture swipe right 3 ${pkgs.swayfx}/bin/swaymsg workspace prev_on_output
    # Optional: 3-finger swipe up for fullscreen toggle
    # gesture swipe up 3 ${pkgs.swayfx}/bin/swaymsg fullscreen toggle
  '';

  # Swappy configuration (screenshot editor) - managed by Home Manager
  # Stylix integration: use Stylix font + accent color when available.
  xdg.configFile."swappy/config".text =
    let
      stylixAvailable =
        systemSettings.stylixEnable == true
        && (config ? stylix)
        && (config.stylix ? fonts)
        && (config ? lib)
        && (config.lib ? stylix)
        && (config.lib.stylix ? colors);

      # Convert 6-digit hex ("rrggbb") to rgba(r,g,b,1)
      # We keep alpha fixed at 1 because Swappy expects a single default color.
      hexToRgbaSolid =
        hex:
        let
          hexDigitToDec =
            d:
            if d == "0" then
              0
            else if d == "1" then
              1
            else if d == "2" then
              2
            else if d == "3" then
              3
            else if d == "4" then
              4
            else if d == "5" then
              5
            else if d == "6" then
              6
            else if d == "7" then
              7
            else if d == "8" then
              8
            else if d == "9" then
              9
            else if d == "a" || d == "A" then
              10
            else if d == "b" || d == "B" then
              11
            else if d == "c" || d == "C" then
              12
            else if d == "d" || d == "D" then
              13
            else if d == "e" || d == "E" then
              14
            else if d == "f" || d == "F" then
              15
            else
              0;
          hexToDec =
            hexStr:
            let
              d1 = builtins.substring 0 1 hexStr;
              d2 = builtins.substring 1 1 hexStr;
            in
            hexDigitToDec d1 * 16 + hexDigitToDec d2;
          r = hexToDec (builtins.substring 0 2 hex);
          g = hexToDec (builtins.substring 2 2 hex);
          b = hexToDec (builtins.substring 4 2 hex);
        in
        "rgba(${toString r}, ${toString g}, ${toString b}, 1)";

      saveDir = "${config.home.homeDirectory}/Pictures/Screenshots";
      fontName =
        if stylixAvailable then config.stylix.fonts.sansSerif.name else "JetBrainsMono Nerd Font";
      accentHex = if stylixAvailable then config.lib.stylix.colors.base0D else "268bd2";
    in
    lib.generators.toINI { } {
      Default = {
        save_dir = saveDir;
        save_filename_format = "swappy-%Y%m%d-%H%M%S.png";
        show_panel = false;
        line_size = 5;
        text_size = 20;
        text_font = fontName;
        custom_color = hexToRgbaSolid accentHex;
      };
    };

  # Ensure the default screenshots directory exists (used by Swappy save_dir).
  home.activation.ensureScreenshotsDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/Pictures/Screenshots" || true
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

  home.file.".config/sway/scripts/window-overview-grouped.sh" = {
    source = ./scripts/window-overview-grouped.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/rofi-power-mode.sh" = {
    source = ./scripts/rofi-power-mode.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/rofi-power-launch.sh" = {
    source = ./scripts/rofi-power-launch.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-perf.sh" = {
    source = ./scripts/waybar-perf.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-metrics.sh" = {
    source = ./scripts/waybar-metrics.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-mic.sh" = {
    source = ./scripts/waybar-mic.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-gpu-tool.sh" = {
    source = ./scripts/waybar-gpu-tool.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-flatpak-updates.sh" = {
    source = ./scripts/waybar-flatpak-updates.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-notifications.sh" = {
    source = ./scripts/waybar-notifications.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-vpn-wg-client.sh" = {
    source = ./scripts/waybar-vpn-wg-client.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-nixos-update.sh" = {
    source = ./scripts/waybar-nixos-update.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/idle-inhibit-status.sh" = {
    source = ./scripts/idle-inhibit-status.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/idle-inhibit-toggle.sh" = {
    source = ./scripts/idle-inhibit-toggle.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/swaysome-assign-groups.sh" = {
    source = ./scripts/swaysome-assign-groups.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/workspace-utils.sh" = {
    source = ./scripts/workspace-utils.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/workspace-nav-prev.sh" = {
    source = ./scripts/workspace-nav-prev.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/workspace-nav-next.sh" = {
    source = ./scripts/workspace-nav-next.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/workspace-move-prev.sh" = {
    source = ./scripts/workspace-move-prev.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/workspace-move-next.sh" = {
    source = ./scripts/workspace-move-next.sh;
    executable = true;
  };

  # Generate swaybar-toggle script with proper package paths
  home.file.".config/sway/scripts/swaybar-toggle.sh" = {
    text = ''
      #!/bin/sh
      # Toggle SwayFX's default bar (swaybar) visibility
      # The bar is disabled by default in the config (mode invisible)
      # This script allows manual toggling when needed

      # Get current bar mode
      CURRENT_MODE=$(${pkgs.swayfx}/bin/swaymsg -t get_bar_config bar-0 | ${pkgs.jq}/bin/jq -r '.mode' 2>/dev/null)

      if [ "$CURRENT_MODE" = "invisible" ] || [ -z "$CURRENT_MODE" ]; then
        # Bar is invisible or doesn't exist - show it
        ${pkgs.swayfx}/bin/swaymsg bar bar-0 mode dock
        # Optional notification (fails gracefully if libnotify not available)
        command -v notify-send >/dev/null 2>&1 && notify-send -t 2000 "Swaybar" "Bar enabled (dock mode)" || true
      else
        # Bar is visible - hide it
        ${pkgs.swayfx}/bin/swaymsg bar bar-0 mode invisible
        # Optional notification (fails gracefully if libnotify not available)
        command -v notify-send >/dev/null 2>&1 && notify-send -t 2000 "Swaybar" "Bar disabled (invisible mode)" || true
      fi
    '';
    executable = true;
  };

  # Base Sway packages (startup-app scripts are provided by `startup-apps.nix`)
  home.packages = with pkgs; [
    # SwayFX and related
    swayfx
    swaylock-effects
    swayidle
    swaynotificationcenter
    waybar # Waybar status bar (also configured via programs.waybar)
    swaysome # Workspace namespace per monitor

    # Screenshot workflow
    grim
    slurp
    swappy
    font-awesome_5 # Swappy uses Font Awesome icons

    # Gaming tools
    gamescope
    mangohud

    # Terminal and tools
    jq # CRITICAL: Required for screenshot script
    wl-clipboard
    cliphist # Clipboard history manager for Wayland

    # Touchpad gestures
    libinput-gestures

    # System tools
    networkmanagerapplet
    blueman
    polkit_gnome
    pavucontrol # GUI audio mixer (referenced in waybar config)
    gnome-themes-extra # Adwaita dark theme for GTK3 apps (fixes light mode fallback)
  ];
}
