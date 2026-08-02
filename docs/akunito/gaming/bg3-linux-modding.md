---
id: gaming.bg3-linux-modding
summary: Modding Baldur's Gate 3 on NixOS/Proton with Script Extender, vkBasalt CAS and FSR4 upscaling on RDNA4
tags: [gaming, baldurs-gate-3, proton, vkbasalt, fsr4, amd, modding, steam]
related_files: [user/app/gaming/vkbasalt.nix, system/app/steam.nix, lib/defaults.nix]
date: 2026-08-02
status: published
---

# Baldur's Gate 3 — Linux Modding Setup

Graphics-and-quality-of-life modding for BG3 (Steam appid `1086940`) under Proton on DESK.
Deliberately excludes gameplay/balance overhauls — see [§7](#7-what-else-is-out-there) for the
wider landscape.

---

## Table of Contents

1. [Key paths](#1-key-paths)
2. [Steam launch options](#2-steam-launch-options)
3. [Script Extender](#3-script-extender)
4. [Installing mods](#4-installing-mods)
5. [The mod list](#5-the-mod-list)
6. [Patch-day recovery](#6-patch-day-recovery)
7. [What else is out there](#7-what-else-is-out-there)
8. [Troubleshooting](#8-troubleshooting)

---

## ⚠️ Achievements are a one-way door

Any mod — from Nexus **or** from Larian's own in-game mod browser — flags the save as modded
and **permanently disables Steam achievements for that save**. There is no way to un-flag it
afterwards.

Install **Achievement Enabler** (Nexus `668`) *before* creating the first save, or accept that
the playthrough earns none.

---

## 1. Key paths

| What | Path |
|---|---|
| Game dir | `/mnt/DATA/SteamLibrary/steamapps/common/Baldurs Gate 3` |
| Executables | `<game>/bin/` (`bg3.exe` = Vulkan, `bg3_dx11.exe` = DX11) |
| Script Extender | `<game>/bin/DWrite.dll` |
| Texture packs | `<game>/Data/` (drop the mod's `Generated/` folder here) |
| Proton prefix | `/mnt/DATA/SteamLibrary/steamapps/compatdata/1086940/pfx` |
| `.pak` mods | `<prefix>/drive_c/users/steamuser/AppData/Local/Larian Studios/Baldur's Gate 3/Mods/` |
| Load order | `<prefix>/.../Larian Studios/Baldur's Gate 3/PlayerProfiles/Public/modsettings.lsx` |

Shell shortcut worth keeping around:

```bash
BG3=/mnt/DATA/SteamLibrary/steamapps/common/"Baldurs Gate 3"
BG3PFX=/mnt/DATA/SteamLibrary/steamapps/compatdata/1086940/pfx/drive_c/users/steamuser/AppData/Local/"Larian Studios"/"Baldur's Gate 3"
```

---

## 2. Steam launch options

Steam → Baldur's Gate 3 → Properties → Launch Options. DESK runs this under the shared
gamescope wrapper at native 4K:

```
env -u WAYLAND_DISPLAY radv_zero_vram=false MANGOHUD=0 ENABLE_LAYER_MESA_ANTI_LAG=1 ~/.config/sway/scripts/gamescope-wrapper.sh -W 3840 -H 2160 -w 3840 -h 2160 -f --rt -- env WINEDLLOVERRIDES="DWrite.dll=n,b" ENABLE_VKBASALT=1 PROTON_FSR4_UPGRADE=1 %command%
```

Without gamescope, the minimal form is just:

```
WINEDLLOVERRIDES="DWrite.dll=n,b" ENABLE_VKBASALT=1 PROTON_FSR4_UPGRADE=1 %command%
```

| Fragment | Why |
|---|---|
| `WINEDLLOVERRIDES="DWrite.dll=n,b"` | Loads Script Extender's `DWrite.dll` instead of Wine's builtin. Without it SE is inert. |
| `ENABLE_VKBASALT=1` | Activates the vkBasalt Vulkan layer for this game only (the layer is opt-in — see [§5](#vkbasalt)). |
| `PROTON_FSR4_UPGRADE=1` | **No-op in BG3 on AMD** — kept for other titles. See below. |

**The second `env`, after gamescope's `--`, is deliberate.** `gamescope-wrapper.sh` passes its
arguments straight through (`setsid gamescope "$@"`), and gamescope execs whatever follows
`--`. Variables placed in the *leading* `env` are inherited by gamescope as well as the game —
and gamescope is itself a Vulkan client, so `ENABLE_VKBASALT=1` there would hook both layers
and apply CAS twice. Scoping it after `--` gives it to the game only.

`-W/-H` and `-w/-h` are identical, so gamescope passes 4K through without scaling.

**MangoHud is not used on DESK** — it breaks the Sway session. `MANGOHUD=0` is kept in the
leading `env` as an explicit guard so nothing downstream can turn it on. See
[§8](#8-troubleshooting) for VRAM monitoring alternatives.

**Keep the Vulkan renderer** in the BG3 launcher. Do not switch to DX11: it costs frames going
through DXVK, and vkBasalt only hooks Vulkan.

### FSR4 — does NOT work out of the box on this machine

⚠️ **`PROTON_FSR4_UPGRADE=1` alone is inert in BG3 on an AMD GPU.** Verified on DESK: the
graphics menu offers only FSR 1 and FSR 2.

`PROTON_FSR4_UPGRADE` works by intercepting a game's **DLSS** calls and servicing them with
FSR4. BG3 ships `bin/nvngx_dlss.dll`, but it **gates the DLSS menu entry behind an NVIDIA RTX
GPU check** — historically people worked around this on Windows with a registry file that
spoofed an RTX card. On Radeon the DLSS option is simply never drawn, so there is no call path
to intercept and the variable does nothing.

The Proton/Mesa prerequisites are otherwise satisfied here (Proton Experimental 11.0-100,
Mesa 25.2.6 RADV) — the blocker is the game, not the stack.

**To actually get FSR4** you need [OptiScaler](https://github.com/optiscaler/OptiScaler),
which hooks the FSR2/FSR3/XeSS inputs BG3 *does* expose and substitutes FSR4. See
[§8](#8-troubleshooting) before attempting it — it stacks a second DLL proxy alongside Script
Extender.

Leaving `PROTON_FSR4_UPGRADE=1` in the launch options is harmless (it is a no-op here) and
becomes meaningful if OptiScaler is later set up to expose DLSS inputs.

**Without OptiScaler**, the sensible settings at 4K on the RX 9070 XT are native resolution
(or FSR 2 Quality if you want the frames) plus vkBasalt CAS.

---

## 2b. Download budget

Relevant when on metered/mobile internet. The **entire graphics benefit of FSR4 + vkBasalt
costs zero mod downloads** — it is launch options plus a nix rebuild (~1.2 MiB of fetches,
everything else builds locally).

| Item | Size | Verified? |
|---|---|---|
| Nix deploy (`install.sh`) | ~1.2 MiB fetch | ✅ measured via `dry-build` |
| Script Extender | ~1–2 MB (a DLL) | estimate |
| Achievement Enabler | < 1 MB | estimate |
| ImpUI / ImprovedUI | a few MB | estimate |
| Native Mod Loader + Native Camera Tweaks | < 1 MB each (DLLs) | estimate |
| Quality of Life Hotkeys, Mod Manager Fixes | small (`.pak`) | estimate |
| Tav's Hair Salon | hundreds of MB — **check the page first** | unverified |
| Immersive World Textures | multi-GB | unverified |
| BG3 Texture Upscale Project | **11 GB download / 27 GB extracted** | ✅ from mod docs |

**Metered-connection order:** do everything in Tier 1 and Tier 3 now (all small), skip Tier 2's
texture packs and Tav's Hair Salon until real internet is back. Texture `.pak` mods are
cosmetic asset replacements — they can be added mid-playthrough with no save impact, so
deferring them costs nothing.

Also avoid `install.sh -u` (flake update) while metered; it re-fetches inputs.

---

## 3. Script Extender

BG3SE (Nexus `2172`, maintained by Norbyte) is the Lua runtime most quality-of-life mods
depend on.

1. Download the archive from Nexus.
2. Extract `DWrite.dll` into `<game>/bin/`.
3. Ensure the `WINEDLLOVERRIDES` fragment is in the launch options.
4. Launch the game — a **version string appears bottom-left on the main menu**. No string
   means it did not load.

`DWrite.dll` is not a game file, so Steam updates leave it alone. It self-updates its own
payload on launch; only the DLL stub is manual.

---

## 4. Installing mods

Since Patch 8, `.pak` files dropped into the `Mods/` folder **show up in BG3's own in-game mod
manager**, where they can be enabled and reordered. On Linux this removes the need to run BG3
Mod Manager under protontricks for ordinary mods.

```bash
cp SomeMod.pak "$BG3PFX/Mods/"
```

Then in-game: Mods → refresh → enable → drag into position → **Save load order**.

Rules:

- **The base-game module always loads first** in `modsettings.lsx`. On Patch 8 this entry is
  `GustavX` (older guides say `Gustav`). Never reorder or remove it.
- Dependencies load **above** the mods that need them (frameworks first).
- `modsettings.lsx` does not exist until the game writes it once; launch vanilla first.
- The `Mods/` folder is **not created by the installer** — `mkdir -p` it before the first copy.
- BG3 Mod Manager (LaughingLeader, or the Linux port) stays available as a fallback if load
  order ever needs surgery — run it via `protontricks` in prefix `1086940`.

---

## 5. The mod list

### Tier 1 — Frameworks (install and load first)

| Mod | Purpose |
|---|---|
| **BG3 Script Extender** (`2172`) | Lua runtime — prerequisite for most QoL mods |
| **Achievement Enabler** (`668`) | Keeps Steam achievements on a modded save. **Before the first save.** |
| **ImpUI / ImprovedUI ReleaseReady** (`366`) | UI framework; removes the modded-game warning, improves character creation. Dependency of many mods. |
| **Mod Configuration Menu (MCM)** | In-game settings panel for mods that support it. Needs SE. |
| **Compatibility Framework** (`1933`) | Cross-mod API for appearance/subclass compat. Install only if a mod asks for it. |

### Tier 2 — Graphics

| Mod | Effect | Cost |
|---|---|---|
| **vkBasalt CAS** | Contrast-adaptive sharpening over the whole frame | **Zero download.** See below |
| **FSR4** | ML upscaling, headroom for higher internal resolution | **Zero download.** See [§2](#2-steam-launch-options) |
| **Immersive World Textures** (`18252`) | AI upscale of every albedo texture at a strict 2× (1K→2K, 2K→4K) | **Preferred pack.** Multi-GB. Do not stack with other texture upscales. |
| **BG3 Texture Upscale Project** (`12402`) | 4× upscale — sharper, much heavier | 11 GB download / 27 GB extracted, +3–5 GB VRAM. Drop `Generated/` into `<game>/Data/`. **Alternative to IWT, never both.** |
| **Tav's Hair Salon** (`213`) | 150+ hairstyles, some with physics; vanilla hair untouched | Plain `.pak`, no dependencies. Large — check size before downloading on a metered link. |

#### vkBasalt

Packaged declaratively: flag `vkbasaltEnable` (`lib/defaults.nix`), config
`user/app/gaming/vkbasalt.nix`, and the package is added to `programs.steam.extraPackages`
(`system/app/steam.nix`) so the layer manifest is visible inside Steam's FHS environment.

- The layer manifest declares `enable_environment = ENABLE_VKBASALT=1`, so it is **opt-in** and
  cannot leak into other Vulkan applications.
- Toggle in-game with **`Home`** to A/B the effect.
- Config lands at `~/.config/vkBasalt/vkBasalt.conf`. Built-in effects are `cas`, `dls`,
  `fxaa`, `smaa`, `lut` only — the nixpkgs package bundles **no ReShade `.fx` shaders**, so
  `reshadeTexturePath`/`reshadeIncludePath` are intentionally unset.
- `casSharpness` is 0.35 rather than upstream's 0.4 because FSR4 already sharpens.

#### Why not ReShade

ReShade does not support Vulkan under Wine/Proton. Presets like *True ReShade* would require
switching BG3 to the DX11 renderer, losing both FSR4 and vkBasalt. Not worth it on RADV.

### Tier 3 — Quality of life

| Mod | Effect | Caveat |
|---|---|---|
| **Native Camera Tweaks** (`945`) | Unlocks camera zoom / FOV / angle — the single biggest change to how the game *looks* | DLL mod. Requires **Native Mod Loader** (`944`), which replaces `<game>/bin/bink2w64.dll` — a real game file. Reverted by every patch and by "Verify integrity". Optional. |
| **WASD Character Movement** | Direct third-person movement instead of click-to-move | Needs SE. Pairs with Native Camera Tweaks. |
| **Quality of Life Hotkeys** (`23380`) | Learn spells from scrolls, organise party, send-to-character | Needs SE. No balance change. |
| **Mod Manager Fixes and Tweaks** (`11954`) | Fixes the in-game mod manager's rough edges | Relevant since we rely on the in-game manager. |

---

## 6. Patch-day recovery

After any BG3 update — or any "Verify integrity of game files":

1. **`bin/bink2w64.dll` is reverted.** Reinstall Native Mod Loader if you use DLL mods. This
   happens *every* time; it is an official game file.
2. **Check the Script Extender version string** on the main menu. `DWrite.dll` normally
   survives, but SE needs a build matching the new game version.
3. **Check mods for the `Patch 8 Compatible` tag** on Nexus before re-enabling.
4. **`.pak` cosmetic and texture mods** are safe to add or remove between sessions. **Script
   Extender gameplay mods are not** — removing one mid-playthrough can corrupt a save.

---

## 7. What else is out there

Excluded here as first-playthrough-inappropriate, but all supported by this same stack on a
replay:

- **Levelling / power** — `UnlockLevelCurve` (level 13–20), extra feats, XP tuning
- **Classes & spells** — 5e Spells, Artificer, homebrew subclasses, spell-slot overhauls
- **Party** — Party Limit Begone (1–16 companions), custom and recruitable companions
- **Gear** — Basket Full of Equipment and similar early-access gear packs
- **Races** — Ghastly Ghouls (Lich / Ghoul / Wight / Mummy), half-celestial and half-fiend
- **Difficulty** — combat overhauls, AI rewrites, Honour-mode tuning
- **Camp & roleplay** — expanded camp, romance and dialogue extensions
- **Utility** — in-game console, respec-anywhere, inventory editors

---

## 8. Troubleshooting

**No Script Extender version on the main menu**
Launch options missing or quoted wrong; or `DWrite.dll` is not in `<game>/bin/`. Confirm Steam
is launching the Proton (Windows) build, not a native path.

**vkBasalt has no effect**
Check `ENABLE_VKBASALT=1` is in the launch options, that `vkbasaltEnable = true` is set for the
profile, and that the manifest exists:

```bash
ls ~/.nix-profile/share/vulkan/implicit_layer.d/vkBasalt.json
ENABLE_VKBASALT=1 vkcube    # visible sharpening = layer works
```

**FSR4 doesn't appear — only FSR 1 and 2**
Expected. BG3 hides its DLSS option on non-NVIDIA GPUs, so `PROTON_FSR4_UPGRADE` has nothing to
hook. See [§2](#2-steam-launch-options). The only route to FSR4 is **OptiScaler**:

- Extract OptiScaler into `<game>/bin/` (beside the exes) and run its `setup-linux.sh`, which
  renames the DLL to a proxy the game will load.
- ⚠️ **It must not pick `DWrite.dll`** — that name is taken by Script Extender. Choose
  `dxgi`, `winmm` or `version` instead, or SE will stop loading.
- Add the chosen proxy to the override list, semicolon-separated:
  `WINEDLLOVERRIDES="DWrite.dll=n,b;dxgi=n,b"`
- In OptiScaler's overlay (`Insert`), select **FSR3.X/4 w/Dx12** as the upscaler.
- `0ptiscaler4linux` automates the Steam/Proton-prefix detection if you prefer.

Worth weighing: this is a second injected DLL layered on top of Script Extender, on a game
that is frequently CPU-bound. The gain over FSR 2 is image quality (less foliage shimmer and
ghosting), not raw frames. Consider deferring until the modding stack is proven stable.

**Mods don't appear in the in-game manager**
Wrong folder (must be inside the Proton prefix, not `~/.local/share`), or hit Refresh. Confirm
the game has written `PlayerProfiles/Public/modsettings.lsx` at least once.

**Monitoring VRAM / framerate without MangoHud**
MangoHud breaks the Sway session on DESK and is deliberately not used here. Alternatives, all
already installed:

```bash
nvtop                    # live GPU + VRAM, curses UI
radeontop                # AMD-specific utilisation
lact                     # GUI (lactd is already running)
watch -n1 'cat /sys/class/drm/card1/device/mem_info_vram_used'   # raw bytes
```

Total VRAM on DESK reads ~15.9 GB from `mem_info_vram_total`. Run one of these on a second
output while the game is in gamescope fullscreen — useful when evaluating a texture pack.

**Crash on load after a patch**
Disable all mods, launch vanilla to confirm the base game is healthy, then re-enable in load
order a few at a time. `bink2w64.dll` reverting is the usual culprit.
