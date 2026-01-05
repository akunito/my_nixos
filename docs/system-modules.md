# System Modules Guide

Complete reference for system-level NixOS modules in this configuration.

## Table of Contents

- [Overview](#overview)
- [Module Categories](#module-categories)
- [Application Modules](#application-modules)
- [Hardware Modules](#hardware-modules)
- [Security Modules](#security-modules)
- [Window Manager Modules](#window-manager-modules)
- [Utility Modules](#utility-modules)
- [Using Modules](#using-modules)

## Overview

System modules are located in the `system/` directory and provide system-level configuration. They are imported in profile `configuration.nix` files and receive variables via `specialArgs`.

### Module Import Syntax

Separate Nix files can be imported as modules using an import block:

```nix
imports = [ import1.nix
            import2.nix
            ...
          ];
```

### Module Structure

```nix
{ lib, systemSettings, pkgs, userSettings, authorizedKeys ? [], ... }:

{
  # Module configuration
  services.example.enable = lib.mkIf systemSettings.exampleEnable true;
  
  # ... more configuration
}
```

## Module Categories

### Application Modules (`system/app/`)

System-level configuration for applications that require system services or privileges.

### Hardware Modules (`system/hardware/`)

Hardware-specific configurations, drivers, and kernel modules.

### Security Modules (`system/security/`)

Security-related configurations including SSH, firewall, encryption, and access control.

### Window Manager Modules (`system/wm/`)

System-level configuration for window managers and desktop environments.

### Utility Modules (`system/bin/`)

System utilities and wrapper scripts.

## Application Modules

### Docker (`system/app/docker.nix`)

**Purpose**: Docker container runtime and management

**Settings**:
- `systemSettings.dockerEnable` - Enable Docker service

**Features**:
- Docker daemon configuration
- Automatic container handling during system updates
- Prevents boot issues with overlay filesystems

**Usage**:
```nix
systemSettings = {
  dockerEnable = true;
};
```

### Virtualization (`system/app/virtualization.nix`)

**Purpose**: QEMU/KVM virtualization support

**Settings**:
- `systemSettings.virtualizationEnable` - Enable virtualization

**Features**:
- Libvirt/QEMU support
- Remote management capability
- Network bridge configuration

**Usage**:
```nix
systemSettings = {
  virtualizationEnable = true;
};
```

### Flatpak (`system/app/flatpak.nix`)

**Purpose**: Flatpak application support

**Settings**:
- `systemSettings.flatpakEnable` - Enable Flatpak

**Features**:
- Flatpak runtime installation
- System-wide Flatpak support

### Steam (`system/app/steam.nix`)

**Purpose**: Steam gaming platform

**Settings**:
- `systemSettings.steamEnable` - Enable Steam

**Features**:
- Steam client installation
- Gaming optimizations

### Gamemode (`system/app/gamemode.nix`)

**Purpose**: Performance optimization for games

**Settings**:
- `systemSettings.gamemodeEnable` - Enable Gamemode

**Features**:
- CPU governor switching
- Process priority optimization

### Samba (`system/app/samba.nix`)

**Purpose**: SMB/CIFS file sharing

**Settings**:
- `systemSettings.sambaEnable` - Enable Samba server

**Features**:
- Samba server configuration
- Network file sharing

### AppImage (`system/app/appimage.nix`)

**Purpose**: AppImage application support

**Settings**:
- `systemSettings.appimageEnable` - Enable AppImage support

**Features**:
- FUSE configuration for AppImages
- User mount permissions

## Hardware Modules

### Drives (`system/hardware/drives.nix`)

**Purpose**: Drive mounting and LUKS encryption

**Settings**:
- `systemSettings.mount2ndDrives` - Enable secondary drive mounting
- `disk1_enabled`, `disk1_name`, `disk1_device`, etc. - Drive configuration

**Features**:
- Automatic LUKS device unlocking
- Secondary drive mounting
- NFS mount support
- Boot options for unreliable drives (`nofail`, `x-systemd.device-timeout`)

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

**Documentation**: See [Drive Management](hardware/drive-management.md)

### Power Management (`system/hardware/power.nix`)

**Purpose**: CPU and system power management

**Settings**:
- `systemSettings.TLP_ENABLE` - Enable TLP power management
- `systemSettings.PROFILE_ON_BAT`, `PROFILE_ON_AC` - Power profiles
- `systemSettings.powerManagement_ENABLE` - Enable power-profiles-daemon

**Features**:
- CPU frequency governors
- Power profile management
- Laptop-specific optimizations

**Documentation**: See [CPU Power Management](hardware/cpu-power-management.md)

### Kernel (`system/hardware/kernel.nix`)

**Purpose**: Kernel configuration and modules

**Settings**:
- `systemSettings.kernelPackages` - Kernel package selection
- `systemSettings.kernelModules` - Kernel modules to load

**Features**:
- Custom kernel selection
- Kernel module loading
- Kernel parameters

**Usage**:
```nix
systemSettings = {
  kernelPackages = pkgs.linuxPackages_latest;
  kernelModules = [ "i2c-dev" "xpadneo" ];
};
```

### Bluetooth (`system/hardware/bluetooth.nix`)

**Purpose**: Bluetooth support

**Settings**:
- `systemSettings.bluetoothEnable` - Enable Bluetooth

**Features**:
- Bluetooth daemon
- Device pairing support

### Printing (`system/hardware/printing.nix`)

**Purpose**: Printer support

**Settings**:
- `systemSettings.servicePrinting` - Enable CUPS printing
- `systemSettings.networkPrinters` - Enable network printer discovery
- `systemSettings.sharePrinter` - Enable printer sharing

**Features**:
- CUPS printing service
- Brother Laser printer drivers
- Network printer support
- Printer sharing (CAPS)

### OpenGL (`system/hardware/opengl.nix`)

**Purpose**: Graphics acceleration

**Settings**:
- `systemSettings.gpuType` - GPU type ("amd", "intel", "nvidia")

**Features**:
- GPU-specific OpenGL configuration
- AMD LACT driver support

### Xbox Controller (`system/hardware/xbox.nix`)

**Purpose**: Xbox controller support

**Settings**:
- `systemSettings.xboxControllerEnable` - Enable Xbox controller

**Features**:
- xpadneo driver
- Wireless Xbox controller support

### NFS Client (`system/hardware/nfs_client.nix`)

**Purpose**: NFS client configuration

**Settings**:
- `systemSettings.nfsClientEnable` - Enable NFS client
- `systemSettings.nfsMounts` - NFS mount points
- `systemSettings.nfsAutoMounts` - Auto-mount configuration

**Features**:
- NFS mount management
- Auto-mount with systemd
- Idle timeout configuration

### NFS Server (`system/hardware/nfs_server.nix`)

**Purpose**: NFS server configuration

**Settings**:
- `systemSettings.nfsServerEnable` - Enable NFS server
- `systemSettings.nfsExports` - NFS export configuration

**Features**:
- NFS server daemon
- Export management
- Access control

### SystemD (`system/hardware/systemd.nix`)

**Purpose**: SystemD configuration

**Settings**:
- Various systemd settings

**Features**:
- Service management
- Timer configuration
- Logging configuration

### Time (`system/hardware/time.nix`)

**Purpose**: System time configuration

**Settings**:
- `systemSettings.timezone` - System timezone

**Features**:
- Timezone configuration
- NTP synchronization

## Security Modules

### SSH Server (`system/security/sshd.nix`)

**Purpose**: SSH server configuration

**Settings**:
- `systemSettings.bootSSH` - Enable SSH on boot (for LUKS unlock)
- `systemSettings.authorizedKeys` - SSH public keys
- `systemSettings.hostKeys` - SSH host keys

**Features**:
- SSH server configuration
- Boot-time SSH for remote LUKS unlock
- Key-based authentication

**Documentation**: See [LUKS Encryption](security/luks-encryption.md)

### Firewall (`system/security/firewall.nix`)

**Purpose**: Network firewall configuration

**Settings**:
- `systemSettings.firewall` - Enable firewall
- `systemSettings.allowedTCPPorts` - Allowed TCP ports
- `systemSettings.allowedUDPPorts` - Allowed UDP ports

**Features**:
- nftables firewall
- Port management
- Network security

### Sudo (`system/security/sudo.nix`)

**Purpose**: Sudo configuration

**Settings**:
- `systemSettings.sudoEnable` - Enable sudo
- `systemSettings.sudoNOPASSWD` - Allow passwordless sudo (NOT recommended)
- `systemSettings.sudoCommands` - Commands with special sudo rules

**Features**:
- Sudo configuration
- Command-specific rules
- NOPASSWD options

**Documentation**: See [Sudo Configuration](security/sudo.md)

### Polkit (`system/security/polkit.nix`)

**Purpose**: Polkit privilege management

**Settings**:
- `systemSettings.polkitEnable` - Enable Polkit
- `systemSettings.polkitRules` - Polkit rules (JavaScript)

**Features**:
- Fine-grained permission control
- Passwordless actions for specific operations
- Group-based rules

**Documentation**: See [Polkit Configuration](security/polkit.md)

### Restic (`system/security/restic.nix`)

**Purpose**: Backup system configuration

**Settings**:
- `systemSettings.resticWrapper` - Enable Restic wrapper
- `systemSettings.homeBackupEnable` - Enable home backup
- `systemSettings.homeBackupExecStart` - Backup script path
- `systemSettings.homeBackupOnCalendar` - Backup schedule

**Features**:
- Restic binary wrapper with capabilities
- SystemD timer for automated backups
- Remote backup support

**Documentation**: See [Restic Backups](security/restic-backups.md)

### GPG (`system/security/gpg.nix`)

**Purpose**: GPG key management

**Settings**:
- GPG agent configuration

**Features**:
- GPG agent
- Key management

### Fail2ban (`system/security/fail2ban.nix`)

**Purpose**: Intrusion prevention

**Settings**:
- Fail2ban service configuration

**Features**:
- Automated ban of malicious IPs
- SSH protection
- Service monitoring

### Firejail (`system/security/firejail.nix`)

**Purpose**: Application sandboxing

**Settings**:
- Firejail configuration

**Features**:
- Application sandboxing
- Security profiles

### Blocklist (`system/security/blocklist.nix`)

**Purpose**: DNS blocklist

**Settings**:
- Blocklist configuration

**Features**:
- Ad blocking
- Malware blocking
- DNS filtering

### OpenVPN (`system/security/openvpn.nix`)

**Purpose**: VPN client support

**Settings**:
- OpenVPN configuration

**Features**:
- VPN client
- Connection management

### Automount (`system/security/automount.nix`)

**Purpose**: Automatic drive mounting

**Settings**:
- Automount configuration

**Features**:
- Automatic USB drive mounting
- Security restrictions

## Window Manager Modules

### Plasma 6 (`system/wm/plasma6.nix`)

**Purpose**: KDE Plasma 6 desktop environment

**Settings**:
- `systemSettings.desktopManager` - Desktop manager selection

**Features**:
- Plasma 6 installation
- SDDM display manager
- Desktop environment setup

**SDDM Configuration**:
- Auto-focus password field on login screen
- Monitor rotation script for multi-monitor setups (uses EDID/model name matching)
- Wayland session support enabled
- Theme configuration via `lib/flake-base.nix` (wallpaper and focus settings)

**GUI Configuration**:
KDE System Settings provides a GUI for SDDM configuration:
- Location: System Settings > Startup and Shutdown > Login Screen (SDDM)
- Features: Theme selection, background customization
- **Note**: The "Apply Plasma Settings" button often fails on NixOS because it attempts to write to `/etc/sddm.conf`, which is managed by NixOS. The script-based approach (using `setupScript`) is preferred for NixOS as it's declaratively managed.

### Hyprland (`system/wm/hyprland.nix`)

**Purpose**: Hyprland Wayland compositor

**Settings**:
- Hyprland system configuration

**Features**:
- Wayland compositor
- GPU acceleration requirements

### XMonad (`system/wm/xmonad.nix`)

**Purpose**: XMonad tiling window manager

**Settings**:
- XMonad system configuration

**Features**:
- Tiling window manager
- X11 support

### Wayland (`system/wm/wayland.nix`)

**Purpose**: Wayland support

**Settings**:
- Wayland configuration

**Features**:
- Wayland session support
- Compositor integration

### X11 (`system/wm/x11.nix`)

**Purpose**: X11 support

**Settings**:
- X11 configuration

**Features**:
- X11 server
- Legacy application support

### Pipewire (`system/wm/pipewire.nix`)

**Purpose**: Audio/video server

**Settings**:
- Pipewire configuration

**Features**:
- Audio server
- Video server
- Low-latency audio

### Fonts (`system/wm/fonts.nix`)

**Purpose**: System fonts

**Settings**:
- Font configuration

**Features**:
- Font installation
- Font configuration

### D-Bus (`system/wm/dbus.nix`)

**Purpose**: D-Bus message bus

**Settings**:
- D-Bus configuration

**Features**:
- Inter-process communication
- Service communication

### GNOME Keyring (`system/wm/gnome-keyring.nix`)

**Purpose**: Keyring service

**Settings**:
- Keyring configuration

**Features**:
- Password storage
- Key management

## Utility Modules

### Phoenix (`system/bin/phoenix.nix`)

**Purpose**: Nix command wrapper script

**Features**:
- `phoenix sync` - Synchronize system and home-manager
- `phoenix update` - Update flake inputs
- `phoenix upgrade` - Update and synchronize
- `phoenix gc` - Garbage collection
- `phoenix harden` - Secure system files
- `phoenix soften` - Relax file permissions

**Documentation**: See [Maintenance Guide](maintenance.md#phoenix-wrapper)

## Using Modules

### Importing Modules

In a profile's `configuration.nix`:

```nix
imports = [
  ../../system/app/docker.nix
  ../../system/hardware/drives.nix
  ../../system/security/sshd.nix
];
```

### Conditional Enabling

Modules should use `lib.mkIf` for conditional enabling:

```nix
services.docker.enable = lib.mkIf systemSettings.dockerEnable true;
```

### Accessing Variables

Modules receive variables via function arguments:

```nix
{ lib, systemSettings, pkgs, userSettings, authorizedKeys ? [], ... }:
```

### Variables from flake.nix

Variables can be imported from `flake.nix` by setting the `specialArgs` block inside the flake. This allows variables to be managed in one place (`flake.nix`) rather than having to manage them in multiple locations.

Common attribute sets passed to system modules:

- `userSettings` - Settings for the normal user (see flake.nix for more details)
- `systemSettings` - Settings for the system (see flake.nix for more details)
- `inputs` - Flake inputs (see flake.nix for more details)
- `pkgs-stable` - Allows including stable versions of packages along with (default) unstable versions

### Boot Options for Unreliable Drives

If you have a drive which can be not connected at all times, you might try to use these options to avoid freezing the boot loader:

```nix
options = [ "nofail" "x-systemd.device-timeout=3s" ];
```

Example usage:

```nix
boot.initrd.luks.devices."luks-a40d2e06-e814-4344-99c8-c2e00546beb3".device = "/dev/disk/by-uuid/a40d2e06-e814-4344-99c8-c2e00546beb3";

fileSystems."/mnt/2nd_NVME" =
  { device = "/dev/mapper/2nd_NVME";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=3s" ];
  };

boot.initrd.luks.devices."2nd_NVME".device = "/dev/disk/by-uuid/a949132d-9469-4d17-af95-56fdb79f9e4b";

fileSystems."/mnt/DATA" =
  { device = "/dev/disk/by-uuid/B8AC28E3AC289E3E";
    fsType = "ntfs3";
    options = [ "nofail" "x-systemd.device-timeout=3s" ];
  };

fileSystems."/mnt/NFS_media" =
  { device = "192.168.20.200:/mnt/hddpool/media";
    fsType = "nfs4";
    options = [ "nofail" "x-systemd.device-timeout=3s" ];
  };
```

## Related Documentation

- [Configuration Guide](configuration.md) - Understanding configuration structure
- [Hardware Guide](hardware.md) - Hardware-specific documentation
- [Security Guide](security.md) - Security configurations

**Related Documentation**: See [system/README.md](../../system/README.md) for directory-level documentation.

**Note**: The original [system/README.org](../../system/README.org) file is preserved for historical reference.

