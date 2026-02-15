# Keybindings Reference

Complete reference for all keybindings across window managers and applications in this NixOS configuration.

## Table of Contents

- [Overview](#overview)
- [Hyper Key System](#hyper-key-system)
- [Mouse Button Mapping](#mouse-button-mapping)
- [Window Manager Keybindings](#window-manager-keybindings)
- [Terminal Keybindings](#terminal-keybindings)
- [Common Keybindings](#common-keybindings)

## Overview

This configuration uses a consistent keybinding system across different window managers. The primary modifier is the **Hyper key**, which is mapped to CapsLock via the `keyd` service for system-wide keyboard remapping.

### Keybinding Philosophy

- **Hyper Key**: CapsLock acts as the primary modifier (Ctrl+Alt+Super)
- **Consistency**: Similar actions use similar keybindings across WMs
- **Application Shortcuts**: Letter-based shortcuts for quick app launching
- **Workspace Management**: Number keys for direct workspace access

## Hyper Key System

The Hyper key is the foundation of the keybinding system. It's configured via `system/wm/keyd.nix` and works at the kernel input level, making it available in all environments (Sway, Plasma, Hyprland, console, TTY, and login screens).

### Hyper Key Configuration

- **Physical Key**: CapsLock
- **Function**: Acts as Hyper (Ctrl+Alt+Super) when held, Escape when tapped
- **Configuration**: `system/wm/keyd.nix`
- **Notation**: `${hyper}` in Sway, `$mainMod` in Hyprland

### Why Hyper Key?

The Hyper key provides:
- **Non-conflicting**: Doesn't interfere with application shortcuts
- **Ergonomic**: CapsLock is easily accessible
- **System-wide**: Works everywhere, not just in window managers
- **Consistent**: Same modifier across all WMs

## Mouse Button Mapping

Mouse side buttons can be remapped to modifier combinations using keyd, providing an ergonomic way to access modifiers without using keyboard keys.

### Mouse Button Configuration

- **Physical Button**: Mouse side button (mouse1)
- **Function**: Acts as Control+Alt when held
- **Configuration**: `system/wm/keyd.nix`
- **Device Matching**: Requires explicit device IDs (keyd's `*` wildcard only matches keyboards)

### Configuration Details

The mouse button mapping uses `overload(combo_C_A, noop)` syntax:
- **`combo_C_A`**: Layer that sends Control+Alt modifiers
- **`noop`**: Dummy key that does nothing (prevents unwanted key events on release)

**Why `noop` instead of `esc`?**:
- Mouse buttons don't have a "tap" concept like keyboard keys
- Using `esc` would send Escape on every button release
- Using `noop` prevents any unwanted key events while maintaining modifier behavior

### Adding More Mice

To add mouse button mapping for additional mice:

1. Find the mouse device ID using `sudo keyd monitor` (press the side button and note the vendor:product ID)
2. Add a new entry in `system/wm/keyd.nix`:

```nix
keyboards.your_mouse = {
  ids = [ "vendor:product" ];  # Replace with your mouse's ID
  settings = {
    main = {
      mouse1 = "overload(combo_C_A, noop)";
    };
    "combo_C_A:C-A" = {
      noop = "noop";
    };
  };
};
```

### Usage

- **Hold side button**: Activates Control+Alt modifiers
- **Release side button**: Releases Control+Alt modifiers (no other keys sent)
- **Works system-wide**: Available in all applications and environments

**Example**: Hold side button + press `C` = `Ctrl+Alt+C` in any application

## Window Manager Keybindings

### SwayFX

Complete Sway keybindings reference with Hyper key notation.

**Documentation**: [Sway Keybindings](keybindings/sway.md)

**Key Features**:
- Hyper key (`${hyper}`) = CapsLock (Ctrl+Alt+Super)
- Rofi launchers (combi, calc, emoji, file browser)
- Local workspace cycling (Q/W for current monitor)
- Direct workspace access (1-0)
- Application shortcuts (T, R, L, E, D, V, G, Y, N, P, C, M, B)

### Hyprland

Complete Hyprland keybindings reference with main modifier.

**Documentation**: [Hyprland Keybindings](keybindings/hyprland.md)

**Key Features**:
- Main modifier (`$mainMod`) = SUPERCTRLALT (same as Hyper)
- Workspace controller script (`workspace-controller.sh`) - Replaces swaysome for per-monitor workspace groups
- Window movement script (`window-move.sh`) - Conditional floating/tiled logic
- App toggle script (`app-toggle.sh`) - Launch/focus/hide logic
- nwggrid application launcher
- Direct workspace access (1-0) with per-monitor workspace groups
- Special workspaces (scratchpads)
- Media controls (volume, brightness, music)

**Migration**: See [SwayFX to Hyprland Migration Guide](user-modules/sway-to-hyprland-migration.md) for script details.

## Terminal Keybindings

### Integrated Terminal Keybindings (VS Code/Cursor)

The integrated terminals in VS Code and Cursor require special keybinding configuration to ensure proper copy/paste behavior.

**Script**: `fix-terminals` - Python script to configure terminal keybindings

**Usage**:
```sh
fix-terminals
```

**What It Does**:
- Patches `keybindings.json` for VS Code and Cursor
- Adds required keybindings:
  - `Ctrl+V` → `workbench.action.terminal.paste` (when terminal focused)
  - `Ctrl+C` → `workbench.action.terminal.copySelection` (when terminal focused and text selected)

**Features**:
- **Idempotent**: Safe to run multiple times
- **Backup**: Creates `.bak` files before modifying
- **Fresh Install Support**: Creates directories if they don't exist
- **JSON Comment Support**: Handles VS Code/Cursor JSON with comments

**Module**: `user/app/terminal/fix-terminals.nix`

**Documentation**: See [Scripts Reference](scripts.md#fix-terminals) for complete usage.

### Terminal Emulator Keybindings

#### Alacritty

- `Ctrl+C` → Copy
- `Ctrl+V` → Paste
- `Ctrl+Shift+C` → Send SIGINT (original Ctrl+C)
- `Ctrl+Shift+X` → Send CAN (original Ctrl+X)
- `Ctrl+Shift+V` → Send SYN (original Ctrl+V)

**Configuration**: `user/app/terminal/alacritty.nix`

#### Kitty

Window decorations match Alacritty styling.

**Configuration**: `user/app/terminal/kitty.nix`

#### Tmux

- `?` → Display keybindings menu
- `|` → Split vertical
- `-` → Split horizontal
- `n` → Next window
- `p` → Previous window
- `c` → New window
- `,` → Rename window
- `x` → Close pane
- `&` → Close window
- `[` → Copy mode
- `]` → Paste buffer

**Configuration**: `user/app/terminal/tmux.nix`

## Common Keybindings

### Workspace Navigation

**SwayFX**:
- `${hyper}+Q` / `${hyper}+W` → Previous/Next workspace (local, current monitor)
- `${hyper}+1` through `${hyper}+0` → Direct workspace access (using `swaysome`)
- `${hyper}+Shift+1` through `${hyper}+Shift+0` → Move window to workspace (using `swaysome`)

**Hyprland**:
- `$mainMod+Q` / `$mainMod+W` → Previous/Next workspace (current monitor)
- `$mainMod+1` through `$mainMod+0` → Direct workspace access (using `workspace-controller.sh`)
- `$mainMod+Shift+1` through `$mainMod+Shift+0` → Move window to workspace (using `workspace-controller.sh`)

**Note**: Both use per-monitor workspace groups (1-10 on Mon1, 11-20 on Mon2). SwayFX uses `swaysome`, Hyprland uses `workspace-controller.sh`.

### Window Management

**Focus Navigation**:
- Sway: `${hyper}+h/j/k` → Focus left/down/up
- Hyprland: `SUPER+H/J/K/L` → Focus left/down/up/right

**Window Movement**:
- SwayFX: `${hyper}+Shift+j/colon/Shift+k/Shift+l` → Move left/right/down/up (using `window-move.sh`)
- Hyprland: `$mainMod+Shift+j/colon/Shift+k/Shift+l` → Move left/right/down/up (using `window-move.sh`)

**Note**: Both use conditional logic (floating: 5% movement, tiled: swap position)

**Window Toggles**:
- Fullscreen: `${hyper}+f` (Sway) / `SUPER+SPACE` (Hyprland)
- Floating: `${hyper}+Shift+space` (Sway) / `$mainMod+Shift+T` (Hyprland)
- Kill: `${hyper}+Escape` (Sway) / `SUPER+Q` (Hyprland)

### Application Launchers

**Sway**:
- `${hyper}+space` or `${hyper}+BackSpace` → Rofi launcher
- `${hyper}+x` → Rofi calculator
- `${hyper}+period` → Rofi emoji picker
- `${hyper}+slash` → Rofi file browser
- `${hyper}+Tab` → Window overview (Mission Control-like)

**Hyprland**:
- `SUPER+code:9` or `SUPER+code:66` → nwggrid launcher
- `SUPER+code:47` → Fuzzel launcher
- `SUPER+W` → nwg-dock

### Screenshots

**Sway**:
- `${hyper}+Shift+x` → Full screen screenshot
- `${hyper}+Shift+c` → Area selection screenshot
- `Print` → Area selection screenshot

**Hyprland**:
- `code:107` → Area selection screenshot
- `SHIFT+code:107` → Area selection (output only)
- `SUPER+code:107` → Full screen screenshot
- `CTRL+code:107` → Area selection to clipboard
- `SUPERCTRL+code:107` → Full screen to clipboard

## Related Documentation

- [Mouse Button Mapping Guide](keybindings/mouse-button-mapping.md) - Quick guide for mapping mouse buttons to modifiers
- [Scripts Reference](scripts.md) - Complete script documentation including `fix-terminals`
- [User Modules](user-modules.md) - Terminal and application modules
- [System Modules](system-modules.md) - Keyd configuration (`system/wm/keyd.nix`)

