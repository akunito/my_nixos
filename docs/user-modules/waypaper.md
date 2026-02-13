---
id: waypaper
summary: Waypaper GUI wallpaper manager — single source of truth for wallpaper restore in Sway (swww backend)
tags: [waypaper, wallpaper, sway, swww, gui, stylix, systemd-user]
related_files:
  - user/app/waypaper/waypaper.nix
  - user/app/swww/swww.nix
  - user/wm/sway/swayfx-config.nix
  - profiles/DESK-config.nix
  - profiles/LAPTOP-base.nix
  - lib/defaults.nix
---

# Waypaper — GUI Wallpaper Manager (Single Source of Truth)

Waypaper is a lightweight GUI wallpaper manager that integrates with the swww daemon for SwayFX. When enabled (`waypaperEnable = true`), it becomes the **single source of truth** for wallpaper restore — replacing swww-restore on boot, monitor wake, and Home-Manager rebuild.

## Overview

- **Backend**: swww (Wayland Animated Wallpaper Daemon)
- **Frontend**: Waypaper GUI
- **Keybinding**: Hyper+Shift+B (Ctrl+Alt+Super+Shift+B)
- **Config**: `~/.config/waypaper/config.ini` (imperative, user-managed)
- **State model**: User sets wallpaper via GUI → config.ini updated → `waypaper --restore` reads it

## Wallpaper Restore Architecture

When `waypaperEnable = true`, the wallpaper restore ownership transfers from swww to Waypaper:

```
┌─────────────────────────────────────────────────────────────┐
│                 waypaperEnable = true                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  swww-daemon.service  ── still runs (backend, unchanged)    │
│  swww-restore.service ── disabled (no WantedBy)             │
│  swwwRestoreAfterSwitch ── disabled (HM hook removed)       │
│                                                             │
│  waypaper-restore.service ── ACTIVE (WantedBy sway-session) │
│  waypaperRestore ── ACTIVE (HM activation hook)             │
│  sway-resume-monitors ── calls waypaper-restore.service     │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                 waypaperEnable = false (backward compat)     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  swww-daemon.service  ── runs (backend)                     │
│  swww-restore.service ── ACTIVE (WantedBy sway-session)     │
│  swwwRestoreAfterSwitch ── ACTIVE (HM activation hook)      │
│  sway-resume-monitors ── calls swww-restore.service         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Behavior by Scenario

| Scenario | waypaperEnable=true | waypaperEnable=false |
|---|---|---|
| Boot / login | waypaper-restore.service | swww-restore.service |
| Monitor wake | waypaper-restore.service | swww-restore.service |
| HM switch / sync-user.sh | waypaperRestore hook | swwwRestoreAfterSwitch hook |
| Manual restore | `systemctl --user start waypaper-restore` | `systemctl --user start swww-restore` |

## waypaper-restore-wrapper

The restore wrapper (`waypaper.nix`) incorporates the same robust wait logic as swww-restore:

1. **Source `sway-session.env`** — picks up SWAYSOCK and WAYLAND_DISPLAY
2. **Resolve SWAYSOCK** — falls back to scanning `$XDG_RUNTIME_DIR/sway-ipc.*.sock`
3. **Wait for Sway outputs** — polls `swaymsg -t get_outputs` up to 30s
4. **Wait for swww-daemon** — polls `swww query` up to 30s
5. **Stylix fallback** — if `~/.config/waypaper/config.ini` doesn't exist and `stylixEnable = true`, generates a default config pointing to `config.stylix.image`
6. **Run `waypaper --restore`**

### First-Run Flow (No Waypaper Config Yet)

1. `waypaper-restore` starts → waits for daemon + outputs
2. Detects no `~/.config/waypaper/config.ini`
3. Generates default config from Stylix image path (`/nix/store/...`)
4. Runs `waypaper --restore` → wallpaper appears

### Normal Flow (Waypaper Configured)

1. `waypaper-restore` starts → waits for daemon + outputs
2. Reads existing `~/.config/waypaper/config.ini` (user's imperative choice)
3. Runs `waypaper --restore` → wallpaper appears

## Configuration

### Enable in Profile

**For DESK:**
```nix
# profiles/DESK-config.nix
systemSettings = {
  swwwEnable = true;        # Backend daemon (required)
  waypaperEnable = true;    # GUI frontend + restore ownership
};
```

**For Laptops:**
```nix
# profiles/LAPTOP-base.nix (inherited by LAPTOP_L15, LAPTOP_AGA, LAPTOP_YOGAAKU)
systemSettings = {
  swwwEnable = true;        # Backend daemon (required)
  waypaperEnable = true;    # GUI frontend + restore ownership
};
```

### Flag Definition

```nix
# lib/defaults.nix
systemSettings = {
  waypaperEnable = false;  # Enable Waypaper GUI (requires swwwEnable)
};
```

## Usage

### Launch GUI

- **Keybinding**: Hyper+Shift+B (Ctrl+Alt+Super+Shift+B)
- **Command**: `waypaper`
- **Application Launcher**: Search for "Waypaper" in Rofi

### GUI Workflow

1. Press Hyper+Shift+B to launch Waypaper
2. GUI opens as a floating window (1200x800px)
3. Select monitor from dropdown (if multi-monitor)
4. Browse wallpapers from selected folder
5. Click wallpaper to apply
6. Close GUI — config.ini is saved automatically

### Manual Restoration

```bash
# Restore saved wallpapers
waypaper --restore

