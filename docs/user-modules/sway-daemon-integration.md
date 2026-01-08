---
id: user-modules.sway-daemon-integration
summary: Sway session services are managed via systemd --user units bound to sway-session.target (official/systemd approach; no custom daemon-manager).
tags: [sway, swayfx, systemd-user, waybar, home-manager, session]
related_files:
  - user/wm/sway/**
  - system/wm/sway.nix
  - docs/user-modules/sway-daemon-integration.md
key_files:
  - user/wm/sway/default.nix
  - user/wm/sway/waybar.nix
  - system/wm/sway.nix
activation_hints:
  - If Sway session services start late/missing (waybar, tray apps, swaync)
  - If fixing relog issues, ordering, or environment propagation to systemd --user units
---

# Sway session services (systemd-first / official approach)

This repo manages Sway session services using **systemd --user** units bound to a dedicated session target (`sway-session.target`). There is **no custom daemon-manager** lifecycle system.

## Where it lives

- `user/wm/sway/default.nix`
  - writes `%t/sway-session.env` (session-scoped env file)
  - starts `sway-session.target`
  - defines/overrides `systemd.user.targets.sway-session` and `systemd.user.services.*` so services are Sway-only
- `user/wm/sway/waybar.nix`
  - Waybar config (Home Manager)
- `system/wm/sway.nix`
  - enables SwayFX and shared system requirements

## Key ideas

- **Dedicated target**: `sway-session.target` is the boundary for Sway-only services.
- **Ordering**: tray-dependent services should order `After=waybar.service` so SNI is ready deterministically.
- **Restart semantics**: systemd provides `Restart=on-failure` and clean relog behavior.
- **Environment containment**: services read session/theme vars from `%t/sway-session.env` (e.g. `/run/user/$UID/sway-session.env`), avoiding persistent systemd manager env leakage into other sessions (e.g. Plasma).

## Troubleshooting checklist

- Confirm Sway startup runs the session helpers:
  - `%t/sway-session.env` exists
  - `sway-session.target` is started
- Check logs for a specific service:
  - `journalctl --user -u waybar.service -b`
  - `journalctl --user -u swaync.service -b`
- Verify ordering if a tray app starts before Waybar:
  - ensure `After=waybar.service` (and `Wants=waybar.service` if needed)


