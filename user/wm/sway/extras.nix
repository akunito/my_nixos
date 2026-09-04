{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  userSettings,
  systemSettings,
  ...
}:

let
  # The compositor package this profile actually runs. MUST match
  # user/wm/sway/swayfx-config.nix and system/wm/sway.nix — home.packages below
  # installs it into the HM profile, so shipping the other one collides on
  # bin/swaybar and the whole home-manager-path build fails:
  #   pkgs.buildEnv error: two given paths contain a conflicting subpath:
  #     `.../sway-1.11/bin/swaybar' and `.../swayfx-0.5.3/bin/swaybar'
  swayPkg = if (systemSettings.swayUseSwayfx or true) then pkgs.swayfx else pkgs.sway;
in
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

    gesture swipe left 3 ${swayPkg}/bin/swaymsg workspace next_on_output
    gesture swipe right 3 ${swayPkg}/bin/swaymsg workspace prev_on_output
    # Optional: 3-finger swipe up for fullscreen toggle
    # gesture swipe up 3 ${swayPkg}/bin/swaymsg fullscreen toggle
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

  # Create default workspace-groups.conf if it doesn't exist
  # This enables the imperative GUI workflow for workspace group assignment
  home.activation.ensureWorkspaceGroupsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    WS_GROUPS_CONFIG="$HOME/.config/sway/workspace-groups.conf"
    if [ ! -f "$WS_GROUPS_CONFIG" ]; then
      mkdir -p "$(dirname "$WS_GROUPS_CONFIG")"
      cat > "$WS_GROUPS_CONFIG" << 'EOF'
# Workspace Group Configuration
# Format: MONITOR_HARDWARE_ID=GROUP_NUMBER
# Generated by sync-user.sh - edit via workspace-groups-gui (Hyper+`)
#
# Each group contains workspaces 1-10 for that monitor:
#   Group 1 = WS 11-20
#   Group 2 = WS 21-30
#   Group 3 = WS 31-40
#   etc.
#
# Use 'swaymsg -t get_outputs' to find your monitor hardware IDs
# (make + model + serial)

# Auto-assign unknown monitors
*=auto
EOF
    fi
  '';

  # Install scripts to .config/sway/scripts/
  home.file.".config/sway/scripts/screenshot.sh" = {
    source = ./scripts/screenshot.sh;
    executable = true;
  };

  # Local-LLM control surface: waybar shows the state, rofi does the acting.
  # Gated on the same flag as the waybar module, so a host with no local model
  # (LAPTOP_X13) gets neither the widget, nor the menu, nor the scripts behind
  # them — nothing to render and nothing to stumble into.
  home.file.".config/sway/scripts/waybar-llm.sh" =
    lib.mkIf (systemSettings.ollamaServerEnable or false) {
      source = ./scripts/waybar-llm.sh;
      executable = true;
    };

  home.file.".config/sway/scripts/rofi-llm-menu.sh" =
    lib.mkIf (systemSettings.ollamaServerEnable or false) {
      source = ./scripts/rofi-llm-menu.sh;
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

  home.file.".config/sway/scripts/waybar-toggle.sh" = {
    source = ./scripts/waybar-toggle.sh;
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

  home.file.".config/sway/scripts/waybar-notifications.sh" = {
    source = ./scripts/waybar-notifications.sh;
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

  home.file.".config/sway/scripts/swaysome-groups-setup.sh" = {
    source = ./scripts/swaysome-groups-setup.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/swaysome-groups-startup.sh" = {
    source = ./scripts/swaysome-groups-startup.sh;
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

  home.file.".config/sway/scripts/gamescope-wrapper.sh" = {
    source = ./scripts/gamescope-wrapper.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/gpu-session-trace.sh" = {
    source = ./scripts/gpu-session-trace.sh;
    executable = true;
  };

  # Base Sway packages (startup-app scripts are provided by `startup-apps.nix`)
  home.packages = with pkgs; [
    # The compositor (SwayFX or upstream sway — see swayPkg above)
    swayPkg
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
    #
    # gamescope comes from UNSTABLE deliberately. This profile's `pkgs` is
    # nixpkgs-stable (nixos-25.11), which is still on 3.16.17 — a version caught
    # between two 3.16.x bugs we actually hit on DESK:
    #   - its Wayland backend aborts (SIGABRT in CWaylandInputThread::ThreadFunc)
    #     partway into a Black Desert launch, killing the game ~10s in
    #   - `--force-grab-cursor`, which the whole 3.16.x line still needs to stop
    #     the camera pointing at the floor, causes multi-second freezes on mouse
    #     movement (upstream #1851)
    # Refreshing flake.lock cannot fix this, because the lock does not move the
    # stable input's package set. Unstable is eleven point releases ahead.
    pkgs-unstable.gamescope
    mangohud

    # Terminal and tools
    jq # CRITICAL: Required for screenshot script
    wl-clipboard
    cliphist # Clipboard history manager for Wayland

    # Touchpad gestures
    libinput-gestures

    # Media control
    playerctl # MPRIS media player control (play/pause/next/prev)

    # System tools
    networkmanagerapplet
    blueman
    polkit_gnome
    pavucontrol # GUI audio mixer (referenced in waybar config)
    gnome-themes-extra # Adwaita dark theme for GTK3 apps (fixes light mode fallback)
  ];
}
