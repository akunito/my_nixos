---
id: user-modules.gaming
summary: Implementation details for Gaming on NixOS, covering Lutris/Bottles wrappers, Vulkan/RDNA 4 driver fixes, and Wine troubleshooting.
tags: [gaming, lutris, bottles, wine, vulkan, amd, rdna4, wrappers, antimicrox, controllers]
related_files:
  - user/app/games/games.nix
  - user/app/games/games-light.nix
  - user/app/games/games-heavy.nix
  - system/app/steam.nix
  - system/app/gamemode.nix
  - system/hardware/opengl.nix
  - system/app/proton.nix
  - system/app/starcitizen.nix
---

# Gaming on NixOS

This module documents the gaming setup, specifically addressing compatibility issues with bleeding-edge AMD RDNA 4 hardware and NixOS's unique environment.

## Architecture Overview

The gaming stack consists of:
- **Lutris & Bottles**: Game managers installed via Home Manager.
- **Wine/Proton**: Compatibility layers.
- **Mesa (RADV)**: The open-source Vulkan driver for AMD.
- **Wrappers**: Custom `makeWrapper` logic injected into Lutris/Bottles to ensure correct driver discovery and environment variables.

## Module Structure

Gaming is split into 3 independent groups, each with its own flag:

```
user/app/games/
  games.nix          # Dispatcher (imported when gamesEnable=true)
  games-light.nix    # Light group (gamesLightEnable)
  games-heavy.nix    # Heavy/Proton group (protongamesEnable)

system/app/
  steam.nix          # Steam (steamPackEnable) — system-level
  gamemode.nix       # GameMode (gamemodeEnable) — system-level
```

### Flag Reference

| Flag | Scope | Group | Contents |
|------|-------|-------|----------|
| `gamesEnable` | user | Master gate | Must be true for any gaming submodule |
| `gamesLightEnable` | user | Light | RetroArch (15+ cores), pegasus, supertuxkart, antimicrox, airshipper, qjoypad, pokefinder |
| `protongamesEnable` | user | Heavy | Bottles, Lutris, protonup-qt, Wine, Vulkan tools, AMD wrappers |
| `steamPackEnable` | user | Steam | Steam + gamescope + mangohud (system-level via `system/app/steam.nix`) |
| `gamemodeEnable` | system | System | Feral GameMode CPU/screensaver optimization |
| `dolphinEmulatorPrimehackEnable` | user | Light sub-flag | Dolphin Emulator with Primehack |
| `rpcs3Enable` | user | Light sub-flag | RPCS3 PS3 emulator |
| `GOGlauncherEnable` | user | Heavy sub-flag | Heroic Games Launcher |
| `starcitizenEnable` | user | Heavy sub-flag | RSI Launcher + kernel tweaks |

### Profile Examples

- **Full gaming (DESK)**: `gamesEnable + gamesLightEnable + protongamesEnable + steamPackEnable + gamemodeEnable`
- **Light + Steam (LAPTOP_X13)**: `gamesEnable + gamesLightEnable + steamPackEnable`
- **No gaming (VM/VPS)**: All flags false (defaults)

## RDNA 4 (RX 9000 Series) & Vulkan 1.4 Issues

**Problem:**
As of early 2026, Mesa's `radv` driver for RDNA 4 (gfx12) is functional but marks itself as "non-conformant/experimental". If `VK_LAYER_MESA_device_select` is active, it may crash applications or fail to find the driver entirely with `ERROR_INCOMPATIBLE_DRIVER`.

**Fix:**
We globally disable the device selection layer for gaming sessions in `user/app/games/games-heavy.nix`:

```nix
home.sessionVariables = {
  NODEVICE_SELECT = "1"; # Fix crash on RDNA 4 (disable VK_LAYER_MESA_device_select)
  AMD_VULKAN_ICD = "radv";
};
```

This variable is also reinforced in the Lutris/Bottles wrapper args.

## Wrappers (Lutris & Bottles)

Standard NixOS packages for Lutris and Bottles sometimes fail to propagate `VK_ICD_FILENAMES` or `XDG_DATA_DIRS` correctly when launched via D-Bus/Rofi, or isolate them too strictly in their FHS environments.

We wrap these binaries in `user/app/games/games-heavy.nix` to:
1.  **Inject ICD Paths**: Explicitly set `VK_ICD_FILENAMES` to point to `/run/opengl-driver/.../radeon_icd.*.json`.
2.  **Fix Python Protocol Buffers**: Set `PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION="python"` for Lutris.
3.  **Logging**: Redirect wrapper debug output to `~/.local/state/lutris-wrapper.log` for troubleshooting.

**Code Reference:**
See `amdWrapperArgs` in `user/app/games/games-heavy.nix`.

## Wine Troubleshooting

### "Found no drivers" / `ERROR_INCOMPATIBLE_DRIVER`
- **Cause**: RDNA 4 experimental driver status + `device_select` layer.
- **Fix**: Check `NODEVICE_SELECT=1` is set. Verify `vulkaninfo`.

### `wine: WINEARCH set to win64 but ... is a 32-bit installation`
- **Cause**: The default `~/.wine` prefix was created as 32-bit (likely by an old `winetricks` run or accident), but the game/Wine is 64-bit.
- **Fix**:
    ```bash
    # Backup old prefix
    mv ~/.wine ~/.wine32_legacy
    # Initialize fresh 64-bit prefix
    WINEARCH=win64 WINEPREFIX=~/.wine wineboot
    ```

### Game crashes instantly (Exit Code 13568)
- **Cause**: Missing dependencies (DirectX, VC++ Runtime) or "System Wine" (staging/bleeding-edge) incompatibility.
- **Fix 1 (Recommended)**: Use **GE-Proton** (Lutris-GE) as the runner in Lutris. It has game-specific patches pre-applied.
- **Fix 2 (Manual)**: Install core dependencies in the prefix:
    ```bash
    winetricks vcrun2022 d3dcompiler_47 dxvk
    ```

## Environment & D-Bus Activation

Many gaming issues (especially with Flatpaks or apps launched via keybindings) are caused by environment variables not being propagated to the D-Bus activation environment.

**Fix:**
In `user/wm/sway/swayfx-config.nix`, we explicitly import critical variables into the D-Bus and systemd environments:
```nix
command = "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP SWAYSOCK XDG_DATA_DIRS VK_ICD_FILENAMES NODEVICE_SELECT BOTTLES_IGNORE_SANDBOX";
```

### "Unsupported Environment" (Bottles)
If Bottles shows a warning about "Unsupported Environment" or "Sandboxed format", it can be silenced by overriding the package:
```nix
(pkgs.bottles.override { removeWarningPopup = true; })
```
We also set `BOTTLES_IGNORE_SANDBOX = "1"` in `home.sessionVariables` and the Sway session environment to ensure it runs correctly outside of Flatpak.

## AMDVLK vs RADV
We explicitly use **RADV** (Mesa).
- `amdvlk` package is deprecated/removed in Nixpkgs.
- `AMD_VULKAN_ICD="radv"` enforces this preference.

## Controller Mapping (antimicrox)

For mapping game controllers (joysticks, gamepads) to keyboard/mouse inputs (useful for older PC games that lack controller support):

- **Package**: `antimicrox` (installed via Home Manager in `user/app/games/games-light.nix`)
- **Use case**: Map controller buttons to keyboard keys for games without native controller support
- **Launch**: Run `antimicrox` from terminal or app launcher to configure mappings

**Example mappings:**
- D-pad → Arrow keys
- Analog stick → WASD
- Triggers → Mouse buttons
- Face buttons → Game-specific keys (Space, Enter, etc.)
