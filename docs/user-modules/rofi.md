---
id: user-modules.rofi
summary: Rofi configuration (Stylix-templated theme, unified combi launcher, power script-mode, and grouped window overview).
tags: [rofi, launcher, sway, swayfx, wayland, stylix, base16, scripts]
related_files:
  - user/wm/sway/rofi.nix
  - user/wm/sway/default.nix
  - user/wm/sway/waybar.nix
  - user/wm/sway/scripts/window-overview-grouped.sh
  - user/wm/sway/scripts/rofi-power-mode.sh
  - user/wm/sway/scripts/rofi-power-launch.sh
---

# Rofi (SwayFX)

This repo uses **rofi** as the primary launcher on SwayFX, with:

- A **unified launcher** (rofi `combi`) bound to `${hyper}+space`
- A **power menu** implemented as a rofi **script-mode** (`power`)
- A **grouped window overview** (app → window) bound to `${hyper}+Tab`
- A rofi theme generated from **Stylix Base16 colors** (when Stylix is enabled)

## Where it’s configured

- **Rofi config + theme**: `user/wm/sway/rofi.nix`
  - Generates `~/.config/rofi/themes/custom.rasi`
  - Sets `programs.rofi.extraConfig` (modi, combi-modi, window-format, icons, etc.)
- **Sway bindings**: `user/wm/sway/default.nix`
- **Waybar power button**: `user/wm/sway/waybar.nix`

## Stylix “inheritance” (how colors flow into rofi)

Rofi is themed by templating a `.rasi` theme using Stylix colors:

- If Stylix is enabled for Sway sessions, `user/wm/sway/rofi.nix` uses:
  - `config.lib.stylix.colors.base00..base0F`
  - Example: `selected-col` comes from `base0D`
- Otherwise it falls back to a static palette.

This means you generally:

- Change **global palette** via `userSettings.theme` (affects Stylix/base16)
- Change **rofi-specific UI** (padding, radius, selection intensity, layout) in `user/wm/sway/rofi.nix`

## Unified combi launcher

The unified launcher is `combi` with these modes:

- `drun`, `run`, `window`, `filebrowser`, `calc`, `emoji`, `power`

### Mode switching

Inside rofi:

- `Ctrl+Tab` → next mode
- `Ctrl+Shift+Tab` → previous mode

## Power menu (rofi script-mode)

Power actions are provided by a rofi script-mode:

- Script: `user/wm/sway/scripts/rofi-power-mode.sh`
- Mode name: `power`
- Supports: Lock, Logout, Restart, Shutdown, Suspend, Hibernate

Waybar uses `rofi-power-launch.sh` to ensure the **Home-Manager wrapped rofi** is used (so plugin modes don’t error in minimal PATH environments).

## Grouped window overview

Script: `user/wm/sway/scripts/window-overview-grouped.sh`

Behavior:

- Shows apps grouped by `app_id` / XWayland `class` (with counts)
- If an app has **one** window, selection focuses it directly
- If multiple, it opens a second menu listing windows (`[workspace] title`)

