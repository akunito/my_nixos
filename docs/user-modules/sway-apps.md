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
`LAPTOP_X13` since 2026-09-06. With the flag ON, `swayfx-config.nix` stops
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

- `Hyper+Shift+n`
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
sway-apps windows list|focused|pick
sway-apps git status|commit|push|pull
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
