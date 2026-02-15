---
id: workflow.multi-user
summary: Multi-user branch management workflow for akunito (main) and ko-mi (komi)
tags: [git, workflow, multi-user, branches, merge]
related_files: [profiles/MACBOOK-KOMI-config.nix, secrets/komi/**, .claude/commands/merge-branches.md]
date: 2026-02-15
status: published
---

# Multi-User Branch Workflow

## Overview

This repo is shared between two users on separate branches:

| User | Branch | Profiles | Focus |
|------|--------|----------|-------|
| **akunito** | `main` | DESK, LAPTOP_*, LXC_*, VMHOME | NixOS infrastructure, desktops, laptops, containers |
| **ko-mi** | `komi` | MACBOOK-KOMI | macOS/darwin configuration |

## Merge Cadence

- **main -> komi**: Weekly or when main has useful changes (keeps komi up to date)
- **komi -> main**: When komi has stable, tested darwin changes to share

Use the `/merge-branches` skill to automate the merge process.

## Branch Rules

### Rules for komi branch

**CAN freely modify:**
- Darwin-specific files: `profiles/darwin/`, `system/darwin/`, `MACBOOK-*`
- Komi's personal files: `komi-init.lua`, `secrets/komi/`
- Claude Code skills: `.claude/commands/`

**CAN add to shared modules (with guards):**
- Darwin guards: `lib.mkIf isDarwin`, `lib.optionals isDarwin`
- Defensive null-checks that benefit all platforms

**MUST NOT modify:**
- `secrets/domains.nix`, `secrets/control-panel.nix`
- LXC profiles (`profiles/LXC_*`)
- System services (`system/app/` except `system/darwin/`)
- `flake.nix` (unified flake, managed on main)

**MUST use feature flags:**
- New features: add flag to `lib/defaults.nix` (default `false`)
- Enable in your profile only
- Never add packages unconditionally to shared modules

### Rules for main branch

**CAN freely modify:**
- All Linux/NixOS infrastructure
- Shared modules (be careful not to break darwin)

**MUST NOT modify:**
- `secrets/komi/`
- `MACBOOK-KOMI-config.nix` (komi's profile)
- `komi-init.lua` (komi's Hammerspoon config)

**SHOULD test darwin:**
- After touching shared modules: `nix eval .#darwinConfigurations.MACBOOK-KOMI.config.system.stateVersion`

## Merge Checklist

### Before merging komi -> main

```
[ ] git diff main...komi -- no unexpected shared module changes
[ ] nix eval .#nixosConfigurations.DESK.config.system.stateVersion
[ ] nix eval .#nixosConfigurations.LXC_monitoring.config.system.stateVersion
```

### Before merging main -> komi

```
[ ] nix eval .#darwinConfigurations.MACBOOK-KOMI.config.system.stateVersion
```

## Secrets Isolation

- `secrets/domains.nix` - encrypted with akunito's git-crypt key (default)
- `secrets/komi/` - encrypted with komi's separate git-crypt key (`git-crypt-komi`)
- Neither user can read the other's encrypted secrets

### Setting up komi's git-crypt key (one-time)

```bash
git-crypt init --key-name komi
git-crypt export-key --key-name komi ~/komi-git-crypt-key
# Share ~/komi-git-crypt-key securely with komi
```

## Shared Module Conventions

When modifying files under `user/`, `lib/`, or `system/` (not `system/darwin/`):

1. **Platform guards for packages:** Use `lib.optionals (!pkgs.stdenv.isDarwin)` for Linux-only packages
2. **Never comment out globally:** Don't disable packages for all platforms when only one has issues
3. **Feature flags for optional features:** Default `false` in `lib/defaults.nix`, each profile enables
4. **Defensive null-checks:** Safe to add `or null`, `or false`, `or ""` fallbacks
