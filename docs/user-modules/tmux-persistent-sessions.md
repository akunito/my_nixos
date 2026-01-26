---
id: user-modules.tmux-persistent-sessions
summary: Complete guide to tmux persistent sessions with automatic save/restore across reboots using tmux-continuum and tmux-resurrect plugins
tags: [tmux, persistent, sessions, restore, reboot, systemd, continuum, resurrect]
related_files:
  - user/app/terminal/tmux.nix
  - user/app/terminal/alacritty.nix
  - user/app/terminal/kitty.nix
  - docs/user-modules/tmux.md
key_files:
  - user/app/terminal/tmux.nix
  - docs/user-modules/tmux-persistent-sessions.md
activation_hints:
  - If setting up persistent tmux sessions across reboots
  - If troubleshooting session restoration issues
  - If modifying tmux session persistence behavior
---

# Tmux Persistent Sessions Across Reboots

## Overview

This document describes the complete solution for maintaining tmux sessions across system reboots using a combination of tmux plugins, systemd services, and custom wrapper scripts. The solution ensures that your terminal sessions, windows, and panes are automatically saved and restored after a reboot.

## Components of the Solution

### 1. Core Plugins

- **tmux-resurrect**: Saves and restores tmux sessions, including windows, panes, and current working directories
- **tmux-continuum**: Provides automatic periodic saving and automatic restoration of sessions

### 2. Systemd User Service

A systemd user service (`tmux-server.service`) starts the tmux server automatically at login, ensuring sessions can be restored before terminals connect.

### 3. Custom Wrapper Scripts

- **tmux-resurrect-save-wrapper**: Prevents duplicate saves in the same second
- **tmux-resurrect-restore-wrapper**: Ensures sessions are restored only once per server start
- **tmux-resurrect-fix-last**: Fixes broken 'last' symlink before tmux server starts
- **Terminal wrappers** (alacritty-tmux-wrapper, kitty-tmux-wrapper): Handle session attachment with fallback strategies

## How It Works

### Server Startup Sequence

1. **Systemd Service**: `tmux-server.service` starts the tmux server at login via systemd
2. **Fix Last Link**: `tmux-resurrect-fix-last` ensures the 'last' restore link points to the most recent save
3. **Server Initialization**: Tmux server loads with plugins and configuration

### Session Restoration Process

1. **Client Attachment**: When a terminal connects (via alacritty/kitty wrapper), it attempts to attach to existing sessions
2. **Restore Trigger**: The `client-attached` hook triggers `tmux-resurrect-restore-wrapper`
3. **One-Time Restore**: The restore wrapper ensures sessions are restored only once per server start
4. **Bootstrap Session**: If no sessions exist, a bootstrap session is created to trigger the restore process

### Session Persistence Process

1. **Periodic Saving**: tmux-continuum automatically saves sessions every 5 minutes
2. **Event-Based Saving**: Sessions are saved when clients detach or sessions close
3. **Duplicate Prevention**: The save wrapper prevents multiple saves in the same second
4. **Data Storage**: Session data is stored in `~/.tmux/resurrect/` directory

## What Gets Restored

### Automatically Restored ✅

1. **Session Structure**: All sessions, windows, and panes with their exact layout
2. **Working Directories**: Each pane's current working directory is preserved
3. **Pane States**: Zoomed panes, active pane, and focus positions
4. **Session Context**: Active and alternative session/window selections

### Process Restoration ✅ (Configured)

The following programs will be automatically restarted when sessions are restored:
- **Text Editors**: `vim`, `nvim`, `emacs`
- **System Monitors**: `htop`, `btop`, `btm`, `top`
- **Utilities**: `ssh`, `less`, `man`, `tail`, `watch`

**Important Notes**:
- Programs restart in their **default state** (no internal state preserved)
- For `vim`/`nvim`: Special session handling preserves open files and layouts (requires vim-obsession plugin)
- SSH connections will **not** preserve authentication or session state
- Programs with complex internal state may not restore perfectly

### NOT Restored ❌

1. **In-Session Shell History**: The command history buffer of running shells is not restored
   - However, all commands are saved to permanent history via Atuin (see below)
2. **Process Internal State**: Programs' memory state, scroll positions, filters, or interactive modes
3. **TTY Output**: Terminal scrollback buffer and displayed content
4. **Network Connections**: Active SSH sessions, tunnels, or forwarded ports

## Shell History Solution

While tmux-resurrect cannot restore the in-session shell history buffer, this configuration uses **Atuin** for superior shell history management:

- **Auto-Sync**: History syncs every 5 minutes and on every command
- **Cross-Session**: All commands are immediately available in all tmux panes
- **Cloud Backup**: History is backed up to Atuin's cloud service
- **Smart Search**: Press `Ctrl+R` or `↑` to search through complete history
- **Context Aware**: Maintains command context including directories and exit codes

This means even if a pane is restored fresh, you have instant access to your complete command history across all sessions and machines.

## Key Features

### 1. Automatic Restoration
Sessions are automatically restored when the tmux server starts after a reboot, without user intervention.

### 2. Duplicate Save Prevention
Custom wrapper scripts prevent multiple saves happening in the same second, which can corrupt the 'last' symlink.

### 3. Single Restore Guarantee
Sessions are restored only once per server start, preventing multiple restorations when multiple terminals connect.

