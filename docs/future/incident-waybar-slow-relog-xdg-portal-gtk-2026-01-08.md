---
id: future.incident-waybar-slow-relog-xdg-portal-gtk-2026-01-08
summary: Waybar delayed 2–4 minutes after fast relog in Sway due to xdg-desktop-portal-gtk failures + systemd start-limit lockout; fixed via portal-gtk drop-in (UnsetEnvironment=DISPLAY + no start-limit + restart).
tags: [incident, sway, swayfx, waybar, xdg-desktop-portal, xdg-desktop-portal-gtk, systemd-user, dbus, relog]
related_files:
  - user/wm/sway/session-env.nix
  - user/wm/sway/session-systemd.nix
  - user/wm/sway/waybar.nix
  - docs/user-modules/sway-daemon-integration.md
  - docs/future/sway-daemon-relog-notes-2026-01-08.md
---

# Incident report — Waybar slow after fast relog (SwayFX) due to portal-gtk failures (2026-01-08)

## Summary

On **logout → login to SwayFX** (especially **fast relogs**), **Waybar startup could take ~2–4 minutes**, and some apps (e.g. Flatpak Vivaldi) would start slowly. After a full reboot, everything started fast.

Root cause was **portal activation instability** during the relog window:

- `xdg-desktop-portal-gtk` repeatedly failed to attach to a display (often `DISPLAY=:0` / X11 path) and exited.
- systemd start-rate limiting could lock the service into a failed/dead state long enough for **Waybar to hit DBus activation timeouts** for `org.freedesktop.portal.Desktop` and crash-loop.

We fixed it by making `xdg-desktop-portal-gtk`:

- **not see X11 DISPLAY** (service-scoped `UnsetEnvironment=DISPLAY`)
- **retry on failure without start-limit lockout** (`Restart=on-failure` + `StartLimitIntervalSec=0`)
- **prefer Wayland when in Sway** (service-scoped env via `%t/sway-portal.env`, plus an ExecStart wrapper for additional safety)

## Impact

- Waybar can take **minutes** to appear after fast relog.
- Flatpak apps can be delayed due to portal activation issues.
- User experience degradation primarily during quick logout/login cycles.

## Environment

- **WM/Compositor**: SwayFX (wlroots)
- **Service model**: systemd-first Sway session services bound to `sway-session.target`
- **Tray host**: Waybar tray module (StatusNotifierWatcher)
- **Portals involved**:
  - `xdg-desktop-portal.service`
  - `xdg-desktop-portal-gtk.service`
  - `xdg-desktop-portal-wlr` (backend for wlroots)

## Symptoms (runtime evidence)

### 1) Waybar portal timeout + crash

Observed in Waybar journal:

- `Error calling StartServiceByName for org.freedesktop.portal.Desktop: Timeout was reached`

This correlated with portal backend failures during relog.

### 2) `xdg-desktop-portal-gtk` failing to open a display

Observed in portal-gtk journal (examples):

- `Error reading events from display: Broken pipe`
- `cannot open display: :0`
- later, after `DISPLAY` was removed from the unit env, the message became:
  - `cannot open display:` (empty) — consistent with `DISPLAY` no longer being set.

### 3) systemd start-limit lockout (pre-fix)

Observed:

- `Start request repeated too quickly.`

When this happened, DBus activation for portals could remain broken long enough for client timeouts.

## Diagnosis

### Key observation

Waybar doesn’t just “start slowly” — it can **block on portal DBus activation**, and if `xdg-desktop-portal-gtk` is flapping or dead, it can hit its own timeout and exit. That creates the “minutes to appear” pattern via retries/restarts.

### Why the issue was worse on fast relog

During fast relog, the user systemd manager and D-Bus session can briefly present a partial/stale environment. In particular:

- `DISPLAY` can be present (e.g. `:0`) even though we are in a Wayland session.
- A portal backend can start before the compositor/socket is actually usable.

## Fix (final)

Implemented in `user/wm/sway/default.nix` as a **systemd user drop-in** for `xdg-desktop-portal-gtk.service` plus a small wrapper:

### 1) Make portal-gtk resilient to relog timing

Drop-in behavior:

- `Restart=on-failure`
- `RestartSec=1s`
- `StartLimitIntervalSec=0` (prevent lockout during short flapping windows)

### 2) Prevent accidental X11 selection during Sway

Drop-in behavior:

- `UnsetEnvironment=DISPLAY` (service-scoped; avoids X11 attach attempts like `:0`)
- `EnvironmentFile=-%t/sway-portal.env` (created by Sway on startup)

### 3) Keep environment propagation minimal and safe

Sway startup ensures systemd --user / DBus activation sees core Wayland session variables:

- `dbus-update-activation-environment --systemd WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP`

Theme variables remain Sway-scoped (Stylix containment preserved).

## Verification (post-fix runtime evidence)

Verified in the failing relog scenario that:

- No more Waybar portal timeouts:
  - `journalctl --user -u waybar.service -b | rg 'StartServiceByName|org\\.freedesktop\\.portal\\.Desktop|Timeout was reached'` produced no matches.
- No more portal-gtk start-limit lockouts:
  - `journalctl --user -u xdg-desktop-portal-gtk.service -b | rg 'Start request repeated too quickly|start-limit'` produced no matches.
- Units stable:
  - `systemctl --user show waybar.service -p Result -p NRestarts`
  - `systemctl --user show xdg-desktop-portal-gtk.service -p Result -p NRestarts`
  - `systemctl --user show xdg-desktop-portal.service -p Result -p NRestarts`

## “How to debug quickly” (if this ever returns)

1) Check the portal backend:

- `journalctl --user -b -u xdg-desktop-portal-gtk.service --no-pager -o short-iso | tail -n 260`
- `systemctl --user status xdg-desktop-portal-gtk.service --no-pager -l`
- `systemctl --user cat xdg-desktop-portal-gtk.service`

2) Check portal broker:

- `journalctl --user -b -u xdg-desktop-portal.service --no-pager -o short-iso | tail -n 260`

3) Check Waybar:

- `journalctl --user -b -u waybar.service --no-pager -o short-iso | tail -n 260`

4) Confirm the drop-in is active:

- `systemctl --user show xdg-desktop-portal-gtk.service -p DropInPaths -p FragmentPath --no-pager`

## Notes

- The portal-gtk failures (`Broken pipe`) can still happen occasionally during compositor restarts; the fix is that they **no longer cascade** into multi-minute Waybar absence because:
  - the service keeps retrying safely, and
  - it cannot get locked out by start-limit, and
  - it won’t try to bind to X11 via `DISPLAY=:0` in Sway sessions.


