{ pkgs, lib, userSettings, config, systemSettings, ... }:

{
  home.packages = with pkgs; [
    alacritty
  ];
  programs.alacritty.enable = true;
  programs.alacritty.settings = lib.mkMerge [
    {
      window.opacity = lib.mkForce 0.85;
      font = {
        normal = {
          family = userSettings.font;
          style = "Regular";
        };
        size = 12;
        # Font rendering settings for proper alignment
        builtin_box_drawing = true;
        offset = {
          x = 0;
          y = 0;
        };
        glyph_offset = {
          x = 0;
          y = 0;
        };
      };
      # Font rendering options for better alignment
      render_timer = false;
      use_thin_strokes = true;
      # Additional rendering settings for proper font alignment
      debug.render_timer = false;
      debug.highlight_damage = false;
      
      # CRITICAL: Disable audio bell
      bell = {
        animation = "EaseOutExpo";
        duration = 0;
      };
      
      # CRITICAL: Ensure Alt keys pass through to applications (Tmux)
      # Do not define any keybindings that capture Alt combinations
      # Let Alt keys pass through to Tmux for Alt+Arrow navigation
      
      # Use Ctrl+X/C/V for cut/copy/paste (standard shortcuts)
      # Ctrl+Shift+C sends SIGINT (original Ctrl+C - interrupt process)
      key_bindings = [
        { key = "X"; mods = "Control"; action = "Copy"; }  # Cut (copy selection)
        { key = "C"; mods = "Control"; action = "Copy"; }  # Copy
        { key = "V"; mods = "Control"; action = "Paste"; } # Paste
        # Send original control characters via Ctrl+Shift (for SIGINT and other functions)
        { key = "C"; mods = "Control|Shift"; chars = "\x03"; }  # SIGINT (original Ctrl+C - interrupt process)
        { key = "X"; mods = "Control|Shift"; chars = "\x18"; }  # Original Ctrl+X
        { key = "V"; mods = "Control|Shift"; chars = "\x16"; }  # Original Ctrl+V
      ];
    }
    # CRITICAL: Check if Stylix is actually available (not just enabled)
    # Stylix is disabled for Plasma 6 even if stylixEnable is true
    # However, if SwayFX is enabled via enableSwayForDESK, Stylix should be enabled for SwayFX
    (lib.mkIf (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)) {
      # Stylix color integration
      colors = {
        primary = {
          background = "#${config.lib.stylix.colors.base00}";
          foreground = "#${config.lib.stylix.colors.base07}";
        };
        cursor = {
          text = "#${config.lib.stylix.colors.base00}";
          cursor = "#${config.lib.stylix.colors.base07}";
        };
        selection = {
          text = "#${config.lib.stylix.colors.base07}";
          background = "#${config.lib.stylix.colors.base0D}";
        };
        normal = {
          black = "#${config.lib.stylix.colors.base00}";
          red = "#${config.lib.stylix.colors.base08}";
          green = "#${config.lib.stylix.colors.base0B}";
          yellow = "#${config.lib.stylix.colors.base0A}";
          blue = "#${config.lib.stylix.colors.base0D}";
          magenta = "#${config.lib.stylix.colors.base0E}";
          cyan = "#${config.lib.stylix.colors.base0C}";
          white = "#${config.lib.stylix.colors.base05}";
        };
        bright = {
          black = "#${config.lib.stylix.colors.base03}";
          red = "#${config.lib.stylix.colors.base08}";
          green = "#${config.lib.stylix.colors.base0B}";
          yellow = "#${config.lib.stylix.colors.base0A}";
          blue = "#${config.lib.stylix.colors.base0D}";
          magenta = "#${config.lib.stylix.colors.base0E}";
          cyan = "#${config.lib.stylix.colors.base0C}";
          white = "#${config.lib.stylix.colors.base07}";
        };
      };
    })
  ];
}
