# Scripts Documentation

Complete reference for all shell scripts in this repository.

## Table of Contents

- [Overview](#overview)
- [Installation Scripts](#installation-scripts)
- [Synchronization Scripts](#synchronization-scripts)
- [Update Scripts](#update-scripts)
- [Maintenance Scripts](#maintenance-scripts)
- [Security Scripts](#security-scripts)
- [Utility Scripts](#utility-scripts)
- [Helper Scripts](#helper-scripts)
- [Script Usage Patterns](#script-usage-patterns)

## Overview

This repository contains shell scripts for automating common tasks, system maintenance, and configuration management. Scripts are located in the repository root and can be run directly or via the `aku` wrapper command.

### Script Categories

- **Installation**: Initial setup and installation
- **Synchronization**: Applying configuration changes
- **Update**: Updating flake inputs and system
- **Maintenance**: System cleanup and optimization
- **Security**: File permissions and hardening
- **Utility**: Helper scripts for specific tasks

## Installation Scripts

### install.sh

**Purpose**: Main installation script for setting up the NixOS configuration.

**Usage**:
```sh
./install.sh <path> <profile> [sudo_password] [-s|--silent]
```

**Parameters**:
- `<path>` - Path to dotfiles directory (e.g., `~/.dotfiles`)
- `<profile>` - Profile name (e.g., `HOME`, `DESK`, `LAPTOP`)
- `[sudo_password]` - Optional sudo password for non-interactive use
- `[-s|--silent]` - Silent mode (non-interactive)

**Notes**:
- Sudo is authenticated early in the run to reduce mid-run prompts. On DESK + LAPTOP, sudo is configured to cache authentication for ~3 hours.
- Docker is only acted on if the Docker daemon is running and there are running containers (then you’ll be prompted to stop them).
- Maintenance is always run automatically (quiet) near the end; run `./maintenance.sh` directly if you want the interactive menu.

**What It Does**:
1. Fetches and resets repository to latest remote commit
2. Records active profile in `.active-profile`
3. Sets up environment files (`set_environment.sh`)
4. Generates SSH keys for boot-time SSH (if enabled)
5. Updates flake.lock
6. Handles Docker containers (only prompts if there are running containers; can stop them automatically)
7. Generates hardware configuration
8. Hardens system files
10. Rebuilds NixOS system
11. Installs Home Manager configuration
12. Runs maintenance script automatically (quiet) and waits for completion (see `maintenance.log`; run `./maintenance.sh` manually for interactive mode)
13. Reconciles Flatpak baseline vs installed apps (optional; see `scripts/flatpak-reconcile.sh`)
14. Starts startup services (optional)

**Features**:
- Interactive and silent modes
- Logging to `install.log`
- Automatic log rotation (10MB max, keeps 3 old logs)
- Color-coded output
- Error handling

**Related**: See [Installation Guide](installation.md)

### scripts/flatpak-reconcile.sh

**Purpose**: Compares a profile’s declarative Flatpak baseline against currently installed Flatpaks (both `--user` and `--system`) and offers to install/remove/snapshot.

**When it runs**: Called by `install.sh` near the end (after Home Manager + maintenance, before the ending menu).

**Baseline file**:
- Per-profile: `profiles/<PROFILE>-flatpaks.json` (example: `profiles/DESK-flatpaks.json`)

**Format**:
```json
{
  "user": ["com.spotify.Client"],
  "system": ["org.videolan.VLC"]
}
```

**Behavior**:
- If the baseline file is missing/invalid: **no-op**
- If the baseline file exists but is empty (`[]`), it’s treated as **opted-in** and the script can offer **Snapshot** to populate it
- If Flatpak can’t be queried reliably (missing command/timeout/error): **no-op** (prevents false “everything missing” on fresh installs)
- If there’s drift: prints missing/extra per scope and offers:
  - Install missing (user/system)
  - Uninstall extra (user/system)
  - Snapshot baseline to match installed (explicit opt-in; won’t overwrite with empty without confirmation)
- In `--silent` mode: never prompts; only logs drift summary (if any)

### set_environment.sh

**Purpose**: Sets up environment-specific files and configurations.

**Usage**: Called automatically by `install.sh`

**What It Does**:
- Hostname-based configuration
- Copies SSL certificates (if configured)
- Sets up local environment files (stored in `local/` directory, gitignored)
- Handles absolute paths (not allowed in NixOS)

**Customization**: Edit this script directly to add hostname-specific environment setup.

**Example Hostnames**:
- `nixosaga` - Aga's system (currently no actions)
- `nixosLabaku` - Lab system (currently no actions)

**Use Cases**:
- Copy SSL certificates to system locations
- Set up local configuration files
- Import environment-specific settings

**Note**: The `local/` directory is gitignored, so you can store system-specific files there.

### stop_external_drives.sh

**Purpose**: Stops external drives and mounts before generating hardware configuration.

**Usage**: Called automatically by `install.sh` before hardware config generation

**Parameters**:
- `[silent_mode]` - Optional silent mode flag

**What It Does**:
- Stops NFS mounts via systemctl
- Stops Docker containers
- Unmounts external drives
- Hostname-specific actions

**Why**: Prevents hardware-configuration.nix from including temporary mounts (NFS, Docker overlayfs) that could cause boot issues.

**Hostname-Based Actions**:
- `nixosaga` - Stops NFS mounts (downloads, Books, Media, Backups)
- `nixosaku` - Stops Docker containers
- `nixosLabaku` - Stops Docker containers

**Customization**: 
- Copy to `~/myScripts/stop_external_drives.sh` and customize for your system
- Add your hostname case with your specific drives/services

**Example**:
```sh
# For hostname "nixosaku"
docker stop $(sudo docker ps -a -q)
sudo systemctl stop mnt-NFS_media.mount
```

**Note**: This is a sample script. Customize it for your specific system configuration.

### startup_services.sh

**Purpose**: Starts services after installation/upgrade.

**Usage**: Called automatically by `install.sh` at the end

**What It Does**:
- Hostname-based service startup
- Interactive menu for service management (for `nixosaku`)
- Mounts NFS drives
- Starts Docker containers via docker-compose
- Updates Flatpak (optional)
- Runs backups (optional)

**Hostname-Based Actions**:
- `nixosaku` - Interactive menu with options:
  - Update Flatpak
  - Run backups
  - Mount SSHFS volumes
  - Start NFS mounts
- `nixosLabaku` - Automatic startup:
  - Checks drive directories
  - Starts NFS mounts
  - Starts Docker services (nextcloud, syncthing, freshrss, etc.)

**Customization**: 
- Copy to `~/myScripts/startup_services.sh` and customize for your system
- Add your hostname case with your specific services

**Example Menu Options** (for `nixosaku`):
- `1` - Mount homelab HOME via SSHFS
- `2` - Mount homelab DATA_4TB via SSHFS and backup
- `3` - Mount homelab HDD_4TB via SSHFS
- `4` - Mount leftyworkout_TEST project via SSHFS
- `5-7` - Start NFS mounts (media, emulators, library)
- `S` - Stop all external drives
- `Q` - Quit menu

**Note**: This is a sample script. Customize it for your specific system configuration.

## Synchronization Scripts

### sync.sh

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

### sync-system.sh

**Purpose**: Synchronizes system configuration only.

**Usage**:
```sh
./sync-system.sh
# Or via aku
aku sync system
```

**What It Does**:
- Rebuilds NixOS system configuration
- Applies system-level changes

**Command**:
```sh
sudo nixos-rebuild switch --flake $SCRIPT_DIR#$ACTIVE_PROFILE --show-trace
```

### sync-user.sh

**Purpose**: Synchronizes home-manager configuration only.

**Usage**:
```sh
./sync-user.sh
# Or via aku
aku sync user
```

**What It Does**:
- Installs/updates Home Manager configuration
- Applies user-level changes
- Runs post-hooks (`sync-posthook.sh`)

**Command**:
```sh
home-manager switch --flake $SCRIPT_DIR#$ACTIVE_PROFILE --show-trace
```

### sync-posthook.sh

**Purpose**: Runs post-synchronization hooks to refresh applications.

**Usage**: Called automatically by `sync-user.sh`

**What It Does**:
- **XMonad**: Kills xmobar, recompiles and restarts xmonad, restarts dunst, applies background
- **Hyprland**: Reloads hyprland, restarts waybar, fnott, hyprpaper, nwggrid-server
- **Emacs**: Reloads doom-stylix theme

**Purpose**: Ensures applications pick up configuration changes without manual restart.

## Update Scripts

### update.sh

**Purpose**: Updates flake inputs (flake.lock) without rebuilding.

**Usage**:
```sh
./update.sh
# Or via aku
aku update
```

**What It Does**:
- Updates `flake.lock` with latest package versions
- Does not rebuild system
- Falls back to alternative update methods if primary fails

**Command**:
```sh
sudo nix flake update --flake "$SCRIPT_DIR"
```

### upgrade.sh

**Purpose**: Updates flake inputs and synchronizes system.

**Usage**:
```sh
./upgrade.sh [path] [profile] [-s|--silent]
```

**Parameters**:
- `[path]` - Optional dotfiles directory path
- `[profile]` - Optional profile name
- `[-s|--silent]` - Silent mode

**What It Does**:
1. Switches flake profile (if profile provided)
2. Handles Docker containers
3. Updates flake.lock (`update.sh`)
4. Synchronizes system and user (`sync.sh`)
5. Runs maintenance script (optional)

**Note**: Does not pull from git (use `pull.sh` for that).

### pull.sh

**Purpose**: Pulls changes from git repository while preserving local edits.

**Usage**:
```sh
./pull.sh
# Or via aku
aku pull
```

**What It Does**:
1. Softens file permissions (for git operations)
2. Stashes local changes
3. Pulls from remote repository
4. Re-applies stashed changes
5. Hardens file permissions

**Use Case**: Updating secondary systems while preserving local customizations.

**Command Sequence**:
```sh
soften.sh
git stash
git pull
git stash apply
harden.sh
```

## Maintenance Scripts

### maintenance.sh

**Purpose**: Automated system maintenance and cleanup.

**Usage**:
```sh
./maintenance.sh [-s|--silent]
```

**Options**:
- `-s, --silent` - Run all tasks silently without menu

**What It Does**:
1. **System Generations Cleanup**: Keeps last 6 generations (count-based), removes older
2. **Home Manager Generations Cleanup**: Keeps last 4 generations (count-based), removes older
3. **User Generations Cleanup**: Removes generations older than 15 days (time-based)
4. **Garbage Collection**: Collects unused Nix store entries orphaned by generation deletion

**Configuration**:
```sh
SystemGenerationsToKeep=6      # Keep last 6 system generations (count-based: +N)
HomeManagerGenerationsToKeep=4 # Keep last 4 home-manager generations (count-based: +N)
UserGenerationsKeepOnlyOlderThan="15d"  # Delete user generations older than 15 days (time-based: Nd)
```

**Logging**: All actions logged to `maintenance.log` with timestamps. Includes summary statistics.

**Interactive Menu**:
- `1` - Run all tasks
- `2` - Prune system generations (Keep last 6)
- `3` - Prune home-manager generations (Keep last 4)
- `4` - Remove user generations older than 15d
- `5` - Run garbage collection
- `Q` - Quit

**Note**: The script must be run as a normal user (not root). It uses `sudo` internally when needed.

### Sudo prompt behavior (DESK + LAPTOP)

On DESK and LAPTOP profiles, sudo is configured to keep the authentication timestamp cached longer (3 hours) to reduce repeated password prompts during long maintenance / install operations.\n+
**Related**: See [Maintenance Guide](maintenance.md)

### autoSystemUpdate.sh

**Purpose**: Automated system update script for SystemD timers.

**Usage**: Designed to be called by SystemD timer

**Parameters**:
- `[path]` - Optional dotfiles directory path

**What It Does**:
1. Updates flake.lock (`update.sh`)
2. Rebuilds system (`nixos-rebuild switch`)
3. Runs maintenance script silently (`maintenance.sh -s`)

**Requirements**: Must run as root

**Use Case**: Automated system updates via SystemD timer.

**Example SystemD Timer**:
```nix
systemd.timers.auto-system-update = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};

systemd.services.auto-system-update = {
  serviceConfig.Type = "oneshot";
  script = ''
    ${pkgs.bash}/bin/bash ${./autoSystemUpdate.sh} $DOTFILES_DIR
  '';
};
```

**Note**: Commented out sections for stopping/starting services can be enabled if needed.

### autoUserUpdate.sh

**Purpose**: Automated user/home-manager update script for SystemD timers.

**Usage**: Designed to be called by SystemD timer

**Parameters**:
- `[path]` - Optional dotfiles directory path

**What It Does**:
- Updates Home Manager configuration
- Uses `nix run home-manager/master` with experimental features

**Requirements**: Must run as regular user (not root)

**Use Case**: Automated Home Manager updates via SystemD timer.

**Example SystemD Timer**:
```nix
systemd.timers.auto-user-update = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};

systemd.services.auto-user-update = {
  serviceConfig = {
    Type = "oneshot";
    User = "username";
  };
  script = ''
    ${pkgs.bash}/bin/bash ${./autoUserUpdate.sh} $DOTFILES_DIR
  '';
};
```

## Security Scripts

### harden.sh

**Purpose**: Makes system-level configuration files read-only for unprivileged users.

**Usage**:
```sh
sudo ./harden.sh [path]
# Or via aku
aku harden
```

**Parameters**:
- `[path]` - Optional dotfiles directory path

**What It Does**:
- Changes ownership of system files to root (UID 0, GID 0)
- Prevents unprivileged users from modifying:
  - `system/` directory
  - `profiles/*/configuration.nix` files
  - `flake.nix` and `flake.lock`
  - `patches/` directory
  - Installation and update scripts

**Security Note**: Assumes user has UID/GID 1000. After hardening, `nix flake update` requires root.

**When to Use**:
- After installation
- After making configuration changes
- Before leaving system unattended

### soften.sh

**Purpose**: Relaxes file permissions to allow editing by unprivileged user.

**Usage**:
```sh
sudo ./soften.sh [path]
# Or via aku
aku soften
```

**Parameters**:
- `[path]` - Optional dotfiles directory path

**What It Does**:
- Changes ownership of all files to user (UID 1000, GID users)
- Allows unprivileged user to edit all files

**Security Warning**: ⚠️ After running this, unprivileged users can modify system configuration files, which may compromise system security after `nixos-rebuild switch`.

**When to Use**:
- Temporarily for git operations
- When editing configuration files
- Before running `pull.sh`

**Important**: Always run `harden.sh` again after editing!

### cleanIPTABLESrules.sh

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

**Warning**: ⚠️ This removes all firewall rules. Make sure you have alternative protection or will configure firewall immediately after.

**Note**: Called automatically by `install.sh` if user confirms.

## Utility Scripts

### fix-terminals

**Purpose**: Configure VS Code and Cursor terminal keybindings for proper copy/paste behavior.

**Usage**:
```sh
fix-terminals
```

**What It Does**:
- Patches `keybindings.json` files for VS Code and Cursor
- Adds required keybindings:
  - `Ctrl+V` → `workbench.action.terminal.paste` (when terminal focused)
  - `Ctrl+C` → `workbench.action.terminal.copySelection` (when terminal focused and text selected)

**Key Features**:
- **Idempotent**: Safe to run multiple times without duplicating entries
- **Backup**: Creates `.bak` files before modifying configuration files
- **Fresh Install Support**: Creates parent directories if they don't exist (e.g., `~/.config/Code/User/`)
- **JSON Comment Support**: Handles VS Code/Cursor JSON files with comments (strips comments before parsing)

**Target Files**:
- `~/.config/Code/User/keybindings.json` (VS Code)
- `~/.config/Cursor/User/keybindings.json` (Cursor)

**Module**: `user/app/terminal/fix-terminals.nix`

**Related**: See [Terminal Keybindings](../keybindings.md#terminal-keybindings) for complete documentation.

### scripts/generate_docs_index.py

**Purpose**: Generates a Router + Catalog index for AI context retrieval optimization.

**Usage**:
```sh
python3 scripts/generate_docs_index.py
```

**What It Does**:
1. Scans project structure (`docs/`, `system/`, `user/`, `profiles/`, `lib/`)
2. Parses Nix files to extract module purposes and `lib.mkIf` conditional logic
3. Parses Markdown files to extract summaries
4. Generates a hierarchical index organized by:
   - Flake Architecture
   - Profiles
   - System Modules (by category)
   - User Modules (by category)
   - Documentation (by structure level)

**Features**:
- **Nix Module Parsing**: Extracts first comment block as module purpose
- **Conditional Detection**: Identifies `lib.mkIf` conditions and notes when modules are active
- **Documentation Structure Detection**: Recognizes 3-level and 4-level documentation structures
- **Auto-Generation Warning**: Index file includes warning header to prevent manual editing

**Output**:
- Creates/updates:
  - `docs/00_ROUTER.md` (small routing table)
  - `docs/01_CATALOG.md` (full catalog)
  - `docs/00_INDEX.md` (compatibility shim)
- Each entry includes: Title, Summary, File Path, and Conditional Logic (if applicable)

**When to Regenerate**:
- After adding new major modules
- After restructuring documentation
- After modifying `lib.mkIf` conditions in modules
- When index becomes outdated

**Note**: The index is auto-generated. Do not edit `docs/00_INDEX.md` manually. Always regenerate using this script.

**Dependencies**:
- Python 3.6 or higher
- Standard library only (no external dependencies)

**Error Handling**:
- If Python 3 is not available, script will output a clear warning
- Handles missing directories gracefully
- Provides helpful error messages for unreadable files

### handle_docker.sh

**Purpose**: Stops Docker containers before system updates to prevent boot issues.

**Usage**: Called automatically by `install.sh` and `upgrade.sh`

**Parameters**:
- `[silent_mode]` - Optional silent mode flag

**What It Does**:
1. Checks if Docker is installed
2. Checks if Docker is running
3. Lists running containers
4. Prompts user to stop (unless silent mode)
5. Stops all running containers

**Why**: Docker overlay filesystems can cause boot failures when NixOS tries to mount them during boot.

**Related**: See [Maintenance Guide](maintenance.md#docker-container-management)

### themes/background-test.sh

**Purpose**: Tests if theme background URLs are accessible.

**Usage**:
```sh
cd themes
./background-test.sh
```

**What It Does**:
- Iterates through all theme directories
- Tests each theme's `backgroundurl.txt` URL using `curl`
- Reports which backgrounds download successfully
- Reports which backgrounds fail (in red)

**Use Case**: Troubleshooting theme installation failures due to broken background URLs.

**Output**:
- Normal text: Background downloads successfully
- Red text: Background download fails

**How It Works**:
```sh
# For each theme directory
curl --head --fail $(cat $theme/backgroundurl.txt)
```

**Related**: See [Themes Guide](themes.md) for theme troubleshooting.

## Helper Scripts

### user/wm/plasma6/_export_homeDotfiles.sh

**Purpose**: Exports Plasma 6 configuration files from `$HOME` to source directory.

**Usage**:
```sh
cd user/wm/plasma6
./_export_homeDotfiles.sh
```

**What It Does**:
- Copies Plasma dotfiles from `$HOME` to `~/.dotfiles-plasma-config/source/`
- Preserves current Plasma configuration for version control

**When to Use**: When you want to save your current Plasma settings to the repository.

### user/wm/plasma6/_remove_homeDotfiles.sh

**Purpose**: Removes Plasma dotfiles from `$HOME` to prepare for symlink setup.

**Usage**:
```sh
cd user/wm/plasma6
./_remove_homeDotfiles.sh
```

**What It Does**:
- Moves Plasma dotfiles from `$HOME` to temporary directory
- Prepares for Home Manager to create symlinks

**When to Use**: Before initial Home Manager setup or when resetting Plasma configuration.

### user/wm/plasma6/_check_directories.sh

**Purpose**: Checks if required Plasma configuration directories exist.

**Usage**: Called by Plasma 6 module during Home Manager build

**What It Does**:
- Verifies source directory structure exists
- Checks for user-specific directories
- Ensures Plasma configuration can be properly linked

**Related**: See [Plasma 6 Documentation](user-modules/plasma6.md) for details.

### user/wm/xmonad/startup.sh

**Purpose**: XMonad startup script executed when XMonad starts.

**Usage**: Called automatically by XMonad on window manager startup

**What It Does**:
- Starts XMonad-related services and daemons
- Sets up environment variables
- Applies XMonad-specific configurations
- Initializes auxiliary utilities

**Related**: See [XMonad Documentation](user-modules/xmonad.md) for details.

### user/wm/sway/desk-startup-apps-init

**Purpose**: Non-blocking initialization script for DESK profile that sets up workspaces and unlocks KWallet using a GPG-encrypted password file.

**Usage**: Called automatically by Sway on startup (only for DESK profile)

**What It Does**:
- Sets up workspaces on primary and secondary monitors (fast, non-blocking)
- Waits for Sway socket to be ready (required for GPG pinentry to have a display)
- Checks for GPG-encrypted password file at `~/.config/kwallet/password.gpg`
- Decrypts password file using GPG (GPG agent handles passphrase if cached)
- Attempts to unlock KWallet with decrypted password using `kwalletcli` (secure here-string method)
- Falls back to GUI prompt if password file missing, decryption fails, or unlock fails
- Launches background launcher script (`desk-startup-apps-launcher`) to monitor unlock status
- Exits immediately (system continues starting normally, no blocking)

**Key Features**:
- Non-blocking system startup
- GPG-encrypted password file integration (uses existing GPG agent infrastructure)
- Automatic password decryption (if GPG agent passphrase cached)
- KWallet version compatibility (kwalletd5 and kwalletd6)
- Graceful fallback to GUI prompt

**Password File Setup**:
```bash
# Create directory
mkdir -p ~/.config/kwallet

# Create and encrypt password file (replace with your email/key ID)
echo "your-kwallet-password" | gpg --encrypt --recipient "your-email@example.com" -o ~/.config/kwallet/password.gpg

# Set secure permissions
chmod 600 ~/.config/kwallet/password.gpg
```

**Note**: The password file uses GPG encryption. If your GPG agent has the passphrase cached (same system used for SSH keys), decryption happens automatically. Otherwise, GPG will prompt for the passphrase via pinentry.

**Related**: See [Sway Configuration](../user-modules/sway.md) for details.

### user/wm/sway/desk-startup-apps-launcher

**Purpose**: Manual app launcher for DESK profile that launches applications to their assigned workspaces.

**Usage**: Triggered manually via keybinding (`${hyper}+Shift+Return`) or called directly

**What It Does**:
- Checks if KWallet is unlocked (exits if not unlocked)
- Shows Rofi confirmation dialog asking user to confirm app launch
- Launches applications in parallel (all apps launch simultaneously)
- Handles Flatpak app detection and launching
- Falls back to native packages if Flatpak version not available

**Key Features**:
- KWallet unlock check (requires KWallet to be unlocked before launching)
- Rofi confirmation dialog (user must confirm before apps launch)
- Flatpak app support (checks if apps are installed via Flatpak)
- Parallel app launching (all apps launch simultaneously)
- Declarative workspace assignment (Sway's `assign` rules handle placement automatically)

**Application Assignments** (handled by Sway's declarative `assign` rules in `swayfx-config.nix`):
- **Vivaldi**: Assigned to workspace 11
- **Cursor**: Assigned to workspace 12
- **Chromium**: Assigned to workspace 22
- **Obsidian**: Assigned to workspace 21

**Workspace Management**:
- Workspace-to-output assignments are handled declaratively in Sway's configuration using hardware IDs
- App-to-workspace assignments are handled declaratively via Sway's `assign` rules
- The script does NOT perform any workspace switching or management - it simply launches apps and lets Sway's configuration handle placement

**Flatpak App Handling**:
- Checks if apps are installed via Flatpak using `flatpak list` or `flatpak info`
- Launches Flatpak apps with `flatpak run APP_ID`
- Falls back to native packages if Flatpak version not available
- Supports both Flatpak and native app IDs in Sway assign rules

**Related**: See [Sway Configuration](../user-modules/sway.md) and [Sway Output Layout](../user-modules/sway-output-layout-kanshi.md) for details.

### user/app/ranger/scope.sh

**Purpose**: Ranger file preview script for file content preview.

**Usage**: Used automatically by Ranger file manager for file previews

**What It Does**:
- Provides file preview functionality in Ranger
- Handles different file types (text, images, etc.)
- Displays file contents in preview pane

**Related**: See [Ranger Documentation](user-modules/ranger.md) for details.

### profiles/wsl/nixos-wsl/syschdemd.sh

**Purpose**: WSL-specific system change daemon for NixOS-WSL.

**Usage**: Part of NixOS-WSL integration, called by WSL system

**What It Does**:
- Manages WSL-specific system changes
- Handles Windows integration
- Processes WSL system events

**Note**: This is part of the NixOS-WSL project, not custom code. See [WSL Profile Documentation](../profiles.md#wsl-profile) for details.

## Script Usage Patterns

### Typical Workflow

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

**Maintenance**:
```sh
aku gc 30d
./maintenance.sh
```

### Quick Reference

| Script | Purpose | Usage | Requires Sudo |
|--------|---------|-------|---------------|
| `install.sh` | Main installation | `./install.sh <path> <profile> [-s]` | Yes |
| `sync.sh` | Sync system + user | `./sync.sh` or `aku sync` | Yes (system) |
| `sync-system.sh` | Sync system only | `./sync-system.sh` or `aku sync system` | Yes |
| `sync-user.sh` | Sync user only | `./sync-user.sh` or `aku sync user` | No |
| `update.sh` | Update flake.lock | `./update.sh` or `aku update` | Yes |
| `upgrade.sh` | Update + sync | `./upgrade.sh [path] [profile] [-s]` or `aku upgrade` | Yes |
| `pull.sh` | Pull from git | `./pull.sh` or `aku pull` | Yes (temporarily) |
| `maintenance.sh` | System cleanup | `./maintenance.sh [-s]` | Yes (some tasks) |
| `harden.sh` | Secure files | `sudo ./harden.sh [path]` or `aku harden` | Yes |
| `soften.sh` | Relax permissions | `sudo ./soften.sh [path]` or `aku soften` | Yes |
| `handle_docker.sh` | Stop containers | Called automatically | No |
| `cleanIPTABLESrules.sh` | Clear firewall | `sudo ./cleanIPTABLESrules.sh` | Yes |
| `stop_external_drives.sh` | Stop mounts | Called automatically | Yes |
| `set_environment.sh` | Environment setup | Called automatically | No |
| `startup_services.sh` | Start services | Called automatically | No |
| `autoSystemUpdate.sh` | Auto system update | SystemD timer | Yes |
| `autoUserUpdate.sh` | Auto user update | SystemD timer | No |
| `themes/background-test.sh` | Test theme URLs | `./themes/background-test.sh` | No |

### Silent/Non-Interactive Mode

Many scripts support silent mode for automation:

```sh
./install.sh ~/.dotfiles "HOME" -s
./upgrade.sh ~/.dotfiles "HOME" -s
./maintenance.sh -s
```

### Script Dependencies

Scripts call each other in this order:

```
install.sh
├── set_environment.sh
├── handle_docker.sh
├── stop_external_drives.sh
├── update.sh
├── harden.sh
├── soften.sh
├── sync-system.sh
├── sync-user.sh
│   └── sync-posthook.sh
├── maintenance.sh
└── startup_services.sh

upgrade.sh
├── handle_docker.sh
├── update.sh
└── sync.sh
    ├── sync-system.sh
    └── sync-user.sh
        └── sync-posthook.sh
```

## Best Practices

### 1. Use Aku Wrapper

Prefer using `aku` commands over direct script execution:
- Consistent interface
- Error handling
- Logging

### 2. Test Before Production

Test scripts on non-critical systems first:
- Verify behavior
- Check error handling
- Review logs

### 3. Review Logs

Check log files after operations:
- `install.log` - Installation operations
- `maintenance.log` - Maintenance operations

### 4. Customize Helper Scripts

Copy and customize these scripts for your system:
- `stop_external_drives.sh` → `~/myScripts/stop_external_drives.sh`
- `startup_services.sh` → `~/myScripts/startup_services.sh`
- `set_environment.sh` - Edit directly

### 5. Security

- Run `harden.sh` after installation
- Use `soften.sh` temporarily only
- Review security implications of custom scripts

## Troubleshooting

### Script Fails with Permission Error

**Problem**: Script can't access files.

**Solution**:
```sh
sudo ./soften.sh
# Make changes
sudo ./harden.sh
```

### Docker Containers Not Stopping

**Problem**: `handle_docker.sh` fails to stop containers.

**Solution**:
```sh
# Manual stop
docker stop $(docker ps -q)

# Or force stop
docker kill $(docker ps -q)
```

### Script Hangs

**Problem**: Script waits for user input.

**Solution**: Use silent mode or check if script is waiting for input.

### Log Files Too Large

**Problem**: Log files consuming disk space.

**Solution**: Logs auto-rotate at 10MB, but you can manually clean:
```sh
rm install.log_*.old
rm maintenance.log_*.old
```

## Script Dependencies Graph

```
install.sh
├── set_environment.sh
├── handle_docker.sh
├── stop_external_drives.sh (customizable)
├── update.sh
├── harden.sh
├── soften.sh (temporary)
├── sync-system.sh
├── sync-user.sh
│   └── sync-posthook.sh
├── maintenance.sh
└── startup_services.sh (customizable)

upgrade.sh
├── handle_docker.sh
├── update.sh
└── sync.sh
    ├── sync-system.sh
    └── sync-user.sh
        └── sync-posthook.sh

pull.sh
├── soften.sh
├── git operations
└── harden.sh

autoSystemUpdate.sh
├── update.sh
├── sync-system.sh
└── maintenance.sh -s

autoUserUpdate.sh
└── sync-user.sh
    └── sync-posthook.sh
```

## Script Customization

### Customizable Scripts

These scripts are designed to be customized for your system:

1. **stop_external_drives.sh**
   - Copy to `~/myScripts/stop_external_drives.sh`
   - Add your hostname case
   - Customize drive stopping logic

2. **startup_services.sh**
   - Copy to `~/myScripts/startup_services.sh`
   - Add your hostname case
   - Customize service startup logic

3. **set_environment.sh**
   - Edit directly in repository
   - Add hostname-specific environment setup

### Script Parameters

Most scripts accept optional parameters:

- **Path Parameter**: `./script.sh [path]` - Dotfiles directory path
- **Silent Mode**: `./script.sh [-s|--silent]` - Non-interactive mode
- **Profile Parameter**: `./script.sh [path] [profile]` - Profile selection

## Related Documentation

- [Maintenance Guide](maintenance.md) - Maintenance tasks and automation
- [Installation Guide](installation.md) - Installation procedures
- [Configuration Guide](configuration.md) - Configuration management
- [Aku Wrapper](maintenance.md#aku-wrapper) - Command wrapper documentation

