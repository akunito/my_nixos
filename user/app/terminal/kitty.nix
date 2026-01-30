{ pkgs, lib, userSettings, config, systemSettings, ... }:

let
  # Wrapper script to auto-start tmux with kitty session
  # Robust fail-safe strategy: start-server → wait for restore → attach/new-session → shell fallback
  # This ensures the user always gets a working terminal, even if systemd service fails
  kitty-tmux = pkgs.writeShellScriptBin "kitty-tmux" ''
    # Use -u flag to force UTF-8 mode for Nerd Font icon support
    TMUX="${pkgs.tmux}/bin/tmux -u"
    ZSH="${pkgs.zsh}/bin/zsh"
    DATE="${pkgs.coreutils}/bin/date"
    MKDIR="${pkgs.coreutils}/bin/mkdir"
    ID="${pkgs.coreutils}/bin/id"
    SED="${pkgs.gnused}/bin/sed"
    TMUX_CONF="''${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"

    LOG_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/tmux"
    LOG_FILE="$LOG_DIR/kitty-wrapper.log"
    $MKDIR -p "$LOG_DIR" >/dev/null 2>&1 || true

    TMUX_TMPDIR="''${TMUX_TMPDIR:-''${XDG_RUNTIME_DIR:-/run/user/$($ID -u)}}"
    export TMUX_TMPDIR

    log() {
      printf '%s %s\n' "$($DATE +"%F %T")" "$*" >>"$LOG_FILE"
    }

    log "start pid=$$"
    log "env DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY SWAYSOCK=$SWAYSOCK XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR TMUX_TMPDIR=$TMUX_TMPDIR TMUX=$TMUX"
    if [ -f "$TMUX_CONF" ]; then
      log "tmux_conf=$TMUX_CONF exists=yes"
    else
      log "tmux_conf=$TMUX_CONF exists=no"
    fi

    # Ensure tmux server is running (force config path to load plugins)
    log "tmux start-server (with -f)"
    if $TMUX -f "$TMUX_CONF" start-server >/dev/null 2>&1; then
      log "tmux start-server ok"
    else
      log "tmux start-server failed exit=$?"
    fi

    if $TMUX display-message -p -F '#{start_time}' >/dev/null 2>&1; then
      START_TIME="$($TMUX display-message -p -F '#{start_time}' 2>/dev/null || true)"
      CONTINUUM="$($TMUX show-options -gqv @continuum-restore 2>/dev/null || true)"
      RES_RESTORE="$($TMUX show-options -gqv @resurrect-restore-script-path 2>/dev/null || true)"
      RES_SAVE="$($TMUX show-options -gqv @resurrect-save-script-path 2>/dev/null || true)"
      log "tmux server start_time=$START_TIME continuum_restore=''${CONTINUUM:-unset} resurrect_restore=''${RES_RESTORE:-unset} resurrect_save=''${RES_SAVE:-unset}"
      SERVER_PATH="$($TMUX show-environment -g PATH 2>/dev/null | $SED 's/^PATH=//')"
      log "tmux server PATH=''${SERVER_PATH:-unset}"
    else
      log "tmux server not reachable after start-server"
    fi

    # Primary: attach to existing kitty session if already restored
    if $TMUX has-session -t kitty 2>/dev/null; then
      log "attach kitty (has-session)"
      exec $TMUX attach -t kitty
    fi
    log "kitty session not found"

    # CRITICAL: Trigger manual restore if no sessions exist and continuum is enabled.
    # This prevents a deadlock where continuum waits for a client attach, but we wait for sessions.
    if [ -z "$($TMUX list-sessions 2>/dev/null)" ] && [ "$CONTINUUM" = "on" ] && [ -n "$RES_RESTORE" ]; then
      log "triggering manual restore via $RES_RESTORE"
      $TMUX run-shell "$RES_RESTORE"
    fi

    # Wait for continue restore to populate sessions (avoid creating a fresh session too early)
    i=0
    while [ "$i" -lt 50 ]; do
      if $TMUX has-session -t kitty 2>/dev/null; then
        log "attach kitty (restored during wait)"
        exec $TMUX attach -t kitty
      fi

      SESSIONS="$($TMUX list-sessions -F '#S' 2>/dev/null || true)"
      log "wait loop $i: sessions=[$SESSIONS]"
      
      sleep 0.2
      i=$((i + 1))
    done

    # Fallback 1: no restored sessions, create new kitty session
    log "no restored sessions; creating kitty session"
    if $TMUX new-session -d -s kitty 2>/dev/null; then
      log "attach kitty (new-session)"
      exec $TMUX attach -t kitty
    fi
    log "tmux new-session failed exit=$?"

    # Fallback 2: If tmux fails entirely, fall back to plain shell
    log "fallback to zsh"
    exec $ZSH -l
  '';
in
{
  home.packages = with pkgs; [
    kitty
    # Explicitly install JetBrains Mono Nerd Font to ensure it's available
    nerd-fonts.jetbrains-mono
    kitty-tmux
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
      shell = "${kitty-tmux}/bin/kitty-tmux";
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
