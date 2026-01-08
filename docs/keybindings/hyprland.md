# Hyprland Keybindings Reference

Complete reference for all Hyprland keybindings in this NixOS configuration.

## Table of Contents

- [Overview](#overview)
- [Main Modifier](#main-modifier)
- [System](#system)
- [Launchers](#launchers)
- [Workspace Navigation](#workspace-navigation)
- [Window Management](#window-management)
- [Application Shortcuts](#application-shortcuts)
- [Screenshots](#screenshots)
- [Media Controls](#media-controls)
- [Special Workspaces](#special-workspaces)

## Overview

Hyprland is a dynamic tiling Wayland compositor. All keybindings use the **main modifier** (`$mainMod`) which is equivalent to the Hyper key (SUPERCTRLALT).

**Configuration File**: `user/wm/hyprland/hyprland.nix`

**Main Modifier**: `$mainMod` = SUPERCTRLALT (same as Hyper)

**Reference**: See [Keyd Configuration](../../system/wm/keyd.nix) for Hyper key setup.

## Main Modifier

The main modifier is the primary modifier for all Hyprland keybindings. It's equivalent to the Hyper key:

- **Definition**: `$mainMod = SUPERCTRLALT`
- **Physical Key**: CapsLock (via keyd)
- **Notation**: `$mainMod` in Hyprland configuration
- **System-wide**: Works in all environments (Hyprland, console, TTY, login)

**See Also**: [Hyper Key System](../keybindings.md#hyper-key-system)

## System

### Kill Window

- **`SUPER+Q`** → Kill active window
- **`CTRL+ALT+Delete`** → Kill active window (alternative)
- **`SUPER+Shift+K`** → Kill active window (alternative)

### Exit Hyprland

- **`SUPER+Shift+Q`** → Exit Hyprland

### Suspend

- **`SUPER+Shift+S`** → Suspend system

### Lock Session

- **`SUPER+CTRL+L`** → Lock session (loginctl)
- **`Lid Switch`** → Lock session on lid close

## Launchers

### Application Launchers

- **`SUPER+code:9`** or **`SUPER+code:66`** → nwggrid-wrapper (application launcher)
- **`SUPER+code:47`** → Fuzzel launcher
- **`SUPER+W`** → nwg-dock-wrapper (application dock)

## Workspace Navigation

### Direct Workspace Access

Direct workspace access on current monitor:

- **`$mainMod+1`** through **`$mainMod+0`** → Focus workspace 1-10 on current monitor
- **`$mainMod+Shift+1`** through **`$mainMod+Shift+0`** → Move window to workspace 1-10

### Workspace Cycling

- **`$mainMod+Q`** → Previous workspace on current monitor (`m-1`)
- **`$mainMod+W`** → Next workspace on current monitor (`m+1`)
- **`$mainMod+Shift+Q`** → Move window to previous workspace on current monitor
- **`$mainMod+Shift+W`** → Move window to next workspace on current monitor

### Workspace Navigation (Alternative)

- **`SUPER+CTRL+right`** → Next workspace (hyprnome)
- **`SUPER+CTRL+left`** → Previous workspace (hyprnome --previous)
- **`SUPER+Shift+right`** → Move window to next workspace (hyprnome --move)
- **`SUPER+Shift+left`** → Move window to previous workspace (hyprnome --previous --move)

### Special Workspace

- **`$mainMod+Z`** → Move to workspace +30 (silent, hidden workspace)

## Window Management

### Focus Navigation

- **`SUPER+H`** → Focus left
- **`SUPER+J`** → Focus down
- **`SUPER+K`** → Focus up
- **`SUPER+L`** → Focus right

### Window Movement

- **`SUPER+Shift+H`** → Move window left
- **`SUPER+Shift+J`** → Move window down
- **`SUPER+Shift+K`** → Move window up
- **`SUPER+Shift+L`** → Move window right

### Window Toggles

- **`SUPER+SPACE`** → Fullscreen (1)
- **`SUPER+Shift+F`** → Fullscreen (0)
- **`$mainMod+Shift+T`** → Toggle floating
- **`$mainMod+Shift+G`** → Toggle floating and pin
- **`SUPER+Y`** → All windows float (workspaceopt allfloat)

### Window Pin

- **`SUPER+CTRL+P`** → Pin window (keep on top)

### Window Cycling

- **`ALT+TAB`** → Cycle next window
- **`ALT+TAB`** → Bring active to top
- **`ALT+Shift+TAB`** → Cycle previous window
- **`ALT+Shift+TAB`** → Bring active to top

## Application Shortcuts

### Terminal

- **`SUPER+RETURN`** → Launch terminal (from `userSettings.term`)
- **`SUPER+Shift+RETURN`** → Launch floating terminal (`--class float_term`)

### Editor

- **`SUPER+A`** → Launch editor (from `userSettings.spawnEditor`)

### Browser

- **`SUPER+S`** → Launch browser (from `userSettings.spawnBrowser`)
- **`SUPER+CTRL+S`** → Container open (qutebrowser only)

### Application Toggles

Applications use conditional logic: focus if running, launch if not.

- **`$mainMod+G`** → Chromium (focus or launch)
- **`$mainMod+E`** → Dolphin file manager (focus or launch)
- **`$mainMod+V`** → Vivaldi browser (focus or launch)
- **`$mainMod+C`** → VS Code (focus or launch)
- **`$mainMod+D`** → Obsidian (focus or launch)

### Special Workspace Applications

- **`$mainMod+S`** → Magic workspace (special workspace with multiple toggles)

## Screenshots

Screenshots use `grim` and `slurp`:

- **`code:107`** → Area selection screenshot
- **`SHIFT+code:107`** → Area selection screenshot (output only)
- **`SUPER+code:107`** → Full screen screenshot
- **`CTRL+code:107`** → Area selection to clipboard
- **`SHIFT+CTRL+code:107`** → Area selection to clipboard (output only)
- **`SUPER+CTRL+code:107`** → Full screen to clipboard

### Screenshot OCR

- **`SUPER+Shift+T`** → Screenshot OCR (screenshot-ocr script)
  - Takes screenshot, runs OCR, copies text to clipboard

## Media Controls

### Volume

- **`code:122`** → Lower volume
- **`code:123`** → Raise volume
- **`code:121`** or **`code:256`** → Mute toggle
- **`SHIFT+code:122`** → Lower volume (alternative)
- **`SHIFT+code:123`** → Raise volume (alternative)

### Brightness

- **`code:232`** → Lower brightness
- **`code:233`** → Raise brightness

### Keyboard Backlight

- **`code:237`** → Lower keyboard backlight
- **`code:238`** → Raise keyboard backlight

### Music Controls (Lollypop)

- **`code:172`** → Toggle play/pause
- **`code:208`** → Toggle play/pause (alternative)
- **`code:209`** → Toggle play/pause (alternative)
- **`code:174`** → Stop
- **`code:171`** → Next track
- **`code:173`** → Previous track

### Color Picker

- **`SUPER+C`** → Color picker (hyprpicker + wl-copy)

### Clipboard

- **`SUPER+V`** → Copy clipboard (remove newlines, wl-copy)

## Special Workspaces

Hyprland uses special workspaces for scratchpads and floating applications.

### Scratchpad Workspaces

- **`$mainMod+T`** → Toggle scratch_term (terminal scratchpad)
- **`$mainMod+L`** → Toggle scratch_telegram (Telegram scratchpad)
- **`$mainMod+Y`** → Toggle scratch_spotify (Spotify scratchpad)
- **`SUPER+F`** → Toggle scratch_ranger (Ranger file manager scratchpad)
- **`SUPER+N`** → Toggle scratch_numbat (Numbat calculator scratchpad)
- **`SUPER+B`** → Toggle scratch_btm (Bottom system monitor scratchpad)
- **`SUPER+M`** → Toggle scratch_music (Lollypop music player scratchpad)
- **`SUPER+D`** → Toggle scratch_element (Element chat scratchpad)
- **`SUPER+code:172`** → Toggle scratch_pavucontrol (PulseAudio control scratchpad)

### Scratchpad Configuration

All scratchpads are configured with:
- Floating windows
- 80% width, 85% height
- Centered on screen
- Special workspace assignment

## Utilities

### Notifications

- **`SUPER+X`** → Dismiss notification (fnottctl dismiss)
- **`SUPER+Shift+X`** → Dismiss all notifications (fnottctl dismiss all)

### Network Manager

- **`SUPER+I`** → NetworkManager dmenu (networkmanager_dmenu)

### Password Manager

- **`SUPER+P`** → Keepmenu (password manager)

### Profile Management

- **`SUPER+Shift+P`** → Hyprland profile dmenu (hyprprofile-dmenu)

### Refresh

- **`SUPER+CTRL+R`** → Phoenix refresh (phoenix refresh)

### OBS Studio Pass-Through

- **`SUPER+R`** → Pass to OBS Studio (when OBS is running)
- **`SUPER+Shift+R`** → Pass to OBS Studio (when OBS is running)

### Calculator

- **`code:148`** → Launch calculator (numbat in terminal)

## Mouse Bindings

- **`ALT+mouse:272`** → Move window (drag)
- **`ALT+mouse:273`** → Resize window (drag)

## Related Documentation

- [Main Keybindings Reference](../keybindings.md) - Overview and common keybindings
- [Keyd Configuration](../../system/wm/keyd.nix) - Hyper key setup
- [Hyprland Configuration](../../user/wm/hyprland/hyprland.nix) - Complete Hyprland configuration

