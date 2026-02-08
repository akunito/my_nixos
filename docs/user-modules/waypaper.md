---
id: waypaper
summary: Waypaper GUI wallpaper manager for Sway (swww backend)
tags: [waypaper, wallpaper, sway, swww, gui]
related_files:
  - user/app/waypaper/waypaper.nix
  - user/app/swww/swww.nix
  - profiles/DESK-config.nix
  - profiles/LAPTOP-base.nix
---

# Waypaper - GUI Wallpaper Manager for Sway

Waypaper is a lightweight GUI wallpaper manager that integrates with the swww wallpaper daemon for SwayFX. It provides a visual interface for selecting wallpapers with multi-monitor support and automatic restoration.

## Overview

- **Backend**: swww (Wayland Animated Wallpaper Daemon)
- **Frontend**: Waypaper GUI (315 KB)
- **Keybinding**: Hyper+Shift+S (Ctrl+Alt+Super+Shift+S)
- **Storage**: `~/.config/waypaper/` (wallpaper config and state)

## Features

- Multi-monitor wallpaper configuration
- Per-monitor wallpaper selection
- Automatic restoration on login
- Restoration after Home-Manager rebuild
- Native `waypaper --restore` command
- Minimal footprint (315 KB)
- Actively maintained

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Sway Session Startup                     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ├─► swww-daemon.service (backend)
                     │   └─► Manages wallpaper rendering
                     │
                     └─► waypaper-restore.service (restoration)
                         ├─► After: swww-daemon.service
                         └─► ExecStart: waypaper --restore

┌─────────────────────────────────────────────────────────────┐
│                User Interaction (Hyper+Shift+S)             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     └─► waypaper (GUI)
                         ├─► Select wallpapers per monitor
                         ├─► Preview in GUI
                         ├─► Apply via swww backend
                         └─► Save config to ~/.config/waypaper/
