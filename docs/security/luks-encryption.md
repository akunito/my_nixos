# LUKS Encryption & Remote Unlocking

Complete guide to setting up LUKS disk encryption with SSH remote unlock capability.

## Table of Contents

- [Overview](#overview)
- [Remote Disk Unlocking](#remote-disk-unlocking)
- [Setting Up LUKS Devices](#setting-up-luks-devices)
- [Automatic Mounting](#automatic-mounting)
- [Additional LUKS Devices](#additional-luks-devices)
- [Troubleshooting](#troubleshooting)

## Overview

This configuration supports full disk encryption using LUKS with the ability to unlock drives remotely via SSH during boot. This is particularly useful for servers that need to be restarted remotely.

### Features

- **Full Disk Encryption**: Root filesystem encrypted with LUKS
- **Remote Unlock**: SSH server on boot for remote unlocking
- **Multiple Devices**: Support for additional encrypted drives
- **Automatic Unlock**: Secondary drives unlocked automatically after root

## Remote Disk Unlocking

### How It Works

1. System boots into initrd (initial RAM disk)
2. SSH server starts before LUKS unlock
3. You connect via SSH and provide LUKS passphrase
4. LUKS device is unlocked
5. System continues booting normally

### Prerequisites

- SSH client on your remote machine
- SSH public key added to `authorizedKeys`
- Network connectivity to the server

### Configuration

Enable SSH on boot in your flake:

```nix
systemSettings = {
  bootSSH = true;
  authorizedKeys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC..."
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
  ];
  hostKeys = [ "/etc/secrets/initrd/ssh_host_rsa_key" ];
};
```

### Connecting for Unlock

1. **Boot the system** (or restart)

2. **Connect via SSH**:
   ```sh
   ssh root@SERVER_IP
   ```
   
   Note: You'll connect as `root` during initrd phase.

3. **Unlock the drive**:
   ```sh
   # You'll be prompted for the LUKS passphrase
   # Enter it to unlock the drive
   ```

4. **System continues booting** automatically after unlock

### Security Considerations

- SSH keys are the only authentication method during boot
- Use strong SSH keys (ed25519 recommended)
- Keep private keys secure
- Consider using a dedicated unlock key separate from regular SSH keys

**Reference**: [NixOS Wiki - Remote Disk Unlocking](https://nixos.wiki/wiki/Remote_disk_unlocking)

## Setting Up LUKS Devices

### Primary Root Drive

The root filesystem should already be encrypted if you installed NixOS with encryption. The configuration is typically in `hardware-configuration.nix`:

```nix
boot.initrd.luks.devices."root".device = "/dev/disk/by-uuid/...";
```

### Additional LUKS Devices

To add additional encrypted drives:

1. **Get the UUID**:
   ```sh
   sudo blkid
   # Find your encrypted partition UUID
   ```

2. **Add to configuration**:
   ```nix
   boot.initrd.luks.devices."DATA_4TB" = {
     device = "/dev/disk/by-uuid/YOUR-UUID-HERE";
     preLVM = true;  # Unlock before LVM if using LVM
   };
   ```

3. **Rebuild system**:
   ```sh
   phoenix sync system
   ```

4. **Reboot and unlock**:
   - The device will appear as `/dev/mapper/DATA_4TB`
   - Unlock it during boot (or automatically if configured)

## Automatic Mounting

### Mounting Encrypted Drives

After unlocking, drives can be mounted automatically:

```nix
fileSystems."/mnt/DATA_4TB" = {
  device = "/dev/mapper/DATA_4TB";
  fsType = "ext4";
  options = [ "defaults" ];
};
```

### Boot Options for Unreliable Drives

For drives that may not always be connected:

```nix
fileSystems."/mnt/DATA_4TB" = {
  device = "/dev/mapper/DATA_4TB";
  fsType = "ext4";
  options = [ 
    "nofail"                    # Don't fail boot if unavailable
    "x-systemd.device-timeout=3s"  # Timeout for device availability
  ];
};
```

**Options Explained**:
- **nofail**: System boots even if drive is unavailable
- **x-systemd.device-timeout**: How long to wait for device (3 seconds)

### Using Flake Variables

Configure drives via flake variables:

```nix
systemSettings = {
  mount2ndDrives = true;
  
  # Disk 1
  disk1_enabled = true;
  disk1_name = "/mnt/DATA_4TB";
  disk1_device = "/dev/mapper/DATA_4TB";
  disk1_fsType = "ext4";
  disk1_options = [ "nofail" "x-systemd.device-timeout=3s" ];
  
  # Additional disks...
};
```

The `drives.nix` module will automatically configure these.

## Additional LUKS Devices

### Adding Secondary Encrypted Drives

Complete setup process:

1. **Format the drive** (if not already formatted):
   ```sh
   # WARNING: This will destroy all data!
   sudo cryptsetup luksFormat /dev/sdX1
   ```

2. **Open the device**:
   ```sh
   sudo cryptsetup luksOpen /dev/sdX1 DATA_4TB
   ```

3. **Create filesystem**:
   ```sh
   sudo mkfs.ext4 /dev/mapper/DATA_4TB
   ```

4. **Get UUID**:
   ```sh
   sudo blkid /dev/sdX1
   # Copy the UUID
   ```

5. **Add to configuration**:
   ```nix
   boot.initrd.luks.devices."DATA_4TB" = {
     device = "/dev/disk/by-uuid/YOUR-UUID";
   };
   
   fileSystems."/mnt/DATA_4TB" = {
     device = "/dev/mapper/DATA_4TB";
     fsType = "ext4";
   };
   ```

6. **Create mount point**:
   ```sh
   sudo mkdir -p /mnt/DATA_4TB
   ```

7. **Rebuild and test**:
   ```sh
   phoenix sync system
   sudo reboot
   ```

### Automatic Unlock of Secondary Drives

Secondary drives can be unlocked automatically using a keyfile:

1. **Create keyfile**:
   ```sh
   sudo dd if=/dev/urandom of=/etc/secrets/luks-keys/DATA_4TB.key bs=512 count=8
   sudo chmod 600 /etc/secrets/luks-keys/DATA_4TB.key
   ```

2. **Add keyfile to LUKS**:
   ```sh
   sudo cryptsetup luksAddKey /dev/disk/by-uuid/YOUR-UUID /etc/secrets/luks-keys/DATA_4TB.key
   ```

3. **Configure automatic unlock**:
   ```nix
   boot.initrd.luks.devices."DATA_4TB" = {
     device = "/dev/disk/by-uuid/YOUR-UUID";
     keyFile = "/etc/secrets/luks-keys/DATA_4TB.key";
   };
   ```

**Security Note**: The keyfile must be stored on an encrypted partition (like root) for this to be secure.

## Troubleshooting

### Cannot Connect via SSH During Boot

**Problem**: Can't connect to SSH server during boot.

**Solutions**:
1. Check network connectivity
2. Verify SSH keys are correct
3. Check firewall rules
4. Verify `bootSSH = true` in configuration
5. Check system logs: `journalctl -b`

### Wrong Passphrase

**Problem**: Passphrase doesn't work.

**Solutions**:
1. Verify you're using the correct passphrase
2. Check keyboard layout (may be different during boot)
3. Try connecting via console if available
4. Verify LUKS device UUID is correct

### Drive Not Unlocking

**Problem**: Drive doesn't unlock automatically.

**Solutions**:
1. Check keyfile path and permissions
2. Verify keyfile is added to LUKS device
3. Check system logs for errors
4. Test manual unlock: `sudo cryptsetup luksOpen /dev/sdX1 NAME`

### Drive Not Mounting

**Problem**: Drive unlocks but doesn't mount.

**Solutions**:
1. Check filesystem: `sudo fsck /dev/mapper/DATA_4TB`
2. Verify mount point exists: `ls -la /mnt/DATA_4TB`
3. Check fileSystems configuration
4. Review system logs: `journalctl -u mnt-DATA_4TB.mount`

### Boot Hangs Waiting for Drive

**Problem**: Boot hangs waiting for unavailable drive.

**Solutions**:
1. Add `nofail` option to fileSystems
2. Add `x-systemd.device-timeout=3s` option
3. Check if drive is physically connected
4. Verify drive UUID is correct

## Best Practices

### 1. SSH Keys

- Use strong keys (ed25519 recommended)
- Use dedicated unlock keys
- Store keys securely
- Rotate keys periodically

### 2. Passphrases

- Use strong, unique passphrases
- Store recovery keys securely
- Consider using a password manager
- Test unlock procedure regularly

### 3. Drive Management

- Use UUIDs, not device names
- Document drive purposes
- Keep drive configurations in version control
- Test drive mounting after changes

### 4. Security

- Keep system updated
- Monitor SSH access logs
- Use firewall to restrict SSH access
- Consider VPN instead of exposing SSH

## Related Documentation

- [Drive Management](../hardware/drive-management.md) - General drive setup
- [Security Guide](../security.md) - Overall security configuration
- [NixOS Wiki - Remote Disk Unlocking](https://nixos.wiki/wiki/Remote_disk_unlocking)

