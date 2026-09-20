# AkuWM configuration

Two layers, merged in this order and then put on top of AkuWM's built-in
defaults:

| file | what belongs in it |
|---|---|
| `common.json` | everything shared: the rules, the workspaces, the chords, the look |
| `DESK_W11.json` | only what is true of this machine, chiefly the monitor identities |

The machine layer overrides **by id**, field by field: an entry whose `id` is
already in `common.json` is merged into it, so switching one rule off here is
three lines, not a copy of the rule. An entry with a new id is appended.
Nothing is ever removed by merging — to switch something off, set
`"enabled": false`.

AkuWM finds this directory through `AKUWM_STATE_DIR`, and falls back to the
dotfiles checkout it is running from. The machine layer's name comes from
`AKUWM_PROFILE`, else `ENV_PROFILE`, else `DESK_W11`.

Runtime state — the log and the layout journal — is **not** here: it is per
machine and changes every minute, and lives in `%LOCALAPPDATA%\akuwm\`.

## Where this came from

`common.json` was produced by `akuwm config import glazewm`, which read the
GlazeWM configuration (21 rules, 20 workspaces), the raise-or-launch table in
`hyper-desktops.ahk` (13 apps) and the Windows Startup folder (4 entries) that
ran this desk before AkuWM. Re-running it needs `--force`.

The two `monitors` entries have no identity yet: their EDID is filled in on the
desk once AkuWM can read it (M1). Until then `akuwm doctor` warns about it,
because a role matched by position is a role a sleep cycle can move.

The application itself is at `github.com/akunito/AkuWM` (MIT); the plan is
`docs/akunito/infrastructure/desk-w11-akuwm-plan.md`.
