# Security Guide

Complete guide to security configurations and features in this NixOS setup.

## Table of Contents

- [Overview](#overview)
- [SSH Configuration](#ssh-configuration)
- [LUKS Encryption](#luks-encryption)
- [Firewall](#firewall)
- [Sudo Configuration](#sudo-configuration)
- [Polkit Rules](#polkit-rules)
- [Backup System](#backup-system)
- [File Permissions](#file-permissions)
- [Best Practices](#best-practices)

## Overview

This configuration includes comprehensive security features including disk encryption, SSH management, firewall configuration, and automated backups.

## SSH Configuration

### SSH Server on Boot

SSH can be enabled during boot to allow remote LUKS disk unlocking.

**Configuration**:
```nix
systemSettings = {
  bootSSH = true;
  authorizedKeys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC..."
  ];
  hostKeys = [ "/etc/secrets/initrd/ssh_host_rsa_key" ];
};
```

**Features**:
- SSH server starts before LUKS unlock
- Allows remote disk unlocking
- Key-based authentication only
- Host keys stored securely

**Documentation**: See [LUKS Encryption](security/luks-encryption.md)

### SSH Key Management

SSH keys are centralized in the flake configuration:

```nix
systemSettings = {
  authorizedKeys = [
    "ssh-rsa ... key1"
    "ssh-ed25519 ... key2"
  ];
};
```

These keys are automatically propagated to:
- Root user (for boot SSH)
- Regular user account
- System services that need SSH access

## LUKS Encryption

Full disk encryption with remote unlock capability.

### Features

- **Full Disk Encryption**: Root filesystem encrypted with LUKS
- **Remote Unlock**: SSH server on boot for remote unlocking
- **Multiple Devices**: Support for additional encrypted drives
- **Automatic Unlock**: Secondary drives unlocked automatically after root

### Configuration

See [LUKS Encryption Documentation](security/luks-encryption.md) for complete setup guide.

### Quick Setup

1. **Add LUKS device to configuration**:
   ```nix
   boot.initrd.luks.devices."DATA_4TB".device = "/dev/disk/by-uuid/...";
   ```

2. **Enable SSH on boot** (for remote unlock):
   ```nix
   systemSettings = {
     bootSSH = true;
     authorizedKeys = [ "your-ssh-key" ];
   };
   ```

3. **Mount encrypted drive**:
   ```nix
   fileSystems."/mnt/DATA_4TB" = {
     device = "/dev/mapper/DATA_4TB";
     fsType = "ext4";
   };
   ```

## Firewall

Network firewall using nftables.

### Configuration

```nix
systemSettings = {
  firewall = true;
  allowedTCPPorts = [ 22 80 443 ];
  allowedUDPPorts = [ 51820 ];  # WireGuard example
};
```

### Features

- **Default Deny**: All ports closed by default
- **Selective Opening**: Only specified ports are open
- **TCP/UDP Support**: Separate configuration for TCP and UDP
- **Automatic Management**: Rules applied automatically on rebuild

### Common Ports

- `22` - SSH
- `80` - HTTP
- `443` - HTTPS
- `51820` - WireGuard VPN
- `47984-48010` - Sunshine (game streaming)

## Sudo Configuration

Flexible sudo/doas configuration with fine-grained control.

### Basic Configuration

```nix
systemSettings = {
  sudoEnable = true;
  sudoNOPASSWD = false;  # NOT recommended for security
  sudoCommands = [
    {
      command = "/run/current-system/sw/bin/systemctl suspend";
      options = [ "NOPASSWD" ];
    }
  ];
};
```

### Sudo Options

- **NOPASSWD**: Execute without password prompt
- **SETENV**: Allow environment variable modification

### Security Recommendations

⚠️ **Warning**: Enabling `sudoNOPASSWD` for all commands is NOT recommended. Instead:

1. Use specific command rules in `sudoCommands`
2. Use Polkit for GUI applications
3. Use SSH key forwarding for remote operations

**Documentation**: See [Sudo Configuration](security/sudo.md)

## Polkit Rules

Fine-grained permission management for system operations.

### Configuration

```nix
systemSettings = {
  polkitEnable = true;
  polkitRules = ''
    polkit.addRule(function(action, subject) {
      if (
        subject.isInGroup("users") && (
          // Allow reboot and power-off
          action.id == "org.freedesktop.login1.reboot" ||
          action.id == "org.freedesktop.login1.power-off" ||
          
          // Allow managing specific systemd units
          (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "mnt-NFS_Backups.mount") ||
          
          // Allow running specific commands
          (action.id == "org.freedesktop.policykit.exec" &&
            (action.lookup("command") == "/run/current-system/sw/bin/rsync" ||
             action.lookup("command") == "/run/current-system/sw/bin/restic"))
        )
      ) {
        return polkit.Result.YES;
      }
    });
  '';
};
```

### Common Actions

- `org.freedesktop.login1.reboot` - System reboot
- `org.freedesktop.login1.power-off` - System shutdown
- `org.freedesktop.login1.suspend` - System suspend
- `org.freedesktop.systemd1.manage-units` - Manage systemd units
- `org.freedesktop.policykit.exec` - Execute commands

**Documentation**: See [Polkit Configuration](security/polkit.md)

## Backup System

Automated backup system using Restic.

### Features

- **Incremental Backups**: Only changed files are backed up
- **Automated Scheduling**: SystemD timers for regular backups
- **Remote Support**: Copy backups to remote servers
- **Secure**: Encrypted backups with password protection
- **Efficient**: Deduplication and compression

### Configuration

```nix
systemSettings = {
  # Restic wrapper with capabilities
  resticWrapper = true;
  rsyncWrapper = true;
  
  # Home backup
  homeBackupEnable = true;
  homeBackupExecStart = "/run/current-system/sw/bin/sh /path/to/backup.sh";
  homeBackupUser = "username";
  homeBackupOnCalendar = "0/6:00:00";  # Every 6 hours
  
  # Remote backup
  remoteBackupEnable = true;
  remoteBackupExecStart = "/path/to/remote-backup.sh";
};
```

### Restic Wrapper

The Restic binary is wrapped with capabilities to allow backing up files without full root access:

- `cap_dac_read_search` - Read files regardless of permissions
- Owned by user, group wheel
- Restricted permissions

### Sudo Configuration for Backups

```nix
systemSettings = {
  sudoCommands = [
    {
      command = "/run/current-system/sw/bin/restic";
      options = [ "NOPASSWD" "SETENV" ];
    }
    {
      command = "/run/current-system/sw/bin/rsync";
      options = [ "NOPASSWD" "SETENV" ];
    }
  ];
};
```

**Documentation**: See [Restic Backups](security/restic-backups.md)

## File Permissions

### System File Hardening

System-level configuration files can be made read-only:

```sh
# Make system files read-only
./harden.sh

# Relax permissions for editing
./soften.sh
```

**What it does**:
- Makes system config files read-only for unprivileged users
- Prevents accidental modification
- Use `soften.sh` temporarily for editing

### Secure File Storage

Sensitive files should be stored with restricted permissions:

```sh
# Create secure directory
mkdir -p ~/Sync/.maintenance/passwords
chmod 700 ~/Sync/.maintenance/passwords

# Store password file
sudo nano ~/Sync/.maintenance/passwords/restic.key
sudo chown root:root ~/Sync/.maintenance/passwords/restic.key
sudo chmod 600 ~/Sync/.maintenance/passwords/restic.key
```

## Best Practices

### 1. SSH Keys

- Use strong key types (ed25519 recommended)
- Never share private keys
- Use different keys for different purposes
- Rotate keys periodically

### 2. Encryption

- Always encrypt sensitive data
- Use strong passphrases
- Store recovery keys securely
- Test unlock procedure regularly

### 3. Firewall

- Default deny, explicit allow
- Only open necessary ports
- Review firewall rules regularly
- Use VPN for remote access instead of exposing ports

### 4. Sudo/Polkit

- Prefer Polkit for GUI applications
- Use specific command rules, not blanket NOPASSWD
- Review sudo rules regularly
- Use SSH key forwarding for remote operations

### 5. Backups

- Test restore procedures regularly
- Store backups off-site
- Encrypt backups
- Monitor backup success
- Keep multiple backup generations

### 6. Updates

- Keep system updated
- Review security advisories
- Test updates on non-critical systems first
- Keep backups before major updates

## Related Documentation

- [LUKS Encryption](security/luks-encryption.md) - Detailed encryption setup
- [Restic Backups](security/restic-backups.md) - Backup system configuration
- [Sudo Configuration](security/sudo.md) - Sudo setup details
- [Polkit Configuration](security/polkit.md) - Polkit rules guide

