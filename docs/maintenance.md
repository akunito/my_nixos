# Maintenance & Scripts Guide

Complete guide to maintaining your NixOS configuration and using the provided scripts.

## Table of Contents

- [Overview](#overview)
- [Aku Wrapper](#aku-wrapper)
- [Maintenance Script](#maintenance-script)
- [Installation Scripts](#installation-scripts)
- [Sync Scripts](#sync-scripts)
- [Update Scripts](#update-scripts)
- [Security Scripts](#security-scripts)
- [Automated Maintenance](#automated-maintenance)
- [Best Practices](#best-practices)

## Overview

This configuration includes several scripts to automate common tasks and maintain system health. All scripts are located in the repository root and can be run directly or via the `aku` wrapper.

**For complete script documentation**, see [Scripts Reference](scripts.md) which provides detailed information about all scripts, their parameters, usage patterns, and customization options.

## Aku Wrapper

The `aku` command is a wrapper script that simplifies common NixOS operations.

### Installation

The aku wrapper is automatically installed as part of the system configuration in `system/bin/aku.nix`.

### Available Commands

#### Sync Commands

```sh
aku sync          # Synchronize system and home-manager
aku sync system   # Only synchronize system (nixos-rebuild switch)
aku sync user     # Only synchronize home-manager
```

**What it does**:
- `aku sync` runs `sync.sh` which calls both `sync-system.sh` and `sync-user.sh`
- Applies configuration changes to the system
- Equivalent to `nixos-rebuild switch` + `home-manager switch`

#### Update Commands

```sh
aku update         # Update flake inputs (flake.lock)
aku upgrade        # Update and synchronize (update + sync)
```

**What it does**:
- `aku update` runs `update.sh` to update `flake.lock`
- `aku upgrade` runs `upgrade.sh` which updates and then syncs

#### Refresh Command

```sh
aku refresh        # Refresh posthooks (stylix, daemons)
```

**What it does**:
- Runs `sync-posthook.sh`
- Refreshes Stylix themes
- Restarts dependent daemons

#### Pull Command

```sh
aku pull           # Pull from git and merge local changes
```

**What it does**:
- Runs `pull.sh`
- Fetches from remote repository
- Attempts to merge local changes
- Useful for updating systems other than your main system

#### Garbage Collection

```sh
aku gc             # Garbage collect (interactive)
aku gc full        # Delete everything not in use
aku gc 15d         # Delete everything older than 15 days
aku gc 30d         # Delete everything older than 30 days
aku gc Xd          # Delete everything older than X days
```

**What it does**:
- Removes old Nix store entries
- Frees disk space
- `full` removes all unused packages
- `Xd` removes packages older than X days

#### Security Commands

```sh
aku harden         # Make system files read-only
aku soften        # Relax file permissions (for editing)
```

**What it does**:
- `harden` makes system-level config files read-only for unprivileged users
- `soften` relaxes permissions for editing (use temporarily)

## Maintenance Script

The `maintenance.sh` script automates system maintenance tasks.

### Usage

```sh
# Interactive mode
./maintenance.sh

# Silent mode (no logging)
./maintenance.sh -s
# or
./maintenance.sh --silent
```

### What It Does

1. **System Generations Cleanup**
   - Keeps last 6 system generations (count-based: `+N` syntax)
   - Removes older generations

2. **Home Manager Generations Cleanup**
   - Keeps last 4 Home Manager generations (count-based: `+N` syntax)
   - Removes older generations

3. **User Generations Cleanup**
   - Removes user generations older than 15 days (time-based: `Nd` syntax)

4. **Garbage Collection**
   - Collects garbage from system and user stores
   - Removes store paths orphaned by generation deletion
   - Frees disk space

### Configuration

Edit these variables in `maintenance.sh`:

```sh
SystemGenerationsToKeep=6      # Keep last 6 system generations (count-based)
HomeManagerGenerationsToKeep=4  # Keep last 4 home-manager generations (count-based)
UserGenerationsKeepOnlyOlderThan="15d"  # Delete user generations older than 15 days (time-based)
```

### Logging

Maintenance actions are logged to `maintenance.log`:
- Timestamped entries
- Automatic log rotation (10MB max)
- Keeps last 3 log files

## Installation Scripts

### install.sh

Main installation script. See [Installation Guide](installation.md) for details.

**Usage**:
```sh
./install.sh ~/.dotfiles "PROFILE" [-s]
```

**Features**:
- Clones/updates repository
- Switches profile
- Sets up environment
- Generates SSH keys
- Handles Docker containers
- Rebuilds system
- Runs maintenance

### handle_docker.sh

Stops Docker containers to prevent boot issues.

**Usage**:
```sh
./handle_docker.sh
```

**Why**: Docker overlay filesystems can break NixOS boot process. This script stops containers before system updates.

## Sync Scripts

### sync.sh

Synchronizes both system and home-manager configurations.

**Usage**:
```sh
./sync.sh
```

**What it does**:
- Calls `sync-system.sh`
- Calls `sync-user.sh`

### sync-system.sh

Synchronizes system configuration only.

**Usage**:
```sh
./sync-system.sh
```

**What it does**:
- Runs `nixos-rebuild switch --flake .#system`
- Applies system-level changes

### sync-user.sh

Synchronizes home-manager configuration only.

**Usage**:
```sh
./sync-user.sh
```

**What it does**:
- Runs `home-manager switch --flake .#user`
- Applies user-level changes

### sync-posthook.sh

Runs post-synchronization hooks.

**Usage**:
```sh
./sync-posthook.sh
```

**What it does**:
- Refreshes Stylix themes
- Restarts dependent daemons
- Applies theme changes

## Update Scripts

### update.sh

Updates flake inputs.

**Usage**:
```sh
./update.sh
```

**What it does**:
- Updates `flake.lock` with latest versions
- Does not rebuild system

### upgrade.sh

Updates and synchronizes.

**Usage**:
```sh
./upgrade.sh
```

**What it does**:
- Runs `update.sh`
- Runs `sync.sh`
- Full system update

### pull.sh

Pulls from git repository.

**Usage**:
```sh
./pull.sh
```

**What it does**:
- Fetches from remote
- Attempts to merge local changes
- Useful for secondary systems

## Security Scripts

### harden.sh

Makes system-level configuration files read-only.

**Usage**:
```sh
./harden.sh
```

**What it does**:
- Sets system files to read-only for unprivileged users
- Prevents accidental modification of system configs
- Run after installation or major changes

### soften.sh

Relaxes file permissions for editing.

**Usage**:
```sh
./soften.sh
```

**What it does**:
- Makes system files writable
- Use temporarily for git operations or editing
- Run `harden.sh` again after editing

## Automated Maintenance

### Cron/SystemD Timer

You can automate maintenance tasks using systemd timers or cron.

**Example systemd timer** (create in your configuration):

```nix
systemd.timers.maintenance = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "weekly";
    Persistent = true;
  };
};

systemd.services.maintenance = {
  serviceConfig.Type = "oneshot";
  script = ''
    ${pkgs.bash}/bin/bash ${./maintenance.sh} -s
  '';
};
```

### Auto-Upgrade System

The maintainer uses a custom script to update NixOS systems remotely via SSH. See the [README](../README.md#usage) for details.

**Note**: Official NixOS auto-upgrade wasn't working with this configuration, so a workaround was implemented.

## Docker Container Management

### The Problem

Docker overlay filesystems can cause boot failures when NixOS tries to mount them during boot.

### The Solution

The `install.sh` and `upgrade.sh` scripts automatically stop Docker containers before system updates.

**Manual handling**:
```sh
# Stop all containers
docker stop $(docker ps -q)

# Or use the script
./handle_docker.sh
```

**More information**: [NixOS Discourse Discussion](https://discourse.nixos.org/t/docker-switch-overlay-overlay2-fs-lead-to-emergency-console/29217/4)

## Best Practices

### 1. Regular Maintenance

Run maintenance script regularly:
```sh
# Weekly
aku gc 7d
./maintenance.sh
```

### 2. Before Major Updates

```sh
# Update and rebuild
aku upgrade

# Clean up old generations
aku gc 30d
```

### 3. After Configuration Changes

```sh
# Test build first
nixos-rebuild build --flake .#system

# Then apply
aku sync

# Harden files
aku harden
```

### 4. Disk Space Management

Monitor disk usage:
```sh
# Check Nix store size
du -sh /nix/store

# Garbage collect
aku gc 30d

# Check generations
nix-env --list-generations -p /nix/var/nix/profiles/system
home-manager generations
```

### 5. Backup Before Major Changes

Before major configuration changes:
1. Note current generation numbers
2. Test build first
3. Keep a backup of `flake.nix`

### 6. Log Monitoring

Check maintenance logs:
```sh
tail -f maintenance.log
```

## Troubleshooting

### Script Fails with Permission Error

**Problem**: Script can't write to files.

**Solution**:
```sh
# Soften permissions
./soften.sh

# Make changes
# ...

# Harden again
./harden.sh
```

### Maintenance Script Fails

**Problem**: Maintenance script errors out.

**Solution**:
1. Check log file: `maintenance.log`
2. Run commands manually to identify issue
3. Check disk space: `df -h`

### Aku Command Not Found

**Problem**: `aku` command doesn't work.

**Solution**:
1. Rebuild system: `sudo nixos-rebuild switch --flake .#system`
2. Check if aku is installed: `which aku`
3. Source shell configuration: `source ~/.zshrc` or `source ~/.bashrc`

## Related Documentation

- [Scripts Documentation](scripts.md) - Complete reference for all shell scripts
- [Installation Guide](installation.md) - Initial setup
- [Configuration Guide](configuration.md) - Configuration management
- [README](../README.md) - Project overview

