---
id: user-modules.sway-apps
title: sway-apps — window rules and startup apps manager
tags: [sway, window-rules, startup, gui, cli]
related:
  - user/wm/sway/sway-apps/
  - user/wm/sway/apps/
  - user/wm/sway/swayfx-config.nix
---

# sway-apps

GUI (GTK4 + libadwaita) and CLI that own two things for Sway:

1. **Window rules** — `for_window`, `assign` and `no_focus` lines.
2. **Startup apps** — a *manual* launch list (nothing runs at login).

Flag: `swayAppsEnable` (`lib/defaults.nix`, default `false`). Enabled on
`LAPTOP_X13` since 2026-09-06 and on `DESK` since 2026-09-07. With the flag ON, `swayfx-config.nix` stops
emitting its hardcoded rules and includes `~/.config/sway/sway-apps.conf`
instead. With it OFF nothing changes (DESK still uses the legacy rules).

## Where things live

| What | Path |
|------|------|
| Tool source | `user/wm/sway/sway-apps/` (nix module `default.nix`, python `sway_apps/`) |
| State (in the repo) | `user/wm/sway/apps/common.json` + `user/wm/sway/apps/<ENV_PROFILE>.json` |
| Generated include | `~/.config/sway/sway-apps.conf` (never edit; regenerate with `sway-apps apply`) |
| Log | `~/.local/state/sway-apps/sway-apps.log` — 5 × 10 MiB rotating, 50 MiB cap; warnings mirrored to journald (`journalctl --user -t sway-apps`) |
| Learned app_ids | `~/.local/state/sway-apps/learned.json` |
| Stylix tokens for the GUI | `~/.config/sway-apps/theme-stylix.css` (written by nix when `stylixEnable`) |
| User themes | `~/.config/sway-apps/themes/<name>.css`, selected by `~/.config/sway-apps/config.json` `{"theme": "<name>", "color_scheme": "dark|light"}` |

The profile layer overrides a common item with the same `id` field by field,
so one machine can disable or retarget a shared rule without forking it.

## Monitors, workspace pins and the workspace map

Each machine keeps a **monitor table** in its profile layer: a *role* shared
across machines (`main`, `second`, `tv`, `left`), the sway hardware id
(`make model serial`) and a workspace **group** (decade: group 1 = ws 11-20).
From it the tool emits `workspace N output "<hw id>"` lines into the include.
`sway-apps monitors fix-orphans` (run once at login by the sway startup list)
moves sway's default group-0 workspace into the pinned decade. Both DESK and X13 use this model; X13's dock
monitor becomes role `second` the first time it is connected
(`sway-apps monitors add second HDMI-A-1 --group 2`).

Rules can target a workspace **symbolically** (`--target main:2`, or the
role/slot picker in the GUI): the number is resolved per machine and rewritten
automatically when a monitor's group changes; the last resolved number stays
stored as the fallback for machines that lack the role (doctor reports those).

