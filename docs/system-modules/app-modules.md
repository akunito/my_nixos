---
id: system-modules.app
summary: System application modules — Docker, Virtualization (QEMU/KVM/SPICE), Flatpak, Steam, Gamemode, Samba, AppImage
tags: [system-modules, docker, virtualization, flatpak, steam, gamemode, samba, appimage]
related_files: [system/app/*.nix]
date: 2026-02-15
status: published
---

# Application Modules (`system/app/`)

## Docker (`system/app/docker.nix`)

**Purpose**: Docker container runtime and management

**Settings**: `systemSettings.dockerEnable`

**Features**:
- Docker daemon configuration
- Automatic container handling during system updates
- Prevents boot issues with overlay filesystems

## Virtualization (`system/app/virtualization.nix`)

**Purpose**: QEMU/KVM virtualization support with SPICE integration for clipboard sharing and display management

**Settings**: `userSettings.virtualizationEnable`

**Features**:
- Libvirt/QEMU support with virt-manager
- SPICE protocol support for bidirectional clipboard and display integration
- OVMF (UEFI firmware) support
- USB redirection via SPICE
- Remote management capability
- Network bridge configuration

**Host Packages**:
- `virt-manager` - VM management UI
- `virt-viewer` - Standalone viewer with SPICE support
- `spice`, `spice-gtk`, `spice-protocol` - SPICE client libraries
- `virtio-win` - Windows VirtIO drivers and SPICE guest tools ISO

**Important Notes**:
- `services.qemuGuest` and `services.spice-vdagentd` are for when **NixOS runs AS a guest VM**, not for managing guest VMs
- The host uses `spice-gtk` (via virt-manager) as the SPICE client
- `spice-vdagent` is a guest daemon and should NOT be installed on the host

**Guest VM Setup**:

**For NixOS Guests**:
```nix
services.qemuGuest.enable = true;
services.spice-vdagentd.enable = true;  # Enables clipboard/resolution syncing
```

**For Non-NixOS Linux Guests**: Install `spice-vdagent` via package manager and enable the service.

**For Windows Guests**: See [Windows 11 QXL Setup Guide](../user-modules/windows11-qxl-setup.md) for complete instructions including QXL vs VirtIO-GPU options and video memory configuration.

**Per-VM Configuration** (via virt-manager):
- **Display**: Use SPICE (not VNC)
- **Video**: QXL (recommended for Windows 11 with SPICE) or VirtIO
- **Channel**: Add Spice Agent (`spicevmc`, target: `virtio`, name: `com.redhat.spice.0`)

**Video Memory for High Resolutions**:
- 4K: `vgamem='131072'` (128MB), `ram='262144'` (256MB)
- 2K: `vgamem='65536'` (64MB), `ram='131072'` (128MB)

**Default Network**: `virbr0` is created automatically by libvirtd. If missing: `virsh net-start default && virsh net-autostart default`

## Flatpak (`system/app/flatpak.nix`)

**Purpose**: Flatpak application support

**Settings**: `systemSettings.flatpakEnable`

## Steam (`system/app/steam.nix`)

**Purpose**: Steam gaming platform

**Settings**: `systemSettings.steamEnable`

**Features**: Steam client installation, gaming optimizations

## Gamemode (`system/app/gamemode.nix`)

**Purpose**: Performance optimization for games

**Settings**: `systemSettings.gamemodeEnable`

**Features**: CPU governor switching, process priority optimization

## Samba (`system/app/samba.nix`)

**Purpose**: SMB/CIFS file sharing

**Settings**: `systemSettings.sambaEnable`

## AppImage (`system/app/appimage.nix`)

**Purpose**: AppImage application support

**Settings**: `systemSettings.appimageEnable`

**Features**: FUSE configuration for AppImages, user mount permissions
