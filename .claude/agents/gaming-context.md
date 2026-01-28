# Gaming Agent Context

This context applies when working with gaming modules: `user/app/games/**`, `system/app/proton.nix`, `system/app/starcitizen.nix`

## Required Reading

Before making changes, read: `docs/user-modules/gaming.md`

## Architecture

The gaming stack is split across system and user levels:

### System Level
- `system/app/proton.nix`: Bottles overlay + `BOTTLES_IGNORE_SANDBOX` env var (no packages)
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
