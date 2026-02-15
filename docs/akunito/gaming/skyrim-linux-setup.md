# Skyrim Modded Setup on NixOS/Linux — Setup Guide

This guide documents the complete process for installing and running modded Skyrim (LoreRim, Wildlander, etc.) on NixOS using Jackify, Proton, and Gamescope under Sway/Wayland.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Jackify Installation on NixOS](#2-jackify-installation-on-nixos)
3. [Modlist Installation Process](#3-modlist-installation-process)
4. [Post-Installation Fixes](#4-post-installation-fixes)
5. [Steam Launch Options](#5-steam-launch-options)
6. [Anniversary Edition CC Content](#6-anniversary-edition-cc-content)
7. [Key Paths Reference](#7-key-paths-reference)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Prerequisites

- **NixOS** with `steam-run` available (provided by `programs.steam.enable = true` or `pkgs.steam-run`)
- **Steam** with Skyrim Special Edition installed
- **Proton 9.0 (Beta)** installed via Steam (Steam → Settings → Compatibility → enable Steam Play for all titles)
- **Gamescope** (for Wayland/Sway compositing — avoids window/mouse issues)
- **Python 3.13+** (via Nix, for Jackify's backend)

---

## 2. Jackify Installation on NixOS

### 2.1 Download and Extract

Jackify is an AppImage-based modlist installer (alternative to Wabbajack for Linux).

```bash
# Download Jackify.AppImage to your tools directory
mkdir -p /mnt/2nd_NVME/Games/Tools/Jackify
# Place Jackify.AppImage in the above directory

# Extract the AppImage (NixOS can't run AppImages directly)
cd /mnt/2nd_NVME/Games/Tools/Jackify
steam-run ./Jackify.AppImage --appimage-extract
# Move contents to the expected cache location:
mkdir -p ~/.cache/appimage-run/
mv squashfs-root ~/.cache/appimage-run/<hash>
# The hash is the SHA256 of the AppImage file
```

### 2.2 The NixOS Launcher Script

NixOS cannot run most Linux binaries directly due to its non-FHS filesystem layout. The custom launcher script `run-jackify.sh` (located at `/mnt/2nd_NVME/Games/Tools/Jackify/run-jackify.sh`) handles all compatibility:

**What it does:**

1. **Python environment**: Uses NixOS's Python 3.13 with explicit Nix store library paths for Qt/PySide6, OpenGL, Wayland, X11, fontconfig, dbus, Kerberos, OpenSSL, and more (15+ library paths)

2. **FHS binary wrapping**: Wraps bundled ELF binaries (`cabextract`, `7z`) with `steam-run` so NixOS can execute them:
   ```bash
   # The script automatically wraps detected ELF tools:
   mv cabextract cabextract.bin
   # Creates wrapper: exec steam-run cabextract.bin "$@"
   ```

3. **Winetricks patches** (Proton compatibility):
   - **Null-byte stripping**: Proton's `cmd.exe` outputs null bytes in paths, which makes `grep` treat output as binary. The script patches winetricks to pipe through `tr -d '\0'`
   - **WINEDEBUG fix**: Changes `WINEDEBUG=-all` to `WINEDEBUG=fixme-all` because Proton completely suppresses `cmd.exe` stdout with `-all`, breaking path detection

4. **Wine wrapper patches**:
   - Replaces `#!/bin/bash` with `#!/usr/bin/env bash` (NixOS doesn't have `/bin/bash`)
   - Wraps wine calls with `steam-run` for FHS compatibility
   - Adds `wineserver -k` cleanup after each wine operation to prevent stale `/dev/shm/wine-*-fsync` files across separate `steam-run` invocations

5. **TMPDIR preservation**: Sets `TMPDIR`/`TMP`/`TEMP` to `$JACKIFY_HOME/.tmp` because `steam-run` mounts its own `/tmp`, breaking wine's stderr redirect to temp files

**To run Jackify:**
```bash
cd /mnt/2nd_NVME/Games/Tools/Jackify
./run-jackify.sh
```

### 2.3 Jackify Configuration

- Config file: `~/.config/jackify/config.json`
- Data directory: `~/Jackify/` (or custom path set in config)
- OAuth tokens: `~/Jackify/token-status.json` (Nexus Mods authentication)
- Wine wrappers: `~/Jackify/wine_wrappers/` (generated per-Proton version)

---

## 3. Modlist Installation Process

### 3.1 Using Jackify GUI

1. Run `./run-jackify.sh` from the Jackify directory
2. Select a modlist (e.g., LoreRim, Wildlander)
3. Configure paths:
   - **Install location**: e.g., `/mnt/2nd_NVME/Games/Skyrim/LoreRim/`
   - **Downloads folder**: e.g., `/mnt/2nd_NVME/Games/Skyrim/Downloads/`
   - **Skyrim base game**: Points to your Steam Skyrim installation
4. Jackify will download mods from Nexus and install them

### 3.2 Manual Proton Prefix Creation

If Jackify's automated prefix creation fails (common on NixOS), manually create it:

```bash
export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/akunito/.steam/steam"
export STEAM_COMPAT_DATA_PATH="/home/akunito/.steam/steam/steamapps/compatdata/<APPID>"
# Replace <APPID> with the Steam app ID (e.g., 3500610100 for LoreRim)

# Create prefix using Proton
steam-run python3 \
  "/home/akunito/.steam/steam/steamapps/common/Proton 9.0 (Beta)/proton" \
  run echo "Prefix created"
```

### 3.3 Post-Install MO2 Setup

After modlist installation, MO2 (Mod Organizer 2) is bundled inside the modlist directory. Launch it via the modlist's MO2 executable through Proton/steam-run.

---

## 4. Post-Installation Fixes

### 4.1 ENB Linux Fix (CRITICAL)

ENB requires a special flag for Linux/Proton. Set `LinuxVersion=true` in **ALL active** `enblocal.ini` files.

There are typically two locations that both need this fix:

**1. ENB Local Override mod** (engine settings):
```
<modlist>/mods/ENB Local Override (ALWAYS KEEP ON)/Root/enblocal.ini
```

**2. ENB preset mod** (visual preset):
```
<modlist>/mods/<ENB Preset Name>/Root/enblocal.ini
```

Add or verify in `[GLOBAL]` section:
```ini
[GLOBAL]
LinuxVersion=true
```

Both files must have this setting. The ENB Local Override takes priority for engine settings, but the preset's enblocal.ini also gets loaded.

### 4.2 Gamescope Sway Crash Fix

Without the `-r` (refresh rate) flag, gamescope can crash the Sway compositor when alt-tabbing or on resolution changes.

Add `-r 120` to gamescope launch options (adjust to your monitor's refresh rate).

### 4.3 Mouse/Window Grab Fix

Under Sway/Wayland, the game window may not properly capture the mouse. Add:
```
-g --force-grab-cursor
```
to gamescope launch options.

### 4.4 DXVK AMD Pipeline Fix

On AMD GPUs, DXVK's graphics pipeline library can cause shader compilation stuttering or crashes. Create/edit:

```
<modlist>/Stock Game/dxvk.conf
```

Add:
```
dxvk.enableGraphicsPipelineLibrary = False
```

This disables async pipeline compilation which is problematic on some AMD driver versions.

---

## 5. Steam Launch Options

### 5.1 Full Launch Options Template

Add to Steam → Skyrim → Properties → Launch Options:

```
MANGOHUD=0 STEAM_COMPAT_MOUNTS="/mnt/2nd_NVME/SteamLibrary:/mnt/DATA/SteamLibrary:/mnt/2nd_NVME" gamescope -W 3840 -H 2160 -w 3840 -h 2160 -f -r 120 -g --force-grab-cursor -- %command%
```

### 5.2 Explanation of Options

| Option | Purpose |
|--------|---------|
| `MANGOHUD=0` | Disable MangoHUD overlay (set to 1 to enable FPS counter) |
| `STEAM_COMPAT_MOUNTS="..."` | Make additional drives visible to Proton (critical for mods on secondary drives) |
| `gamescope` | Wayland-native game compositor (avoids Sway window management issues) |
| `-W 3840 -H 2160` | Outer resolution (your monitor resolution) |
| `-w 3840 -h 2160` | Inner/game resolution |
| `-f` | Fullscreen |
| `-r 120` | Refresh rate limit (prevents Sway crash, match your monitor) |
| `-g --force-grab-cursor` | Properly grab mouse cursor in game window |
| `-- %command%` | Pass through to the actual game executable |

### 5.3 Adjusting for Different Monitors

- **1440p 165Hz**: `-W 2560 -H 1440 -w 2560 -h 1440 -f -r 165`
- **1080p 60Hz**: `-W 1920 -H 1080 -w 1920 -h 1080 -f -r 60`
- **Ultrawide 3440x1440**: `-W 3440 -H 1440 -w 3440 -h 1440 -f -r 144`

---

## 6. Anniversary Edition CC Content

### 6.1 Requirements

- You must own the **Anniversary Edition DLC** in Steam
- Many modlists (LoreRim, etc.) require the full CC content library

### 6.2 Downloading CC Content

If Creation Club content is not present after installing AE DLC:

1. Open Steam → Right-click Skyrim Special Edition → Properties
2. Click **Verify Integrity of Game Files**
3. Steam will download all CC content

### 6.3 Verification

Check your Skyrim `Data` folder for CC files:
```bash
ls /mnt/2nd_NVME/SteamLibrary/steamapps/common/Skyrim\ Special\ Edition/Data/cc*.{esl,bsa,esm} 2>/dev/null | wc -l
```

You should have approximately **175 files** (mix of `cc*.esl`, `cc*.bsa`, and `cc*.esm`). If the count is significantly lower, re-verify game files in Steam.

---

## 7. Key Paths Reference

| Item | Path |
|------|------|
| **Jackify AppImage** | `/mnt/2nd_NVME/Games/Tools/Jackify/Jackify.AppImage` |
| **Jackify launcher** | `/mnt/2nd_NVME/Games/Tools/Jackify/run-jackify.sh` |
| **Jackify data** | `~/Jackify/` |
| **Jackify config** | `~/.config/jackify/config.json` |
| **LoreRim install** | `/mnt/2nd_NVME/Games/Skyrim/LoreRim/` |
| **LoreRim profiles** | `/mnt/2nd_NVME/Games/Skyrim/LoreRim/profiles/Ultra/` |
| **Wildlander install** | `/mnt/2nd_NVME/Games/Skyrim/Wildlander/Wildlander/` |
| **Mod downloads** | `/mnt/2nd_NVME/Games/Skyrim/Downloads/` |
| **Skyrim base game** | `/mnt/2nd_NVME/SteamLibrary/steamapps/common/Skyrim Special Edition/` |
| **LoreRim Proton prefix** | `~/.steam/steam/steamapps/compatdata/3500610100/` |
| **Proton 9.0 Beta** | `~/.local/share/Steam/steamapps/common/Proton 9.0 (Beta)/` |
| **ENB Local Override** | `<modlist>/mods/ENB Local Override (ALWAYS KEEP ON)/Root/` |
| **ENB Preset (Cabbage)** | `<modlist>/mods/Cabbage ENB - Lore Cut NEW VERSION - (HEAVIER)/Root/` |
| **DXVK config** | `<modlist>/Stock Game/dxvk.conf` |

---

## 8. Troubleshooting

### Game won't launch / CTD on startup
1. Verify ENB `LinuxVersion=true` is set in **both** enblocal.ini files
2. Check DXVK config exists with `enableGraphicsPipelineLibrary = False`
3. Verify Proton prefix exists at the correct path
4. Check Steam launch options include `STEAM_COMPAT_MOUNTS` for all drives with mod data

### Black screen / no display
1. Ensure gamescope resolution matches your monitor
2. Try without gamescope first to isolate the issue
3. Check if Proton version matches what the modlist expects

### Mouse doesn't work properly
1. Add `--force-grab-cursor` to gamescope options
2. Ensure `-g` flag is present
3. If using multiple monitors, gamescope `-f` should focus the correct one

### Sway crashes when alt-tabbing
1. Add `-r <refresh_rate>` to gamescope options
2. This is a known gamescope/Sway interaction bug

### Winetricks/DXVK install fails during modlist setup
1. Ensure `run-jackify.sh` has applied the winetricks patches (check console output)
2. Manually verify null-byte and WINEDEBUG patches were applied
3. Try running with `WINEDEBUG=+relay` for detailed wine logs

### Mod Organizer 2 can't find game
1. Verify `STEAM_COMPAT_MOUNTS` includes the drive where Skyrim is installed
2. Check that the modlist's `ModOrganizer.ini` points to the correct game path
3. The Stock Game folder inside the modlist should contain a copy of the Skyrim executables

### Performance issues
1. Check that MangoHUD shows expected GPU/CPU usage
2. ENB is the biggest performance factor — try a lighter preset
3. Grass mods (`iMinGrassSize`, `iGrassCellRadius`) can be tuned in `skyrimprefs.ini`
4. Disable ENB depth of field and ambient occlusion for significant FPS gains
