---
id: user-modules.stylix-containment
summary: Stylix theming containment in this repo (Sway gets Stylix; Plasma 6 does not) via env isolation + session-scoped systemd.
tags: [stylix, sway, swayfx, plasma6, qt, gtk, containment, systemd-user, home-manager]
related_files:
  - user/style/stylix.nix
  - user/wm/sway/**
  - system/wm/plasma6.nix
  - user/wm/plasma6/**
key_files:
  - user/style/stylix.nix
  - user/wm/sway/default.nix
activation_hints:
  - If Plasma 6 picks up qt5ct / Stylix variables unexpectedly
  - If SwayFX loses Stylix theming after logging into Plasma 6
  - If user systemd services leak theme variables across sessions
---

# Stylix containment (Sway vs Plasma 6)

This repo uses Stylix for **Sway/SwayFX theming**, but avoids breaking **Plasma 6** (which has its own theming stack). The solution is **containment**: keep the global user environment clean, then inject theme variables only inside Sway sessions.

## The core idea

- **Global environment is forced-empty** for theme vars (so Plasma 6 doesn’t inherit them).\n
- **Sway sessions re-inject** the needed variables early during compositor startup.\n
- **Systemd user services** that should be Sway-only read a **session-scoped env file** (`%t/sway-session.env`).\n
- We avoid mutating systemd’s persistent user-manager environment (which can “leak” across sessions).\n

## Where containment is implemented

### 1) Force-unset global theme variables (Home Manager)

In [`user/style/stylix.nix`](../../user/style/stylix.nix), we force theme variables to empty strings:
- `QT_QPA_PLATFORMTHEME = lib.mkForce ""`
- `GTK_THEME = lib.mkForce ""`
- `GTK_APPLICATION_PREFER_DARK_THEME = lib.mkForce ""`
- `QT_STYLE_OVERRIDE = lib.mkForce ""`

This prevents Plasma 6 sessions from accidentally using qt5ct/Stylix settings.

### 2) Re-inject theme variables only for SwayFX

In [`user/wm/sway/default.nix`](../../user/wm/sway/default.nix), Sway sets theme variables via:
- `wayland.windowManager.sway.extraSessionCommands`

This re-enables Stylix theming *inside Sway* without affecting Plasma 6.

### 3) Session-scoped environment file for systemd --user services

Also in [`user/wm/sway/default.nix`](../../user/wm/sway/default.nix), we snapshot session vars to:
- `%t/sway-session.env` (typically `/run/user/$UID/sway-session.env`)

Then Sway-only systemd services use:
- `EnvironmentFile=-%t/sway-session.env`

This keeps Sway services correctly themed without persisting theme vars globally.

## `enableSwayForDESK` and Qt/qt5ct files

Plasma 6 can interact badly with qt5ct files if it starts reading them.\n
This repo’s rules (see comments in `user/style/stylix.nix`) are:\n
- When `userSettings.wm == "plasma6"` and `enableSwayForDESK == false`: remove qt5ct files.\n
- When `enableSwayForDESK == true`: allow qt5ct files to exist for Sway, but Plasma 6 should not use them because `QT_QPA_PLATFORMTHEME` is unset globally.\n

## Wallpaper services and containment

Wallpaper backends must also respect the session boundary:\n
- Bind Sway wallpaper units to `sway-session.target`\n
- Avoid starting them in Plasma 6\n

The swww integration follows the same pattern: it binds `swww-daemon.service` / `swww-restore.service` to `sway-session.target` and uses `%t/sway-session.env`.


