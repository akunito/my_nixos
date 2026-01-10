---
id: user-modules.swaybgplus
summary: GUI multi-monitor wallpapers for SwayFX/Wayland via SwayBG+ (Home-Manager/NixOS-safe; no Stylix/Plasma conflicts).
tags: [sway, swayfx, wayland, wallpapers, swaybg, home-manager, stylix, systemd-user, gtk3]
related_files:
  - user/pkgs/swaybgplus.nix
  - user/app/swaybgplus/**
  - user/wm/sway/**
  - user/wm/hyprland/**
  - profiles/**
key_files:
  - user/pkgs/swaybgplus.nix
  - user/app/swaybgplus/swaybgplus.nix
  - user/wm/sway/default.nix
  - profiles/DESK-config.nix
activation_hints:
  - If `swaybgplus-gui` launches but wallpapers do not appear
  - If saving monitor/output changes fails with read-only errors
  - If Stylix wallpaper service conflicts with SwayBG+
---

# SwayBG+ (GUI wallpapers for SwayFX / Wayland)

This repo integrates **SwayBG+** as a GUI tool to set wallpapers on **multiple monitors** in **SwayFX** (Wayland).

## What this integration does (important on NixOS/HM)

- **Wallpaper apply is GUI-driven**: the GUI includes an **Apply** action that starts `swaybg` and writes the persisted config.
- **Monitor/output layout saves are NixOS-safe** (optional): if your Sway config is Home-Manager managed (symlink into `/nix/store`), SwayBG+ can write output lines to:
  - `~/.config/sway/swaybgplus-outputs.conf`
  - When Sway includes this file, `swaymsg reload` applies it.
  - **Important**: if you use **kanshi** for output layout (recommended for “phantom OFF monitors”), do **not** include this file, or it can override kanshi and reintroduce phantom regions.
- **Persistence is handled by systemd**: a user unit restores wallpapers at Sway session start.
- **Home-Manager rebuild-safe**: Home-Manager activation can reload `systemd --user` and kill `swaybg`; this repo re-triggers wallpaper restore once after `reloadSystemd` when (and only when) a real Sway IPC socket is present.
- **Restore is startup-race safe**: the restore wrapper re-sources `%t/sway-session.env` while waiting, auto-detects a live `SWAYSOCK` if missing, and waits briefly for `swaymsg` to become responsive before applying.
- **Stylix containment is preserved**: when SwayBG+ is enabled, the Stylix-managed `swaybg` service is not started for Sway (avoids fighting wallpapers), while Plasma 6 containment remains unchanged.

## Where it lives

- **Package**: `user/pkgs/swaybgplus.nix`
  - wraps GTK3/gi typelibs (fixes `Namespace Gtk not available`)
  - patches upstream to be Home-Manager read-only-config compatible
  - adds the GUI “Apply” action
- **Home-Manager module**: `user/app/swaybgplus/swaybgplus.nix`
  - installs desktop entry / binaries
  - provides `swaybgplus-restore.service` (oneshot) to restore wallpaper on session start
- **Sway integration**: `user/wm/sway/default.nix`
  - disables Stylix `swaybg` service when `systemSettings.swaybgPlusEnable = true`
  - (legacy/optional) can include `~/.config/sway/swaybgplus-outputs.conf` for output layout changes — but this should be disabled when kanshi owns output layout
- **Profile toggle**: `profiles/DESK-config.nix`
  - `systemSettings.swaybgPlusEnable = true;`

## Usage (SwayFX)

- **Set wallpaper**:
  - Run `swaybgplus-gui`
  - “Load Image” → pick a file
  - Click **Apply** → wallpaper is applied immediately
  - Persistence file is written to `~/.local/state/swaybgplus/backgrounds/current_config.json` (used by restore service; survives HM rebuilds)

- **Set per-output positions/resolution/scale**:
  - Adjust outputs in the GUI
  - Click **Save** → writes to `~/.config/sway/swaybgplus-outputs.conf`
  - Run `swaymsg reload` to apply output changes **only if** Sway includes that file and you are not using kanshi for output layout

## Troubleshooting

- **After rebuild/reboot the wallpaper is “gone” (but you already set one before)**
  - Check whether the config still exists:
    - `~/.local/state/swaybgplus/backgrounds/current_config.json`
  - If it exists, this is usually either:
    - **startup race** (restore ran before `SWAYSOCK`/outputs were ready), or
    - `swaybg` got killed during a **Home-Manager / systemd --user reload**
  - This repo mitigates both by waiting for IPC readiness and (on HM switch) triggering restore once after `reloadSystemd` if a live Sway IPC socket is detected.
  - Debug commands:
    - `systemctl --user status swaybgplus-restore.service`
    - `journalctl --user -u swaybgplus-restore.service -b`

- **GUI opens but wallpaper doesn’t change**
  - Ensure you clicked **Apply** (Save is output config, not wallpaper).
  - Verify persistence exists:
    - `~/.local/state/swaybgplus/backgrounds/current_config.json`

- **Saving output config fails / read-only errors**
  - On Home-Manager, `~/.config/sway/config` is commonly a symlink into `/nix/store`.
  - SwayBG+ writes output lines to `~/.config/sway/swaybgplus-outputs.conf`.
  - If kanshi owns output layout, do **not** include this file; keep it for reference only.
  - If you are not using kanshi for output layout, ensure Sway includes it and then run `swaymsg reload`.

- **Wallpaper fights with Stylix**
  - When SwayBG+ is enabled, this repo disables Stylix’s Sway-only `swaybg` service to avoid double-ownership.
  - Plasma 6 remains contained (Stylix behavior there should not be affected).


