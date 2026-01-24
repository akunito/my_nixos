{ config, pkgs, lib, systemSettings, userSettings, ... }:

let
  # ssh-smart script: reads hosts from .ssh/config and provides interactive selection
  ssh-smart = pkgs.writeShellScriptBin "ssh-smart" ''
    #!/usr/bin/env bash
    # ssh-smart: Interactive SSH host selection from .ssh/config
    
    SSH_CONFIG="''${SSH_CONFIG:-$HOME/.ssh/config}"
    
    if [ ! -f "$SSH_CONFIG" ]; then
      echo "Error: SSH config file not found at $SSH_CONFIG" >&2
      exit 1
    fi
    
    # Extract Host entries from .ssh/config (ignoring wildcards and comments)
    # This regex matches "Host" followed by a hostname (not starting with * or ?)
    HOSTS=$(grep -E "^[[:space:]]*Host[[:space:]]+[^*?]" "$SSH_CONFIG" | \
            sed -E 's/^[[:space:]]*Host[[:space:]]+//' | \
            grep -v "^[[:space:]]*$" | \
            sort -u)
    
    if [ -z "$HOSTS" ]; then
      echo "No hosts found in $SSH_CONFIG" >&2
      exit 1
    fi
    
    # Use fzf if available, otherwise use a simple selection
    if command -v fzf >/dev/null 2>&1; then
      SELECTED=$(echo "$HOSTS" | fzf --height=40% --border --prompt="SSH to: ")
    else
      # Simple numbered selection
      echo "Available hosts:"
      echo "$HOSTS" | nl -w2 -s'. '
      echo ""
      read -p "Select host number: " SELECTION
      SELECTED=$(echo "$HOSTS" | sed -n "''${SELECTION}p")
    fi
    
    if [ -z "$SELECTED" ]; then
      echo "No host selected. Exiting." >&2
      exit 1
    fi
    
    # Connect via SSH
    exec ssh "$SELECTED" "$@"
  '';
  
  # ssh-smart-tmux: wrapper that opens ssh-smart in a new pane for interactive selection
  ssh-smart-tmux = pkgs.writeShellScriptBin "ssh-smart-tmux" ''
    #!/usr/bin/env bash
    # Wrapper to run ssh-smart in a new tmux pane for interactive selection
    ${pkgs.tmux}/bin/tmux new-window -n "ssh-smart" "${ssh-smart}/bin/ssh-smart"
  '';

  # Prevent duplicate resurrect saves in the same second (avoids broken 'last' symlink)
  tmux-resurrect-save-wrapper = pkgs.writeShellScriptBin "tmux-resurrect-save-wrapper" ''
    #!/usr/bin/env bash
    set -euo pipefail

    TMUX_SAVE="${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/save.sh"
    TMUX_BIN="${pkgs.tmux}/bin/tmux"
    DATE="${pkgs.coreutils}/bin/date"
    CAT="${pkgs.coreutils}/bin/cat"
    ECHO="${pkgs.coreutils}/bin/echo"
    GREP="${pkgs.gnugrep}/bin/grep"
    FLOCK="${pkgs.util-linux}/bin/flock"

    LOCK_DIR="''${XDG_RUNTIME_DIR:-/tmp}"
    LOCK_FILE="$LOCK_DIR/tmux-resurrect-save.lock"
    STATE_FILE="$LOCK_DIR/tmux-resurrect-save.last"

    exec 9>"$LOCK_FILE"
    if ! $FLOCK -n 9; then
      exit 0
    fi

    # Avoid overwriting 'last' with an empty save
    sessions="$($TMUX_BIN list-sessions -F '#S' 2>/dev/null || true)"
    if [ -z "$sessions" ]; then
      exit 0
    fi
    non_bootstrap="$(printf '%s\n' "$sessions" | $GREP -v '^__bootstrap$' || true)"
    if [ -z "$non_bootstrap" ]; then
      exit 0
    fi

    now="$($DATE +%s)"
    if [ -f "$STATE_FILE" ]; then
      last="$($CAT "$STATE_FILE" 2>/dev/null || true)"
      if [ -n "$last" ] && [ "$now" -le "$last" ]; then
        exit 0
      fi
    fi

    $ECHO "$now" > "$STATE_FILE"
    exec "$TMUX_SAVE" "$@"
  '';

  # Restore once per server start, triggered on first client attach
  tmux-resurrect-restore-wrapper = pkgs.writeShellScriptBin "tmux-resurrect-restore-wrapper" ''
    #!/usr/bin/env bash
    set -euo pipefail

    TMUX_BIN="${pkgs.tmux}/bin/tmux"
    DATE="${pkgs.coreutils}/bin/date"
    MKDIR="${pkgs.coreutils}/bin/mkdir"
    TAIL="${pkgs.coreutils}/bin/tail"

    LOG_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/tmux"
    LOG_FILE="$LOG_DIR/resurrect-restore.log"
    $MKDIR -p "$LOG_DIR" >/dev/null 2>&1 || true

    log() {
      printf '%s %s\n' "$($DATE +"%F %T")" "$*" >>"$LOG_FILE"
    }

    RESTORED="$($TMUX_BIN show-options -gqv @resurrect-restored 2>/dev/null || true)"
    if [ "$RESTORED" = "1" ]; then
      log "skip: already restored"
      exit 0
    fi

    BOOTSTRAP="__bootstrap"
    sessions="$($TMUX_BIN list-sessions -F '#S' 2>/dev/null || true)"
    if [ -n "$sessions" ] && [ "$sessions" != "$BOOTSTRAP" ]; then
      log "skip: sessions already present [$sessions]"
      $TMUX_BIN set -g @resurrect-restored 1
      exit 0
    fi

    RESTORE_SCRIPT="$($TMUX_BIN show-options -gqv @resurrect-restore-script-path 2>/dev/null || true)"
    if [ -z "$RESTORE_SCRIPT" ]; then
      log "restore script not set"
      exit 0
    fi

    log "running restore script $RESTORE_SCRIPT"
    if "$RESTORE_SCRIPT" >>"$LOG_FILE" 2>&1; then
      log "restore script ok"
    else
      log "restore script failed exit=$?"
    fi

    $TMUX_BIN set -g @resurrect-restored 1

    if $TMUX_BIN has-session -t kitty 2>/dev/null; then
      log "switch to kitty"
      $TMUX_BIN switch-client -t kitty || true
    else
      sessions="$($TMUX_BIN list-sessions -F '#S' 2>/dev/null || true)"
      if [ -n "$sessions" ]; then
        target="$(printf '%s\n' "$sessions" | $TAIL -n 1)"
        log "switch to last session=$target"
        $TMUX_BIN switch-client -t "$target" || true
      fi
    fi

    if $TMUX_BIN has-session -t "$BOOTSTRAP" 2>/dev/null; then
      log "kill bootstrap session"
      $TMUX_BIN kill-session -t "$BOOTSTRAP" || true
    fi
  '';

  # Fix broken resurrect 'last' symlink before tmux server starts
  tmux-resurrect-fix-last = pkgs.writeShellScriptBin "tmux-resurrect-fix-last" ''
    #!/usr/bin/env bash
    set -euo pipefail

    LS="${pkgs.coreutils}/bin/ls"
    LN="${pkgs.coreutils}/bin/ln"
    HEAD="${pkgs.coreutils}/bin/head"
    BASENAME="${pkgs.coreutils}/bin/basename"

    RES_DIR="$HOME/.tmux/resurrect"
    LAST="$RES_DIR/last"

    if [ ! -d "$RES_DIR" ]; then
      exit 0
    fi

    if [ ! -e "$LAST" ]; then
      latest="$($LS -t "$RES_DIR"/tmux_resurrect_*.txt 2>/dev/null | $HEAD -n 1 || true)"
      if [ -n "$latest" ]; then
        $LN -sfn "$($BASENAME "$latest")" "$LAST"
      fi
    fi
  '';
