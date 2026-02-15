---
id: system-modules.hardware
summary: System hardware modules — drives, power, kernel, Bluetooth, printing, OpenGL, Xbox, NFS, SystemD, time
tags: [system-modules, hardware, drives, power, kernel, bluetooth, printing, opengl, nfs]
related_files: [system/hardware/*.nix]
date: 2026-02-15
status: published
---

# Hardware Modules (`system/hardware/`)

## Drives (`system/hardware/drives.nix`)

**Purpose**: Drive mounting and LUKS encryption

**Settings**:
- `systemSettings.mount2ndDrives` - Enable secondary drive mounting
- `disk1_enabled`, `disk1_name`, `disk1_device`, etc. - Drive configuration

**Features**: Automatic LUKS device unlocking, secondary drive mounting, NFS mount support, boot options for unreliable drives (`nofail`, `x-systemd.device-timeout`)

**Usage**:
```nix
systemSettings = {
  mount2ndDrives = true;
  disk1_enabled = true;
  disk1_name = "/mnt/DATA";
  disk1_device = "/dev/mapper/DATA";
  disk1_fsType = "ext4";
  disk1_options = [ "nofail" "x-systemd.device-timeout=3s" ];
};
```

**Documentation**: See [Drive Management](../hardware/drive-management.md)

## Power Management (`system/hardware/power.nix`)

**Purpose**: CPU and system power management

**Settings**:
- `systemSettings.TLP_ENABLE` - Enable TLP power management
- `systemSettings.PROFILE_ON_BAT`, `PROFILE_ON_AC` - Power profiles
- `systemSettings.powerManagement_ENABLE` - Enable power-profiles-daemon

**Documentation**: See [CPU Power Management](../akunito/hardware/cpu-power-management.md)

## Kernel (`system/hardware/kernel.nix`)

**Purpose**: Kernel configuration and modules

**Settings**:
- `systemSettings.kernelPackages` - Kernel package selection
- `systemSettings.kernelModules` - Kernel modules to load

**Usage**:
```nix
systemSettings = {
  kernelPackages = pkgs.linuxPackages_latest;
  kernelModules = [ "i2c-dev" "xpadneo" ];
};
```

## Bluetooth (`system/hardware/bluetooth.nix`)

**Purpose**: Bluetooth support

**Settings**: `systemSettings.bluetoothEnable`

## Printing (`system/hardware/printing.nix`)

**Purpose**: Printer support

**Settings**:
- `systemSettings.servicePrinting` - Enable CUPS printing
- `systemSettings.networkPrinters` - Enable network printer discovery
- `systemSettings.sharePrinter` - Enable printer sharing

**Features**: CUPS printing service, Brother Laser printer drivers, network printer support

## OpenGL (`system/hardware/opengl.nix`)

**Purpose**: Graphics acceleration

**Settings**: `systemSettings.gpuType` - GPU type ("amd", "intel", "nvidia")

**Features**: GPU-specific OpenGL configuration, AMD LACT driver support

## Xbox Controller (`system/hardware/xbox.nix`)

**Purpose**: Xbox controller support

**Settings**: `systemSettings.xboxControllerEnable`

**Features**: xpadneo driver, wireless Xbox controller support

## NFS Client (`system/hardware/nfs_client.nix`)

**Purpose**: NFS client configuration

**Settings**:
- `systemSettings.nfsClientEnable`
- `systemSettings.nfsMounts` - Mount points
- `systemSettings.nfsAutoMounts` - Auto-mount configuration

## NFS Server (`system/hardware/nfs_server.nix`)

**Purpose**: NFS server configuration

**Settings**:
- `systemSettings.nfsServerEnable`
- `systemSettings.nfsExports` - Export configuration

## SystemD (`system/hardware/systemd.nix`)

**Purpose**: SystemD configuration (service management, timer configuration, logging)

## Time (`system/hardware/time.nix`)

**Purpose**: System time configuration

**Settings**: `systemSettings.timezone`

### Boot Options for Unreliable Drives

If a drive may not always be connected, use these options to avoid freezing the boot loader:

```nix
options = [ "nofail" "x-systemd.device-timeout=3s" ];
```
