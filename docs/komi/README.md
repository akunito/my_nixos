# komi docs

macOS/darwin documentation specific to komi's environment.

## Contents

- `macos-installation.md` — Installing dotfiles on macOS with nix-darwin
- `macos-komi-migration.md` — Migrating from standalone macos-setup to Nix-managed
- `komi-onboarding.md` — Multi-user branch setup and workflow
- `komi-proxmox-guide.md` — Proxmox basics for komi

## Secrets

Current komi docs are public and don't need encryption. If you ever need to store secrets:

- The `secrets/komi/` directory pattern already exists in `.gitattributes`
- Initialize a komi git-crypt key: `git-crypt init --key-name komi`
- Export the key: `git-crypt export-key --key-name komi ~/komi-git-crypt-key`

For shared docs (security/, setup/, user-modules/), see the parent `docs/` directory.
