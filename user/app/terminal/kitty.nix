{ pkgs, lib, userSettings, config, systemSettings, ... }:

{
  home.packages = with pkgs; [
    kitty
  ];
  programs.kitty.enable = true;
  programs.kitty.settings = lib.mkMerge [
    {
      background_opacity = lib.mkForce "0.85";
      modify_font = "cell_width 90%";
      # Window decorations - match Alacritty (default shows decorations, window manager handles styling)
      hide_window_decorations = "no"; # Show window decorations like Alacritty
      window_border_width = "0"; # No border (window manager handles it)
      window_margin_width = "0"; # No margin
      font_size = "12";
      font_family = userSettings.font;
      
      # CRITICAL: Disable audio bell
      enable_audio_bell = false;
      
      # CRITICAL: Ensure Alt keys pass through to applications (Tmux)
      # Do not define any keybindings that capture Alt combinations
      # Let Alt keys pass through to Tmux for Alt+Arrow navigation
      
      # Socket listener for automation
      allow_remote_control = "yes";
      listen_on = "unix:/tmp/mykitty";
    }
    (lib.mkIf (systemSettings.stylixEnable == true) {
      # Stylix color integration (matching Alacritty)
      foreground = "#${config.lib.stylix.colors.base07}";
      background = "#${config.lib.stylix.colors.base00}";
      selection_foreground = "#${config.lib.stylix.colors.base07}";
      selection_background = "#${config.lib.stylix.colors.base0D}";
      # Cursor colors to match Alacritty
      cursor = "#${config.lib.stylix.colors.base07}";
      cursor_text_color = "#${config.lib.stylix.colors.base00}";
      # Normal colors (0-7) - matching Alacritty's normal colors
      color0 = "#${config.lib.stylix.colors.base00}";   # black
      color1 = "#${config.lib.stylix.colors.base08}";   # red
      color2 = "#${config.lib.stylix.colors.base0B}";   # green
      color3 = "#${config.lib.stylix.colors.base0A}";   # yellow
      color4 = "#${config.lib.stylix.colors.base0D}";   # blue
      color5 = "#${config.lib.stylix.colors.base0E}";   # magenta
      color6 = "#${config.lib.stylix.colors.base0C}";   # cyan
      color7 = "#${config.lib.stylix.colors.base05}";   # white
      # Bright colors (8-15) - matching Alacritty's bright colors
      color8 = "#${config.lib.stylix.colors.base03}";   # bright black
      color9 = "#${config.lib.stylix.colors.base08}";   # bright red
      color10 = "#${config.lib.stylix.colors.base0B}";  # bright green
      color11 = "#${config.lib.stylix.colors.base0A}";  # bright yellow
      color12 = "#${config.lib.stylix.colors.base0D}";  # bright blue
      color13 = "#${config.lib.stylix.colors.base0E}";  # bright magenta
      color14 = "#${config.lib.stylix.colors.base0C}";  # bright cyan
      color15 = "#${config.lib.stylix.colors.base07}";  # bright white
    })
  ];
  programs.kitty.keybindings = {
    # Use Ctrl+X/C/V for cut/copy/paste (standard shortcuts)
    "ctrl+x" = "copy_to_clipboard";  # Cut (copy selection)
    "ctrl+c" = "copy_to_clipboard";  # Copy
    "ctrl+v" = "paste_from_clipboard";  # Paste
    # Send original control characters via Ctrl+Shift (for SIGINT and other functions)
    "ctrl+shift+c" = "send_text all \\x03";  # SIGINT (original Ctrl+C - interrupt process)
    "ctrl+shift+x" = "send_text all \\x18";  # Original Ctrl+X
    "ctrl+shift+v" = "send_text all \\x16";  # Original Ctrl+V
  };
}
