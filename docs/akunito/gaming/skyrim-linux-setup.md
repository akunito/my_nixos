---
id: gaming.skyrim-linux-setup
summary: Complete guide for modded Skyrim (LoreRim) on NixOS/Linux with ENB, Gamescope, and AMD GPU performance tuning
tags: [gaming, skyrim, enb, gamescope, proton, amd, performance, wayland]
related_files: [system/app/gamemode.nix, user/app/games/games.nix]
date: 2026-09-13
status: published  # install WIPED 2026-09-13; restore path in section 9
---

# Skyrim Modded Setup on NixOS/Linux — Setup Guide

This guide documents the complete process for installing and running modded Skyrim (LoreRim, Wildlander, etc.) on NixOS using Jackify, Proton, and Gamescope under Sway/Wayland.

> **STATUS 2026-09-13 — the install is GONE.** The partition that held everything
> (`/mnt/2nd_NVME`, LUKS+ext4 on `nvme0n1p5`) was wiped and handed back to Windows
> as a second NTFS partition (Aion 2 and other Windows-only games). Every
> `/mnt/2nd_NVME/...` path below is historical. What survived is a **backup bundle**
> on `/mnt/DATA_SATA3/Skyrim-LoreRim-backup-2026-09-13/` (6.6 GB: profiles + saves,
> MO2 config, overwrite/, tools/, the hand-added survival mods, the ENB/INI tweaks,
> Jackify). The 4155-mod `mods/` tree (277 GB) and the 9513 Nexus archives in
> `Downloads/` (256 GB) were deliberately **not** kept — a reinstall re-downloads
> them through Jackify. **To reinstall, go straight to [section 9](#9-reinstalling-from-the-2026-09-13-bundle).**

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Jackify Installation on NixOS](#2-jackify-installation-on-nixos)
3. [Modlist Installation Process](#3-modlist-installation-process)
4. [Post-Installation Fixes](#4-post-installation-fixes) (ENB, Gamescope, Mouse, DXVK, ENB Effects, Framerate, Kernel, VRAM Leak)
5. [Steam Launch Options](#5-steam-launch-options)
6. [Anniversary Edition CC Content](#6-anniversary-edition-cc-content)
7. [Key Paths Reference](#7-key-paths-reference)
8. [Troubleshooting](#8-troubleshooting)
9. [Reinstalling from the 2026-09-13 bundle](#9-reinstalling-from-the-2026-09-13-bundle)

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

### 4.2 Gamescope Frame Pacing (IMPORTANT)

**Do NOT use `-r <rate>` with gamescope on Wayland.** Setting a refresh rate limiter (e.g., `-r 120`) causes gamescope to repeatedly upscale frames via FSR when the game renders below that rate, wasting GPU resources and causing system-wide lag (including secondary monitors). This is a known issue on the Wayland backend (gamescope issue #1479).

Instead, let Sway's monitor refresh rate and SSEDisplayTweaks handle frame timing.

### 4.3 Mouse/Window Grab Fix

Use `LockCursor=true` in SSEDisplayTweaks INI for cursor confinement instead of `--force-grab-cursor`, which causes extreme lag spikes on gamescope 3.16.x (issue #1851).

### 4.4 DXVK Config: GPL Fix + VRAM Cap (CRITICAL)

On AMD GPUs, DXVK and RADV can both enable Graphics Pipeline Library (GPL) simultaneously — DXVK via `dxvk.enableGraphicsPipelineLibrary = True` and RADV via `RADV_PERFTEST=gpl` in launch options. This **double GPL** creates duplicate pipeline objects causing unbounded VRAM growth.

Additionally, RADV has a catastrophic performance cliff when VRAM fills completely (Mesa issue #3698): GPU utilization drops to 0%, frametime spikes to 398ms, FPS drops to 3. Unlike the Windows AMD driver, RADV cannot gracefully overflow to system RAM. Capping reported VRAM prevents reaching this cliff.

Create/edit:
```
<modlist>/Stock Game/dxvk.conf
```

Add:
```ini
dxvk.enableGraphicsPipelineLibrary = False

dxgi.maxDeviceMemory = 8192
dxgi.maxSharedMemory = 8192
```

- **GPL = False**: RADV handles GPL via `RADV_PERFTEST=gpl` in launch options; DXVK must NOT also enable it
- **VRAM cap = 8GB**: Prevents DXVK/Skyrim from allocating beyond ~8GB, keeping headroom for driver/compositor; avoids RADV's catastrophic overflow behavior

### 4.5 ENB Linux-Problematic Effects (IMPORTANT)

Disable these effects in the ENB preset's `enbseries.ini` (`[EFFECT]` section) — they are broken or cause stutter on Linux/Proton:

```ini
EnableSunGlare=false        # Causes brightness stutter on Linux
EnableUnderwaterShader=false # Known broken on Linux/Proton
```

File location:
```
<modlist>/mods/<ENB Preset Name>/Root/enbseries.ini
```

### 4.6 SSEDisplayTweaks Framerate Limit

Set `FramerateLimit` to match your achievable FPS, not your monitor's refresh rate. If your game runs at 39-45 FPS with ENB, a 120 FPS limit wastes CPU cycles and causes Havok physics to calculate for 120 FPS headroom.

```ini
FramerateLimit = 60
```

File location:
```
<modlist>/mods/LoreRim - MCM and INI Settings/SKSE/Plugins/SSEDisplayTweaks.ini
```

### 4.7 AMD Kernel Optimizations (NixOS)

For AMD GPUs (RDNA 4 / 9700XT), the `split_lock_detect=off` kernel parameter prevents the kernel from penalizing Wine/Proton split-lock instructions, which can cause micro-stutters. This is set automatically via `system/app/gamemode.nix` when `gpuType = "amd"`.

Verify after reboot:
```bash
cat /proc/cmdline | grep split_lock_detect
```

### 4.8 VRAM Leak Prevention (AMD 16GB GPUs) — SOLVED

Modded Skyrim on Linux suffers progressive VRAM exhaustion: VRAM climbs to 15.7/16 GB over ~10 minutes regardless of ENB status, then RADV's poor overflow handling stalls the GPU. The leak persists after closing the game (gamescope holds the VRAM). This does NOT happen on Windows.

**Root cause: Gamescope Wayland backend.** When gamescope inherits `WAYLAND_DISPLAY` from Sway, it uses the Wayland backend which leaks VRAM progressively. Forcing gamescope to use X11/Xwayland via `env -u WAYLAND_DISPLAY` eliminates the leak entirely.

**Fix applied:**
```
env -u WAYLAND_DISPLAY radv_zero_vram=false MANGOHUD=0 ENABLE_LAYER_MESA_ANTI_LAG=1 ~/.config/sway/scripts/gamescope-wrapper.sh -W 2560 -H 1440 -w 2560 -h 1440 -f --mangoapp --rt -- %command%
```

**Additional config** (in `dxvk.conf` — see section 4.4):
- `dxvk.enableGraphicsPipelineLibrary = False` — prevents double GPL with RADV
- `dxgi.maxDeviceMemory = 8192` / `dxgi.maxSharedMemory = 8192` — safety cap against RADV overflow

**Test results (2026-02-16):**

| Test | Launch options change | Result |
|------|---------------------|--------|
| 1 | dxvk.conf fixes only (GPL=False + VRAM caps) | VRAM still leaked |
| 2 | + `radv_zero_vram=false` | VRAM still leaked |
| 3 | + `env -u WAYLAND_DISPLAY` | **Stable 30-40 min, no leak** |

**Optional:** Install [Skyrim AE Memory Leak Fix](https://www.nexusmods.com/skyrimspecialedition/mods/169302) via MO2 — addresses Skyrim's own memory leak in Anniversary Edition.

---

## 5. Steam Launch Options

### 5.1 Full Launch Options Template

Add to Steam → Skyrim → Properties → Launch Options:

```
env -u WAYLAND_DISPLAY radv_zero_vram=false MANGOHUD=0 ENABLE_LAYER_MESA_ANTI_LAG=1 ~/.config/sway/scripts/gamescope-wrapper.sh -W 2560 -H 1440 -w 2560 -h 1440 -f --mangoapp --rt -- %command%
```

### 5.2 Explanation of Options

| Option | Purpose |
|--------|---------|
| `env -u WAYLAND_DISPLAY` | Forces gamescope to use X11/Xwayland backend — **prevents VRAM leak** on Wayland (see 4.8) |
| `radv_zero_vram=false` | Disables RADV zero-fill on VRAM allocations — reduces overhead on kernel 6.2+ |
| `MANGOHUD=0` | Prevents global MangoHud from injecting (gamescope uses `--mangoapp` instead) |
| `ENABLE_LAYER_MESA_ANTI_LAG=1` | AMD Anti-Lag via Mesa's implicit Vulkan layer — reduces input latency by pacing CPU-GPU sync (requires Mesa 25.3+) |
| `gamescope-wrapper.sh` | Wrapper script that sets `STEAM_COMPAT_MOUNTS` and launches gamescope |
| `-W 2560 -H 1440` | Outer resolution (your monitor resolution) |
| `-w 2560 -h 1440` | Inner/game resolution (native 1440p, no upscaling) |
| `-f` | Fullscreen |
| `--mangoapp` | MangoHud as gamescope-native overlay (no duplicate injection) |
| `--rt` | Realtime scheduling for gamescope threads (prevents GPU clock oscillation) |
| `-- %command%` | Pass through to the actual game executable |

**Removed options** (cause issues):
- `RADV_PERFTEST=gpl` — GPL not needed; dxvk.conf has GPL disabled and VRAM caps handle overflow
- `-r <rate>` — causes FSR upscale spam when game FPS < target rate (issue #1479)
- `--force-grab-cursor` — causes extreme lag spikes on gamescope 3.16.x (issue #1851); use SSEDisplayTweaks `LockCursor=true` instead
- `-F fsr` — not needed when running at native resolution; adds compositor overhead

**Alternative: Test without gamescope** (if native 1440p with no FSR):
```
radv_zero_vram=false MANGOHUD=1 ENABLE_LAYER_MESA_ANTI_LAG=1 %command%
```
If performance improves without gamescope, the compositor overhead isn't worth it at native resolution.

### 5.3 Adjusting for Different Monitors

- **4K with FSR**: `-W 3840 -H 2160 -w 2560 -h 1440 -F fsr -f`
- **1440p native**: `-W 2560 -H 1440 -w 2560 -h 1440 -f`
- **1080p native**: `-W 1920 -H 1080 -w 1920 -h 1080 -f`
- **Ultrawide 3440x1440**: `-W 3440 -H 1440 -w 3440 -h 1440 -f`

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

> Historical — these paths no longer exist (see the status banner). The bundle
> equivalents are listed in section 9.2.

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
1. Set `LockCursor=true` in SSEDisplayTweaks INI (preferred over `--force-grab-cursor`)
2. If using multiple monitors, gamescope `-f` should focus the correct one

### System-wide lag during gameplay (secondary monitors stutter)
1. Remove `-r <rate>` from gamescope options — causes FSR upscale spam on Wayland
2. Remove `--force-grab-cursor` — causes lag spikes on gamescope 3.16.x
3. Ensure `RADV_PERFTEST` and `MANGOHUD` are NOT set session-wide (check `echo $RADV_PERFTEST`)
4. Use `--mangoapp` instead of `MANGOHUD=1` with gamescope
5. Verify SwayFX blur/shadows are disabled for gamescope window (check sway config)

### Winetricks/DXVK install fails during modlist setup
1. Ensure `run-jackify.sh` has applied the winetricks patches (check console output)
2. Manually verify null-byte and WINEDEBUG patches were applied
3. Try running with `WINEDEBUG=+relay` for detailed wine logs

### Mod Organizer 2 can't find game
1. Verify `STEAM_COMPAT_MOUNTS` includes the drive where Skyrim is installed
2. Check that the modlist's `ModOrganizer.ini` points to the correct game path
3. The Stock Game folder inside the modlist should contain a copy of the Skyrim executables

### VRAM leak / progressive performance degradation (AMD GPUs)
1. **Most likely fix**: Add `env -u WAYLAND_DISPLAY` before gamescope — forces X11/Xwayland backend, prevents gamescope Wayland backend VRAM leak (see 4.8)
2. Add `radv_zero_vram=false` to launch options — reduces VRAM allocation overhead on kernel 6.2+
3. Check `dxvk.conf` has `dxvk.enableGraphicsPipelineLibrary = False` — prevents double GPL with RADV
4. Check `dxvk.conf` has `dxgi.maxDeviceMemory = 8192` and `dxgi.maxSharedMemory = 8192` — safety cap against RADV catastrophic overflow at 16GB
5. Optionally install [Skyrim AE Memory Leak Fix](https://www.nexusmods.com/skyrimspecialedition/mods/169302) mod via MO2

### World map invisible / shows only sky (FWMF flat map broken on Linux)

**Symptom**: Pressing M shows a purple/blue sky background with map markers floating in space. A sliver of map texture may be visible at the screen edge. Local maps work fine.

**Cause**: Flat World Map Framework (FWMF) renders the world map as a 2D plane. On Linux/Proton, the FWMF SKSE plugin (`FlatMapMarkersSSE.dll`) and/or the flat map mesh don't render correctly, leaving the camera looking at empty sky instead of the map plane. INI fixes (`fMapWorldMaxPitch`, blur settings, focal depth) do not resolve the issue — the flat plane simply doesn't display properly under Proton/DXVK.

**Fix**: Disable FWMF and all paper map mods in MO2, reverting to the vanilla 3D world map.

In `profiles/<profile>/modlist.txt`, change `+` to `-` for:
- `Flat World Map Framework (FWMF)`
- `Skyrim Paper Map by Caro Tuts for FWMF`
- All area-specific paper maps (`Vigilant Paper Map for FWMF`, `Duncan's Paper Maps for FWMF`, `Solstheim and Baan Malur Paper Map for FWMF`, etc.)

In `profiles/<profile>/plugins.txt`, remove the `*` prefix from:
- `FWMF for Fantasy Paper Maps.esp`
- `DLC1MapMarkerEnabler.esp`
- `FWMF - Ultimate Patch.esp`

**What was tried and didn't work**:
1. Adjusting `[MapMenu]` in `skyrim.ini` (`fMapWorldMaxPitch=20`, `fMapWorldYawRange=10`, blur settings) — no effect
2. Applying all 16 FWMF recommended INI values (zoom speed, focal depth, height adjustment force) — no effect
3. Toggling ENB on/off (Shift+F12) while on map — no effect
4. Manual camera adjustment (scroll wheel, right-click drag) — flat plane not visible at any angle

**Note**: `RUSTIC MAPS` is NOT related — it retextures decorative in-world maps (`textures/dlc02/clutter/`), not the world map. Keep it enabled.

### Performance issues
1. Check that MangoHUD shows expected GPU/CPU usage
2. ENB is the biggest performance factor — try a lighter preset
3. Grass mods (`iMinGrassSize`, `iGrassCellRadius`) can be tuned in `skyrimprefs.ini`
4. Disable ENB depth of field and ambient occlusion for significant FPS gains
5. Disable `EnableSunGlare` and `EnableUnderwaterShader` in ENB `enbseries.ini` — both are broken/problematic on Linux
6. Lower `FramerateLimit` in SSEDisplayTweaks to match achievable FPS (e.g., 60) to reduce Havok physics overhead
7. Verify `split_lock_detect=off` is in kernel params (`cat /proc/cmdline`) — prevents Wine/Proton penalty on RDNA 4
8. Use `ENABLE_LAYER_MESA_ANTI_LAG=1` in launch options for AMD Anti-Lag (Mesa 25.3+)
9. If running at native resolution without FSR, test without gamescope to eliminate compositor overhead

---

## 9. Reinstalling from the 2026-09-13 bundle

### 9.1 What was running when it was wiped

| Item | Value |
|------|-------|
| Modlist | **LoreRim** (Wabbajack `LoreRim_@@_LoreRim.wabbajack`, installed 2026-02-13 via Jackify) |
| MO2 | 2.5.2, portable (`portable.txt`), instance dir = modlist dir |
| Active profile | `Ultra-survival` (LoreRim's `Ultra` + FWMF disabled + survival overhaul from `lorerim-survival-mods.md`) |
| Other profiles | `Ultra` (FWMF still on), `Ultra-BACKUP-presurvival` (pristine Ultra, pre-survival), `Default` |
| Saves | 695 files in `profiles/Ultra-survival/saves/` (3.1 GB), last save 2026-02-16; small sets in `Ultra` and the backup profile |
| Mods | 4155 in `mods/`; 7 added by hand on 2026-02-15 (Campfire, Frostfall, Frostfall - Seasons, Campfire+Frostfall SSE Update, Hunterborn, Hunterborn SE MCM, Scarcity SE) |
| ENB | Cabbage ENB - Lore Cut NEW VERSION (HEAVIER), `LinuxVersion=true` in 3 `enblocal.ini` (Cabbage HEAVIER, ENB Local Override, Silent Horizons 2), `EnableSunGlare=false` + `EnableUnderwaterShader=false` in Cabbage HEAVIER `enbseries.ini` |
| SSEDisplayTweaks | `FramerateLimit = 60`, `LockCursor = true` |
| skyrim.ini (Ultra-survival) | `fDefaultWorldTimescale=12` |
| `Stock Game/dxvk.conf` | GPL off + 8 GB VRAM cap (section 4.4) |
| Steam | Skyrim SE (appid 489830) + AE; non-Steam shortcut "LoreRim" → `mods/Skyrim Script Extender (SKSE64)/Root/skse64_loader.exe`, Proton prefix `~/.steam/steam/steamapps/compatdata/3500610100/` (2 GB, still in `~`) |
| Proton | Jackify config says `Proton - Experimental`; the launch options in section 5 were tuned on Proton 9.0 Beta |
| Jackify | `Jackify.AppImage` from 2026-02-07 (295 MB), extracted to `~/.cache/appimage-run/d67b55f99bc53837d30dd3e4e77655f471496c157adf7813e10316e54abce220/` |

### 9.2 Bundle layout — `/mnt/DATA_SATA3/Skyrim-LoreRim-backup-2026-09-13/`

```
LoreRim/                      # the MO2 instance MINUS mods/ and Stock Game/
  profiles/{Default,Ultra,Ultra-BACKUP-presurvival,Ultra-survival}/   # modlist.txt, plugins.txt, loadorder.txt,
                                                                       # skyrim*.ini, saves/, BethINI cache
  ModOrganizer.ini            # paths still say Z:\mnt\2nd_NVME\... — fix on restore (9.3 step 5)
  overwrite/                  # 131 MB of Synthesis/xEdit/DynDOLOD output
  tools/                      # 2.3 GB: Synthesis, SSEEdit, DynDOLOD, LOOT, BethINI, ... (settings included)
  plugins/ dlls/ loot/ backups/ logs/ crashDumps/ *.compiler_settings nxmhandler.ini ...
  Stock Game/dxvk.conf        # ONLY this file from Stock Game
  mods/
    Campfire - Complete Camping System/            # 7 hand-added survival mods, complete
    Frostfall - Hypothermia Camping Survival/
    Frostfall - Seasons/
    Campfire and Frostfall - Unofficial SSE Update/
    Hunterborn/  Hunterborn SE MCM/  Scarcity SE - Less Loot Mod/
    ENB Local Override (ALWAYS KEEP ON)/Root/*.ini             # ONLY the ini files
    Cabbage ENB - Lore Cut NEW VERSION - (HEAVIER)/Root/*.ini  # ONLY the ini files
    Silent Horizons 2/Root/*.ini                               # ONLY the ini files
    LoreRim - MCM and INI Settings/SKSE/Plugins/SSEDisplayTweaks.ini
Downloads-survival/           # 158 MB: the Nexus archives (+ .meta) of the survival mods
download-survival-mods.py     # Nexus Premium downloader; DOWNLOAD_DIR is hardcoded — edit it
Tools/Jackify/                # Jackify.AppImage + run-jackify.sh (NixOS launcher)
```

Still in `~` and untouched: `~/.config/jackify/` (config.json, nexus-oauth.json — Nexus
OAuth token), `~/Jackify/` (engine, caches, `downloaded_mod_lists/*.wabbajack`,
`wine_wrappers/`), the Proton prefix `compatdata/3500610100`, the Steam shortcut.

### 9.3 Restore procedure

1. **Pick a home for it.** ~600 GB free: install ~280 GB + downloads ~260 GB + Skyrim SE 20 GB. A Steam library on the same disk keeps `STEAM_COMPAT_MOUNTS` simple. Call it `$SKY` below (e.g. `/mnt/DATA_SATA3/Games/Skyrim`).
2. **Skyrim SE + AE in Steam**, then *Verify integrity* until `Data/` holds ~175 `cc*` files (section 6). Proton 9.0 Beta (or whatever the modlist page asks for) enabled.
3. **Jackify.** Copy `Tools/Jackify/` to `$SKY/../Tools/Jackify/` and read `run-jackify.sh` before running it — it hardcodes two things that will be stale:
   - `APP=` the extracted AppImage dir under `~/.cache/appimage-run/<sha256>/` — re-extract per section 2.1 (`steam-run ./Jackify.AppImage --appimage-extract`), the sha256 of the AppImage is the dir name.
   - `PYTHON=` and the 15 `EXTRA_LIBS` entries are **/nix/store paths that have already been garbage-collected**. Regenerate them: `nix build --print-out-paths nixpkgs#python313` (a plain interpreter is what the env was), and for each lib `nix eval --raw nixpkgs#<pkg>.outPath` (`glib`, `zstd`, `zlib`, `gcc.cc.lib`→`stdenv.cc.cc.lib`, `libglvnd`, `xorg.libxcb`, `xorg.libX11`, `libxkbcommon`, `wayland`, `dbus.lib`, `fontconfig.lib`, `freetype`, `krb5.lib`, `openssl.out`). A newer Jackify release may not need any of this — check its NixOS story first.
   - Update `~/.config/jackify/config.json`: `default_install_parent_dir`, `default_download_parent_dir`, `modlist_downloads_base_dir` → `$SKY`.
4. **Install LoreRim with Jackify** to `$SKY/LoreRim`, downloads to `$SKY/Downloads`. This is the 256 GB Nexus re-download: a **Nexus Premium** key makes it unattended; without it Jackify stops on every archive. Manual prefix fallback in section 3.2. *Check the LoreRim version*: the bundle's `modlist.txt` names mods by their 2026-02 names — a newer LoreRim may have renamed/dropped some, in which case merge the profile by hand rather than copying it over.
5. **Overlay the bundle** (LoreRim same version → copy; newer version → diff first):
   ```bash
   B=/mnt/DATA_SATA3/Skyrim-LoreRim-backup-2026-09-13
   rsync -a "$B/LoreRim/profiles/" "$SKY/LoreRim/profiles/"        # profiles + saves
   rsync -a "$B/LoreRim/overwrite/" "$SKY/LoreRim/overwrite/"
   rsync -a "$B/LoreRim/mods/" "$SKY/LoreRim/mods/"                # 7 survival mods + the ini overlays
   cp "$B/LoreRim/Stock Game/dxvk.conf" "$SKY/LoreRim/Stock Game/"
   cp "$B/Downloads-survival/"* "$SKY/Downloads/"                  # so MO2 sees the archives
   ```
   Do **not** copy `ModOrganizer.ini` blindly: take the fresh one from the new install and port over only `selected_profile=Ultra-survival` and the `customExecutables` block (the LoreRim/SKSE launcher); every path inside it is `Z:\mnt\2nd_NVME\...`. Same for `tools/`: only restore it if the new install's tools are missing settings you miss (Synthesis pipelines live in `tools/Synthesis/`).
6. **Re-apply the Linux fixes** — sections 4.1 (ENB `LinuxVersion=true`, already inside the 3 restored ini), 4.4 (dxvk.conf, restored), 4.5, 4.6, then the launch options from section 5 on the Steam shortcut. Re-create the "LoreRim" non-Steam shortcut if `shortcuts.vdf` lost it, pointing at the new `skse64_loader.exe`; the old prefix `3500610100` can be reused if the shortcut keeps that appid, otherwise let Steam make a new one.
7. **Saves**: MO2 profile-local saves are in `profiles/Ultra-survival/saves/` — they load as long as the plugin list matches. Start from `Ultra-BACKUP-presurvival` if the survival mods are not wanted.
8. Run **LOOT** and **Synthesis** from MO2 once (section "Post-Install Verification" in `lorerim-survival-mods.md`), then play.

### 9.4 Why the paths in this repo may still say `/mnt/2nd_NVME`

`profiles/DESK-config.nix` used the `disk1_*` slot for this partition; it is disabled
now and the slot's defaults in `lib/defaults.nix` were renamed to a generic
`DATA_LUKS`. `system/hardware-configuration.nix` lost both the `fileSystems` entry and
the `boot.initrd.luks.devices."2nd_NVME"` line — that line is the one that would hang
the boot if it ever came back while the partition is gone.

