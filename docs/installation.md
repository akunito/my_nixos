# Installation Guide

Complete guide for installing and setting up this NixOS configuration repository.

## AI agent context (Router/Catalog)

If you’re using Cursor or another coding agent, the intended retrieval flow is: `docs/00_ROUTER.md` → relevant docs → scoped code. See `docs/agent-context.md`.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Installation](#quick-installation)
- [Interactive Installation](#interactive-installation)
- [Silent Installation](#silent-installation)
- [Manual Installation](#manual-installation)
- [Post-Installation](#post-installation)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- NixOS system (or NixOS installation media)
- Git installed
- Sudo/root access
- Basic understanding of NixOS flakes

### Required Nix Features

Ensure these experimental features are enabled in your Nix configuration:

```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

## Quick Installation

The fastest way to install is using the automated installation script:

```sh
# Interactive mode
./install.sh ~/.dotfiles "PROFILE"

# Silent mode (non-interactive)
./install.sh ~/.dotfiles "PROFILE" -s
```

Where `PROFILE` corresponds to a flake file:
- `HOME` → uses `flake.HOME.nix`
- `DESK` → uses `flake.DESK.nix`
- `LAPTOP` → uses `flake.LAPTOP.nix`
- etc.

## Interactive Installation

The interactive installation script guides you through the process:

1. **Clone or Update Repository**
   - If the repository doesn't exist, it will be cloned
   - If it exists, it will fetch and reset to the latest remote version

2. **Select Profile**
   - Choose the appropriate flake profile file
   - The script will copy `flake.PROFILE.nix` to `flake.nix`

3. **Environment Setup**
   - Optionally set up additional environment files
   - Configure local settings (stored in `local/` directory, ignored by git)

4. **SSH Keys for Boot**
   - If SSH on boot is enabled, root SSH keys will be generated
   - Used for remote LUKS disk unlocking

5. **Update Flake Lock**
   - Updates `flake.lock` with latest dependencies

6. **Docker Handling**
   - Stops Docker containers to prevent boot issues
   - See [Docker Issues](#docker-issues) for more information

7. **Hardware Configuration**
   - Generates `hardware-configuration.nix` if needed
   - Detects boot mode (UEFI/BIOS)

8. **System Rebuild**
   - Rebuilds NixOS system configuration
   - Installs Home Manager configuration

9. **Maintenance Script**
   - Optionally runs maintenance tasks
   - Cleans up old generations

10. **Startup Services**
    - Optionally runs custom startup services script
    - Located at `startup_services.sh`

## Silent Installation

For automated installations or scripts:

```sh
./install.sh ~/.dotfiles "PROFILE" -s
```

Silent mode:
- Skips all interactive prompts
- Uses default options
- Runs maintenance script automatically
- Starts startup services automatically

## Manual Installation

If you prefer to install manually or the automated script doesn't work:

### 1. Clone Repository

```sh
git clone <your-repo-url> ~/.dotfiles
cd ~/.dotfiles
```

### 2. Select Profile

Copy the appropriate flake file:

```sh
cp flake.PROFILE.nix flake.nix
```

### 3. Edit Configuration

Edit `flake.nix` and update:
- `username` - Your username
- `name` - Your name/identifier
- `hostname` - System hostname
- `timezone` - Your timezone
- Other system-specific settings

### 4. Generate Hardware Configuration

If this is a new system:

```sh
sudo nixos-generate-config --show-hardware-config > system/hardware-configuration.nix
```

### 5. Rebuild System

```sh
sudo nixos-rebuild switch --flake ~/.dotfiles#system
```

### 6. Install Home Manager

```sh
nix run home-manager/master -- switch --flake ~/.dotfiles#user
```

### 7. Harden System Files (Optional)

```sh
./harden.sh
```

This makes system-level configuration files read-only for unprivileged users.

## Post-Installation

### Verify Installation

1. **Check System Status**
   ```sh
   systemctl status
   ```

2. **Verify Home Manager**
   ```sh
   home-manager generations
   ```

3. **Test Phoenix Wrapper**
   ```sh
   phoenix sync
   ```

### First Steps

1. **Update System**
   ```sh
   phoenix upgrade
   ```

2. **Configure SSH Keys** (if needed)
   - Edit `authorizedKeys` in your flake file
   - Rebuild: `phoenix sync system`

3. **Set Up Backups** (if enabled)
   - See [Restic Backups Documentation](security/restic-backups.md)

4. **Configure Themes**
   - See [Themes Documentation](themes.md)

## Troubleshooting

### Common Issues

#### Installation Fails with Bootloader Error

**Problem**: Installation fails with bootloader-related errors.

**Solutions**:
- Check boot mode in `flake.nix`:
  - UEFI: Set `bootMode = "uefi"` and `bootMountPath = "/boot"`
  - BIOS: Set `bootMode = "bios"` and `grubDevice = "/dev/sda"` (or your device)
- Verify EFI partition is mounted at `/boot` for UEFI systems
- Check disk device identifiers with `lsblk`

#### Home Manager Fails with File Conflicts

**Problem**: Home Manager fails with "Existing file is in the way" errors.

**Solution**:
```sh
# Remove conflicting files
rm ~/.gtkrc-2.0
rm ~/.config/Trolltech.conf
# ... remove other conflicting files as listed

# Retry installation
nix run home-manager/master -- switch --flake ~/.dotfiles#user
```

#### Docker Issues

**Problem**: System fails to boot after Docker containers were running.

**Cause**: NixOS picks up Docker overlay filesystems during boot, which can break the boot process.

**Solution**: The `install.sh` script automatically stops Docker containers. If you encounter this manually:

```sh
# Stop all Docker containers
docker stop $(docker ps -q)

# Or use the provided script
./handle_docker.sh
```

More information: [NixOS Discourse Discussion](https://discourse.nixos.org/t/docker-switch-overlay-overlay2-fs-lead-to-emergency-console/29217/4)

#### Theme Background Download Fails

**Problem**: Installation fails with "could not download {image file}".

**Solution**:
1. Test theme backgrounds:
   ```sh
   ./themes/background-test.sh
   ```
2. Select a theme with a working background in `flake.nix`
3. Retry installation

#### Partial Install (Missing Applications)

**Problem**: After installation, many applications are missing.

**Cause**: Home Manager refused to build due to conflicting files.

**Solution**: See "Home Manager Fails with File Conflicts" above.

#### VM Installation - Hyprland Doesn't Work

**Problem**: After installing to a VM, Hyprland crashes on login.

**Solution**: Enable 3D acceleration in your VM settings. Hyprland requires hardware acceleration.

### Getting Help

If you encounter issues not covered here:

1. Check the [Maintenance Documentation](maintenance.md)
2. Review [Configuration Documentation](configuration.md)
3. Check NixOS logs: `journalctl -xe`
4. Review installation log: `install.log`

## Advanced Topics

### Custom Installation Directory

You can install to any directory:

```sh
./install.sh /custom/path "PROFILE"
```

Make sure to update `dotfilesDir` in `flake.nix`:

```nix
dotfilesDir = "/custom/path";
```

### Installing from NixOS ISO

Currently, the automated script only works on an existing NixOS installation. For installation from ISO:

1. Follow manual installation steps
2. Or modify the script for ISO-specific requirements

### Installing Home Manager Only

To install only Home Manager configuration on a non-NixOS Linux system:

1. Install Nix package manager
2. Install Home Manager
3. Clone this repository
4. Run: `nix run home-manager/master -- switch --flake ~/.dotfiles#user`

Note: Some features require NixOS system configuration and won't work.

## Related Documentation

- [Scripts Documentation](scripts.md) - Detailed script reference
- [Configuration Guide](configuration.md) - Understanding and customizing configuration
- [Profiles Guide](profiles.md) - Available profiles and their purposes
- [Maintenance Guide](maintenance.md) - Ongoing maintenance tasks

