---
id: scripts.sync-update
summary: Synchronization and update scripts — sync.sh, sync-system.sh, sync-user.sh, update.sh, upgrade.sh, pull.sh
tags: [scripts, sync, update, upgrade, flake]
related_files: [sync.sh, sync-system.sh, sync-user.sh, sync-posthook.sh, update.sh, upgrade.sh, pull.sh]
date: 2026-02-15
status: published
---

# Synchronization & Update Scripts

## sync.sh

**Purpose**: Synchronizes both system and home-manager configurations.

**Usage**:
```sh
./sync.sh
# Or via aku
aku sync
```

**What It Does**:
- Calls `sync-system.sh`
- Calls `sync-user.sh`

**Equivalent To** (where `$ACTIVE_PROFILE` is read from `.active-profile`):
- `nixos-rebuild switch --flake .#$ACTIVE_PROFILE`
- `home-manager switch --flake .#$ACTIVE_PROFILE`

## sync-system.sh

**Purpose**: Synchronizes system configuration only.

**Usage**:
```sh
./sync-system.sh
# Or via aku
aku sync system
```

**Command**:
```sh
sudo nixos-rebuild switch --flake $SCRIPT_DIR#$ACTIVE_PROFILE --show-trace
```

## sync-user.sh

**Purpose**: Synchronizes home-manager configuration only.

**Usage**:
```sh
./sync-user.sh
# Or via aku
aku sync user
```

**Command**:
```sh
home-manager switch --flake $SCRIPT_DIR#$ACTIVE_PROFILE --show-trace
```

## sync-posthook.sh

**Purpose**: Runs post-synchronization hooks to refresh applications.

**Usage**: Called automatically by `sync-user.sh`

**What It Does**:
- **XMonad**: Kills xmobar, recompiles and restarts xmonad, restarts dunst, applies background
- **Hyprland**: Reloads hyprland, restarts waybar, fnott, hyprpaper, nwggrid-server
- **Emacs**: Reloads doom-stylix theme

## update.sh

**Purpose**: Updates flake inputs (flake.lock) without rebuilding.

**Usage**:
```sh
./update.sh
# Or via aku
aku update
```

**Command**:
```sh
sudo nix flake update --flake "$SCRIPT_DIR"
```

## upgrade.sh

**Purpose**: Updates flake inputs and synchronizes system.

**Usage**:
```sh
./upgrade.sh [path] [profile] [-s|--silent]
```

**What It Does**:
1. Switches flake profile (if profile provided)
2. Handles Docker containers
3. Updates flake.lock (`update.sh`)
4. Synchronizes system and user (`sync.sh`)
5. Runs maintenance script (optional)

**Note**: Does not pull from git (use `pull.sh` for that).

## pull.sh

**Purpose**: Pulls changes from git repository while preserving local edits.

**Usage**:
```sh
./pull.sh
# Or via aku
aku pull
```

**Command Sequence**:
```sh
soften.sh
git stash
git pull
git stash apply
harden.sh
```

**Use Case**: Updating secondary systems while preserving local customizations.

## Typical Workflow

**Initial Installation**:
```sh
./install.sh ~/.dotfiles "DESK"
```

**Regular Updates**:
```sh
aku upgrade
```

**Quick Sync**:
```sh
aku sync
```

**Silent/Non-Interactive Mode**:
```sh
./install.sh ~/.dotfiles "HOME" -s
./upgrade.sh ~/.dotfiles "HOME" -s
```
