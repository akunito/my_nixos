{ config, pkgs, lib, systemSettings, userSettings, ... }:

let
  # Clipboard command differs between macOS (pbcopy) and Linux (wl-copy)
  clipboardCmd = if pkgs.stdenv.isDarwin
    then "pbcopy"
    else "${pkgs.wl-clipboard}/bin/wl-copy";

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
    ${pkgs.tmux}/bin/tmux new-window -a -n "ssh-smart" "${ssh-smart}/bin/ssh-smart"
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
    READLINK="${pkgs.coreutils}/bin/readlink"
    LN="${pkgs.coreutils}/bin/ln"
    RM="${pkgs.coreutils}/bin/rm"
    LS="${pkgs.coreutils}/bin/ls"
    BASENAME="${pkgs.coreutils}/bin/basename"

    LOCK_DIR="''${XDG_RUNTIME_DIR:-/tmp}"
    LOCK_FILE="$LOCK_DIR/tmux-resurrect-save.lock"
    STATE_FILE="$LOCK_DIR/tmux-resurrect-save.last"

    RES_DIR="$HOME/.tmux/resurrect"
    RES_LAST="$RES_DIR/last"

    exec 9>"$LOCK_FILE"
    if ! $FLOCK -n 9; then
      exit 0
    fi

    # Don't save during the boot restore race. A save that fires while resurrect is
    # still rebuilding panes can capture 'pane' lines without the matching 'window'
    # (layout) lines. Such a file restores as even splits instead of the saved 2x2
    # layout, because restore_window_properties has no '^window' lines to apply via
    # select-layout. Skip until restore has completed (@resurrect-restored=1) or the
    # server has been up past a short grace window.
    restored="$($TMUX_BIN show-options -gqv @resurrect-restored 2>/dev/null || true)"
    if [ "$restored" != "1" ]; then
      start="$($TMUX_BIN display-message -p -F '#{start_time}' 2>/dev/null || true)"
      now0="$($DATE +%s)"
      if [ -n "$start" ] && [ "$start" -gt 0 ] 2>/dev/null; then
        if [ "$(( now0 - start ))" -lt 90 ]; then
          exit 0
        fi
      fi
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

    rc=0
    "$TMUX_SAVE" "$@" || rc=$?

    # Validate the freshly written save. A real session always produces at least one
    # 'window' (layout) line. A save with zero window lines is degraded:
    #   * panes but no windows  -> restores as even splits (mid-restore snapshot), or
    #   * no panes at all        -> an 8-byte 'state'-only file (a save/teardown race
    #                               where the session vanished mid-dump).
    # Either one, left as 'last', restores broken or blank. So if the new save has no
    # window lines, discard it and repoint 'last' at the most recent save that DOES
    # have window lines (not just the immediate previous one, in case it was already
    # clobbered by an earlier degraded save).
    new_target="$($READLINK "$RES_LAST" 2>/dev/null || true)"
    if [ -n "$new_target" ] && [ -f "$RES_DIR/$new_target" ]; then
      # NOTE: 'grep -c' PRINTS the count (0) on no match AND exits 1, so the old
      # idiom `grep -c ... || echo 0` produced the two-line string "0\n0", making
      # the `[ "$wins" -eq 0 ]` test error out ("integer expression expected").
      # As an `if` condition that error read as false, so this rollback NEVER ran
      # and degraded saves (even-splits or empty) survived as 'last'. Use `|| true`
      # (grep already prints the count) and default empty -> 0.
      wins="$($GREP -cE '^window' "$RES_DIR/$new_target" 2>/dev/null || true)"
      wins="''${wins:-0}"
      if [ "$wins" -eq 0 ]; then
        good=""
        for f in $($LS -t "$RES_DIR"/tmux_resurrect_*.txt 2>/dev/null); do
          [ "$f" = "$RES_DIR/$new_target" ] && continue
          fw="$($GREP -cE '^window' "$f" 2>/dev/null || true)"
          fw="''${fw:-0}"
          if [ "$fw" -gt 0 ]; then
            good="$f"
            break
          fi
        done
        if [ -n "$good" ]; then
          $LN -sfn "$($BASENAME "$good")" "$RES_LAST"
          $RM -f "$RES_DIR/$new_target"
        fi
      fi
    fi

    exit $rc
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

  # Wraps the tab pills onto extra status lines and stores each window's line in @row (status-format[1..4] show
  # the windows whose @row matches; line 0 is a blank margin above the bar). Up to 2 pill rows get a blank line
  # between them (lines 1,3); 3-4 rows drop the gap (lines 1-4) — tmux caps status at 5 lines.
  # Pill width = "I:" + name cut at 15 (+…) + 2 caps + 1 separator; #{w:} is display width (#{n:} counts bytes).
  # Runs from hooks on window link/unlink/rename (auto-rename fires window-renamed), client attach/resize, and
  # from the #() in status-format[0] every status-interval.
  tmux-status-rows = pkgs.writeShellScript "tmux-status-rows" ''
    T=${pkgs.tmux}/bin/tmux
    $T list-clients -F '#{client_session} #{client_width}' 2>/dev/null | while read -r s w; do
      row=1 x=0 ids=() rows=() curs=()
      while read -r i pw cur; do
        pw=$((pw + 3))
        if (( x > 0 && x + pw > w + 1 && row < 4 )); then row=$((row + 1)); x=0; fi
        x=$((x + pw))
        ids+=("$i") rows+=("$row") curs+=("$cur")
      done < <($T list-windows -t "$s" -F '#{window_index} #{w:#{?#{&&:#{@claude},#{==:#{pane_current_command},claude}},xx,#{?#{m/r:^(zsh|bash|fish|sh|claude)$,#{pane_current_command}},,xx}}#{window_index}:#{=/15/…:window_name}} #{@row}')
      gap=0; (( row <= 2 )) && gap=1
      for k in "''${!ids[@]}"; do
        line=''${rows[k]}; (( gap )) && line=$((line * 2 - 1))
        [ "''${curs[k]}" = "$line" ] || $T set -wq -t "$s:''${ids[k]}" @row "$line"
      done
      lines=$row; (( gap )) && lines=$((row * 2 - 1))
      [ "$($T show -qv -t "$s" status)" = "$((lines + 1))" ] || $T set -q -t "$s" status "$((lines + 1))"
    done
  '';

  # Ensure a detached bootstrap session exists so continuum's auto-save has a target
  # and the save-wrapper's "skip empty" guard only fires when there are no real sessions.
  # Matches the '__bootstrap' name the restore-wrapper already expects (see below).
  tmux-bootstrap-session = pkgs.writeShellScriptBin "tmux-bootstrap-session" ''
    #!/usr/bin/env bash
    TMUX_BIN="${pkgs.tmux}/bin/tmux"
    if ! "$TMUX_BIN" has-session -t __bootstrap 2>/dev/null; then
      "$TMUX_BIN" new-session -d -s __bootstrap "${pkgs.coreutils}/bin/sleep infinity"
    fi
  '';

  # Save current state if (and only if) there are real sessions. Used as ExecStop
  # so systemd saves the session before killing tmux on reboot/shutdown.
  tmux-save-on-stop = pkgs.writeShellScriptBin "tmux-save-on-stop" ''
    #!/usr/bin/env bash
    TMUX_BIN="${pkgs.tmux}/bin/tmux"
    if "$TMUX_BIN" list-sessions >/dev/null 2>&1; then
      "${tmux-resurrect-save-wrapper}/bin/tmux-resurrect-save-wrapper" quiet || true
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
    terminal = "xterm-256color";  # Better key sequence support (Home/End keys)
    
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

      # No gaps in tab numbers after closing one; new tabs (-a on every new-window binding, here and in
      # user/wm/sway/apps/common.json) open right after the current tab instead of in the first free index.
      set -g renumber-windows on

      # Wheel x3 over tmux's defaults: copy mode (shell scrollback) 15 lines per notch instead of 5; mouse-aware
      # apps (Claude Code, nvim, less) get each wheel event forwarded three times. The terminal's own scroll
      # multiplier never applies here — with mouse on, every notch reaches tmux as a single event.
      bind -T copy-mode-vi WheelUpPane select-pane \; send -X -N 15 scroll-up
      bind -T copy-mode-vi WheelDownPane select-pane \; send -X -N 15 scroll-down
      bind -T copy-mode WheelUpPane select-pane \; send -X -N 15 scroll-up
      bind -T copy-mode WheelDownPane select-pane \; send -X -N 15 scroll-down
      bind -n WheelUpPane if -F "#{||:#{alternate_on},#{pane_in_mode},#{mouse_any_flag}}" { send -M ; send -M ; send -M } { copy-mode -e }
      bind -n WheelDownPane if -F "#{||:#{alternate_on},#{pane_in_mode},#{mouse_any_flag}}" { send -M ; send -M ; send -M }

      # CRITICAL: Enable extended keys (tmux 3.2+) for proper Shift+Enter handling
      # This allows tmux to understand and forward CSI u encoded sequences
      set -s extended-keys on
      set -as terminal-features 'xterm*:extkeys'

      # Multi-line input: Forward Shift+Enter as CSI u sequence to the pane
      # Without this, tmux may consume the Shift+Enter key event
      bind -n S-Enter send-keys Escape '[13;2u'

      # CRITICAL: Clipboard integration (pbcopy on macOS, wl-copy on Linux)
      set -g set-clipboard on
      bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "${clipboardCmd}"
      bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "${clipboardCmd}"

      # Modern copy mode
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi r send-keys -X rectangle-toggle
      # Ctrl+Up/Down scrolling in copy mode
      bind-key -T copy-mode-vi C-Up send-keys -X scroll-up
      bind-key -T copy-mode-vi C-Down send-keys -X scroll-down
      
      # ============================================================================
      # BASIC NAVIGATION (with Ctrl+O prefix)
      # ============================================================================
      
      # Show keybindings menu
      ${if (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || (systemSettings.enableSwayForDESK or false) == true)) then ''
        bind h display-menu -T "#[align=centre fg=#${config.lib.stylix.colors.base0D}]Keybindings" \
          "Split Vertical" "e" "split-window -h -c '#{pane_current_path}'" \
          "Split Horizontal" "r" "split-window -v -c '#{pane_current_path}'" \
          "New Window" "t" "new-window -a -c '#{pane_current_path}'" \
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
          "New Window" "t" "new-window -a -c '#{pane_current_path}'" \
          "Next Window" "w" "next-window" \
          "Previous Window" "q" "previous-window" \
          "Rename Window" "2" "command-prompt -I '#W' 'rename-window %%'" \
          "Close Window" "z" "kill-window" \
          "Close Pane" "x" "kill-pane" \
          "Copy Mode" "[" "copy-mode" \
          "Paste" "]" "paste-buffer" \
          "Help" "?" "list-keys"
      ''}
      
      # The navigation binds below are owned by sway-apps when swayAppsEnable
      # is on (user/wm/sway/apps/common.json, section "shortcuts", kind tmux;
      # generated into ~/.config/tmux/sway-apps.conf and sourced at the end of
      # this file). They stay here as the fallback for other profiles.
      ${lib.optionalString (!(systemSettings.swayAppsEnable or false)) ''
      # Window and pane management
      bind e split-window -h -c "#{pane_current_path}"
      bind r split-window -v -c "#{pane_current_path}"
      bind t new-window -a -c "#{pane_current_path}"
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
      bind -n C-M-t new-window -a -c "#{pane_current_path}"
      bind -n C-M-w next-window
      bind -n C-M-q previous-window
      bind -n C-M-y command-prompt -I "#W" "rename-window '%%'"
      bind -n C-M-z kill-window
      bind -n C-M-x kill-pane
      
      # Scrolling
      bind -n C-M-d copy-mode
      bind -n C-M-s copy-mode -u
      # Ctrl+Up/Down for scrolling (enter copy mode and scroll)
      bind -n C-Up copy-mode \; send-keys -X scroll-up
      bind -n C-Down copy-mode \; send-keys -X scroll-down
      
      # Copy mode and paste
      bind -n C-M-[ copy-mode
      bind -n C-M-] paste-buffer
      
      # Plugin shortcuts
      # Copycat search - use the plugin's search functionality
      # Copycat uses prefix+/ by default, but we bind it to Ctrl+Alt+P
      bind -n C-M-p copy-mode \; send-keys /
      ''}
      # SSH smart launcher - open in new window for interactive selection
      bind -n C-M-a run-shell "${ssh-smart-tmux}/bin/ssh-smart-tmux"
      
      # Fast navigation menu
      ${if (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || (systemSettings.enableSwayForDESK or false) == true)) then ''
        bind -n C-M-H display-menu -T "#[align=centre fg=#${config.lib.stylix.colors.base0D}]Fast Navigation" \
          "Split Vertical" "C-M-e" "split-window -h" \
          "Split Horizontal" "C-M-r" "split-window -v" \
          "New Window" "C-M-t" "new-window -a -c '#{pane_current_path}'" \
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
          "New Window" "C-M-t" "new-window -a -c '#{pane_current_path}'" \
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
      
      # Window name = Claude Code session title while claude runs in the active pane.
      # Claude sets the pane title (OSC 2) to "<glyph> <session name>": ✳ idle, a braille spinner while busy;
      # the glyph is stripped. A manual rename turns automatic-rename off for that window, as before.
      set -g automatic-rename-format "#{?pane_in_mode,[tmux],#{?#{==:#{pane_current_command},claude},#{=50;s/^[^ ]+ //:pane_title},#{pane_current_command}}}#{?pane_dead,[dead],}"

      # Status bar with Stylix colors showing windows (tabs) and panes
      # CRITICAL: Check if Stylix is actually available (not just enabled)
      # Stylix is disabled for Plasma 6 even if stylixEnable is true
      # However, if SwayFX is enabled via enableSwayForDESK, Stylix should be enabled for SwayFX
      ${lib.optionalString (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || (systemSettings.enableSwayForDESK or false) == true)) ''
        set -g status-style "bg=#${config.lib.stylix.colors.base00},fg=#${config.lib.stylix.colors.base07}"
        # No session name (fixed per launcher: alacritty/kitty) and no clock — only the tab pills.
        set -g status-left ""
        set -g status-right ""
        # Each tab is a rounded pill (Nerd Font U+E0B6/U+E0B4 caps), name cut at 15 chars; the active one in the accent colour.
        # State icon of the active pane: Claude via @claude from .claude/hooks/tmux-claude-state.sh (hourglass busy, bell
        # needs you, check done; ignored once claude has exited), any other non-shell command = hourglass. tmux-status-rows
        # measures the same branches. Hourglass is a fixed yellow: this palette's base0A is yellow-green (#aec795).
        setw -g window-status-separator " "
        setw -g window-status-format "#[fg=#${config.lib.stylix.colors.base02},bg=#${config.lib.stylix.colors.base00}]#[fg=#${config.lib.stylix.colors.base05},bg=#${config.lib.stylix.colors.base02}]#{?#{&&:#{@claude},#{==:#{pane_current_command},claude}},#{?#{==:#{@claude},busy},#[fg=#e5c07b] ,#{?#{==:#{@claude},wait},#[fg=#${config.lib.stylix.colors.base0B}] ,#[fg=#${config.lib.stylix.colors.base0B}] }},#{?#{m/r:^(zsh|bash|fish|sh|claude)$,#{pane_current_command}},,#[fg=#e5c07b] }}#[fg=#${config.lib.stylix.colors.base05}]#I:#{=/15/…:window_name}#[fg=#${config.lib.stylix.colors.base02},bg=#${config.lib.stylix.colors.base00},nobold]"
        setw -g window-status-current-format "#[fg=#${config.lib.stylix.colors.base0D},bg=#${config.lib.stylix.colors.base00}]#[fg=#${config.lib.stylix.colors.base00},bg=#${config.lib.stylix.colors.base0D},bold]#{?#{&&:#{@claude},#{==:#{pane_current_command},claude}},#{?#{==:#{@claude},busy},#[fg=#e5c07b] ,#{?#{==:#{@claude},wait},#[fg=#${config.lib.stylix.colors.base0B}] ,#[fg=#${config.lib.stylix.colors.base0B}] }},#{?#{m/r:^(zsh|bash|fish|sh|claude)$,#{pane_current_command}},,#[fg=#e5c07b] }}#[fg=#${config.lib.stylix.colors.base00}]#I:#{=/15/…:window_name}#[fg=#${config.lib.stylix.colors.base0D},bg=#${config.lib.stylix.colors.base00},nobold]"
        # Line 0 is a blank margin between the app and the pills; rows 1-4 hold the windows whose @row matches,
        # assigned by tmux-status-rows. status = rows + 1 is set per session by the same script.
        set -g status 2
        # #() reruns the layout every status-interval: the hooks alone were lost once at runtime (2026-10-14, cause unknown)
        # and every window opened after that sat unassigned on row 1, clipped past the 7th pill. The script prints nothing.
        set -g status-format[0] "#(${tmux-status-rows})"
        set -g status-format[1] "#[align=left]#{W:#{?#{||:#{==:#{@row},},#{==:#{@row},1}},#[range=window|#{window_index}]#[push-default]#{T:window-status-format}#[pop-default]#[norange default] ,},#{?#{||:#{==:#{@row},},#{==:#{@row},1}},#[range=window|#{window_index}]#[push-default]#{T:window-status-current-format}#[pop-default]#[norange default] ,}}"
        set -g status-format[2] "#[align=left]#{W:#{?#{==:#{@row},2},#[range=window|#{window_index}]#[push-default]#{T:window-status-format}#[pop-default]#[norange default] ,},#{?#{==:#{@row},2},#[range=window|#{window_index}]#[push-default]#{T:window-status-current-format}#[pop-default]#[norange default] ,}}"
        set -g status-format[3] "#[align=left]#{W:#{?#{==:#{@row},3},#[range=window|#{window_index}]#[push-default]#{T:window-status-format}#[pop-default]#[norange default] ,},#{?#{==:#{@row},3},#[range=window|#{window_index}]#[push-default]#{T:window-status-current-format}#[pop-default]#[norange default] ,}}"
        set -g status-format[4] "#[align=left]#{W:#{?#{==:#{@row},4},#[range=window|#{window_index}]#[push-default]#{T:window-status-format}#[pop-default]#[norange default] ,},#{?#{==:#{@row},4},#[range=window|#{window_index}]#[push-default]#{T:window-status-current-format}#[pop-default]#[norange default] ,}}"
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
      # Pill rows: relayout on anything that changes the tab set, a name or the width. Indices [9] so they never replace other hooks.
      # Visiting a tab marks Claude's done/needs-you icon as read.
      set-hook -g 'session-window-changed[9]' 'if -F "#{m/r:^(done|wait)$,#{@claude}}" "set -pu @claude"'
      set-hook -g 'window-linked[9]' "run-shell -b '${tmux-status-rows}'"
      set-hook -g 'window-unlinked[9]' "run-shell -b '${tmux-status-rows}'"
      set-hook -g 'window-renamed[9]' "run-shell -b '${tmux-status-rows}'"
      set-hook -g 'client-attached[9]' "run-shell -b '${tmux-status-rows}'"
      set-hook -g 'client-resized[9]' "run-shell -b '${tmux-status-rows}'"
      set-hook -g 'client-session-changed[9]' "run-shell -b '${tmux-status-rows}'"
      run-shell -b '${tmux-status-rows}'
      
      # Save on session close/detach to prevent data loss
      # Hook to save when session is closed (all windows in session are closed)
      set-hook -g session-closed "run-shell '${tmux-resurrect-save-wrapper}/bin/tmux-resurrect-save-wrapper quiet'"
      # Hook to save when client detaches (user detaches from tmux)
      set-hook -g client-detached "run-shell '${tmux-resurrect-save-wrapper}/bin/tmux-resurrect-save-wrapper quiet'"
      
      # ============================================================================
      # PROCESS RESTORATION (tmux-resurrect)
      # ============================================================================
      
      # Restore commonly used programs when sessions are restored
      # Programs will be restarted in their default state (no internal state preserved)
      set -g @resurrect-processes 'vim nvim emacs ssh htop btop btm top less man tail watch'
      
      # Special handling for vim/neovim sessions
      # This works with vim-obsession plugin to restore editor state
      set -g @resurrect-strategy-vim 'session'
      set -g @resurrect-strategy-nvim 'session'
      
      # SSH session management
      set -g default-command "${pkgs.zsh}/bin/zsh -l"
      set -ga terminal-overrides ",xterm-256color:Tc"

      # Enable kitty image protocol passthrough for ranger previews
      set -g allow-passthrough on
      set -ga terminal-overrides ',xterm-kitty:Tc'

      ${lib.optionalString (systemSettings.swayAppsEnable or false) ''
      # sway-apps tmux shortcuts (generated; edit in the sway-apps GUI / CLI)
      source-file -q ~/.config/tmux/sway-apps.conf
      ''}
    '';
  };

  # Systemd user service to start tmux server at login (Linux only)
  # This ensures the server is running before terminals open, allowing continuum to restore sessions.
  # Persistence behaviour (ExecStop save, ExecStartPost bootstrap, periodic save timer) is gated
  # behind userSettings.tmuxPersistenceEnable so server/LXC profiles don't pick it up.
  systemd.user.services = lib.mkIf (!pkgs.stdenv.isDarwin) ({
    tmux-server = {
      Unit = {
        Description = "Tmux server";
        After = [ "sway-session.target" "graphical-session.target" ];
        # Never let a home-manager switch restart the running tmux server — that
        # kills the live session and every attached client. Restarts should only
        # happen on real login/reboot. sd-switch honours keep-old = leave running.
        "X-SwitchMethod" = "keep-old";
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
      } // lib.optionalAttrs (userSettings.tmuxPersistenceEnable or false) {
        ExecStartPost = [ "${tmux-bootstrap-session}/bin/tmux-bootstrap-session" ];
        # CRITICAL: save before systemd kills tmux on reboot/shutdown. This is what
        # gives reboot-persistence — continuum's auto-save alone is not sufficient.
        ExecStop = [ "${tmux-save-on-stop}/bin/tmux-save-on-stop" ];
        TimeoutStopSec = "10";
        KillMode = "mixed";
      };
      Install = {
        WantedBy = [ "sway-session.target" "graphical-session.target" ];
      };
    };
  } // lib.optionalAttrs (userSettings.tmuxPersistenceEnable or false) {
    # Timer-driven periodic save — decoupled from tmux's status-right hack,
    # which our extraConfig overrides and therefore disables continuum's auto-save.
    tmux-resurrect-save = {
      Unit = {
        Description = "Periodic tmux-resurrect save";
        After = [ "tmux-server.service" ];
        Requisite = [ "tmux-server.service" ];
      };
      Service = {
        Type = "oneshot";
        # CRITICAL: without TMUX_TMPDIR the wrapper can't find the server socket
        # (it lives under %t=/run/user/$UID, not /tmp), so it sees zero sessions
        # and skips EVERY periodic save — leaving 'last' to be updated only by the
        # racy detach/shutdown hooks. PATH is needed because resurrect's save.sh
        # shells out to `tmux`/`pgrep`. Mirror tmux-server.service's environment.
        Environment = [
          "TMUX_TMPDIR=%t"
          "PATH=${lib.makeBinPath [ pkgs.tmux pkgs.coreutils pkgs.procps pkgs.gnugrep pkgs.gnused pkgs.gawk pkgs.util-linux pkgs.bash pkgs.nettools pkgs.gnutar ]}"
        ];
        # "quiet": without it resurrect's save.sh runs a "Saving..." spinner + "Tmux environment saved!" in the
        # status line, and a key pressed while that message is up only dismisses it — keystrokes typed during the
        # 5-min save were swallowed (seen 2026-10-14). The prefix+C-s manual save keeps its message.
        ExecStart = "${tmux-resurrect-save-wrapper}/bin/tmux-resurrect-save-wrapper quiet";
      };
    };
  });

  systemd.user.timers = lib.mkIf (!pkgs.stdenv.isDarwin && (userSettings.tmuxPersistenceEnable or false)) {
    tmux-resurrect-save = {
      Unit = { Description = "Periodic tmux-resurrect save timer"; };
      Timer = {
        OnBootSec = "5min";
        OnUnitActiveSec = "5min";
        Unit = "tmux-resurrect-save.service";
      };
      Install = { WantedBy = [ "timers.target" ]; };
    };
  };

  # Launchd agent for tmux server on macOS
  launchd.agents = lib.mkIf pkgs.stdenv.isDarwin {
    tmux-server = {
      enable = true;
      config = {
        Label = "org.tmux.server";
        ProgramArguments = [ "${pkgs.tmux}/bin/tmux" "start-server" ];
        RunAtLoad = true;
        KeepAlive = false;
      };
    };
  };
}

