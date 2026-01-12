---
id: user-modules.sway-output-layout-kanshi
summary: Complete Sway/SwayFX output management with kanshi (monitor config) + swaysome (workspaces), ensuring stability across reloads/rebuilds.
tags: [sway, swayfx, wayland, kanshi, outputs, monitors, workspaces, swaysome, home-manager, systemd-user, plasma6, profiles, reload]
related_files:
  - user/wm/sway/kanshi.nix
  - user/wm/sway/swayfx-config.nix
  - user/wm/sway/scripts/swaysome-assign-groups.sh
  - profiles/*-config.nix
  - lib/defaults.nix
  - lib/flake-base.nix
  - docs/user-modules/swaybgplus.md
key_files:
  - user/wm/sway/kanshi.nix
  - user/wm/sway/swayfx-config.nix
  - profiles/DESK-config.nix
  - lib/defaults.nix
activation_hints:
  - If monitor settings (scale, resolution, transform) revert to defaults on sway reload
  - If workspaces are assigned to wrong outputs after sway reload
  - If the mouse can move into a monitor that is physically OFF
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

- `systemSettings.swayKanshiSettings = [ … ];` (generic)

Meaning: **kanshi is enabled by default for Sway sessions** with a non-opinionated “enable everything” profile. This makes first-time Sway use on new profiles work without needing monitor-specific configuration.

Notes:

- This still remains **Sway-only** (bound to `sway-session.target`), so it does not affect Plasma 6.
- Profiles can (and should) override with an explicit, anti-drift layout when needed.

### DESK override

`profiles/DESK-config.nix` sets:

- `systemSettings.swayKanshiSettings = [ … ];`

This contains Home‑Manager-compatible kanshi `settings` directives (see `kanshi(5)` via Home‑Manager module schema).

### Consumption in Sway module

`user/wm/sway/kanshi.nix`:

- enables `services.kanshi` **only when** `systemSettings.swayKanshiSettings != null`
- binds it to `sway-session.target`
- forces `~/.config/kanshi/config` to be Home‑Manager managed when enabled (prevents drift if the file becomes a regular file)

## Workspace grouping (swaysome)

Workspace grouping is executed **after** kanshi applies the profile:

- kanshi profile includes: `exec swaysome init`, `swaysome rearrange-workspaces`, and workspace assignment scripts

This prevents swaysome from assigning workspace groups to outputs that are going to be disabled by kanshi.

**Note on config reload**:
- **Monitor configuration**: When `swaymsg reload` is run, kanshi profiles are not re-applied by default. To maintain correct monitor settings (scale, resolution, transform), Sway's startup commands include a command that runs `always = true` to restart the kanshi service on every reload.
- **Workspace assignments**: For DESK profile, workspace-to-output assignments are handled declaratively in Sway's configuration using hardware IDs directly. These assignments are loaded when Sway starts, eliminating race conditions and ensuring workspaces are assigned to the correct monitors from the start.

**Note on group numbering**:

- This repo uses `swaysome init 1` and then assigns groups starting at **1**, so **group 0 is never used**.
- Result: first assigned output gets **11–20**, second gets **21–30**, etc.

### Group assignment

- **Default profiles**: Groups are assigned in Sway's output enumeration order. The first detected output gets group 1 (11–20), second gets group 2 (21–30), etc. This is consistent within a session but may vary across hardware changes.

- **DESK profile**: Uses declarative hardware ID-based assignment in Sway's configuration to ensure deterministic mapping that doesn't depend on enumeration order:
  - Samsung → workspaces 11–20
  - NSL → workspaces 21–30
  - Philips → workspaces 31–40
  - BNQ → workspaces 41–50

  The assignment is implemented directly in `swayfx-config.nix` using Sway's native `workspace <number> output "<hardware-id>"` syntax. This declarative approach ensures workspaces are assigned to the correct monitors when Sway starts, before any applications launch, eliminating race conditions. Hardware IDs (Make Model Serial) are used instead of connector names (DP-1, HDMI-A-1) for stability across cable detection order changes.

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

- **Verify reload commands are present**:
  - `grep "restart kanshi" ~/.config/sway/config` (should show systemctl restart command)

- **Check if kanshi restarts on reload**:
  - Run `swaymsg reload`
  - Check `systemctl --user status kanshi.service` (should show recent restart)

- **See Sway's current output state**:
  - `swaymsg -t get_outputs | jq -r '.[] | {name, active, dpms, rect, scale, transform, current_mode}'`

- **If DP-2 transform looks "wrong"**:
  - Some stacks report transform differently. Prefer verifying with `swaymsg -t get_outputs` (JSON) rather than the human output.

- **If workspace assignments are wrong after reload**:
  - DESK profile: Verify workspace-to-output assignments in `swayfx-config.nix` (should use hardware IDs, not connector names)
  - Other profiles: Check that kanshi restart command is present
  - Verify hardware IDs in `swaymsg -t get_outputs` match your profile configuration
  - Check that `swaysome init 1` is present in kanshi profile exec commands (DESK profile)


