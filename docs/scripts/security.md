---
id: scripts.security
summary: Security scripts — cleanIPTABLESrules.sh for firewall reset; harden.sh/soften.sh retired 2026-09-22
tags: [scripts, security, permissions, firewall, hardening]
related_files: [cleanIPTABLESrules.sh, install.sh]
date: 2026-09-22
status: published
---

# Security Scripts

## harden.sh / soften.sh (retired 2026-09-22)

They chowned `~/.dotfiles` (and `flake.nix`, `install.sh`, `system/`, `profiles/`) to root before
`nixos-rebuild` and back to uid 1000 before Home Manager. `install.sh` left the tree user-owned on
success, so the ownership only ever changed during a rebuild — protecting nothing at rest, while
every `git` by the user in that window died with `dubious ownership` (two concurrent deploys hit it
on VPS_PROD). Root never needed it: `sudo nixos-rebuild` exports `SUDO_UID` and git accepts the
caller's files; the weekly root `autoSystemUpdate.sh` adds its own `safe.directory`. Both scripts
also hardcoded uid 1000.

The repo now stays owned by the user for the whole run. Any root-owned file under `~/.dotfiles`
after a deploy is a bug (`find ~/.dotfiles -not -user $USER`). Secrets keep their own mode
tightening in `install.sh` (`harden_secret_permissions`: `secrets/` 0700, `*.nix`/`*.txt` 0600).

## cleanIPTABLESrules.sh

**Purpose**: Clears all iptables and ip6tables rules.

**Usage**:
```sh
sudo ./cleanIPTABLESrules.sh
```

**What It Does**:
- Sets default policies to ACCEPT for INPUT, FORWARD, OUTPUT
- Flushes all tables (nat, mangle, filter)
- Deletes all custom chains
- Clears both IPv4 (iptables) and IPv6 (ip6tables) rules

**When to Use**:
- Before installation if using custom iptables rules
- When switching to NixOS firewall configuration
- To reset firewall to default state
- When iptables rules conflict with NixOS firewall

**Warning**: This removes all firewall rules. Make sure you have alternative protection or will configure firewall immediately after.

**Note**: Called automatically by `install.sh` if user confirms.
