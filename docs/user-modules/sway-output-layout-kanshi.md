---
id: user-modules.sway-output-layout-kanshi
summary: Fix “phantom OFF monitors” in Sway/SwayFX using kanshi (wlroots) + Sway-only systemd target, profile-scoped in flakes.
tags: [sway, swayfx, wayland, kanshi, outputs, monitors, home-manager, systemd-user, plasma6, profiles]
related_files:
  - user/wm/sway/default.nix
  - user/wm/sway/scripts/swaysome-init.sh
  - profiles/*-config.nix
  - lib/defaults.nix
  - lib/flake-base.nix
  - docs/user-modules/swaybgplus.md
key_files:
  - user/wm/sway/default.nix
  - profiles/DESK-config.nix
  - lib/defaults.nix
activation_hints:
  - If the mouse can move into a monitor that is physically OFF
  - If workspaces are assigned to outputs that should be disabled
  - If Sway output layout drifts across relogs/rebuilds
---

# Sway/SwayFX output layout (kanshi) — fix “phantom OFF monitors”

## Problem

On some setups, monitors that are physically **OFF** (but still detected as connected) can behave as if they were **ON**:

- the pointer can move into their coordinate space (“phantom area”)
- workspaces get assigned to them
- focus can land on them during session start

This happens when the compositor keeps those outputs enabled (or when your config applies geometry for them unconditionally).

## Official approach (wlroots/Sway): kanshi

This repo uses **kanshi** (the wlroots/Sway output profile manager) via **Home‑Manager’s official** `services.kanshi` module.

Key properties:

- **Dynamic output application**: kanshi applies output layout on session start (and on output hotplug events).
- **Sway-only containment**: kanshi is bound to `sway-session.target`, so it **does not affect Plasma 6**.
- **Profile-scoped config**: the output layout is **DESK-only** via a `systemSettings` override.

## Repo integration (DESK-only)

### Defaults (all profiles)

`lib/defaults.nix` defines:

- `systemSettings.swayKanshiSettings = null;`

Meaning: **kanshi is disabled by default** in all profiles unless explicitly enabled.

### DESK override

`profiles/DESK-config.nix` sets:

- `systemSettings.swayKanshiSettings = [ … ];`

This contains Home‑Manager-compatible kanshi `settings` directives (see `kanshi(5)` via Home‑Manager module schema).

### Consumption in Sway module

`user/wm/sway/default.nix`:

- enables `services.kanshi` **only when** `systemSettings.swayKanshiSettings != null`
- binds it to `sway-session.target`
- forces `~/.config/kanshi/config` to be Home‑Manager managed when enabled (prevents drift if the file becomes a regular file)

## Workspace grouping (swaysome)

Workspace grouping is executed **after** kanshi applies the profile:

- kanshi profile includes: `exec $HOME/.config/sway/scripts/swaysome-init.sh`

This prevents swaysome from assigning workspace groups to outputs that are going to be disabled by kanshi.

## Important: don’t mix kanshi with SwayBG+ output geometry include

SwayBG+ can write output geometry to:

- `~/.config/sway/swaybgplus-outputs.conf`

If Sway includes that file, it can **re-introduce phantom outputs** by re-enabling or repositioning outputs outside kanshi’s control.

Recommendation:

- **Use kanshi for output layout**
- Use SwayBG+/swww only for wallpapers (do not let them own output layout)

## Troubleshooting

- **Check kanshi unit wiring** (should be Sway-only):
  - `systemctl --user cat kanshi.service`
  - Look for `WantedBy=sway-session.target`

- **Check which profile kanshi applied**:
  - `journalctl --user -u kanshi.service -n 80 --no-pager`

- **See Sway’s current output state**:
  - `swaymsg -t get_outputs | jq -r '.[] | {name, active, dpms, rect, scale, transform, current_mode}'`

- **If DP-2 transform looks “wrong”**:
  - Some stacks report transform differently. Prefer verifying with `swaymsg -t get_outputs` (JSON) rather than the human output.


