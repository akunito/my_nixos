{ config, pkgs, lib, systemSettings, userSettings, ... }:

{
  programs.tmux = {
    enable = true;
    clock24 = true;
    keyMode = "vi";
    mouse = true;
    prefix = "C-a";  # Ctrl+A as prefix (easier than Ctrl+B)
    baseIndex = 1;
    escapeTime = 0;
    terminal = "screen-256color";  # 256-color support
    
    plugins = with pkgs.tmuxPlugins; [
      sensible  # Sensible defaults
      yank      # Better clipboard integration
      # Note: Custom menu is implemented via display-menu in extraConfig (bind ?)
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
      
      # CRITICAL: Fast navigation without prefix (Ctrl+Alt+Arrow to avoid conflict with window manager Alt key)
      # Alt key is now reserved for window manipulation in Sway
      bind -n C-M-Left select-pane -L
      bind -n C-M-Down select-pane -D
      bind -n C-M-Up select-pane -U
      bind -n C-M-Right select-pane -R
      bind -n C-M-h select-pane -L
      bind -n C-M-j select-pane -D
      bind -n C-M-k select-pane -U
      bind -n C-M-l select-pane -R
      
      # Tabs and Splits
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
      bind n next-window
      bind p previous-window
      bind c new-window -c "#{pane_current_path}"
      bind , command-prompt -I "#W" "rename-window '%%'"
      bind x kill-pane
      bind & kill-window
      
      # Keyboard shortcuts display (using tmux-menus plugin)
      # CRITICAL: Check if Stylix is actually available (not just enabled)
      # Stylix is disabled for Plasma 6 even if stylixEnable is true
      # However, if SwayFX is enabled via enableSwayForDESK, Stylix should be enabled for SwayFX
      ${if (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)) then ''
        bind ? display-menu -T "#[align=centre fg=#${config.lib.stylix.colors.base0D}]Keybindings" \
          "Split Vertical" "|" "split-window -h" \
          "Split Horizontal" "-" "split-window -v" \
          "Next Window" "n" "next-window" \
          "Previous Window" "p" "previous-window" \
          "New Window" "c" "new-window" \
          "Rename Window" "," "command-prompt -I '#W' 'rename-window %%'" \
          "Close Pane" "x" "kill-pane" \
          "Close Window" "&" "kill-window" \
          "Copy Mode" "[" "copy-mode" \
          "Paste" "]" "paste-buffer" \
          "Help" "?" "list-keys"
      '' else ''
        bind ? display-menu -T "#[align=centre fg=blue]Keybindings" \
          "Split Vertical" "|" "split-window -h" \
          "Split Horizontal" "-" "split-window -v" \
          "Next Window" "n" "next-window" \
          "Previous Window" "p" "previous-window" \
          "New Window" "c" "new-window" \
          "Rename Window" "," "command-prompt -I '#W' 'rename-window %%'" \
          "Close Pane" "x" "kill-pane" \
          "Close Window" "&" "kill-window" \
          "Copy Mode" "[" "copy-mode" \
          "Paste" "]" "paste-buffer" \
          "Help" "?" "list-keys"
      ''}
      
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
      
      # SSH session management
      set -g default-command "${pkgs.zsh}/bin/zsh -l"
      set -ga terminal-overrides ",xterm-256color:Tc"
      
      # Window navigation
      bind -r C-h select-window -t :-
      bind -r C-l select-window -t :+
    '';
  };
}