# Or via systemd service
systemctl --user start waypaper-restore.service

# Check logs
journalctl --user -u waypaper-restore.service -b --no-pager
```

## Configuration Files

### Config Location
```
~/.config/waypaper/config.ini    # All settings + wallpaper path (single file)
```

### Example config.ini
```ini
[Settings]
folder = /home/akunito/Pictures/Wallpapers
wallpaper = /home/akunito/Pictures/Wallpapers/mountains.jpg
backend = swww
monitors = All
fill = fill
sort = name
color = #ffffff
subfolders = False
number_of_columns = 3
post_command =
swww_transition_type = any
swww_transition_step = 90
swww_transition_angle = 0
swww_transition_duration = 2
swww_transition_fps = 60
```

## Troubleshooting

### Wallpapers Not Restored on Login

```bash
# 1. Check swww daemon
systemctl --user status swww-daemon.service

# 2. Check waypaper-restore service
systemctl --user status waypaper-restore.service
journalctl --user -u waypaper-restore.service -b --no-pager

# 3. Verify swww-restore is NOT auto-starting (when waypaperEnable=true)
systemctl --user status swww-restore.service
# Expected: inactive, no WantedBy in unit file
```

### Wallpaper Reverts After Boot / Monitor Wake

This was the original race condition. If you still see it:

1. Verify `waypaperEnable = true` in your profile
2. Confirm swww-restore has no `[Install]` section:
   ```bash
   systemctl --user cat swww-restore.service | grep -A1 Install
   # Should show nothing (no WantedBy)
   ```
3. Confirm waypaper-restore is the active restore service:
   ```bash
   systemctl --user cat waypaper-restore.service | grep WantedBy
   # Should show: WantedBy=sway-session.target
   ```

### Blank Background on First Run

The Stylix fallback should handle this. If it doesn't:

```bash
# Check if config was generated
cat ~/.config/waypaper/config.ini

# If missing and Stylix is enabled, manually trigger
systemctl --user start waypaper-restore.service
journalctl --user -u waypaper-restore.service -b --no-pager
# Look for: "no config found, generating default from Stylix image"
```

### GUI Doesn't Launch

```bash
which waypaper
waypaper  # Launch manually to see errors
```

## Verification After Deploy

```bash
# 1. swww-restore should NOT auto-start (when waypaperEnable=true)
systemctl --user status swww-restore.service  # expect: inactive

# 2. waypaper-restore should have run successfully
systemctl --user status waypaper-restore.service
journalctl --user -u waypaper-restore.service -b --no-pager

# 3. Test Stylix fallback (first-run simulation)
mv ~/.config/waypaper/config.ini ~/.config/waypaper/config.ini.bak
swww clear
systemctl --user start waypaper-restore.service
cat ~/.config/waypaper/config.ini  # Should contain Stylix image path
mv ~/.config/waypaper/config.ini.bak ~/.config/waypaper/config.ini

# 4. Test imperative persistence
# Open Waypaper GUI, set a new wallpaper, then:
systemctl --user start waypaper-restore.service
# Wallpaper should match what you set in GUI

# 5. Monitor wake test
# Lock screen / let monitors power off, then wake → wallpaper should restore
```

## Migration from SwayBG+

SwayBG+ is deprecated in favor of Waypaper:

```nix
systemSettings = {
  swwwEnable = true;
  waypaperEnable = true;    # Replaces swaybgPlusEnable
  swaybgPlusEnable = false; # DEPRECATED
};
```

## Related Documentation

- `docs/user-modules/swww.md` — swww daemon and swww-restore (backward compat)
- `docs/user-modules/sway-daemon-integration.md` — Sway systemd services
- `user/app/waypaper/waypaper.nix` — Waypaper module implementation
- `user/app/swww/swww.nix` — swww module (daemon + conditional restore)
- `user/wm/sway/swayfx-config.nix` — Monitor wake restore dispatch

## See Also

- Waypaper GitHub: https://github.com/anufrievroman/waypaper
- swww Documentation: https://github.com/Horus645/swww
