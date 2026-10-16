## komi / admin sessions (MACBOOK_KOMI, KOMI_LXC_*) — branch `komi`
Docs: `docs/komi/` (macOS install + migration, LXC). Merge between `komi` and `main` only with `/merge-branches`.
- CAN freely modify: `profiles/MACBOOK-*`, `profiles/darwin/*`, `profiles/KOMI_LXC*` (incl. `KOMI_LXC-base-config.nix`), `system/darwin/*`, `user/app/hammerspoon/komi-*`, `secrets/komi/`, `.claude/commands/`, `docs/komi/`.
- CAN add `KOMI_LXC_*` entries to `flake.nix` (never modify existing entries) and darwin guards to shared modules (`lib.mkIf isDarwin` / `lib.optionals !isDarwin`).
- MUST NOT modify: `secrets/domains.nix`, akunito's LXC profiles, `system/app/` services, existing flake entries. MUST NOT remove Linux functionality from shared modules.
- Apply on macOS: `darwin-rebuild switch --flake .#MACBOOK-KOMI` (rule file `.claude/rules/darwin.md`); on LXC: `install.sh ~/.dotfiles <PROFILE> -s -d -h`.
