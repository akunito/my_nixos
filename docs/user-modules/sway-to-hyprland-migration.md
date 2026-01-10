---
id: user-modules.sway-to-hyprland-migration
summary: Guide to replicate SwayFX workspace and window management semantics in Hyprland using scripts and conventions.
tags: [sway, swayfx, hyprland, migration, wayland, workspaces]
related_files:
  - user/wm/hyprland/**
  - user/wm/sway/**
  - docs/user-modules/sway-to-hyprland-migration.md
key_files:
  - docs/user-modules/sway-to-hyprland-migration.md
activation_hints:
  - If migrating configs from SwayFX to Hyprland or debugging workspace mapping parity
---

# SwayFX to Hyprland Migration Guide

Complete guide for migrating SwayFX window management logic to Hyprland equivalents.

## Overview

This document explains how SwayFX window management features (using `swaysome` for workspace groups) are replicated in Hyprland using custom scripts. The migration maintains strict feature parity, particularly preserving the "per-monitor independent workspace" workflow (1-10 on Mon1, 11-20 on Mon2).

## Architecture

### SwayFX Components

1. **swaysome**: Workspace namespace tool that groups workspaces per monitor
   - Monitor 1: Workspaces 1-10
   - Monitor 2: Workspaces 11-20
   - Monitor 3: Workspaces 21-30
   - Monitor 4: Workspaces 31-40

2. **Workspace assignment scripts**: Initialize workspace groups and assign them to outputs
   - Uses `swaysome init`, `swaysome focus-group`, `swaysome focus`

3. **window-move.sh**: Conditional window movement
   - Floating windows: move by 5% using `swaymsg move <direction> 5 ppt`
   - Tiled windows: swap position using `swaymsg move <direction>`

4. **app-toggle.sh**: Application toggle logic
   - If not running: launch app (with Flatpak detection)
   - If running and focused: hide (scratchpad) or cycle windows
   - If running but not focused: focus first window

### Hyprland Equivalents

Hyprland does not have a native `swaysome` equivalent. We implement the same functionality using custom scripts that calculate workspace numbers based on monitor ID.

## Command Mapping Table

| SwayFX Command | Hyprland Equivalent | Notes |
|----------------|---------------------|-------|
| `swaysome init 1` | Workspace config in `hyprland.conf` | No init needed, workspaces defined statically |
| `swaysome focus <num>` | `workspace-controller.sh focus <num>` | Calculates target workspace: `(MonitorID * 10) + num`, uses `workspace` dispatcher |
| `swaysome move <num>` | `workspace-controller.sh move <num>` | Calculates target workspace: `(MonitorID * 10) + num`, uses `movetoworkspace` dispatcher |
| `swaysome focus-group <num>` | `hyprctl dispatch focusmonitor <name>` + workspace assignment | Focus monitor, then workspace |
| `swaymsg focus output <name>` | `hyprctl dispatch focusmonitor <name>` | Focus monitor |
| `swaymsg move <direction> 5 ppt` | `hyprctl dispatch movewindowpixel <x> <y>` | Floating window movement (calculate 5% of screen) |
| `swaymsg move <direction>` | `hyprctl dispatch movewindow <direction>` | Tiled window swap |
| `swaymsg -t get_tree` | `hyprctl clients -j` | Query windows (JSON format) |
| `swaymsg [con_id=X] focus` | `hyprctl dispatch focuswindow address:<address>` | Focus window by ID |
| `swaymsg move scratchpad` | `hyprctl dispatch movetoworkspacesilent special:scratch_term` | Hide window (use app-specific scratch namespace) |

## Critical Architectural Differences

### 1. Workspace Dispatcher (CRITICAL)

**SwayFX**: `swaysome focus 1` automatically maps to the correct workspace based on monitor.

**Hyprland**: 
- ❌ **WRONG**: `hyprctl dispatch focusworkspaceoncurrentmonitor 1` - This **steals** workspaces from other monitors
- ✅ **CORRECT**: `hyprctl dispatch workspace 11` (calculated) - Respects workspace-to-monitor assignments

**Why**: `focusworkspaceoncurrentmonitor` forces the workspace onto the current monitor, breaking the independent monitor workspace workflow. We must calculate the actual workspace number and use the `workspace` dispatcher.

### 2. Workspace Calculation

The `workspace-controller.sh` script implements the swaysome logic:

```
Target Workspace = (MonitorID * 10) + Index
```

Examples:
- Monitor 0, Key 1 → Workspace 1
- Monitor 1, Key 1 → Workspace 11
- Monitor 2, Key 1 → Workspace 21

### 3. Floating Window Movement

**SwayFX**: `swaymsg move left 5 ppt` (percentage-based)

**Hyprland**: `hyprctl dispatch movewindowpixel -100 0` (integer pixels required)

**Solution**: Calculate 5% of screen resolution using `jq` math:
- Get monitor resolution: `hyprctl monitors -j | jq '.[] | select(.focused == true) | {width, height}'`
- Calculate: `width * 0.05` and `height * 0.05` (round to integer)
- Map directions: `l` → `-X 0`, `r` → `X 0`, `u` → `0 -Y`, `d` → `0 Y`

### 4. Scratchpad Namespace

**SwayFX**: Uses generic "scratchpad" container list

**Hyprland**: Uses special workspaces with namespaces

**Solution**: Use app-specific namespaces (e.g., `special:scratch_term`) to prevent conflicts:
- Hide: `hyprctl dispatch movetoworkspacesilent special:scratch_term`
- Show: `hyprctl dispatch togglespecialworkspace scratch_term`

### 5. Window Addressing

**SwayFX**: Uses `con_id` (container ID)

**Hyprland**: Uses `address` (window address)

**Solution**: Extract `address` field from `hyprctl clients -j` output and use `address:` prefix:
- `hyprctl dispatch focuswindow address:0x12345678`

## Script Architecture

### workspace-controller.sh

Replaces `swaysome` functionality by calculating workspace numbers based on monitor ID.

**Arguments**: `action` (focus/move), `index` (1-9)

**Logic**:
1. Get current Monitor ID: `hyprctl monitors -j | jq '.[] | select(.focused == true) | .id'`
2. Calculate offset: `Offset = MonitorID * 10`
3. Calculate target: `Target = Offset + Index`
4. Execute:
   - `focus`: `hyprctl dispatch workspace $Target`
   - `move`: `hyprctl dispatch movetoworkspace $Target`

### window-move.sh

Conditional window movement (floating vs tiled).

**Arguments**: `direction` (l, r, u, d)

**Logic**:
1. Check if floating: `hyprctl activewindow -j | jq -r '.floating'`
2. **If Tiled**: `hyprctl dispatch movewindow $direction`
3. **If Floating**:
   - Get monitor resolution
   - Calculate 5% delta using `jq` math
   - Map direction to pixel coordinates
   - `hyprctl dispatch movewindowpixel $x $y`

### app-toggle.sh

Application toggle with launch/focus/hide logic.

**Arguments**: `app_class`, `launch_command...`

**Logic**:
1. Search clients: `hyprctl clients -j | jq` (find by `class` or `initialClass`)
2. **Not Running**: Launch app (with Flatpak detection)
3. **Running & Focused**: 
   - Single window: `movetoworkspacesilent special:scratch_term`
   - Multiple windows: Cycle to next window
4. **Running & In Special Workspace**: 
   - `togglespecialworkspace scratch_term`
   - Then `focuswindow address:<addr>`
5. **Running & Visible (Unfocused)**: 
   - `focuswindow address:<addr>`
   - **CRITICAL**: Do NOT toggle special workspace (might hide visible window)

## Keybinding Migration

### Workspace Navigation

**SwayFX**:
```
${hyper}+1 = "exec swaysome focus 1"
${hyper}+Shift+1 = "exec swaysome move 1"
```

**Hyprland**:
```
bind=$mainMod,1,exec,~/.config/hypr/scripts/workspace-controller.sh focus 1
bind=$mainMod SHIFT,1,exec,~/.config/hypr/scripts/workspace-controller.sh move 1
```

### Window Movement

**SwayFX**:
```
${hyper}+Shift+j = "exec window-move.sh left"
```

**Hyprland**:
```
bind=$mainMod SHIFT,J,exec,~/.config/hypr/scripts/window-move.sh l
```

### App Toggles

**SwayFX**:
```
${hyper}+T = "exec app-toggle.sh kitty kitty"
```

**Hyprland**:
```
bind=$mainMod,T,exec,~/.config/hypr/scripts/app-toggle.sh kitty kitty
```

## Prerequisites

### Workspace Rules

**CRITICAL**: The `workspace-controller.sh` script requires static workspace-to-monitor assignments in `hyprland.conf` or `hyprland.nix`:

```
workspace = 1, monitor:DP-1
workspace = 2, monitor:DP-1
...
workspace = 11, monitor:DP-2
workspace = 12, monitor:DP-2
...
```

Without these rules, `hyprctl dispatch workspace 11` might create the workspace on the wrong monitor if it doesn't exist yet.

### Dependencies

- `jq`: Required for JSON parsing and math calculations
- `hyprctl`: Hyprland command-line utility (included with Hyprland)

## File Locations

- **Scripts**: `user/wm/hyprland/scripts/`
  - `workspace-controller.sh`
  - `window-move.sh`
  - `app-toggle.sh`
- **Configuration**: `user/wm/hyprland/hyprland.nix`
- **Documentation**: `docs/user-modules/sway-to-hyprland-migration.md`

## Related Documentation

- [SwayFX Keybindings Reference](../keybindings/sway.md)
- [Hyprland Keybindings Reference](../keybindings/hyprland.md)
- [Main Keybindings Reference](../keybindings.md)

