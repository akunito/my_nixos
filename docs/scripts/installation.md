---
id: scripts.installation
summary: Installation and deployment scripts — install.sh, deploy.sh, set_environment.sh, flatpak-reconcile.sh
tags: [scripts, installation, deployment, flatpak]
related_files: [install.sh, deploy.sh, set_environment.sh, stop_external_drives.sh, startup_services.sh, scripts/flatpak-reconcile.sh]
date: 2026-02-15
status: published
---

# Installation Scripts

## install.sh

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
- Docker is only acted on if the Docker daemon is running and there are running containers (then you'll be prompted to stop them).
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

**Related**: See [Installation Guide](../installation.md)

## scripts/flatpak-reconcile.sh

**Purpose**: Compares a profile's declarative Flatpak baseline against currently installed Flatpaks (both `--user` and `--system`) and offers to install/remove/snapshot.

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
- If the baseline file exists but is empty (`[]`), it's treated as **opted-in** and the script can offer **Snapshot** to populate it
- If Flatpak can't be queried reliably (missing command/timeout/error): **no-op** (prevents false "everything missing" on fresh installs)
- If there's drift: prints missing/extra per scope and offers:
  - Install missing (user/system)
  - Uninstall extra (user/system)
  - Snapshot baseline to match installed (explicit opt-in; won't overwrite with empty without confirmation)
- In `--silent` mode: never prompts; only logs drift summary (if any)

## set_environment.sh

**Purpose**: Sets up environment-specific files and configurations.

**Usage**: Called automatically by `install.sh`

**What It Does**:
- Hostname-based configuration
- Copies SSL certificates (if configured)
- Sets up local environment files (stored in `local/` directory, gitignored)
- Handles absolute paths (not allowed in NixOS)

**Note**: The `local/` directory is gitignored, so you can store system-specific files there.

## stop_external_drives.sh

**Purpose**: Stops external drives and mounts before generating hardware configuration.

**Usage**: Called automatically by `install.sh` before hardware config generation

**What It Does**:
- Stops NFS mounts via systemctl
- Stops Docker containers
- Unmounts external drives
- Hostname-specific actions

**Why**: Prevents hardware-configuration.nix from including temporary mounts (NFS, Docker overlayfs) that could cause boot issues.

## startup_services.sh

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
- `nixosaku` - Interactive menu with options (mount SSHFS, NFS, etc.)
- `nixosLabaku` - Automatic startup (NFS, Docker services)
