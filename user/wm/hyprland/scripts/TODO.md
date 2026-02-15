# Hyprland Migration TODO

Brief checklist of missing SwayFX features for future DESK profile implementation.

## Status

✅ **Completed**:
- Workspace controller script (`workspace-controller.sh`) - Replaces swaysome
- Window movement script (`window-move.sh`) - Floating/tiled conditional logic
- App toggle script (`app-toggle.sh`) - Launch/focus/hide logic
- Core workspace keybindings (1-0, Shift+1-0)
- Basic window movement keybindings
- Basic app toggles (G, E, V, C, D)

## Missing Keybindings

### Application Shortcuts
- `$mainMod+R` → Alacritty (`app-toggle.sh Alacritty alacritty`)
- `$mainMod+L` → Telegram (currently uses special workspace, needs app-toggle.sh)
- `$mainMod+U` → DBeaver (`app-toggle.sh io.dbeaver.DBeaverCommunity dbeaver`)
- `$mainMod+A` → Pavucontrol (`app-toggle.sh pavucontrol pavucontrol`)
- `$mainMod+Y` → Spotify (currently uses special workspace, needs app-toggle.sh)
- `$mainMod+N` → nwg-look (`app-toggle.sh nwg-look nwg-look`)
- `$mainMod+P` → Bitwarden (`app-toggle.sh Bitwarden bitwarden`)
- `$mainMod+M` → Mission Center (`app-toggle.sh mission-center mission-center`)
- `$mainMod+B` → Bottles (`app-toggle.sh com.usebottles.bottles bottles`)

### Window Management
- `$mainMod+Escape` → Kill window (`hyprctl dispatch killactive`)
- `$mainMod+Shift+f` → Floating toggle (`hyprctl dispatch togglefloating`)
- `$mainMod+Shift+s` → Sticky toggle (`hyprctl dispatch pin`) - Note: Hyprland uses "pin" not "sticky"
- `$mainMod+Shift+g` → Fullscreen toggle (`hyprctl dispatch fullscreen`)
- `$mainMod+f` → Fullscreen toggle (alternative)

### Window Resizing
- `$mainMod+Shift+u` → Resize shrink width 5% (`hyprctl dispatch resizeactive -5% 0`)
- `$mainMod+Shift+p` → Resize grow width 5% (`hyprctl dispatch resizeactive 5% 0`)
- `$mainMod+Shift+i` → Resize grow height 5% (`hyprctl dispatch resizeactive 0 5%`)
- `$mainMod+Shift+o` → Resize shrink height 5% (`hyprctl dispatch resizeactive 0 -5%`)

### Window Focus Navigation (Alternative)
- `$mainMod+Shift+comma` → Focus left (`hyprctl dispatch movefocus l`)
- `$mainMod+question` → Focus right (`hyprctl dispatch movefocus r`)
- `$mainMod+less` → Focus down (`hyprctl dispatch movefocus d`)
- `$mainMod+greater` → Focus up (`hyprctl dispatch movefocus u`)

### Monitor Navigation
- `$mainMod+Left` → Focus monitor left (`hyprctl dispatch focusmonitor l`)
- `$mainMod+Right` → Focus monitor right (`hyprctl dispatch focusmonitor r`)
- `$mainMod+Up` → Focus monitor up (`hyprctl dispatch focusmonitor u`)
- `$mainMod+Down` → Focus monitor down (`hyprctl dispatch focusmonitor d`)
- `$mainMod+Shift+Left` → Move window to monitor left (`hyprctl dispatch movewindow mon:l`)
- `$mainMod+Shift+Right` → Move window to monitor right (`hyprctl dispatch movewindow mon:r`)

### Scratchpad
- `$mainMod+minus` → Show scratchpad (`hyprctl dispatch togglespecialworkspace scratch`)
- `$mainMod+Shift+minus` → Move window to scratchpad (`hyprctl dispatch movetoworkspacesilent special:scratch`)
- `$mainMod+Shift+e` → Hide window (move to scratchpad) (`hyprctl dispatch movetoworkspacesilent special:scratch`)

### Launchers
- `$mainMod+space` → Rofi combi launcher (`rofi -show combi -combi-modi 'drun,run,window' -show-icons`)
- `$mainMod+BackSpace` → Rofi combi launcher (alternative)
- `$mainMod+x` → Rofi calculator (`rofi -show calc -modi calc -no-show-match -no-sort`)
- `$mainMod+period` → Rofi emoji picker (`rofi -show emoji`)
- `$mainMod+slash` → Rofi file browser (`rofi -show filebrowser`)

### Window Overview
- `$mainMod+Tab` → Window overview (`rofi -show window` with grid layout)

### Workspace Toggle
- `Mod4+Tab` → Workspace back and forth (`hyprctl dispatch workspace previous`)

### Utilities
- `$mainMod+Shift+v` → Clipboard history (`cliphist list | rofi -dmenu | cliphist decode | wl-copy`)
- `$mainMod+Shift+BackSpace` → Power menu (create `power-menu.sh` script)
- `$mainMod+Shift+End` → Exit Hyprland (with confirmation dialog)

### Screenshots
- `$mainMod+Shift+x` → Full screen screenshot (create `screenshot.sh` script)
- `$mainMod+Shift+c` → Area selection screenshot
- `Print` → Area selection screenshot

### System
- `$mainMod+Shift+r` → Reload Hyprland configuration (`hyprctl reload`)
- `$mainMod+Shift+Return` → Manual startup apps launcher (if DESK profile)

## Scripts to Create

1. **screenshot.sh** - Screenshot workflow (full screen and area selection)
   - Use `grim` and `slurp` (already in Hyprland config)
   - Match SwayFX screenshot.sh behavior

2. **power-menu.sh** - Power menu script
   - Match SwayFX power-menu.sh behavior
   - Use rofi or fuzzel for menu

## Notes

- **Sticky Windows**: Hyprland uses `pin` dispatcher instead of Sway's `sticky` property
- **Scratchpad Namespace**: Use app-specific namespaces (e.g., `special:scratch_term`) to avoid conflicts
- **Window Resizing**: Hyprland supports percentage-based resizing (`resizeactive 5% 0`), no script needed
- **Monitor Navigation**: Hyprland uses `mon:l`, `mon:r` syntax for monitor-relative movement

## Related Documentation

- [SwayFX to Hyprland Migration Guide](../../../../docs/user-modules/sway-to-hyprland-migration.md) - Complete migration documentation
- [SwayFX Keybindings Reference](../../../../docs/akunito/keybindings/sway.md) - SwayFX keybinding reference
- [Hyprland Keybindings Reference](../../../../docs/akunito/keybindings/hyprland.md) - Hyprland keybinding reference
- [User Modules Guide](../../../../docs/user-modules.md) - Window manager modules overview
- [Main Keybindings Reference](../../../../docs/akunito/keybindings.md) - Common keybindings across WMs

