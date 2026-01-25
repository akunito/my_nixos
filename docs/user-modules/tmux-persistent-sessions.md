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

## Key Features

### 1. Automatic Restoration
Sessions are automatically restored when the tmux server starts after a reboot, without user intervention.

### 2. Duplicate Save Prevention
Custom wrapper scripts prevent multiple saves happening in the same second, which can corrupt the 'last' symlink.

### 3. Single Restore Guarantee
Sessions are restored only once per server start, preventing multiple restorations when multiple terminals connect.

### 4. Robust Fallback Strategy
Terminal wrappers implement a multi-stage fallback:
- First: Attach to existing named session (alacritty/kitty)
- Second: Wait for continuum to restore sessions
- Third: Create bootstrap session to trigger restore
- Fourth: Create new named session
- Fifth: Fall back to plain shell

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

## Benefits

- **Zero Data Loss**: Sessions are saved every 5 minutes plus on events
- **Seamless Experience**: Sessions restore automatically after reboot
- **Robust Recovery**: Multiple fallback mechanisms ensure terminals always work
- **Performance Optimized**: Efficient saving prevents system overhead
- **Reliable**: Handles edge cases like broken symlinks and duplicate saves

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