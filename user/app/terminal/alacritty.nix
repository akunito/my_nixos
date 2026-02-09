{ pkgs, lib, userSettings, config, systemSettings, ... }:

let
  # Wrapper script to auto-start tmux with alacritty session
  # Robust fail-safe strategy: start-server → wait for restore → attach/new-session → shell fallback
  alacritty-tmux = pkgs.writeShellScriptBin "alacritty-tmux" ''
    TMUX="${pkgs.tmux}/bin/tmux"
    ZSH="${pkgs.zsh}/bin/zsh"
    DATE="${pkgs.coreutils}/bin/date"
    MKDIR="${pkgs.coreutils}/bin/mkdir"
    ID="${pkgs.coreutils}/bin/id"
    SED="${pkgs.gnused}/bin/sed"
    TMUX_CONF="''${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"

    LOG_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/tmux"
    LOG_FILE="$LOG_DIR/alacritty-wrapper.log"
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

    # Primary: attach to existing alacritty session if already restored
    if $TMUX has-session -t alacritty 2>/dev/null; then
      log "attach alacritty (has-session)"
      exec $TMUX attach -t alacritty
    fi
    log "alacritty session not found"

    # CRITICAL: Trigger manual restore if no sessions exist and continuum is enabled.
    # This prevents a deadlock where continuum waits for a client attach, but we wait for sessions.
    if [ -z "$($TMUX list-sessions 2>/dev/null)" ] && [ "$CONTINUUM" = "on" ] && [ -n "$RES_RESTORE" ]; then
      log "triggering manual restore via $RES_RESTORE"
      $TMUX run-shell "$RES_RESTORE"
    fi

    # Wait for continuum restore to populate sessions (avoid creating a fresh session too early)
    i=0
    while [ "$i" -lt 50 ]; do
      if $TMUX has-session -t alacritty 2>/dev/null; then
        log "attach alacritty (restored during wait)"
        exec $TMUX attach -t alacritty
      fi

      SESSIONS="$($TMUX list-sessions -F '#S' 2>/dev/null || true)"
      log "wait loop $i: sessions=[$SESSIONS]"

      sleep 0.2
      i=$((i + 1))
    done

    # Fallback 1: no restored sessions, create new alacritty session
    log "no restored sessions; creating alacritty session"
    if $TMUX new-session -d -s alacritty 2>/dev/null; then
      log "attach alacritty (new-session)"
      exec $TMUX attach -t alacritty
    fi
    log "tmux new-session failed exit=$?"

    # Fallback 2: If tmux fails entirely, fall back to plain shell
    log "fallback to zsh"
    exec $ZSH -l
  '';
in
{
  home.packages = with pkgs; [
    alacritty
    # Explicitly install JetBrains Mono Nerd Font to ensure it's available
    nerd-fonts.jetbrains-mono
    alacritty-tmux
  ];
  programs.alacritty.enable = true;
  programs.alacritty.settings = lib.mkMerge [
    {
      window.opacity = 0.85;
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
      # Use the wrapper script that falls back to zsh if tmux fails
      # CRITICAL: Use terminal.shell instead of deprecated shell
      terminal = {
        shell = {
          program = "${alacritty-tmux}/bin/alacritty-tmux";
        };
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

          # Multi-line input: Shift+Enter sends CSI u encoded escape sequence
          { key = "Return"; mods = "Shift"; chars = "\\u001b[13;2u"; }
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