### 4. Robust Fallback Strategy
Terminal wrappers implement a smart deadlock-breaking strategy:
1.  **Check for Session**: Checks if the specific session (`kitty` or `alacritty`) already exists.
2.  **Manual Restore Trigger**: If *no* sessions exist, the wrapper explicitly triggers the `tmux-resurrect` restore script. This breaks the "deadlock" where `continuum` waits for a client attach while the wrapper waits for sessions.
3.  **Wait Loop**: Waits for the specific named session to appear (up to 10s).
4.  **Strict Attachment**: Attaches *only* to the matching session (Kitty -> `kitty`, Alacritty -> `alacritty`).
5.  **Creation Fallback**: If the session never appears (first run), it creates a new one with the correct name.
6.  **Shell Fallback**: If all else fails, falls back to a plain Zsh shell.

### 5. Broken Link Repair
The fix-last script repairs broken 'last' symlinks before the server starts, ensuring reliable restoration.

## Configuration Details

### Tmux Configuration (from tmux.nix)

```bash
# Session persistence settings
set -g @continuum-save-interval '5'           # Save every 5 minutes
set -g @continuum-restore 'on'                # Auto-restore on server start
set -g @continuum-restore-max-delay '60'      # Max delay for first client restore
set -g @continuum-save 'on'                   # Enable auto-saving

# Custom script paths
set -g @resurrect-save-script-path "${tmux-resurrect-save-wrapper}/bin/tmux-resurrect-save-wrapper"
set -g @resurrect-restore-script-path "${tmux-resurrect-restore-wrapper}/bin/tmux-resurrect-restore-wrapper"

# Process restoration settings
set -g @resurrect-processes 'vim nvim emacs ssh htop btop btm top less man tail watch'
set -g @resurrect-strategy-vim 'session'
set -g @resurrect-strategy-nvim 'session'

# Hooks for event-based saving
set-hook -g client-attached "run-shell '${tmux-resurrect-restore-wrapper}/bin/tmux-resurrect-restore-wrapper'"
set-hook -g session-closed "run-shell 'tmux show-options -g @resurrect-save-script-path 2>/dev/null | awk \"{print \$2}\" | xargs -r sh'"
set-hook -g client-detached "run-shell 'tmux show-options -g @resurrect-save-script-path 2>/dev/null | awk \"{print \$2}\" | xargs -r sh'"
```

### Systemd Service Configuration

```nix
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
    WantedBy = [ "sway-session.target" "graphual-session.target" ];
  };
};
```

## Troubleshooting

### Common Issues

1. **Sessions not restoring after reboot**:
   - Check if `tmux-server.service` is running: `systemctl --user status tmux-server`
   - Verify resurrection files exist in `~/.tmux/resurrect/`
   - Check logs in `~/.cache/tmux/resurrect-restore.log`

2. **Duplicate saves causing corruption**:
   - The save wrapper should prevent this, but check `~/.cache/tmux/tmux-resurrect-save.last`

3. **Terminal not attaching to restored sessions**:
   - Check wrapper logs in `~/.cache/tmux/alacritty-wrapper.log` or `~/.cache/tmux/kitty-wrapper.log`

### Log Files Location

- Tmux server restore logs: `~/.cache/tmux/resurrect-restore.log`
- Alacritty wrapper logs: `~/.cache/tmux/alacritty-wrapper.log`
- Kitty wrapper logs: `~/.cache/tmux/kitty-wrapper.log`

### 5. Benefits

- **Zero Data Loss**: Sessions are saved every 5 minutes plus on events
- **Seamless Experience**: Sessions restore automatically after reboot
- **Robust Recovery**: Multiple fallback mechanisms ensure terminals always work
- **Performance Optimized**: Efficient saving prevents system overhead
- **Reliable**: Handles edge cases like broken symlinks and duplicate saves

## User Guide: How to Use

This feature works automatically in the background. You do not need to manually save or restore sessions under normal modifications.

### Automatic Behavior
1.  **On Reboot**: Just open your terminal (Kitty or Alacritty). The wrapper will automatically find and restore your previous session.
2.  **On Close**: Closing a window or detaching automatically triggers a save.
3.  **On Work**: Your environment is auto-saved every 5 minutes.

### Manual Override (Optional)
If you need to force a save state immediately (e.g., right before a risky operation):
- Press `Ctrl + O` (Prefix) then `Ctrl + S`.
- To manually restore (if needed): `Ctrl + O` then `Ctrl + R`.

### Strict Separation
- **Kitty** will always load the `kitty` tmux session.
- **Alacritty** will always load the `alacritty` tmux session.
- They operate independently, so you can have different work contexts in each terminal.

## Integration Points

This solution integrates with:
- **SwayFX sessions** via `sway-session.target`
- **Graphical sessions** via `graphical-session.target`
- **Alacritty and Kitty terminals** via wrapper scripts
- **Stylix theming** for consistent appearance
- **Systemd user services** for reliable startup

## Related Documentation

- [Tmux Module Documentation](tmux.md) - General tmux configuration
- [Terminal Configuration](../keybindings.md) - Terminal keybindings and setup
- [Systemd User Services](../user-modules/sway-daemon-integration.md) - Sway session services integration