# Restic Backups

Complete guide to setting up and configuring automated backups using Restic.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Restic Binary Wrapper](#restic-binary-wrapper)
- [Sudo Configuration](#sudo-configuration)
- [Repository Password](#repository-password)
- [SystemD Service](#systemd-service)
- [Backup Scripts](#backup-scripts)
- [Remote Backup](#remote-backup)
- [Troubleshooting](#troubleshooting)

## Overview

Restic is a modern backup program that does fast, secure, incremental backups. This configuration uses Restic with SystemD timers for automated periodic backups.

### Features

- **Incremental Backups**: Only backs up changed files
- **Encryption**: All backups are encrypted
- **Deduplication**: Efficient storage usage
- **Automated**: SystemD timers for scheduled backups
- **Secure**: Wrapper with minimal required permissions

### Related Links

- [Restic Documentation](https://restic.readthedocs.io/en/latest/010_introduction.html)
- [NixOS Wiki - Restic](https://wiki.nixos.org/wiki/Restic)
- [NixOS Wiki - Sudo](https://nixos.wiki/wiki/Sudo)
- [NixOS Wiki - SystemD Timers](https://nixos.wiki/wiki/Systemd/Timers)

## Installation

### Step 1: Add Restic Package

Add Restic to system packages in your flake:

```nix
systemSettings = {
  systemPackages = [
    pkgs.nfs-utils
    pkgs.restic  # Add Restic here
  ];
};
```

### Step 2: Apply Configuration

Run the install script to apply changes:

```sh
cd ~/.dotfiles
./install.sh ~/.dotfiles "PROFILE"
```

## Restic Binary Wrapper

The Restic binary wrapper provides secure access with minimal required permissions.

### Purpose

The wrapper ensures:
- Binary is accessible only to the specified user
- Has just enough system-level permissions (via capabilities) to perform backups
- Others cannot misuse or tamper with it

### Capability: cap_dac_read_search

`cap_dac_read_search` allows the binary to bypass **file read and directory search permission checks**, even if the user lacks read or search permissions for specific files or directories.

This capability is useful for Restic to back up files and directories that are not directly accessible to the user due to strict permissions.

### Configuration

The wrapper is configured in `system/security/restic.nix`:

```nix
{ lib, userSettings, systemSettings, pkgs, authorizedKeys ? [], ... }:

{
  # Create restic user (optional)
  users.users.restic = {
    isNormalUser = true;
  };
  
  # Wrapper for restic
  security.wrappers.restic = {
    source = "/run/current-system/sw/bin/restic";
    owner = userSettings.username;  # Sets the owner of the restic binary (rwx)
    group = "wheel";  # Sets the group of the restic binary (none)
    permissions = "u=rwx,g=,o=";  # Permissions of the restic binary
    capabilities = "cap_dac_read_search=+ep";  # Sets the capabilities
  };
}
```

### Finding Binary Paths

You can check the paths:
```sh
which restic
# Or
ll /run/current-system/sw/bin/
```

The wrapper will be available at `/run/wrappers/bin/restic`.

## Sudo Configuration

Configure sudo to allow Restic to run without password prompts.

### Step 1: Add to Flake Configuration

Add Restic to sudo commands in `flake.PROFILE.nix`:

```nix
systemSettings = {
  sudoNOPASSWD = true;  # NOT Recommended, check sudo.md for more info
  sudoCommands = [
    {
      command = "/run/current-system/sw/bin/restic";  # Same for no wrapper binary
      options = [ "NOPASSWD" "SETENV" ];
    }
  ];
};
```

**Note**: We don't need to grant sudo for the Restic wrapper (`/run/wrappers/bin/restic`), only for the regular binary if needed.

### Step 2: Configure Sudo Module

The `sudo.nix` module grabs these variables and configures sudo:

```nix
security.sudo = {
  enable = systemSettings.sudoEnable;
  extraRules = lib.mkIf (systemSettings.sudoNOPASSWD == true) [{
    users = [ "${userSettings.username}" ];
    commands = systemSettings.sudoCommands;
  }];
  extraConfig = with pkgs; ''
    Defaults:picloud secure_path="${lib.makeBinPath [
      systemd
    ]}:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
  '';
};
```

Make sure `sudo.nix` is sourced in your profile's `configuration.nix`.

## Repository Password

### Storage Location

**TODO**: This should be improved with a secret manager.

For now, create a root-owned file with the repository password:

```sh
KEYPATH=~/Sync/.maintenance/passwords/
FILENAME=restic.key
FULLPATH="$KEYPATH""$FILENAME"

mkdir -p $KEYPATH
sudo nano $FULLPATH  # Add your password to the file

# Make sure the permissions are set
sudo chown root:root $FULLPATH
sudo chmod 600 $FULLPATH
ll $FULLPATH
```

### Security Considerations

- Store password file on encrypted partition
- Use restrictive permissions (600)
- Consider using a password manager
- Future: Integrate with secret management system

## SystemD Service

Create a SystemD service and timer for automated backups.

### Step 1: Add Variables to Flake

Add backup configuration to `flake.PROFILE.nix`:

```nix
systemSettings = {
  # Backups
  homeBackupEnable = true;  # Enable home backup service
  homeBackupDescription = "Backup Home Directory with Restic";
  homeBackupExecStart = "/run/current-system/sw/bin/sh /home/username/myScripts/backup.sh";
  homeBackupUser = "username";
  homeBackupTimerDescription = "Timer for home_backup service";
  homeBackupOnCalendar = "*-*-* 0/6:00:00";  # Every 6 hours
  
  # Remote backup (optional)
  remoteBackupEnable = false;
  remoteBackupDescription = "Copy Restic Backup to Remote Server";
  remoteBackupExecStart = "/run/current-system/sw/bin/sh /home/username/myScripts/remote_backup.sh";
};
```

**Note**: It's better to run these tasks as `root` ✅, but this example shows user-level execution for permission demonstration.

### Step 2: Configure Service in restic.nix

The `restic.nix` module creates the service from these variables:

```nix
systemd.services.home_backup = lib.mkIf (systemSettings.homeBackupEnable == true) {
  description = systemSettings.homeBackupDescription;
  serviceConfig = {
    Type = "simple";
    ExecStart = systemSettings.homeBackupExecStart;
    User = systemSettings.homeBackupUser;
    Environment = "PATH=/run/current-system/sw/bin:/usr/bin:/bin";
  };
};

systemd.timers.home_backup = lib.mkIf (systemSettings.homeBackupEnable == true) {
  description = systemSettings.homeBackupTimerDescription;
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = systemSettings.homeBackupOnCalendar;  # Every 6 hours
    Persistent = true;
  };
};
```

### Calendar Format

SystemD timer calendar format examples:
- `*-*-* 0/6:00:00` - Every 6 hours
- `daily` - Once per day at midnight
- `weekly` - Once per week
- `*-*-* 02:00:00` - Daily at 2 AM
- `Mon *-*-* 03:00:00` - Every Monday at 3 AM

## Backup Scripts

### Local Backup Script

Example backup script using the wrapper:

```sh
#!/bin/sh
echo "======================== Local Backup =========================="
export RESTIC_REPOSITORY="/home/username/Sync/.maintenance/Backups/"
export RESTIC_PASSWORD_FILE="/home/username/Sync/.maintenance/passwords/restic.key"

# Use the wrapper path
/run/wrappers/bin/restic backup ~/ \
  --exclude Warehouse \
  --exclude Machines/ISOs \
  --exclude pCloudDrive/ \
  --exclude */bottles/ \
  --exclude Desktop/ \
  --exclude Downloads/ \
  --exclude Videos/ \
  --exclude Sync/ \
  --exclude .com.apple.backupd* \
  --exclude *.sock \
  --exclude */dev/* \
  --exclude .DS_Store \
  --exclude */.DS_Store \
  --exclude .tldrc \
  --exclude .cache/ \
  --exclude .Cache/ \
  --exclude cache/ \
  --exclude Cache/ \
  --exclude */.cache/ \
  --exclude */.Cache/ \
  --exclude */cache/ \
  --exclude */Cache/ \
  --exclude .trash/ \
  --exclude .Trash/ \
  --exclude trash/ \
  --exclude Trash/ \
  --exclude */.trash/ \
  --exclude */.Trash/ \
  --exclude */trash/ \
  --exclude */Trash/ \
  -r $RESTIC_REPOSITORY \
  -p $RESTIC_PASSWORD_FILE

echo "Maintenance"
# Forget old snapshots and prune
/run/wrappers/bin/restic forget \
  --keep-daily 7 \
  --keep-weekly 2 \
  --keep-monthly 1 \
  --prune \
  -r $RESTIC_REPOSITORY \
  -p $RESTIC_PASSWORD_FILE
```

### Script Features

- **Excludes**: Skips unnecessary files (caches, temporary files, etc.)
- **Maintenance**: Automatically forgets old snapshots and prunes
- **Retention Policy**:
  - Keep 7 daily snapshots
  - Keep 2 weekly snapshots
  - Keep 1 monthly snapshot

## Remote Backup

Copy the repository to a remote NFS drive or cloud storage.

### NFS Considerations

When copying to NFS:
- Files owned by root will be owned by the user in NFS
- This is because NFS uses `squash_root` for security
- Use rsync options to avoid copying owner/group

### Step 1: Add Rsync to Sudo

Add rsync to sudo commands:

```nix
systemSettings = {
  sudoCommands = [
    {
      command = "/run/current-system/sw/bin/rsync";
      options = [ "NOPASSWD" "SETENV" ];
    }
  ];
};
```

### Step 2: Remote Backup Script

Example script for copying to NFS:

```sh
#!/bin/sh

# ========================================= CONFIG =========================================
DRIVE_NAME="NFS_Backups"
SERVICE_NAME="mnt-NFS_Backups.mount"
SOURCE="/home/username/.maintenance/Backups/"
DESTINATION="/mnt/NFS_Backups/home.restic/"

# ========================================= FUNCTIONS =========================================
# Check if NFS_Backups is mounted
get_status() {
    status=$(systemctl status $SERVICE_NAME | grep "Active:")
    echo "$status"
}

# Function to try to mount NFS_Backups using systemctl
mount_nfs_backups() {
    echo "Trying to mount $DRIVE_NAME..."
    sudo systemctl start $SERVICE_NAME
    status=$(get_status)
    if echo "$status" | grep -q "active (mounted)"; then
        echo "$DRIVE_NAME mounted successfully."
        return 0
    else
        echo "$DRIVE_NAME could not be mounted."
        return 1
    fi
}

replicate_repo() {
    echo "Replicating repository..."
    echo "Source: $SOURCE"
    echo "Destination: $DESTINATION"

    mkdir -p $DESTINATION

    # -rltpD: recursive, links, times, permissions, devices
    # Remove -o and -g to avoid owner/group issues on NFS
    # -v: verbose, -P: progress
    # --delete: delete files in destination not in source
    sudo rsync -rltpD -vP --delete --delete-excluded $SOURCE $DESTINATION
}

# ========================================= MAIN =========================================
echo "======================== Remote Backup =========================="

main() {
    status=$(get_status)

    if echo "$status" | grep -q "active (mounted)"; then
        echo "$DRIVE_NAME is mounted. Starting remote backup..."
        replicate_repo
    else
        echo "$DRIVE_NAME is not mounted."
        if mount_nfs_backups; then
            # Drive mounted, recall main
            main
        else
            # It failed to mount, we exit
            echo "Skipping remote backup..."
        fi
    fi
}

main
```

### Rsync Options Explained

- **-rltpD**: Equivalent to `-a` (archive) but without `-o` and `-g`
  - `-r`: recursive
  - `-l`: preserve symlinks
  - `-t`: preserve times
  - `-p`: preserve permissions
  - `-D`: preserve devices
- **-v**: verbose output
- **-P**: show progress
- **--delete**: delete files in destination not in source
- **--delete-excluded**: delete excluded files in destination

## Troubleshooting

### Backup Fails with Permission Error

**Problem**: Restic can't read certain files.

**Solutions**:
1. Use the wrapper: `/run/wrappers/bin/restic`
2. Verify wrapper has correct capabilities
3. Check file permissions
4. Run as root if necessary

### Service Not Running

**Problem**: Backup service doesn't start.

**Solutions**:
1. Check service status: `systemctl status home_backup`
2. Check timer status: `systemctl status home_backup.timer`
3. Enable timer: `sudo systemctl enable --now home_backup.timer`
4. Check logs: `journalctl -u home_backup`

### Password File Not Found

**Problem**: Restic can't find password file.

**Solutions**:
1. Verify path in script
2. Check file permissions
3. Verify file exists: `ls -la /path/to/restic.key`
4. Check script environment variables

### Remote Backup Fails

**Problem**: Remote backup script fails.

**Solutions**:
1. Check NFS mount status
2. Verify rsync sudo configuration
3. Check network connectivity
4. Review script logs

## Best Practices

### 1. Backup Frequency

- **Home directory**: Every 6 hours or daily
- **System files**: Weekly or monthly
- **Critical data**: More frequently

### 2. Retention Policy

- Keep multiple generations
- Balance storage vs. recovery options
- Test restore procedures regularly

### 3. Security

- Encrypt backups
- Store password securely
- Use wrapper for minimal permissions
- Test backup integrity

### 4. Monitoring

- Monitor backup success
- Check backup sizes
- Review logs regularly
- Test restore procedures

## Related Documentation

- [Security Guide](../security.md) - Overall security configuration
- [Sudo Configuration](sudo.md) - Sudo setup
- [Hardware Guide](../hardware.md) - NFS configuration

