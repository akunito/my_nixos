{ pkgs, lib, userSettings, config, systemSettings, ... }:

{
  home.packages = with pkgs; [
    alacritty
    # Explicitly install JetBrains Mono Nerd Font to ensure it's available
    nerd-fonts.jetbrains-mono
  ];
  programs.alacritty.enable = true;
  programs.alacritty.settings = lib.mkMerge [
    {
      window.opacity = lib.mkForce 0.85;
      font = {
        normal = {
          # Use "JetBrainsMono Nerd Font Mono" - the exact family name as registered in the system
          # This is the monospace version which is best for terminal use
          # Verified via: fc-list : family | grep JetBrains
          family = "JetBrainsMono Nerd Font Mono";
          style = "Regular";
        };
        size = 12;
        # Font rendering settings for proper alignment
        # Disable builtin_box_drawing if font alignment issues occur
        builtin_box_drawing = false;
        offset = {
          x = 0;
          y = 0;
        };
        glyph_offset = {
          x = 0;
          y = 0;
        };
      };
      # Additional rendering settings for proper font alignment
      # Note: render_timer and use_thin_strokes are deprecated in Alacritty 0.16+
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
      
      # Auto-start tmux with persistent session
      # Attach to "alacritty" session if it exists, otherwise create it
      # Use exec so zsh is replaced by tmux, keeping the terminal alive
      shell = {
        program = "${pkgs.zsh}/bin/zsh";
        args = [ "-c" "exec ${pkgs.tmux}/bin/tmux attach -t alacritty || exec ${pkgs.tmux}/bin/tmux new -s alacritty" ];
      };
      
      # Use Ctrl+C/V for copy/paste (standard shortcuts)
      # Note: Alacritty doesn't support Cut action, so Ctrl+X is not bound
      # Ctrl+Shift+C sends SIGINT (original Ctrl+C - interrupt process)
      # CRITICAL: Alacritty 0.16+ uses [keyboard] section with bindings, not key_bindings
      keyboard = {
        bindings = [
          # Standard Copy/Paste
          { key = "C"; mods = "Control"; action = "Copy"; }  # Copy
          { key = "V"; mods = "Control"; action = "Paste"; } # Paste
          
          # Send original control characters via Ctrl+Shift
          # We use builtins.fromJSON because Nix strings don't support \u escape sequences directly,
          # but JSON does. This generates the raw control character which Home Manager serializes correctly to TOML.
          
          # Ctrl+Shift+C -> SIGINT (ASCII 0x03)
          { key = "C"; mods = "Control|Shift"; chars = builtins.fromJSON ''"\u0003"''; }
          
          # Ctrl+Shift+X -> CAN (ASCII 0x18)
          { key = "X"; mods = "Control|Shift"; chars = builtins.fromJSON ''"\u0018"''; }
          
          # Ctrl+Shift+V -> SYN (ASCII 0x16)
          { key = "V"; mods = "Control|Shift"; chars = builtins.fromJSON ''"\u0016"''; }
        ];
      };
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
