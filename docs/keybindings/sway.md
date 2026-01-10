---
id: keybindings.sway
summary: SwayFX keybindings reference, including unified rofi launcher and window overview.
tags: [sway, swayfx, keybindings, rofi, wayland]
related_files:
  - user/wm/sway/swayfx-config.nix
  - user/wm/sway/rofi.nix
  - user/wm/sway/waybar.nix
  - user/wm/sway/scripts/window-overview-grouped.sh
  - user/wm/sway/scripts/rofi-power-mode.sh
---

# SwayFX Keybindings Reference

Complete reference for all SwayFX keybindings in this NixOS configuration.

## Table of Contents

- [Overview](#overview)
- [Hyper Key](#hyper-key)
- [System](#system)
- [Launchers](#launchers)
- [Workspace Navigation](#workspace-navigation)
- [Window Management](#window-management)
- [Application Shortcuts](#application-shortcuts)
- [Media Keys](#media-keys)
- [Screenshots](#screenshots)
- [Utilities](#utilities)

## Overview

SwayFX is a fork of Sway with additional visual effects (blur, shadows, rounded corners). All keybindings use the **Hyper key** (`${hyper}`) which is mapped to CapsLock via `keyd`.

**Configuration File**: `user/wm/sway/swayfx-config.nix`

**Hyper Key Notation**: `${hyper}` = Mod4+Control+Mod1 (CapsLock via keyd)

**Reference**: See [Keyd Configuration](../../system/wm/keyd.nix) for Hyper key setup.

## Hyper Key

The Hyper key is the primary modifier for all Sway keybindings. It's configured via `system/wm/keyd.nix`:

- **Physical Key**: CapsLock
- **Function**: Hyper (Ctrl+Alt+Super) when held, Escape when tapped
- **Notation**: `${hyper}` in Sway configuration
- **System-wide**: Works in all environments (Sway, console, TTY, login)

**See Also**: [Hyper Key System](../keybindings.md#hyper-key-system)

## System

### Configuration Reload

- **`${hyper}+Shift+r`** → Reload SwayFX configuration

### Startup Applications

- **`${hyper}+Shift+Return`** → Manual startup apps launcher (`desk-startup-apps-launcher`)

### Exit

- **`${hyper}+Shift+End`** → Exit Sway (with confirmation dialog)

### Lock

- **`Mod4+l`** → Lock screen (swaylock-effects)

### Power Menu

- **`${hyper}+Shift+BackSpace`** → Power menu (rofi `power` mode)

## Launchers

### Rofi Universal Launcher

- **`${hyper}+space`** → Rofi unified combi launcher
  - Includes: `drun`, `run`, `window`, `filebrowser`, `calc`, `emoji`, `power`
  - **Tip**: In rofi, use `Ctrl+Tab` / `Ctrl+Shift+Tab` to cycle modes (so you can jump into `emoji` or `calc` quickly).

### Rofi Utilities

- **`${hyper}+x`** → Rofi calculator
- **`${hyper}+period`** → Rofi emoji picker
- **`${hyper}+slash`** → Rofi file browser

### Window Overview

- **`${hyper}+Tab`** → Window overview (Mission Control-like)
  - Grouped by app (app_id / XWayland class), then choose the specific window

### Workspace Toggle

- **`Mod4+Tab`** → Workspace back and forth (toggle between last two workspaces)

## Media Keys

### Volume

- **`XF86AudioLowerVolume`** → Lower volume (OSD via `swayosd-client`)
- **`XF86AudioRaiseVolume`** → Raise volume (OSD via `swayosd-client`)
- **`XF86AudioMute`** → Mute toggle (OSD via `swayosd-client`)
- **`${hyper}+XF86AudioMute`** → Toggle **custom idle inhibit** (systemd user `idle-inhibit.service`)
  - Shows a desktop notification with ON/OFF status
  - This is intentionally separate from Waybar’s built-in `idle_inhibitor` while testing

## Workspace Navigation

### Local Workspace Cycling

Workspace navigation is **local** (within current monitor only) to prevent workspace switching across multiple monitors.

- **`${hyper}+Q`** → Previous workspace on current monitor (`workspace prev_on_output`)
- **`${hyper}+W`** → Next workspace on current monitor (`workspace next_on_output`)
- **`${hyper}+Shift+Q`** → Move window to previous workspace on current monitor
- **`${hyper}+Shift+W`** → Move window to next workspace on current monitor

### Direct Workspace Access

Direct workspace access using `swaysome` workspace groups:

- **`${hyper}+1`** through **`${hyper}+0`** → Focus workspace relative to current monitor (11-20 on monitor 1, 21-30 on monitor 2, etc.)
- **`${hyper}+Shift+1`** through **`${hyper}+Shift+0`** → Move window to workspace relative to current monitor

### Monitor Navigation

- **`${hyper}+Left`** → Focus output left
- **`${hyper}+Right`** → Focus output right
- **`${hyper}+Up`** → Focus output up
- **`${hyper}+Down`** → Focus output down

### Move Window Between Monitors

- **`${hyper}+Shift+Left`** → Move container to output left
- **`${hyper}+Shift+Right`** → Move container to output right

## Window Management

### Focus Navigation

- **`${hyper}+h`** → Focus left
- **`${hyper}+j`** → Focus down
- **`${hyper}+k`** → Focus up
- **Note**: `${hyper}+l` removed to avoid conflict with `${hyper}+L` (Telegram)

### Window Focus Navigation (Alternative)

- **`${hyper}+Shift+comma`** → Focus left
- **`${hyper}+question`** → Focus right
- **`${hyper}+less`** → Focus down
- **`${hyper}+greater`** → Focus up

### Window Movement

Window movement uses custom scripts that handle both floating and tiled windows:

- **`${hyper}+Shift+j`** → Move window left
- **`${hyper}+colon`** → Move window right
- **`${hyper}+Shift+k`** → Move window down
- **`${hyper}+Shift+l`** → Move window up

### Window Resizing

- **`${hyper}+Shift+u`** → Resize shrink width 5 ppt
- **`${hyper}+Shift+p`** → Resize grow width 5 ppt
- **`${hyper}+Shift+i`** → Resize grow height 5 ppt
- **`${hyper}+Shift+o`** → Resize shrink height 5 ppt

### Window Toggles

- **`${hyper}+f`** → Fullscreen toggle
- **`${hyper}+Shift+space`** → Floating toggle
- **`${hyper}+Shift+f`** → Floating toggle (alternative)
- **`${hyper}+Shift+s`** → Sticky toggle
- **`${hyper}+Shift+g`** → Fullscreen toggle (alternative)
- **`${hyper}+Escape`** → Kill window

## Application Shortcuts

All application shortcuts use the `app-toggle.sh` script which toggles applications (focus if running, launch if not).

### Terminal Emulators

- **`${hyper}+T`** → Kitty (`kitty`)
- **`${hyper}+R`** → Alacritty (`alacritty`)

### Communication

- **`${hyper}+L`** → Telegram (`org.telegram.desktop`)

### File Manager

- **`${hyper}+E`** → Dolphin (`org.kde.dolphin`)

### Development Tools

- **`${hyper}+U`** → DBeaver (`io.dbeaver.DBeaverCommunity`)
- **`${hyper}+D`** → Obsidian (`obsidian`)
- **`${hyper}+C`** → Cursor (`cursor`)

### Browsers

- **`${hyper}+V`** → Vivaldi (`com.vivaldi.Vivaldi`)
- **`${hyper}+G`** → Chromium (`chromium-browser`)

### Media & Entertainment

- **`${hyper}+Y`** → Spotify (`spotify`)

### System Tools

- **`${hyper}+A`** → Pavucontrol (`pavucontrol`)
- **`${hyper}+N`** → nwg-look (`nwg-look`)
- **`${hyper}+P`** → Bitwarden (`Bitwarden`)
- **`${hyper}+M`** → Mission Center (`mission-center`)
- **`${hyper}+B`** → Bottles (`com.usebottles.bottles`)

## Screenshots

Screenshots use the `screenshot.sh` script:

- **`${hyper}+Shift+x`** → Full screen screenshot
- **`${hyper}+Shift+c`** → Area selection screenshot
- **`Print`** → Area selection screenshot

## Utilities

### Clipboard History

- **`${hyper}+Shift+v`** → Clipboard history (cliphist + rofi)
  - Opens rofi with clipboard history
  - Selected item is copied to clipboard

### Scratchpad

- **`${hyper}+minus`** → Show scratchpad
- **`${hyper}+Shift+minus`** → Move window to scratchpad
- **`${hyper}+Shift+e`** → Hide window (move to scratchpad)

### Swaybar Toggle

- **`${hyper}+Shift+Home`** → Toggle SwayFX default bar (swaybar)
  - Swaybar is disabled by default
  - Can be toggled manually if needed

## Keybinding Conflicts Avoided

The following keybindings were intentionally removed to avoid conflicts:

- **`${hyper}+d`** → Removed (conflicts with application bindings)
- **`${hyper}+l`** → Removed (conflicts with `${hyper}+L` for Telegram)
- **`${hyper}+s`** → Removed (conflicts with layout bindings)
- **`${hyper}+w`** → Removed (conflicts with `${hyper}+W` for workspace next)
- **`${hyper}+e`** → Removed (conflicts with `${hyper}+E` for Dolphin file explorer)
- **`${hyper}+a`** → Removed (conflicts with `${hyper}+A` for Pavucontrol)
- **`${hyper}+u`** → Removed (conflicts with `${hyper}+U` for DBeaver)

## Related Documentation

- [Main Keybindings Reference](../keybindings.md) - Overview and common keybindings
- [SwayFX Daemon Integration](../user-modules/sway-daemon-integration.md) - Daemon management system
- [Keyd Configuration](../../system/wm/keyd.nix) - Hyper key setup