```

## Configuration

### Enable in Profile

**For DESK:**
```nix
# profiles/DESK-config.nix
systemSettings = {
  swwwEnable = true;        # Backend daemon
  waypaperEnable = true;    # GUI frontend
};
```

**For Laptops:**
```nix
# profiles/LAPTOP-base.nix (inherited by LAPTOP_L15, LAPTOP_YOGAAKU)
systemSettings = {
  swwwEnable = true;        # Backend daemon
  waypaperEnable = true;    # GUI frontend
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

- **Keybinding**: Hyper+Shift+S (Ctrl+Alt+Super+Shift+S)
- **Command**: `waypaper`
- **Application Launcher**: Search for "Waypaper" in Rofi

### GUI Workflow

1. Press Hyper+Shift+S to launch Waypaper
2. GUI opens as a floating window (1200x800px, centered)
3. Select monitor from dropdown (if multi-monitor)
4. Browse wallpapers from selected folder
5. Click wallpaper to preview
6. Click "Apply" to set wallpaper
7. Repeat for each monitor
8. Close GUI - wallpapers are saved automatically

### Multi-Monitor Setup (DESK Example)

**DESK has 4 monitors:**
1. Samsung Odyssey G70NC (3840x2160@120Hz, scale 1.6) - Primary
2. NSL RGB-27QHDS (2560x1440@144Hz, scale 1.25, portrait)
3. Philips FTV (1920x1080@60Hz)
4. BNQ ZOWIE XL (1920x1080@60Hz)

**Workflow:**
1. Launch Waypaper (Hyper+Shift+S)
2. Select "Samsung Odyssey G70NC" from monitor dropdown
3. Choose wallpaper, click Apply
4. Select "NSL RGB-27QHDS" from dropdown
5. Choose different wallpaper, click Apply
6. Repeat for Philips and BNQ
7. Close GUI

Waypaper saves configuration to `~/.config/waypaper/config.ini` with per-monitor settings.

## Restoration

### On Login

Wallpapers are restored automatically when Sway starts via systemd service:

```nix
systemd.user.services.waypaper-restore = {
  Unit = {
    Description = "Waypaper Wallpaper Restoration";
    After = [ "swww-daemon.service" ];
    PartOf = [ "sway-session.target" ];
  };
  Service = {
    Type = "oneshot";
    ExecStart = "waypaper --restore";
  };
  Install = {
    WantedBy = [ "sway-session.target" ];
  };
};
```

### After Home-Manager Rebuild

Home-Manager activation hook automatically restores wallpapers after `home-manager switch`:

```nix
home.activation.waypaperRestore = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  if systemctl --user is-active sway-session.target >/dev/null 2>&1; then
    run waypaper --restore
  fi
'';
```

### Manual Restoration

```bash
# Restore saved wallpapers
waypaper --restore

# Or via systemd service
systemctl --user restart waypaper-restore.service
```

## Configuration Files

### Config Location
```
~/.config/waypaper/
├── config.ini           # Waypaper settings (backend, folder, fill mode)
└── wallpaper.ini        # Per-monitor wallpaper assignments
```

### Example config.ini
```ini
[Settings]
backend = swww
folder = /home/akunito/Pictures/Wallpapers
fill = fill
monitors = all
```

### Example wallpaper.ini
```ini
[Wallpapers]
Samsung Electric Company Odyssey G70NC H1AK500000 = /home/akunito/Pictures/Wallpapers/mountains.jpg
NSL RGB-27QHDS    Unknown = /home/akunito/Pictures/Wallpapers/forest.png
```

## Troubleshooting

### Wallpapers Not Restored on Login

**Check swww daemon:**
```bash
systemctl --user status swww-daemon.service
```

**Check waypaper-restore service:**
```bash
systemctl --user status waypaper-restore.service
journalctl --user -u waypaper-restore.service
```

**Manual restore:**
```bash
waypaper --restore
```

### GUI Doesn't Launch

**Check if Waypaper is installed:**
```bash
which waypaper
waypaper --version
```

**Check keybinding in Sway:**
```bash
swaymsg -t get_binding_state
```

**Launch manually:**
```bash
waypaper
```

### Wrong Monitor Names

Waypaper uses the same hardware IDs as Sway. Check with:
```bash
swaymsg -t get_outputs
```

Output includes `make`, `model`, `serial` - Waypaper concatenates these.

### Wallpapers Disappear After Home-Manager Rebuild

This should be fixed by the activation hook. If it persists:

1. Check activation hook ran:
```bash
journalctl --user -n 100 | grep waypaper
```

2. Manually trigger:
```bash
waypaper --restore
```

3. Verify config exists:
```bash
cat ~/.config/waypaper/wallpaper.ini
```

## Migration from SwayBG+

SwayBG+ is deprecated in favor of Waypaper. Migration is automatic:

**Old config:**
```nix
systemSettings = {
  swwwEnable = true;
  swaybgPlusEnable = true;  # DEPRECATED
};
```

**New config:**
```nix
systemSettings = {
  swwwEnable = true;
  waypaperEnable = true;    # Use this instead
};
```

**Migration steps:**
1. Update profile: `waypaperEnable = true`, `swaybgPlusEnable = false`
2. Rebuild: `sudo nixos-rebuild switch --flake .#DESK`
3. Launch Waypaper: Hyper+Shift+S
4. Re-select wallpapers (SwayBG+ and Waypaper use different config formats)

**Differences:**
- SwayBG+ uses swaybg backend (conflicts with swww)
- Waypaper uses swww backend (same as swww-restore.service)
- Waypaper is lighter (315 KB vs several MB)
- Waypaper has native `--restore` command

## Technical Details

### swww Backend Integration

Waypaper communicates with swww daemon via IPC:

```bash
# Waypaper internally runs commands like:
swww img /path/to/wallpaper.jpg --outputs MONITOR_NAME --transition-type fade
```

### Window Rules

Waypaper window is configured to float and resize:

```nix
# swayfx-config.nix
for_window [app_id="waypaper"] floating enable, resize set 1200 800
```

### Dependencies

- **swww**: Wallpaper rendering backend (systemSettings.swwwEnable)
- **waypaper**: GUI frontend (from nixpkgs)
- **systemd**: Service management for restoration

## Related Documentation

- `docs/user-modules/swww.md` - swww daemon configuration
- `docs/user-modules/sway-daemon-integration.md` - Sway systemd services
- `user/app/waypaper/waypaper.nix` - Waypaper module implementation
- `user/app/swww/swww.nix` - swww daemon implementation

## See Also

- Waypaper GitHub: https://github.com/anufrievroman/waypaper
- swww Documentation: https://github.com/Horus645/swww