Division of labour with nwg-displays: it still owns the physical layout
(`~/.config/sway/outputs`, by connector). `sway-apps monitors pin-geometry on`
re-emits that geometry keyed by hardware id so it survives connector renames.
Do not use nwg-displays' *workspaces* tab (connector based; doctor warns if
its file is non-empty). `workspace-groups-gui` (Hyper+`) was retired on
2026-09-06; the key now opens the Monitors section.

`sway-apps workspaces map` / the Workspaces section show, per monitor and slot,
the apps assigned there and the windows currently open.

### "Always connected" monitors (power-off without evacuation)

A DisplayPort monitor switched OFF drops HPD exactly like an unplugged cable
(measured on DESK: both DP monitors do it), so sway destroys the output and
evacuates its workspaces; software DPMS keeps the connector. The kernel
cannot tell the two apart, so per monitor you can force the connector on:
`sway-apps monitors set main --always-connected` (GUI: switch in Monitors).
This writes `on` to `/sys/class/drm/<connector>/status` through
`sway-connector-force` (system/wm/sway-apps-helper.nix, sudo NOPASSWD, only
when `swayAppsEnable`), is re-applied at every login by `sway-apps monitors
login`, and is released with `--no-always-connected` (`detect`). Caveats: a
genuinely unplugged forced monitor stays a phantom output (pointer can enter
it; use `--no-always-connected` then), and booting with the monitor off
leaves the kernel without EDID for it. Use it on fixed desks (DESK), not on
a laptop's dock monitor (X13 keeps detection). `monitors force status` shows
the kernel status per role.

### Git sync between machines

Every save commits only `user/wm/sway/apps/*.json`, then runs
`sway-apps git sync`: fetch, rebase this machine's state commits onto
upstream and push. If both machines edited the same file the JSON is merged
**by id** (newest `updated_at` per item wins; a one-sided delete wins over an
untouched item; delete vs edit keeps the edit), so no manual conflict
resolution is needed. The GUI also syncs when it opens. Disable with
`{"auto_sync": false}` in `~/.config/sway-apps/config.json`. The sync refuses
to touch a checkout whose unpushed commits include non-state files.

## What a save does

`write JSON → validate → regenerate include → swaymsg reload → apply to
already-open matching windows → git commit (state files only)`. Push is
manual: the GUI footer button or `sway-apps git push`. `install.sh` does
`git reset --hard origin/main`, so **push before deploying** or the local
commits are lost.

Home Manager activation regenerates the include from the repo state on every
`sync-user.sh` / `install.sh` (no reload, no git) so a fresh deploy never
starts with a stale file.

## Opening it

- `Hyper+Shift+n` (Rules) · `Hyper+grave` (Monitors)
- rofi maintenance menu (`Hyper+Shift+Return`) → "Sway Apps: rules & startup";
  its "Startup Apps" entry now runs `sway-apps startup run`.
- `sway-apps` / `sway-apps gui --section rules --select <id>`

## CLI (everything takes `--json`)

```
sway-apps doctor
sway-apps rules list|show|add|set|enable|disable|rm|test|match
sway-apps rules add -c app_id=kitty -a "floating enable" -a "sticky enable"
sway-apps rules add --kind assign -c app_id=code --workspace 12
sway-apps rules test -c app_id=kitty -a "floating toggle"     # live only, nothing saved
sway-apps render [--validate] | sway-apps apply [--live]
sway-apps import-config ~/.config/sway/config --dry-run
sway-apps startup list|add|set|enable|disable|rm|run [ID...]
sway-apps startup add --desktop org.kde.kcalc --workspace 3   # from a .desktop entry
sway-apps apps list [QUERY] [--source flatpak-user] [--all] | apps show ID | apps launch ID
sway-apps monitors outputs|list|add ROLE OUTPUT --group N|set ROLE [--group N|--output X|--rename R|--always-connected]|rm ROLE|apply|pin-geometry on|off|fix-orphans|force status|login
sway-apps workspaces map
sway-apps windows list|focused|pick
sway-apps git status|commit|push|pull|sync
sway-apps log tail [-n 50] [-f] [--level error] [--grep rules.add]
```

Over ssh the tool finds `SWAYSOCK` itself.

## Gotchas learned while building it

- `sway --validate` parses **criteria only**; `for_window` bodies run when a
  window maps. Actions are therefore checked against sway's command table,
  and the definitive check is **Test** (live apply), which surfaces sway's
  real error.
- i3/sway have **no end-of-line comments**: the generated file puts the rule
  label on the line above.
- sway criteria are POSIX regex, unanchored, case-sensitive; `^md\.Obsidian$`
  needs the anchors.
- `writeShellApplication` runs shellcheck: functions that become dead code
  under a flag must be excluded with `lib.optionalString`, not left in.

## Testing

`bash user/wm/sway/sway-apps/tests/cli-smoke.sh [sway-apps-bin]` — 45 checks
against the live session in a throwaway git repo (never touches the real
state). Run it on the machine after a deploy.
