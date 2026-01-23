{ pkgs, lib, userSettings, config, systemSettings, ... }:

let
  # Wrapper script to auto-start tmux with kitty session
  # Robust fail-safe strategy: attach → new-session → plain shell
  # This ensures the user always gets a working terminal, even if systemd service fails
  kitty-tmux-wrapper = pkgs.writeShellScriptBin "kitty-tmux-wrapper" ''
    # Primary: Try to attach to existing kitty session (restored by continuum or already running)
    if ${pkgs.tmux}/bin/tmux has-session -t kitty 2>/dev/null; then
      exec ${pkgs.tmux}/bin/tmux attach -t kitty
    # Fallback 1: If attach fails (server down or no session), create new kitty session
    elif ${pkgs.tmux}/bin/tmux new-session -d -s kitty 2>/dev/null; then
      exec ${pkgs.tmux}/bin/tmux attach -t kitty
    # Fallback 2: If tmux fails entirely, fall back to plain shell
    # This prevents terminal denial-of-service if systemd service fails
    else
      exec ${pkgs.zsh}/bin/zsh -l
    fi
  '';
in
{
  home.packages = with pkgs; [
    kitty
    # Explicitly install JetBrains Mono Nerd Font to ensure it's available
    nerd-fonts.jetbrains-mono
    kitty-tmux-wrapper
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
      # Use "JetBrainsMono Nerd Font Mono" - the exact family name as registered in the system
      # This matches the fix applied to Alacritty
      # Intel One Mono may not be available or correctly named in fontconfig
      font_family = "JetBrainsMono Nerd Font Mono";
      
      # CRITICAL: Disable audio bell
      enable_audio_bell = false;
      
      # CRITICAL: Ensure Alt keys pass through to applications (Tmux)
      # Do not define any keybindings that capture Alt combinations
      # Let Alt keys pass through to Tmux for Alt+Arrow navigation
      
      # Socket listener for automation
      allow_remote_control = "yes";
      listen_on = "unix:/tmp/mykitty";
      
      # Auto-start tmux with persistent session
      # Attach to "kitty" session if it exists, otherwise create it
      # Use the wrapper script that execs tmux, replacing the shell
      shell = "${kitty-tmux-wrapper}/bin/kitty-tmux-wrapper";
    }
    # CRITICAL: Check if Stylix is actually available (not just enabled)
    # Stylix is disabled for Plasma 6 even if stylixEnable is true
    # However, if SwayFX is enabled via enableSwayForDESK, Stylix should be enabled for SwayFX
    (lib.mkIf (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)) {
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
    # Smart Copy/Paste behavior (similar to VS Code)
    # Ctrl+C: If text is selected, copies it. If no text is selected, sends SIGINT (interrupt signal)
    "ctrl+c" = "copy_or_interrupt";
    # Ctrl+V: Paste from clipboard
    "ctrl+v" = "paste_from_clipboard";
    # Send original control characters via Ctrl+Shift (for explicit SIGINT and other functions)
    "ctrl+shift+c" = "send_text all \\x03";  # Always send SIGINT (original Ctrl+C - interrupt process)
    "ctrl+shift+x" = "send_text all \\x18";  # Original Ctrl+X
    "ctrl+shift+v" = "send_text all \\x16";  # Original Ctrl+V
  };
}
