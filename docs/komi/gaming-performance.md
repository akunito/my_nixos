---
id: komi.gaming-performance
summary: Gaming performance tuning for macOS (Whisky/Wine, Warblade)
tags: [gaming, darwin, performance, whisky, wine]
related_files: [user/app/games/**, profiles/MACBOOK-KOMI-config.nix, system/darwin/defaults.nix]
date: 2026-02-22
status: published
---

# Gaming Performance Tuning (macOS)

Optimizations for running Windows games (especially Warblade, a DX9 arcade shooter from ~2004) through Whisky/Wine on Apple Silicon Macs.

## Nix-Managed Optimizations (Automatic)

These are applied automatically when `gamesEnable = true` and/or `gamingPerformanceMode = true` in the profile config.

### Environment Variables (`profiles/darwin/home.nix`)

| Variable | Value | Effect |
|----------|-------|--------|
| `WINEDEBUG` | `-all` | Disables all Wine debug output (medium perf gain) |
| `WINEMSYNC` | `1` | Enables MSync — macOS-native Mach semaphore sync (~50% faster than ESync) |
| `DXVK_ASYNC` | `1` | Enables async shader compilation (reduces stutter) |

These are set as `home.sessionVariables` when `gamesEnable = true`.

### macOS Defaults (`system/darwin/defaults.nix`)

**Always applied (low impact):**
- `NSAutomaticWindowAnimationsEnabled = false` — no window open/close animations
- `NSWindowResizeTime = 0.001` — near-instant window resize

**Manual (requires Full Disk Access — nix-darwin cannot write `com.apple.universalaccess`):**
- System Settings -> Accessibility -> Display -> **Reduce motion** (disables Mission Control animations)
- System Settings -> Accessibility -> Display -> **Reduce transparency** (reduces GPU compositor overhead)

### game-mode Script

Toggle Spotlight indexing and Time Machine during gaming:

```bash
game-mode on    # Pause Spotlight + Time Machine (requires sudo)
game-mode off   # Resume both
```

## Manual Whisky Bottle Settings (CRITICAL)

These must be configured in the Whisky GUI per bottle — they cannot be automated via Nix.

### For Warblade (DX9)

1. **Open Whisky** -> select Warblade bottle -> Config
2. **Set renderer to DXVK** (critical: D3DMetal does NOT support DX9)
3. **Open winecfg** -> set Windows version to **Windows XP** or **Windows 7**
4. **In winecfg Libraries tab** -> add `dsound` override -> set to **(builtin)** (fixes audio stutter)
5. **Disable Retina mode** in bottle settings (halves pixel count, big FPS gain)
6. **Plug in power** — GPU throttles ~50% on battery

### Per-Game Backend Selection Guide

| DirectX Version | Recommended Backend | Notes |
|----------------|-------------------|-------|
| DX9 | **DXVK** | D3DMetal doesn't support DX9 |
| DX10/DX11 | **DXMT** or DXVK | DXMT is newer Metal-native, try both |
| DX12 | **D3DMetal** | Apple's official translation layer |

## Audio Troubleshooting

If audio stutters or cuts out:

1. **dsound builtin** (see step 4 above) — fixes most Wine audio issues
2. **Reset CoreAudio:** `sudo killall coreaudiod` (daemon auto-restarts)
3. **In winecfg Audio tab:** try switching between CoreAudio and PulseAudio backends

## Proton on macOS — Not Possible

Proton is **Linux-only** (DirectX -> Vulkan). macOS has no Vulkan, only Metal. The macOS equivalents are:

| Tool | Status (2026) | Notes |
|------|---------------|-------|
| **CrossOver** ($74/yr) | Active (v26) | Best compatibility, funds Wine development |
| **Whisky** (free) | Archived Apr 2025 | Works for old games, no updates coming |
| **GPTK/Mythic** (free) | Unsupported | Apple developer tool, ~60-70% compat |
| **GameHub** (new) | Early access | Unified launcher, unproven |

## Future Migration

If a macOS update breaks Whisky:
1. **CrossOver** — commercial but actively maintained, same Wine engine
2. **Community fork** — monitor GitHub for Whisky forks
3. **GPTK direct** — Apple's Game Porting Toolkit works standalone for simple games
