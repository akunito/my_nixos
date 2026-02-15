# Drive Management

Complete guide to managing drives, LUKS encryption, and automatic mounting.

## Table of Contents

- [Overview](#overview)
- [LUKS Device Setup](#luks-device-setup)
- [Automatic Mounting](#automatic-mounting)
- [Boot Options](#boot-options)
- [NFS Mounts](#nfs-mounts)
- [Troubleshooting](#troubleshooting)

## Overview

This configuration supports multiple drive types including:
- LUKS encrypted drives
- Standard filesystems (ext4, btrfs, xfs, ntfs3, vfat)
- Network file systems (NFS)
- External drives with boot-time handling

## LUKS Device Setup

### How to Unlock LUKS Drives on Boot by SSH

See [LUKS Encryption Documentation](../../security/luks-encryption.md) for remote unlocking setup.

**Reference**: [NixOS Wiki - Remote Disk Unlocking](https://nixos.wiki/wiki/Remote_disk_unlocking)

### How to Mount LUKS Devices Automatically

#### Prerequisites

The drive needs to be:
1. Already formatted
2. LUKS partition created and assigned
3. Visible at `/dev/mapper/partition_name`

#### Step 1: Add UUID to Configuration

Add the UUID to `boot.initrd.luks.devices` in your configuration (or `drives.nix` module).

**Get the UUID**:
```sh
# General info
sudo fdisk -l

# Get the UUID
sudo blkid
```

**Add to configuration**:
```nix
boot.initrd.luks.devices."DATA_4TB".device = "/dev/disk/by-uuid/YOUR-UUID";
```

This is now done in `your profile config (`profiles/PROFILE-config.nix`)` by variables together with `drives.nix`.

#### Step 2: Run Install Script and Reboot

```sh
./install.sh ~/.dotfiles "PROFILE"
sudo reboot
```

The device should now be unlocked on `/dev/mapper` during boot.

#### Step 3: Create Mount Points

Create directories for mounting:

```sh
mkdir -p /mnt/DATA_4TB
mkdir -p /mnt/Machines
mkdir -p /mnt/TimeShift
```

#### Step 4: Mount Devices

Mount the devices:

```sh
sudo mount /dev/mapper/DATA_4TB /mnt/DATA_4TB
sudo mount /dev/mapper/Machines /mnt/Machines
sudo mount /dev/mapper/TimeShift /mnt/TimeShift
```

#### Step 5: Automatic Mounting

When you run `install.sh` again, the device is added automatically to `hardware-configuration.nix`.

**Note**: If you try to add it manually in `configuration.nix` or `drives.nix`, there may be conflicts. Let the install script handle it.

## Automatic Mounting

### Using Flake Variables

Configure drives via flake variables in `your profile config (`profiles/PROFILE-config.nix`)`:

```nix
systemSettings = {
  mount2ndDrives = true;
  
  # Disk 1
  disk1_enabled = true;
  disk1_name = "/mnt/DATA_4TB";
  disk1_device = "/dev/mapper/DATA_4TB";
  disk1_fsType = "ext4";
  disk1_options = [ "nofail" "x-systemd.device-timeout=3s" ];
  
  # Disk 2
  disk2_enabled = true;
  disk2_name = "/mnt/DATA_SATA3";
  disk2_device = "/dev/disk/by-uuid/B8AC28E3AC289E3E";
  disk2_fsType = "ntfs3";
  disk2_options = [ "nofail" "x-systemd.device-timeout=3s" ];
  
  # Additional disks (disk3_*, disk4_*, etc.)
};
```

The `drives.nix` module automatically configures these.

### Direct Configuration

Alternatively, configure directly in `configuration.nix`:

```nix
fileSystems."/mnt/DATA_4TB" = {
  device = "/dev/mapper/DATA_4TB";
  fsType = "ext4";
  options = [ "defaults" ];
};
```

## Boot Options

### For Unreliable Drives

If a drive may not always be connected, use these options:

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

### Options Explained

- **nofail**: System boots even if drive is unavailable
  - Prevents boot hanging waiting for drive
  - Useful for external drives or network mounts
  
- **x-systemd.device-timeout**: How long to wait for device
  - `3s` = 3 seconds
  - `5s` = 5 seconds
  - Adjust based on drive speed and reliability

### Example: Multiple Drive Types

```nix
# LUKS encrypted drive
fileSystems."/mnt/2nd_NVME" = {
  device = "/dev/mapper/2nd_NVME";
  fsType = "ext4";
  options = [ "nofail" "x-systemd.device-timeout=3s" ];
};

boot.initrd.luks.devices."2nd_NVME".device = "/dev/disk/by-uuid/...";

# NTFS drive
fileSystems."/mnt/DATA" = {
  device = "/dev/disk/by-uuid/B8AC28E3AC289E3E";
  fsType = "ntfs3";
  options = [ "nofail" "x-systemd.device-timeout=3s" ];
};

# NFS mount
fileSystems."/mnt/NFS_media" = {
  device = "192.168.20.200:/mnt/hddpool/media";
  fsType = "nfs4";
  options = [ "nofail" "x-systemd.device-timeout=5s" ];
};
```

## NFS Mounts

### Client Configuration

Configure NFS client mounts:

```nix
systemSettings = {
  nfsClientEnable = true;
  nfsMounts = [
    {
      what = "192.168.20.200:/mnt/hddpool/media";
      where = "/mnt/NFS_media";
      type = "nfs";
      options = "noatime";
    }
    {
      what = "192.168.20.200:/mnt/ssdpool/emulators";
      where = "/mnt/NFS_emulators";
      type = "nfs";
      options = "noatime";
    }
    {
      what = "192.168.20.200:/mnt/ssdpool/library";
      where = "/mnt/NFS_library";
      type = "nfs";
      options = "noatime";
    }
  ];
  
  nfsAutoMounts = [
    {
      where = "/mnt/NFS_media";
      automountConfig = {
        TimeoutIdleSec = "600";  # Unmount after 10 minutes idle
      };
    }
    {
      where = "/mnt/NFS_emulators";
      automountConfig = {
        TimeoutIdleSec = "600";
      };
    }
    {
      where = "/mnt/NFS_library";
      automountConfig = {
        TimeoutIdleSec = "600";
      };
    }
  ];
};
```

### Auto-Mount Features

- **Automatic mounting**: Mounts when accessed
- **Idle timeout**: Unmounts after specified idle time
- **Network resilience**: Handles network disconnections gracefully

### NFS Server Configuration

To share directories via NFS:

```nix
systemSettings = {
  nfsServerEnable = true;
  nfsExports = ''
    /mnt/example   192.168.8.90(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000)
    /mnt/example2  192.168.8.90(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000)
  '';
};
```

## Troubleshooting

### Drive Not Mounting

**Problem**: Drive doesn't mount on boot.

**Solutions**:
1. Check UUID: `sudo blkid`
2. Verify LUKS device is unlocked: `lsblk`
3. Check filesystem: `sudo fsck /dev/mapper/DATA_4TB`
4. Review system logs: `journalctl -u mnt-DATA_4TB.mount`
5. Check mount point exists: `ls -la /mnt/DATA_4TB`

### Boot Hangs Waiting for Drive

**Problem**: Boot hangs waiting for unavailable drive.

**Solutions**:
1. Add `nofail` option to fileSystems
2. Add `x-systemd.device-timeout=3s` option
3. Check if drive is physically connected
4. Verify drive UUID is correct
5. Check network connectivity (for NFS)

### LUKS Device Not Unlocking

**Problem**: LUKS device doesn't unlock during boot.

**Solutions**:
1. Verify UUID in configuration
2. Check LUKS passphrase
3. Test manual unlock: `sudo cryptsetup luksOpen /dev/sdX1 NAME`
4. Review initrd logs: `journalctl -b`
5. Check SSH unlock setup (if using remote unlock)

### Permission Errors

**Problem**: Can't access mounted drive.

**Solutions**:
1. Check filesystem permissions: `ls -la /mnt/DATA_4TB`
2. Verify user is in correct group
3. Check mount options
4. Fix permissions: `sudo chown -R user:group /mnt/DATA_4TB`

### NFS Mount Fails

**Problem**: NFS mount doesn't work.

**Solutions**:
1. Check network connectivity: `ping NFS_SERVER`
2. Verify NFS server is running
3. Check export list on server
4. Test manual mount: `sudo mount -t nfs SERVER:/path /mnt/test`
5. Review NFS logs: `journalctl -u nfs-client`

## Best Practices

### 1. Use UUIDs

Always use UUIDs instead of device names:

✅ **Good**:
```nix
device = "/dev/disk/by-uuid/B8AC28E3AC289E3E";
```

❌ **Bad**:
```nix
device = "/dev/sda1";  # Can change between boots
```

### 2. Add Boot Options for External Drives

For drives that may not always be connected:

```nix
options = [ "nofail" "x-systemd.device-timeout=3s" ];
```

### 3. Document Drive Purposes

Add comments explaining what each drive is for:

```nix
# Main data storage drive
disk1_name = "/mnt/DATA_4TB";

# Backup drive
disk2_name = "/mnt/BACKUP";
```

### 4. Test After Changes

After adding or modifying drives:
1. Test mount manually first
2. Rebuild system
3. Reboot and verify
4. Check logs for errors

### 5. Keep Configurations in Version Control

- Commit drive configurations
- Document drive purposes
- Keep UUIDs documented
- Track changes over time

## Related Documentation

- [LUKS Encryption](../../security/luks-encryption.md) - Encryption setup
- [Hardware Guide](../hardware.md) - General hardware configuration
- [NixOS Wiki - File Systems](https://nixos.wiki/wiki/File_systems)

