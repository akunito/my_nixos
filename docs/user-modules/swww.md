---
id: user-modules.swww
summary: Robust wallpapers for SwayFX via swww (daemon + oneshot restore; rebuild/reboot safe; no polling/flicker).
tags: [swww, sway, swayfx, wayland, wallpapers, systemd-user, home-manager, stylix]
related_files:
  - user/app/swww/**
  - user/wm/sway/**
  - user/wm/hyprland/**
  - profiles/**
  - lib/defaults.nix
key_files:
  - user/app/swww/swww.nix
  - user/wm/sway/default.nix
  - profiles/DESK-config.nix
activation_hints:
  - If wallpaper does not restore after reboot
  - If wallpaper disappears after phoenix sync user / home-manager switch
  - If swww-daemon is running but swww img fails
---

# swww (wallpapers for SwayFX)

This repo supports **swww** as the wallpaper backend for **SwayFX**. The key property is that **a long-lived daemon owns wallpaper state**, and we restore once when the session is ready — **no polling**, no flicker loops.

## What it does

- Starts `swww-daemon` as a **systemd --user service** bound to `sway-session.target`.
- Restores wallpaper via a **oneshot** `swww-restore.service` once both are ready:
  - Sway IPC (`SWAYSOCK` + `swaymsg -t get_outputs`)
  - `swww` socket (`$XDG_RUNTIME_DIR/swww.socket` / `swww query`)
- Re-triggers restore once after Home-Manager reloads `systemd --user` (covers `phoenix sync user`).
- Preserves Stylix containment: it **does not** set global theme env vars.

## Enable (DESK profile)

- `systemSettings.swwwEnable = true;`
- `systemSettings.swaybgPlusEnable = false;` (avoid multiple wallpaper owners)

## Usage (CLI)

- **Set wallpaper**:
  - `swww-set /path/to/image.jpg`

Optional arguments:
- `swww-set /path/to/image.jpg crop`
- `swww-set /path/to/image.jpg crop DP-1,HDMI-A-1`

## State file

Saved under XDG state:
- `${XDG_STATE_HOME:-~/.local/state}/swww/wallpaper.json`

Schema (minimal):
- `image`: path to image
- `resize`: `crop` | `fit` | `stretch` | `no`
- `outputs`: comma-separated output names (optional; empty means “all”)

## First-run behavior

If no state file exists yet:
- If Stylix is enabled, the restore wrapper will fall back to `config.stylix.image`.
- Otherwise it will no-op successfully and print a hint in logs.

## Troubleshooting

- **Wallpaper missing after reboot**
  - Check:
    - `systemctl --user status swww-daemon.service`
    - `systemctl --user status swww-restore.service`
    - `journalctl --user -u swww-restore.service -b --no-pager -n 200`

- **Wallpaper disappears after `phoenix sync user`**
  - This is usually `reloadSystemd` killing background processes.
  - This repo triggers `systemctl --user start swww-restore.service` once after HM’s `reloadSystemd` when in a real Sway session.
  - Inspect:
    - `journalctl --user -u swww-restore.service --no-pager -n 200`

- **swww client fails (“daemon not running”)**
  - The wrapper explicitly waits for `$XDG_RUNTIME_DIR/swww.socket` and `swww query` to succeed before applying.
  - If it still fails, check whether the daemon is in the same user session:
    - `systemctl --user status swww-daemon.service`


