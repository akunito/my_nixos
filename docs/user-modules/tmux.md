---
id: user-modules.tmux
summary: Tmux terminal multiplexer module with custom keybindings, SSH smart launcher, and Stylix integration for modern terminal workflow.
tags: [tmux, terminal, multiplexer, ssh, keybindings, user-modules, stylix]
related_files:
  - user/app/terminal/tmux.nix
  - docs/user-modules/tmux.md
key_files:
  - user/app/terminal/tmux.nix
  - docs/user-modules/tmux.md
activation_hints:
  - If modifying tmux keybindings, plugins, or SSH integration
---

# Tmux Terminal Multiplexer

## What is Tmux?

[Tmux](https://github.com/tmux/tmux) is a terminal multiplexer that allows you to create, access, and control multiple terminal sessions from a single window. It enables persistent sessions, window splitting, and advanced terminal workflows.

![Tmux Screenshot](https://raw.githubusercontent.com/librephoenix/nixos-config-screenshots/main/app/tmux.png)

Key benefits include:
- **Persistent sessions** - Keep terminal sessions running even after logout
- **Window splitting** - Multiple panes in a single window
- **Session management** - Detach and reattach to sessions
- **Scriptable** - Automate complex terminal workflows

## Configuration

This tmux configuration is optimized for modern terminal usage with:

- **Vi-style keybindings** for efficient navigation
- **Custom prefix** (`Ctrl+O`) to avoid conflicts with other tools
- **Smart SSH launcher** with fzf integration
- **Stylix theme integration** for consistent colors
- **Enhanced clipboard support** with wl-clipboard
- **Plugin ecosystem** (sensible, yank, copycat)

### Core Plugins

- **sensible** - Sensible defaults for tmux
- **yank** - Better clipboard integration
- **copycat** - Enhanced search and copy functionality
- **resurrect** - Session save/restore functionality
- **continuum** - Automatic session persistence (saves every 5 minutes)

### Custom Scripts

- **ssh-smart** - Interactive SSH host selection from `~/.ssh/config`
- **ssh-smart-tmux** - Launch SSH selection in new tmux window

## Keybindings

### Basic Navigation (Ctrl+O prefix)

| Key | Action |
|-----|--------|
| `e` | Split window horizontally |
| `r` | Split window vertically |
| `t` | New window |
| `w` | Next window |
| `q` | Previous window |
| `2` | Rename window |
| `z` | Kill window |
| `x` | Kill pane |
| `h` | Show keybindings menu |

### Vi-style Pane Navigation

| Key | Action |
|-----|--------|
| `j` | Select left pane |
| `k` | Select bottom pane |
| `l` | Select top pane |
| `;` | Select right pane |

### Copy Mode (Vi-style)

| Key | Action |
|-----|--------|
| `[` | Enter copy mode |
| `]` | Paste buffer |
| `v` | Begin selection |
| `r` | Toggle rectangle selection |
| `y` | Copy (in copy mode) |

### Fast Navigation (Ctrl+Alt - no prefix)

| Key | Action |
|-----|--------|
| `C-M-e` | Split horizontal |
| `C-M-r` | Split vertical |
| `C-M-t` | New window |
| `C-M-w` | Next window |
| `C-M-q` | Previous window |
| `C-M-y` | Rename window |
| `C-M-z` | Kill window |
| `C-M-x` | Kill pane |
| `C-M-d` | Copy mode |
| `C-M-s` | Copy mode (up) |
| `C-M-[` | Copy mode |
| `C-M-]` | Paste |
| `C-M-p` | Copycat search |
| `C-M-a` | SSH smart launcher |
| `C-M-H` | Show fast navigation menu |

### Pane Navigation (Ctrl+Alt)

| Key | Action |
|-----|--------|
| `C-M-j` | Left pane |
| `C-M-k` | Down pane |
| `C-M-l` | Up pane |
| `C-M-;` | Right pane |
| `C-M-f` | Left pane (alternative) |
| `C-M-g` | Up pane (alternative) |

## SSH Integration

The configuration includes smart SSH tools:

- **ssh-smart** - Interactive host selection using fzf or numbered menu
- **ssh-smart-tmux** - Opens SSH selection in new tmux window
- Reads hosts from `~/.ssh/config` automatically
- Supports both fzf (preferred) and fallback selection

## Stylix Integration

When Stylix is enabled and SwayFX is active (not Plasma 6), tmux automatically:
- Uses Stylix colors for status bar
- Applies theme colors to menus and displays
- Maintains visual consistency with desktop theme

## Session Persistence

Tmux sessions are automatically saved and restored across reboots:

- **Automatic saving**: Sessions are saved every 5 minutes in the background
- **Save on close**: Sessions are automatically saved when:
  - All windows in a session are closed
  - You detach from tmux
- **Automatic restore**: Sessions are automatically restored when tmux starts after a reboot
- **Save location**: `~/.tmux/resurrect/`

This ensures minimal data loss and seamless session recovery. The 5-minute interval provides a good balance between data protection and performance overhead.

### Manual Control

You can also manually save/restore sessions:
- **Manual save**: `Ctrl+O` then `Ctrl+S` (via tmux-resurrect)
- **Manual restore**: `Ctrl+O` then `Ctrl+R` (via tmux-resurrect)

## Integration

The Tmux module is integrated into the user configuration and can be enabled in profiles. See [User Modules Guide](README.md) for details.

## Related Documentation

- [User Modules Guide](README.md) - User-level modules overview
- [Keybindings Guide](../keybindings.md) - General keybinding reference

**Related Documentation**: See [user/app/terminal/tmux.nix](../../../user/app/terminal/tmux.nix) for the complete NixOS/Home Manager configuration.
