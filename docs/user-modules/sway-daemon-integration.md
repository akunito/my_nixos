---
id: user-modules.sway-daemon-integration
summary: Sway session services are managed via systemd --user units bound to sway-session.target (official/systemd approach; no custom daemon-manager).
tags: [sway, swayfx, systemd-user, waybar, home-manager, session]
related_files:
  - user/wm/sway/**
  - system/wm/sway.nix
  - docs/user-modules/sway-daemon-integration.md
key_files:
  - user/wm/sway/session-env.nix
  - user/wm/sway/session-systemd.nix
  - user/wm/sway/swayfx-config.nix
  - user/wm/sway/waybar.nix
  - system/wm/sway.nix
activation_hints:
  - If Sway session services start late/missing (waybar, tray apps, swaync)
  - If fixing relog issues, ordering, or environment propagation to systemd --user units
---

# Sway session services (systemd-first / official approach)

This repo manages Sway session services using **systemd --user** units bound to a dedicated session target (`sway-session.target`). There is **no custom daemon-manager** lifecycle system.

## Where it lives

- `user/wm/sway/session-env.nix`
  - writes `%t/sway-session.env` (session-scoped env file)
  - writes `%t/sway-portal.env` and installs the portal-gtk drop-in (fast relog reliability)
- `user/wm/sway/session-systemd.nix`
  - defines/overrides `systemd.user.targets.sway-session` and `systemd.user.services.*` so services are Sway-only
- `user/wm/sway/swayfx-config.nix`
  - starts `sway-session.target` via a Sway startup command
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

## Waybar-specific troubleshooting

### Waybar exits immediately (config/CSS parse errors)

Waybar will fail fast (exit code 1) if it cannot parse the generated config or CSS. The most common signature is a selector parse error like:

- `style.css:<line>:<col> Expected a valid selector`

Notes:

- Waybar’s CSS parser is **not** a full browser engine; some selectors are rejected (notably attribute selectors like `button[data-name="…"]` or prefix matches like `^=`).
- Prefer simple selectors (`#id`, `.class`, element names) and/or use **Pango markup** in `format` / `format-icons` when you need per-item styling (see `user/wm/sway/waybar.nix` workspaces section).

If you edit `user/wm/sway/waybar.nix`, remember it must be **applied** (Home Manager generation updated) before `~/.config/waybar/style.css` changes:

- `./sync-user.sh` (repo helper; runs `home-manager switch`)


