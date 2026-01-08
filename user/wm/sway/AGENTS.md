## Sway (agent notes)

This directory is SwayFX-specific. Keep changes scoped and avoid leaking Sway-only rules into other WMs.

## Read first

- `docs/00_ROUTER.md` (pick the right ID)
- `docs/user-modules/sway-daemon-integration.md` (canonical daemon architecture doc)

## Critical constraints

- **Systemd-first session services** are the standard: bind Sway-only services to `sway-session.target`.
- Ensure every service is managed by **exactly one** lifecycle mechanism (prefer systemd user services).
- Prefer editing the single source of truth: `user/wm/sway/default.nix`.

