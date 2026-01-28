# SwayFX Feature Testing Guide

## Quick Start

After rebuilding and logging into Sway session, run:

```bash
~/.dotfiles/.cursor/test-swayfx-features.sh
```

This will automatically test daemons, packages, and configuration files.

## Script Management

**Important**: All Sway scripts are managed in the repository at `user/wm/sway/scripts/` and automatically installed to `~/.config/sway/scripts/` via Home Manager configuration. 

- **Edit scripts**: Edit files in `.dotfiles/user/wm/sway/scripts/`
- **Scripts are installed**: Home Manager copies them to `~/.config/sway/scripts/` with executable permissions
- **After editing**: Run `home-manager switch` to apply changes
- **Available scripts**:
  - `app-toggle.sh` - Application launch/toggle/cycle script
  - `window-move.sh` - Conditional window movement (floating vs tiled)
  - `power-menu.sh` - Session management menu (logout, restart, etc.)
  - `screenshot.sh` - Screenshot workflow with Swappy
  - `ssh-smart.sh` - SSH connection management
  - `debug-startup.sh` - Startup debugging and logging

## Manual Testing Checklist

### 1. Visual Verification (Immediate Checks)

- [ ] **Wallpaper**: Check that wallpaper is displayed (not grey screen)
- [ ] **Waybar**: Top bar should be visible with modules (time, workspaces, etc.)
- [ ] **Dock**: Move mouse to bottom edge - dock should appear
- [ ] **Dock Apps**: Open an application (e.g., `kitty`) - icon should appear in dock

### 2. Alt Key Fix (Critical Test)

1. Open a terminal (`Hyper+T` or manually)
2. Start Tmux: `tmux`
3. Create a pane: `Ctrl+A` then `%` (split vertically)
4. **Test**: Hold `Alt` + press `Right Arrow`
   - ✅ **PASS**: Cursor moves right or Tmux switches panes
   - ❌ **FAIL**: Terminal window moves (floating modifier still using Alt)

### 3. Keybindings Test

#### Launcher & Navigation
- [ ] `Hyper+Space` → Opens Rofi launcher (combi mode)
- [ ] `Hyper+BackSpace` → Opens Rofi launcher (alternative)
- [ ] `Hyper+Tab` → Opens Rofi window overview (grid)
- [ ] `Super+Tab` → Switches to previous workspace

#### Screenshots
- [ ] `Hyper+Shift+F` → Takes full monitor screenshot, opens Swappy
- [ ] `Hyper+Shift+C` → Takes area screenshot (select region), opens Swappy
- [ ] `PrintScreen` → Takes area screenshot (backup)

#### Workspace Navigation
- [ ] `Hyper+Q` → Previous workspace
- [ ] `Hyper+W` → Next workspace
- [ ] `Hyper+1` through `Hyper+0` → Switch to workspace 1-10
- [ ] `Hyper+Shift+1` through `Hyper+Shift+0` → Move window to workspace 1-10

#### Application Shortcuts
- [ ] `Hyper+L` → Telegram
- [ ] `Hyper+E` → Dolphin (file manager)
- [ ] `Hyper+T` → Kitty terminal
- [ ] `Hyper+D` → Obsidian
- [ ] `Hyper+V` → Vivaldi browser
- [ ] `Hyper+G` → Chromium browser
- [ ] `Hyper+Y` → Spotify
- [ ] `Hyper+S` → nwg-look
- [ ] `Hyper+P` → Bitwarden
- [ ] `Hyper+C` → VS Code
- [ ] `Hyper+M` → Mission Center
- [ ] `Hyper+B` → Bottles

### 4. Daemon Functionality

#### Clipboard History
1. Copy some text: `Ctrl+Shift+C` in terminal
2. Open Rofi: `Hyper+Space`
3. Type: `clipman pick`
4. Should show clipboard history

#### Touchpad Gestures
- [ ] 3-finger swipe left → Next workspace
- [ ] 3-finger swipe right → Previous workspace

#### Lock Screen
- [ ] Wait 10 minutes OR run: `swaylock --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033`
- [ ] Should show blurred screenshot background

#### Notifications
- [ ] Send a test notification: `notify-send "Test" "This is a test"`
- [ ] Should appear in swaync panel

### 5. Terminal & Tmux Integration

