# Per-machine Claude rules

`../hooks/profile-context.sh` (SessionStart hook, registered in `user/app/claude-code/claude-code.nix`) prints the file(s) for `$ENV_PROFILE` into the session context — in every project on that machine, and nowhere else. CLAUDE.md files cannot do this (per repo, unconditional) and `@import` loads eagerly.

| File | Profiles |
|---|---|
| `workstation.md` | DESK, LAPTOP_X13 |
| `desk-w11.md` | DESK_W11 |
| `komi.md` | MACBOOK_KOMI, KOMI_LXC_* |

Keep the sum of what one profile receives under ~6 KB: hook stdout is capped at 10,000 chars and the overflow goes to a file Claude never reads. Plan: `docs/akunito/plans/claude-md-lazy-loading.md`.
