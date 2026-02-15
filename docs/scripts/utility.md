---
id: scripts.utility
summary: Utility and helper scripts — fix-terminals, generate_docs_index.py, handle_docker.sh, Plasma/Sway/Ranger helpers
tags: [scripts, utility, helper, docker, themes, plasma, sway, ranger]
related_files: [handle_docker.sh, themes/background-test.sh, user/wm/plasma6/_*.sh, user/wm/sway/desk-startup-*, user/app/ranger/scope.sh, scripts/generate_docs_index.py]
date: 2026-02-15
status: published
---

# Utility & Helper Scripts

## fix-terminals

**Purpose**: Configure VS Code and Cursor terminal keybindings for proper copy/paste behavior.

**Usage**:
```sh
fix-terminals
```

**What It Does**:
- Patches `keybindings.json` files for VS Code and Cursor
- Adds `Ctrl+V` → paste and `Ctrl+C` → copy keybindings when terminal focused

**Key Features**:
- **Idempotent**: Safe to run multiple times without duplicating entries
- **Backup**: Creates `.bak` files before modifying configuration files
- **Fresh Install Support**: Creates parent directories if they don't exist

**Module**: `user/app/terminal/fix-terminals.nix`

## scripts/generate_docs_index.py

**Purpose**: Generates a Router + Catalog index for AI context retrieval optimization.

**Usage**:
```sh
python3 scripts/generate_docs_index.py
```

**What It Does**:
1. Scans project structure (`docs/`, `system/`, `user/`, `profiles/`, `lib/`)
2. Parses Nix files to extract module purposes and `lib.mkIf` conditional logic
3. Parses Markdown files to extract summaries
4. Generates a hierarchical index

**Output**:
- `docs/00_ROUTER.md` (small routing table)
- `docs/01_CATALOG.md` (full catalog)
- `docs/00_INDEX.md` (compatibility shim)

**When to Regenerate**: After adding new modules, restructuring documentation, or modifying `lib.mkIf` conditions.

**Dependencies**: Python 3.6+, standard library only.

## handle_docker.sh

**Purpose**: Stops Docker containers before system updates to prevent boot issues.

**Usage**: Called automatically by `install.sh` and `upgrade.sh`

**What It Does**:
1. Checks if Docker is installed and running
2. Lists running containers
3. Prompts user to stop (unless silent mode)
4. Stops all running containers

**Why**: Docker overlay filesystems can cause boot failures when NixOS tries to mount them during boot.

## themes/background-test.sh

**Purpose**: Tests if theme background URLs are accessible.

**Usage**:
```sh
cd themes && ./background-test.sh
```

## Helper Scripts

### Plasma 6 Helpers (`user/wm/plasma6/`)

- `_export_homeDotfiles.sh` - Exports Plasma 6 configs from `$HOME` to source directory
- `_remove_homeDotfiles.sh` - Removes Plasma dotfiles from `$HOME` for symlink setup
- `_check_directories.sh` - Checks if required Plasma config directories exist

### Sway Helpers (`user/wm/sway/`)

- `desk-startup-apps-init` - Non-blocking DESK startup: sets up workspaces, unlocks KWallet via GPG-encrypted password, launches background app launcher
- `desk-startup-apps-launcher` - Manual app launcher (triggered via `${hyper}+Shift+Return`): checks KWallet, shows Rofi confirmation, launches apps in parallel

### Other Helpers

- `user/app/ranger/scope.sh` - Ranger file preview script
- `profiles/wsl/nixos-wsl/syschdemd.sh` - WSL-specific system change daemon
- `user/wm/xmonad/startup.sh` - XMonad startup script

## Best Practices

1. **Use Aku Wrapper**: Prefer `aku` commands over direct script execution
2. **Test Before Production**: Test scripts on non-critical systems first
3. **Review Logs**: Check `install.log` and `maintenance.log` after operations
4. **Customize Helper Scripts**: Copy and customize `stop_external_drives.sh` and `startup_services.sh` to `~/myScripts/`
5. **Security**: Run `harden.sh` after installation, use `soften.sh` temporarily only

## Troubleshooting

- **Permission Error**: Run `sudo ./soften.sh`, make changes, then `sudo ./harden.sh`
- **Docker Not Stopping**: Manual stop with `docker stop $(docker ps -q)` or force with `docker kill $(docker ps -q)`
- **Script Hangs**: Use silent mode or check if script is waiting for input
- **Log Files Too Large**: Logs auto-rotate at 10MB; manually clean with `rm install.log_*.old`
