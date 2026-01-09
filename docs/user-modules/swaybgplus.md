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
- **Monitor/output layout saves are NixOS-safe**: if your Sway config is Home-Manager managed (symlink into `/nix/store`), SwayBG+ writes output lines to:
  - `~/.config/sway/swaybgplus-outputs.conf`
  - Sway includes this file so `swaymsg reload` applies it.
- **Persistence is handled by systemd**: a user unit keeps wallpapers applied during the Sway session (it will re-apply if `swaybg` gets killed during Home-Manager/systemd reloads).
- **Restore is startup-race safe**: the wallpaper ensure service re-sources `%t/sway-session.env` while waiting, auto-detects a live `SWAYSOCK` if missing, and waits briefly for `swaymsg` to become responsive before applying.
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
  - includes `~/.config/sway/swaybgplus-outputs.conf` so output lines are applied on `reload`
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
  - Run `swaymsg reload` to apply output changes

## Troubleshooting

- **After rebuild/reboot the wallpaper is “gone” (but you already set one before)**
  - Check whether the config still exists:
    - `~/.local/state/swaybgplus/backgrounds/current_config.json`
  - If it exists, this is usually either:
    - **startup race** (restore ran before `SWAYSOCK`/outputs were ready), or
    - `swaybg` got killed during a **Home-Manager / systemd --user reload**
  - This repo’s ensure service mitigates both by waiting for IPC readiness and re-applying when `swaybg` disappears.
  - Debug commands:
    - `systemctl --user status swaybgplus-restore.service`
    - `journalctl --user -u swaybgplus-restore.service -b`

- **GUI opens but wallpaper doesn’t change**
  - Ensure you clicked **Apply** (Save is output config, not wallpaper).
  - Verify persistence exists:
    - `~/.local/state/swaybgplus/backgrounds/current_config.json`

- **Saving output config fails / read-only errors**
  - On Home-Manager, `~/.config/sway/config` is commonly a symlink into `/nix/store`.
  - SwayBG+ writes output lines to `~/.config/sway/swaybgplus-outputs.conf`; ensure Sway includes it and then run `swaymsg reload`.

- **Wallpaper fights with Stylix**
  - When SwayBG+ is enabled, this repo disables Stylix’s Sway-only `swaybg` service to avoid double-ownership.
  - Plasma 6 remains contained (Stylix behavior there should not be affected).


