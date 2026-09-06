# sway-apps state

Repo-backed state for `sway-apps` (window rules + manual startup apps).

- `common.json` — shared by every machine.
- `<ENV_PROFILE>.json` — per-machine layer; an item with the same `id` as a
  common one overrides it field by field (disable it, change its workspace, …).

These files are edited by the `sway-apps` GUI/CLI, which auto-commits them.
Do not hand-edit while the GUI is open. Regenerate the Sway include with
`sway-apps apply`. Home Manager regenerates it on every `sync-user.sh`.

Seeded 2026-09-06 from the rules that used to live in
`user/wm/sway/swayfx-config.nix` (74 rules, merged by criteria).