#### Terminal Alt Passthrough
1. Open terminal (Kitty or Alacritty)
2. Start Tmux: `tmux`
3. Create panes: `Ctrl+A` then `%` (vertical), `Ctrl+A` then `"` (horizontal)
4. Test Alt+Arrow navigation:
   - `Alt+Left` → Previous pane
   - `Alt+Right` → Next pane
   - `Alt+Up` → Previous pane
   - `Alt+Down` → Next pane
5. ✅ **PASS**: Panes switch correctly
6. ❌ **FAIL**: Terminal window moves or nothing happens

#### Tmux Clipboard Integration
1. In Tmux, select text (mouse or `Ctrl+A` then `[` then space, move with arrows)
2. Press `y` to copy
3. Paste outside terminal: `Ctrl+Shift+V` or middle-click
4. Should paste the selected text

### 6. Screenshot Workflow

#### Full Monitor Screenshot
1. Press `Hyper+Shift+F`
2. Should immediately capture focused monitor
3. Swappy editor should open with the screenshot
4. Can annotate, crop, or copy

#### Area Screenshot
1. Press `Hyper+Shift+C`
2. Cursor should turn into crosshair
3. Click and drag to select area
4. Swappy editor should open with selected area
5. Can annotate, crop, or copy

### 7. Dock Functionality

#### Auto-Hide
- [ ] Move mouse to bottom edge → Dock appears
- [ ] Move mouse away → Dock hides
- [ ] Dock should be at bottom center

#### Running Applications
1. Open an application (e.g., `kitty`)
2. Check dock → Should show application icon
3. Icon should have indicator showing it's running
4. Click icon → Should focus/raise the application

### 8. Window Management

#### Tiling
- [ ] `Hyper+H/J/K/L` → Focus windows (left/down/up/right)
- [ ] `Hyper+Shift+H/J/K/L` → Move windows
- [ ] `Hyper+F` → Toggle fullscreen
- [ ] `Hyper+Shift+Space` → Toggle floating
- [ ] `Hyper+S` → Stacking layout
- [ ] `Hyper+W` → Tabbed layout
- [ ] `Hyper+E` → Toggle split

#### Scratchpad
- [ ] `Hyper+Shift+Minus` → Move window to scratchpad
- [ ] `Hyper+Minus` → Show scratchpad

### 9. System Monitoring

#### Btop
1. Open terminal
2. Run: `btop`
3. Should show system monitor with Stylix colors (if enabled)
4. Should display CPU, memory, network, processes

### 10. Polkit (No Duplication)

Check systemd service:
```bash
systemctl --user status polkit-gnome-authentication-agent-1
```

Should show:
- ✅ Active and running
- ✅ Only ONE instance (check with `pgrep -x polkit-gnome-authentication-agent-1 | wc -l`)

## Troubleshooting

### Dock Not Showing
- Check if running: `pgrep -x nwg-dock`
- Check config: `~/.config/nwg-dock/style.css` exists
- Restart: `killall nwg-dock && nwg-dock -d -p bottom -i 48`

### Alt Key Still Moving Windows
- Check config: `swaymsg -t get_config | grep floating_modifier`
- Should show: `floating_modifier $mod normal`
- Reload Sway: `Hyper+Shift+R`

### Wallpaper Not Showing
- Check if Stylix is enabled: `cat ~/.currenttheme`
- Check if swaybg is running: `pgrep -x swaybg`
- Manually set: `swaybg -i /path/to/image.jpg -m fill`

### Screenshot Not Working
- Check scripts are executable: `ls -l ~/.config/sway/scripts/`
- Test manually: `~/.config/sway/scripts/screenshot.sh area`
- Check dependencies: `which grim slurp swappy jq`

**Note**: All Sway scripts are managed in the repository at `user/wm/sway/scripts/` and automatically installed to `~/.config/sway/scripts/` via Home Manager. Edit scripts in the repository, not in `~/.config/`.

## Expected Results Summary

After all tests:
- ✅ All daemons running
- ✅ All keybindings working
- ✅ Alt key freed for Tmux
- ✅ Dock shows and auto-hides
- ✅ Screenshots work with Swappy
- ✅ Wallpaper displayed
- ✅ No polkit duplication
- ✅ Touchpad gestures work
- ✅ Clipboard history works

