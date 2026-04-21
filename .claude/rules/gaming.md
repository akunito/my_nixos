---
paths:
  - "user/app/games/**"
  - "system/app/proton.nix"
  - "system/app/starcitizen.nix"
  - "system/app/gamemode.nix"
  - "system/hardware/opengl.nix"
---

# Gaming Rules

Before making changes, read: `docs/user-modules/gaming.md`

## Architecture

### System Level
- `system/app/proton.nix`: Bottles overlay + `BOTTLES_IGNORE_SANDBOX` env var
- `system/app/starcitizen.nix`: Kernel tweaks for Star Citizen performance
- `system/hardware/opengl.nix`: Mesa/Vulkan driver configuration

### User Level (Home Manager)
- `user/app/games/games.nix`: Lutris, Bottles, Heroic, antimicrox + AMD wrappers

## Feature Flags

In profile configs (`profiles/*-config.nix`):
- `protongamesEnable`: Enable proton.nix (Bottles overlay)
- `starcitizenEnable`: Enable starcitizen.nix (kernel tweaks)
- `steamPackEnable`: Enable Steam via system module

## RDNA 4 / Vulkan Fixes

Critical environment variables for AMD RDNA 4 (RX 9000):
```nix
home.sessionVariables = {
  NODEVICE_SELECT = "1";     # Disable VK_LAYER_MESA_device_select (crashes)
  AMD_VULKAN_ICD = "radv";   # Force RADV driver
};
```

## Wrappers

Lutris and Bottles are wrapped with `makeWrapper` to inject:
- `VK_ICD_FILENAMES` pointing to radeon_icd.*.json
- `PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION="python"` for Lutris
- Debug logging to `~/.local/state/lutris-wrapper.log`

## Controller Mapping

- `antimicrox`: Maps gamepad buttons to keyboard/mouse for legacy games
- Installed in `user/app/games/games.nix`

## Common Issues

1. **"Found no drivers"**: Check `NODEVICE_SELECT=1` is set
2. **Bottles sandbox warning**: Ensure `BOTTLES_IGNORE_SANDBOX=1` in environment
3. **Wine arch mismatch**: Delete `~/.wine` and reinit with `WINEARCH=win64`

## Lutris save-protection hygiene

Context: on 2026-04-20 a `nix flake update` bumped `lutris` + `umu-launcher`
and the default wine prefix resolution changed, hiding Rimworld saves behind
a fresh empty prefix. Rule of thumb to prevent a repeat:

1. **Pin `game.prefix` in every Lutris yml** (`~/.local/share/lutris/games/*.yml`).
   Never rely on Lutris/umu defaults — they can change across updates.
   Audit with `scripts/pin-lutris-prefix.sh` (dry run) / `--fix` (to patch).
2. **Save dirs must be symlinks into `~/GameSaves/`**:
   - `<prefix>/drive_c/users/steamuser/AppData/LocalLow` → `~/GameSaves/LocalLow`
   - `<prefix>/drive_c/users/steamuser/AppData/Roaming`  → `~/GameSaves/Roaming`
   - `<prefix>/drive_c/users/steamuser/Documents`        → `~/GameSaves/Documents`
   Use `scripts/redirect-game-saves.sh <prefix-path>` (dry run) / `--execute`.
   Skip `AppData/Local` — caches must stay per-prefix.
3. **Why `~/GameSaves/`**: `scripts/backup-manager.sh` excludes `Games/` and
   `.local/share/bottles/` from restic (too bulky). `~/GameSaves/` has no
   exclude rule, so the 6-hour NAS backup covers all saves automatically.
4. **Automatic pre-update snapshot**: `install.sh` runs `home_backup.service`
   synchronously before `nix flake update` when the profile has
   `protongamesEnable = true`. Override with `BACKUP_BEFORE_UPDATE=0`.
5. **Adding a new game**: after Lutris creates the yml, re-run
   `scripts/pin-lutris-prefix.sh` and `scripts/redirect-game-saves.sh` for the
   new prefix (Lutris has no native "default prefix template" mechanism).