in
{
  home.packages = [ ssh-smart ssh-smart-tmux ];
  
  programs.tmux = {
    enable = true;
    clock24 = true;
    keyMode = "vi";
    mouse = true;
    prefix = "C-o";  # Ctrl+O as prefix
    baseIndex = 1;
    escapeTime = 0;
    terminal = "screen-256color";  # 256-color support
    
    plugins = with pkgs.tmuxPlugins; [
      sensible     # Sensible defaults
      yank         # Better clipboard integration
      copycat      # Enhanced search and copy functionality
      resurrect    # Session save/restore (required by continuum)
      continuum    # Automatic session persistence
    ];
    
    extraConfig = ''
      # CRITICAL: Mouse support
      set -g mouse on
      
      # CRITICAL: Clipboard integration with wl-clipboard
      set -g set-clipboard on
      bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "wl-copy"
      bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "wl-copy"
      
      # Modern copy mode
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi r send-keys -X rectangle-toggle
      
      # ============================================================================
      # BASIC NAVIGATION (with Ctrl+O prefix)
      # ============================================================================
      
      # Show keybindings menu
      ${if (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)) then ''
        bind h display-menu -T "#[align=centre fg=#${config.lib.stylix.colors.base0D}]Keybindings" \
          "Split Vertical" "e" "split-window -h -c '#{pane_current_path}'" \
          "Split Horizontal" "r" "split-window -v -c '#{pane_current_path}'" \
          "New Window" "t" "new-window -c '#{pane_current_path}'" \
          "Next Window" "w" "next-window" \
          "Previous Window" "q" "previous-window" \
          "Rename Window" "2" "command-prompt -I '#W' 'rename-window %%'" \
          "Close Window" "z" "kill-window" \
          "Close Pane" "x" "kill-pane" \
          "Copy Mode" "[" "copy-mode" \
          "Paste" "]" "paste-buffer" \
          "Help" "?" "list-keys"
      '' else ''
        bind h display-menu -T "#[align=centre fg=blue]Keybindings" \
          "Split Vertical" "e" "split-window -h -c '#{pane_current_path}'" \
          "Split Horizontal" "r" "split-window -v -c '#{pane_current_path}'" \
          "New Window" "t" "new-window -c '#{pane_current_path}'" \
          "Next Window" "w" "next-window" \
          "Previous Window" "q" "previous-window" \
          "Rename Window" "2" "command-prompt -I '#W' 'rename-window %%'" \
          "Close Window" "z" "kill-window" \
          "Close Pane" "x" "kill-pane" \
          "Copy Mode" "[" "copy-mode" \
          "Paste" "]" "paste-buffer" \
          "Help" "?" "list-keys"
      ''}
      
      # Window and pane management
      bind e split-window -h -c "#{pane_current_path}"
      bind r split-window -v -c "#{pane_current_path}"
      bind t new-window -c "#{pane_current_path}"
      bind w next-window
      bind q previous-window
      bind 2 command-prompt -I "#W" "rename-window '%%'"
      bind z kill-window
      bind x kill-pane
      
      # Pane navigation (vi-style)
      bind j select-pane -L
      bind k select-pane -D
      bind l select-pane -U
      bind \; select-pane -R
      
      # Copy mode and paste
      bind [ copy-mode
      bind ] paste-buffer
      
      # ============================================================================
      # FAST NAVIGATION (no prefix - Ctrl+Alt)
      # ============================================================================
      
      # Window and pane management
      bind -n C-M-e split-window -h -c "#{pane_current_path}"
      bind -n C-M-r split-window -v -c "#{pane_current_path}"
      bind -n C-M-t new-window -c "#{pane_current_path}"
      bind -n C-M-w next-window
      bind -n C-M-q previous-window
      bind -n C-M-y command-prompt -I "#W" "rename-window '%%'"
      bind -n C-M-z kill-window
      bind -n C-M-x kill-pane
      
      # Scrolling
      bind -n C-M-d copy-mode
      bind -n C-M-s copy-mode -u
      
      # Copy mode and paste
      bind -n C-M-[ copy-mode
      bind -n C-M-] paste-buffer
      
      # Plugin shortcuts
      # Copycat search - use the plugin's search functionality
      # Copycat uses prefix+/ by default, but we bind it to Ctrl+Alt+P
      bind -n C-M-p copy-mode \; send-keys /
      # SSH smart launcher - open in new window for interactive selection
      bind -n C-M-a run-shell "${ssh-smart-tmux}/bin/ssh-smart-tmux"
      
      # Fast navigation menu
      ${if (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)) then ''
        bind -n C-M-H display-menu -T "#[align=centre fg=#${config.lib.stylix.colors.base0D}]Fast Navigation" \
          "Split Vertical" "C-M-e" "split-window -h" \
          "Split Horizontal" "C-M-r" "split-window -v" \
          "New Window" "C-M-t" "new-window" \
          "Next Window" "C-M-w" "next-window" \
          "Previous Window" "C-M-q" "previous-window" \
          "Rename Window" "C-M-y" "command-prompt -I '#W' 'rename-window %%'" \
          "Close Window" "C-M-z" "kill-window" \
          "Close Pane" "C-M-x" "kill-pane" \
          "Scroll Up" "C-M-d" "copy-mode" \
          "Scroll Down" "C-M-s" "copy-mode -u" \
          "Copy Mode" "C-M-[" "copy-mode" \
          "Paste" "C-M-]" "paste-buffer" \
          "Copycat Search" "C-M-p" "copy-mode; send-keys /" \
          "SSH Smart" "C-M-a" "run-shell '${ssh-smart-tmux}/bin/ssh-smart-tmux'" \
          "Help" "?" "list-keys"
      '' else ''
        bind -n C-M-H display-menu -T "#[align=centre fg=blue]Fast Navigation" \
          "Split Vertical" "C-M-e" "split-window -h" \
          "Split Horizontal" "C-M-r" "split-window -v" \
          "New Window" "C-M-t" "new-window" \
          "Next Window" "C-M-w" "next-window" \
          "Previous Window" "C-M-q" "previous-window" \
          "Rename Window" "C-M-y" "command-prompt -I '#W' 'rename-window %%'" \
          "Close Window" "C-M-z" "kill-window" \
          "Close Pane" "C-M-x" "kill-pane" \
          "Scroll Up" "C-M-d" "copy-mode" \
          "Scroll Down" "C-M-s" "copy-mode -u" \
          "Copy Mode" "C-M-[" "copy-mode" \
          "Paste" "C-M-]" "paste-buffer" \
          "Copycat Search" "C-M-p" "copy-mode; send-keys /" \
          "SSH Smart" "C-M-a" "run-shell '${ssh-smart-tmux}/bin/ssh-smart-tmux'" \
          "Help" "?" "list-keys"
      ''}
      
      # ============================================================================
      # PANE NAVIGATION (no prefix - Ctrl+Alt)
      # ============================================================================
      
      # Pane navigation (vi-style)
      bind -n C-M-j select-pane -L
      bind -n C-M-k select-pane -D
      bind -n C-M-l select-pane -U
      bind -n C-M-\; select-pane -R
      
      # Alternative pane navigation
      bind -n C-M-f select-pane -L
      bind -n C-M-g select-pane -U
      
      # Status bar with Stylix colors showing windows (tabs) and panes
      # CRITICAL: Check if Stylix is actually available (not just enabled)
      # Stylix is disabled for Plasma 6 even if stylixEnable is true
      # However, if SwayFX is enabled via enableSwayForDESK, Stylix should be enabled for SwayFX
      ${lib.optionalString (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)) ''
        set -g status-style "bg=#${config.lib.stylix.colors.base00},fg=#${config.lib.stylix.colors.base07}"
        set -g status-left-length 40
        set -g status-right-length 80
        set -g status-left "#[fg=#${config.lib.stylix.colors.base0D}]#S "
        set -g status-right "#[fg=#${config.lib.stylix.colors.base05}]%H:%M %d-%b-%y"
        setw -g window-status-format "#[fg=#${config.lib.stylix.colors.base04}]#I:#W"
        setw -g window-status-current-format "#[fg=#${config.lib.stylix.colors.base0D}]#I:#W"
      ''}
      
      # ============================================================================
      # SESSION PERSISTENCE (tmux-continuum)
      # ============================================================================
      
      # Keep tmux server alive even when no sessions exist yet.
      # This prevents systemd start-server from exiting immediately at login.
      set -g exit-empty off

      # Save session every 5 minutes (minimal overhead, better data protection)
      set -g @continuum-save-interval '5'
      
      # Automatically restore sessions when tmux server starts
      set -g @continuum-restore 'on'

      # Allow auto-restore even if the first client attaches later
      set -g @continuum-restore-max-delay '60'
      
      # Automatically save sessions periodically
      set -g @continuum-save 'on'

      # Use a save wrapper to avoid duplicate saves in the same second
      set -g @resurrect-save-script-path "${tmux-resurrect-save-wrapper}/bin/tmux-resurrect-save-wrapper"

      # Restore on first client attach (server may start without a client)
      set-hook -g client-attached "run-shell '${tmux-resurrect-restore-wrapper}/bin/tmux-resurrect-restore-wrapper'"
      
      # Save on session close/detach to prevent data loss
      # Hook to save when session is closed (all windows in session are closed)
      set-hook -g session-closed "run-shell 'tmux show-options -g @resurrect-save-script-path 2>/dev/null | awk \"{print \\\$2}\" | xargs -r sh'"
      # Hook to save when client detaches (user detaches from tmux)
      set-hook -g client-detached "run-shell 'tmux show-options -g @resurrect-save-script-path 2>/dev/null | awk \"{print \\\$2}\" | xargs -r sh'"
      
      # SSH session management
      set -g default-command "${pkgs.zsh}/bin/zsh -l"
      set -ga terminal-overrides ",xterm-256color:Tc"
    '';
  };

  # Systemd user service to start tmux server at login
  # This ensures the server is running before terminals open, allowing continuum to restore sessions
  systemd.user.services.tmux-server = {
    Unit = {
      Description = "Tmux server";
      After = [ "sway-session.target" "graphical-session.target" ];
    };
    Service = {
      Type = "forking";
      Environment = [
        "TMUX_TMPDIR=%t"
        "PATH=${lib.makeBinPath [ pkgs.tmux pkgs.coreutils pkgs.procps pkgs.gnugrep pkgs.gnused pkgs.gawk pkgs.util-linux pkgs.bash pkgs.nettools pkgs.gnutar ]}"
      ];
      ExecStartPre = [ "${tmux-resurrect-fix-last}/bin/tmux-resurrect-fix-last" ];
      ExecStart = "${pkgs.tmux}/bin/tmux -f %h/.config/tmux/tmux.conf start-server";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "sway-session.target" "graphical-session.target" ];
    };
  };
}

