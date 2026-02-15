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
- [Utilities](#utilities)
- [Media Controls](#media-controls)
- [Special Workspaces](#special-workspaces)

## Overview

Hyprland is a dynamic tiling Wayland compositor. All keybindings use the **main modifier** (`$mainMod`) which is equivalent to the Hyper key (SUPERCTRLALT).

**Configuration File**: `user/wm/hyprland/hyprland.nix`

**Main Modifier**: `$mainMod` = SUPERCTRLALT (same as Hyper)

**Reference**: See [Keyd Configuration](../../../system/wm/keyd.nix) for Hyper key setup.

**Migration Note**: This configuration includes scripts that replicate SwayFX functionality. See [SwayFX to Hyprland Migration Guide](../../user-modules/sway-to-hyprland-migration.md) for details.

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

### Local Workspace Cycling

Workspace navigation is **local** (within current monitor only) to prevent workspace switching across multiple monitors.

- **`$mainMod+Q`** → Previous workspace on current monitor (`focusworkspaceoncurrentmonitor m-1`)
- **`$mainMod+W`** → Next workspace on current monitor (`focusworkspaceoncurrentmonitor m+1`)
- **`$mainMod+Shift+Q`** → Move window to previous workspace on current monitor (`movetoworkspace m-1`)
- **`$mainMod+Shift+W`** → Move window to next workspace on current monitor (`movetoworkspace m+1`)

### Direct Workspace Access

Direct workspace access using `workspace-controller.sh` (Swaysome replacement):

- **`$mainMod+1`** through **`$mainMod+0`** → Focus workspace 1-10 (per-monitor workspace groups)
  - Monitor 0: Key 1 → Workspace 1, Key 2 → Workspace 2, ..., Key 0 → Workspace 10
  - Monitor 1: Key 1 → Workspace 11, Key 2 → Workspace 12, ..., Key 0 → Workspace 20
  - Monitor 2: Key 1 → Workspace 21, Key 2 → Workspace 22, ..., Key 0 → Workspace 30
- **`$mainMod+Shift+1`** through **`$mainMod+Shift+0`** → Move window to workspace 1-10 (per-monitor workspace groups)

**Script**: `workspace-controller.sh` - Calculates target workspace as `(MonitorID * 10) + Index`

**CRITICAL**: Uses `workspace` dispatcher (NOT `focusworkspaceoncurrentmonitor`) to preserve per-monitor workspace groups. See [SwayFX to Hyprland Migration Guide](../../user-modules/sway-to-hyprland-migration.md) for details.

### Workspace Navigation (Alternative)

- **`SUPER+CTRL+right`** → Next workspace (hyprnome)
- **`SUPER+CTRL+left`** → Previous workspace (hyprnome --previous)
- **`SUPER+Shift+right`** → Move window to next workspace (hyprnome --move)
- **`SUPER+Shift+left`** → Move window to previous workspace (hyprnome --previous --move)

### Monitor Navigation

- **`$mainMod+Left`** → Focus monitor left (`hyprctl dispatch focusmonitor l`)
- **`$mainMod+Right`** → Focus monitor right (`hyprctl dispatch focusmonitor r`)
- **`$mainMod+Up`** → Focus monitor up (`hyprctl dispatch focusmonitor u`)
- **`$mainMod+Down`** → Focus monitor down (`hyprctl dispatch focusmonitor d`)

### Move Window Between Monitors

- **`$mainMod+Shift+Left`** → Move window to monitor left (`hyprctl dispatch movewindow mon:l`)
- **`$mainMod+Shift+Right`** → Move window to monitor right (`hyprctl dispatch movewindow mon:r`)

### Special Workspace

- **`$mainMod+Z`** → Move to workspace +30 (silent, hidden workspace)

## Window Management

### Focus Navigation

- **`SUPER+H`** → Focus left
- **`SUPER+J`** → Focus down
- **`SUPER+K`** → Focus up
- **`SUPER+L`** → Focus right

### Window Focus Navigation (Alternative)

- **`$mainMod+Shift+comma`** → Focus left
- **`$mainMod+question`** → Focus right
- **`$mainMod+less`** → Focus down
- **`$mainMod+greater`** → Focus up

### Window Movement

Window movement uses custom scripts that handle both floating and tiled windows:

- **`$mainMod+Shift+j`** → Move window left (`window-move.sh l`)
- **`$mainMod+colon`** → Move window right (`window-move.sh r`)
- **`$mainMod+Shift+k`** → Move window down (`window-move.sh d`)
- **`$mainMod+Shift+l`** → Move window up (`window-move.sh u`)

**Alternative keybindings** (original Hyprland layout):
- **`SUPER+Shift+H`** → Move window left
- **`SUPER+Shift+J`** → Move window down
- **`SUPER+Shift+K`** → Move window up
- **`SUPER+Shift+L`** → Move window right

**Script**: `window-move.sh` - Conditional logic:
- **Floating windows**: Move by 5% of screen size (calculated dynamically)
- **Tiled windows**: Swap position in direction

### Window Resizing

- **`$mainMod+Shift+u`** → Resize shrink width 5% (`hyprctl dispatch resizeactive -5% 0`)
- **`$mainMod+Shift+p`** → Resize grow width 5% (`hyprctl dispatch resizeactive 5% 0`)
- **`$mainMod+Shift+i`** → Resize grow height 5% (`hyprctl dispatch resizeactive 0 5%`)
- **`$mainMod+Shift+o`** → Resize shrink height 5% (`hyprctl dispatch resizeactive 0 -5%`)

### Window Toggles

- **`SUPER+SPACE`** → Fullscreen (1)
- **`SUPER+Shift+F`** → Fullscreen (0)
- **`$mainMod+f`** → Fullscreen toggle (alternative)
- **`$mainMod+Shift+f`** → Floating toggle
- **`$mainMod+Shift+T`** → Toggle floating
- **`$mainMod+Shift+G`** → Toggle floating and pin
- **`$mainMod+Shift+s`** → Pin window (sticky toggle) - Note: Hyprland uses `pin` not `sticky`
- **`$mainMod+Shift+g`** → Fullscreen toggle (alternative)
- **`$mainMod+Escape`** → Kill window (`hyprctl dispatch killactive`)
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

Applications use the `app-toggle.sh` script which toggles applications (focus if running, launch if not, hide if focused).

**Currently Implemented**:
- **`$mainMod+G`** → Chromium (`app-toggle.sh chromium-browser chromium`)
- **`$mainMod+E`** → Dolphin (`app-toggle.sh org.kde.dolphin dolphin`)
- **`$mainMod+V`** → Vivaldi (`app-toggle.sh Vivaldi-nixos vivaldi`)
- **`$mainMod+C`** → VS Code (`app-toggle.sh code code --flags`)
- **`$mainMod+D`** → Obsidian (`app-toggle.sh obsidian obsidian --flags`)

**Script**: `app-toggle.sh` - Application toggle logic:
- **Not Running**: Launch app (with Flatpak detection)
- **Running & Focused**: Hide to scratchpad (single window) or cycle (multiple windows)
- **Running & In Special Workspace**: Toggle special workspace and focus
- **Running & Visible (Unfocused)**: Focus window

**See Also**: [TODO.md](../../../user/wm/hyprland/scripts/TODO.md) for missing app toggles (R, L, U, A, Y, N, P, M, B)

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

### Clipboard History

- **`$mainMod+Shift+v`** → Clipboard history (cliphist + rofi)
  - Opens rofi with clipboard history
  - Selected item is copied to clipboard
  - **Note**: Not yet implemented, see [TODO.md](../../../user/wm/hyprland/scripts/TODO.md)

### Scratchpad

- **`$mainMod+minus`** → Show scratchpad (`hyprctl dispatch togglespecialworkspace scratch`)
- **`$mainMod+Shift+minus`** → Move window to scratchpad (`hyprctl dispatch movetoworkspacesilent special:scratch`)
- **`$mainMod+Shift+e`** → Hide window (move to scratchpad) (`hyprctl dispatch movetoworkspacesilent special:scratch`)

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

- **`SUPER+CTRL+R`** → Phoenix refresh (aku refresh)

### OBS Studio Pass-Through

- **`SUPER+R`** → Pass to OBS Studio (when OBS is running)
- **`SUPER+Shift+R`** → Pass to OBS Studio (when OBS is running)

### Calculator

- **`code:148`** → Launch calculator (numbat in terminal)

### Power Menu

- **`$mainMod+Shift+BackSpace`** → Power menu script
  - **Note**: Not yet implemented, see [TODO.md](../../../user/wm/hyprland/scripts/TODO.md)

### Configuration Reload

- **`$mainMod+Shift+r`** → Reload Hyprland configuration (`hyprctl reload`)
  - **Note**: Not yet implemented, see [TODO.md](../../../user/wm/hyprland/scripts/TODO.md)

### Exit Hyprland

- **`$mainMod+Shift+End`** → Exit Hyprland (with confirmation dialog)
  - **Note**: Not yet implemented, see [TODO.md](../../../user/wm/hyprland/scripts/TODO.md)

## Mouse Bindings

- **`ALT+mouse:272`** → Move window (drag)
- **`ALT+mouse:273`** → Resize window (drag)

## Window Management Scripts

This configuration includes custom scripts that replicate SwayFX functionality:

### workspace-controller.sh

Replaces `swaysome` workspace group mapping. Calculates target workspace based on monitor ID:
- **Usage**: `workspace-controller.sh <action> <index>`
- **Actions**: `focus` or `move`
- **Index**: 1-10 (workspace index within monitor group)
- **Logic**: `Target = (MonitorID * 10) + Index`

**See Also**: [SwayFX to Hyprland Migration Guide](../../user-modules/sway-to-hyprland-migration.md)

### window-move.sh

Conditional window movement (floating vs tiled):
- **Usage**: `window-move.sh <direction>`
- **Directions**: `l` (left), `r` (right), `u` (up), `d` (down)
- **Floating**: Moves by 5% of screen size (calculated dynamically)
- **Tiled**: Swaps position in direction

**See Also**: [SwayFX to Hyprland Migration Guide](../../user-modules/sway-to-hyprland-migration.md)

### app-toggle.sh

Application toggle with launch/focus/hide logic:
- **Usage**: `app-toggle.sh <app_class> <launch_command...>`
- **Features**: Flatpak detection, special workspace support, window cycling

**See Also**: [SwayFX to Hyprland Migration Guide](../../user-modules/sway-to-hyprland-migration.md)

## Keybinding Conflicts Avoided

The following keybindings were intentionally removed to avoid conflicts:

- **`$mainMod+d`** → Removed (conflicts with application bindings)
- **`$mainMod+l`** → Removed (conflicts with `${mainMod}+L` for Telegram)
- **`$mainMod+s`** → Removed (conflicts with layout bindings)
- **`$mainMod+w`** → Removed (conflicts with `${mainMod}+W` for workspace next)
- **`$mainMod+e`** → Removed (conflicts with `${mainMod}+E` for Dolphin file explorer)
- **`$mainMod+a`** → Removed (conflicts with `${mainMod}+A` for Pavucontrol)
- **`$mainMod+u`** → Removed (conflicts with `${mainMod}+U` for DBeaver)

## Related Documentation

- [Main Keybindings Reference](../keybindings.md) - Overview and common keybindings
- [SwayFX Keybindings Reference](sway.md) - SwayFX keybinding reference (for comparison)
- [SwayFX to Hyprland Migration Guide](../../user-modules/sway-to-hyprland-migration.md) - Complete migration documentation
- [Keyd Configuration](../../../system/wm/keyd.nix) - Hyper key setup
- [Hyprland Configuration](../../../user/wm/hyprland/hyprland.nix) - Complete Hyprland configuration
- [Hyprland Scripts TODO](../../../user/wm/hyprland/scripts/TODO.md) - Missing features checklist

