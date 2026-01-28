---
id: desk-vs-laptop-packages
summary: Complete package and feature comparison between DESK and LAPTOP_L15 profiles
tags: [packages, profiles, comparison, DESK, LAPTOP]
---

# DESK vs LAPTOP_L15: Package & Feature Differences

**Status**: Completed
**Created**: 2026-01-28

## Overview

DESK (AMD desktop) and LAPTOP_L15 (Intel laptop) are two separate profiles with different hardware, performance tuning, and software requirements. LAPTOP_L15 inherits common laptop settings from LAPTOP-base.nix.

## Hardware Profile Comparison

| Aspect | DESK | LAPTOP_L15 |
|--------|------|-----------|
| **GPU** | AMD (gpuType = "amd") | Intel (gpuType = "intel") |
| **Performance Tuning** | Desktop (aggressive) | Laptop (battery-optimized) |
| **Power Management** | AC (powerManagement_ENABLE = true) | Battery (TLP_ENABLE = true) |
| **Displays** | 4 monitors (Kanshi layout) | 1 laptop screen (default) |
| **Storage Devices** | 6+ disk/NFS mounts | 3 NFS mounts (simple) |

## System Packages

### LAPTOP-base.nix (Shared Foundation)
Both profiles inherit these system packages:
- vim, wget, nmap, zsh, git, cryptsetup
- home-manager, wpa_supplicant, traceroute
- iproute2, dnsutils, fzf, rsync, nfs-utils, restic
- qt5.qtbase, sunshine (unstable)

### DESK-only System Packages
| Package | Reason | Notes |
|---------|--------|-------|
| `nettools` | Network debugging | netstat, arp, ifconfig tools |
| `python3Minimal` | System automation | For deployment scripts |
| `easyeffects` | Audio processing | PulseAudio/PipeWire EQ |
| `lmstudio` (unstable) | Local LLM hosting | AMD GPU optimized |

### LAPTOP_L15-only System Packages
| Package | Reason | Notes |
|---------|--------|-------|
| `clinfo` | GPU info | Intel GPU diagnostics |
| `dialog` | Terminal UI | Interactive CLI prompts |
| `gparted` | Disk management | Visual partition editor |
| `lm_sensors` | Hardware monitoring | CPU/thermal sensors |
| `sshfs` | Remote mounts | SSH-based file access |

## Home (User) Packages

### LAPTOP-base.nix (Shared Foundation)
Both profiles inherit these home packages:
- zsh, kitty, git, syncthing
- ungoogled-chromium, vscode, obsidian, spotify
- vlc, candy-icons, calibre, libreoffice
- telegram-desktop, qbittorrent, nextcloud-client
- wireguard-tools, bitwarden-desktop, moonlight-qt
- discord, kdePackages.kcalc, gnome-calculator

### DESK-only Home Packages
| Package | Category | Purpose |
|---------|----------|---------|
| `git-crypt` | Utilities | Encrypt git files |
| `code-cursor` | IDE | Cursor Code editor |
| `opencode` | IDE | Alternative code editor |
| `drawio` | Graphics | Diagramming tool |
| `vesktop` | Communication | Discord alternative (Wayland) |
| `powershell` | Shell | PowerShell 7+ |
| `azure-cli` | Cloud | Azure command-line tools |
| `cloudflared` | Networking | Cloudflare tunnel client |
| `rpcs3` | Emulation | PlayStation 3 emulator |
| `teams-for-linux` | Communication | Microsoft Teams |
| `thunderbolt` | Hardware | Thunderbolt device manager |
| `ollama-rocm` | AI/LLM | Local LLM runtime (AMD GPU) |
| `claude-code` | IDE | Claude Code CLI |
| `qwen-code` | IDE | Alibaba Qwen Code editor |
| `antigravity` | Development | Development tools |
| `dbeaver-bin` | Database | Database management GUI |

### LAPTOP_L15-only Home Packages
| Package | Category | Purpose |
|---------|----------|---------|
| `mission-center` | Monitoring | System resource monitor |
| `windsurf` | IDE | Code Windsurf editor |
| `code-cursor` | IDE | Cursor Code editor |
| `kdePackages.dolphin` | File Manager | KDE file manager |
| `vivaldi` | Browser | Vivaldi web browser |

## Feature Flags (System Settings)

### DESK Features
| Flag | Value | Purpose |
|------|-------|---------|
| `amdLACTdriverEnable` | `true` | AMD GPU control application |
| `sambaEnable` | `true` | SMB file sharing |
| `sunshineEnable` | `true` | Game streaming server |
| `wireguardEnable` | `true` | VPN tunnel |
| `xboxControllerEnable` | `true` | Xbox controller support |
| `appImageEnable` | `true` | AppImage application support |
| `gamemodeEnable` | `true` | Game performance optimization |
| `aichatEnable` | `true` | AI chat CLI tool |
| `nixvimEnabled` | `true` | NixVim IDE config |
| `lmstudioEnabled` | `true` | Local LLM hosting |
| `enableSwayForDESK` | `true` | Sway WM option (multi-WM) |
| `protongamesEnable` | `true` | Proton/Wine gaming tools |
| `starcitizenEnable` | `true` | Star Citizen support |
| `GOGlauncherEnable` | `true` | GOG/Epic launcher |
| `dolphinEmulatorPrimehackEnable` | `true` | GameCube/Wii emulation |
| `steamPackEnable` | `true` | Steam client |
| `sddmForcePasswordFocus` | `true` | Multi-monitor login fix |
| `sddmBreezePatchedTheme` | `true` | Custom SDDM theme |
| `atuinAutoSync` | `true` | Shell history cloud sync |

### LAPTOP_L15 Features (from LAPTOP-base.nix)
| Flag | Value | Purpose |
|------|-------|---------|
| `enableLaptopPerformance` | `true` | Laptop performance tuning |
| `enableSwayForDESK` | `true` | Sway WM option |
| `stylixEnable` | `true` | Unified theming |
| `swwwEnable` | `true` | Wallpaper manager |
| `wireguardEnable` | `true` | VPN tunnel |
| `appImageEnable` | `true` | AppImage support |
| `nextcloudEnable` | `true` | Nextcloud sync |
| `gamemodeEnable` | `true` | Game optimization |
| `sunshineEnable` | `true` | Game streaming |
| `xboxControllerEnable` | `true` | Xbox controller |
| `aichatEnable` | `true` | AI chat CLI |
| `nixvimEnabled` | `true` | NixVim config |
| `atuinAutoSync` | `true` | Shell history sync |
| **Gaming Disabled** | `false` | No Proton/Steam/emulators |

## User Settings

| Setting | DESK | LAPTOP_L15 |
|---------|------|-----------|
| **Theme** | "ashes" | "miramare" |
| **File Manager** | dolphin | inherited (vivaldi pkg) |
| **Primary Browser** | vivaldi | vivaldi |
| **Shell Prompt Color** | magenta | cyan |
| **Gaming Support** | Full (Proton/Steam/SC/GOG) | None (use flags to enable) |

## Storage Configuration

### DESK (Desktop-centric)
```
Disk 1: /mnt/2nd_NVME      - ext4 (1048576 buffer)
Disk 2: /mnt/DATA_SATA3    - ntfs3
Disk 3: /mnt/NFS_media     - nfs4 (1MB buffer)
Disk 4: /mnt/NFS_emulators - nfs4 (1MB buffer)
Disk 5: /mnt/NFS_library   - nfs4 (1MB buffer)
Disk 6: /mnt/DATA          - ntfs3
Disk 7: /mnt/EXT           - ext4 (disabled)

NFS Options: rsize=1048576, wsize=1048576, nfsvers=4.2, tcp, hard, intr, timeo=600
```

### LAPTOP_L15 (Mobile-optimized)
```
Disk 1: /mnt/NFS_media     - nfs4 (basic)
Disk 2: /mnt/NFS_library   - nfs4 (basic)
Disk 3: /mnt/NFS_emulators - nfs4 (basic)

NFS Options: noatime only (default buffer sizes)
```

## Network Configuration

| Aspect | DESK | LAPTOP_L15 |
|--------|------|-----------|
| **IP Address** | 192.168.8.96 | 192.168.8.92 |
| **WiFi IP** | 192.168.8.98 | 192.168.8.93 |
| **Printer Support** | Yes | Yes |
| **NFS Mounts** | 3 (optimized buffers) | 3 (default buffers) |
| **NFS Auto-mount** | Yes (600s timeout) | Yes (600s timeout) |

## Display Configuration

### DESK: 4 Monitor Setup
1. **Samsung Odyssey G70NC** (Main)
   - 3840×2160@120Hz
   - Scale 1.6
   - Position: (0, 0)

2. **NSL RGB-27QHDS** (Portrait Secondary)
   - 2560×1440@144Hz
   - Scale 1.25
   - Transform: 270° (portrait right)
   - Position: (2400, -876)

3. **Philips TV** (Optional)
   - 1920×1080@60Hz
   - Position: (3552, -876)

4. **BNQ ZOWIE XL** (Left)
   - 1920×1080@60Hz
   - Position: (-1920, 0)

**Kanshi Profiles:**
- desk-tv: All monitors with TV connected
- desk: Fallback without TV (TV disabled)

### LAPTOP_L15: Default Single Screen
- Uses default laptop display
- Dynamic layout (no hardcoded Kanshi config)

## Power Management

### DESK (AC-powered)
```
powerManagement_ENABLE = true
power-profiles-daemon_ENABLE = true
```
- Active power management
- Platform-level power profiles
- Desktop performance priority

### LAPTOP_L15 (Battery-aware)
```
TLP_ENABLE = true
powerManagement_ENABLE = false
power-profiles-daemon_ENABLE = false

Battery Thresholds:
  START_CHARGE_THRESH_BAT0 = 75
  STOP_CHARGE_THRESH_BAT0 = 80

WiFi Power Save = true
Lid Switch = ignore (docked)
```
- TLP battery optimization
- Battery charge limits (75-80%)
- WiFi power saving enabled
- Lid events ignored (usually docked)

## Security & Access Control

### DESK (More Permissive)
- fuseAllowOther = true (allow FUSE for other users)
- Additional Polkit rule: NFS Backups mount management

### LAPTOP_L15 (Restrictive)
- fuseAllowOther = false
- Basic Polkit rules only

## Summary Table

| Feature Category | DESK | LAPTOP_L15 |
|------------------|------|-----------|
| **Hardware** | AMD Desktop | Intel Laptop |
| **System Packages** | 6 additional | 5 additional |
| **Home Packages** | 16 additional | 5 additional |
| **Storage Devices** | 6+ disks | NFS only |
| **Displays** | 4 monitors (Kanshi) | 1 laptop screen |
| **Gaming** | Full (Proton/Steam/Emulators) | None (disabled) |
| **Cloud Features** | Ollama, Teams, Azure | None |
| **AI/LLM** | Local hosting (ollama-rocm) | None |
| **File Sharing** | Samba (SMB) | VPN only |
| **Power Profile** | AC-optimized | Battery-optimized |
| **Theme** | Dark (ashes) | Mixed (miramare) |

## Key Architectural Decisions

1. **Inheritance Pattern**: LAPTOP_L15 extends LAPTOP-base.nix, avoiding duplication
2. **GPU-specific Packages**: AMD (ollama-rocm, lmstudio) vs Intel (clinfo)
3. **Gaming Ecosystem**: Desktop-only (heavy build size, gaming-specific tools)
4. **Storage Philosophy**: Desktop (multiple physical + NFS) vs Laptop (NFS only)
5. **Power Strategy**: Desktop (high performance) vs Laptop (battery preservation)
6. **Display Management**: Desktop (complex Kanshi layout) vs Laptop (dynamic)
7. **Feature Flags**: All conditional features use flags, no hardcoded hostname checks

## Notes for Maintenance

- **To enable gaming on LAPTOP_L15**: Set `protongamesEnable = true` (will add ~500MB packages)
- **To add AI/LLM to laptop**: Enable `lmstudioEnabled = true` (requires sufficient disk space)
- **To add Samba to laptop**: Set `sambaEnable = true`
- **NFS Tuning**: DESK uses large buffers (1MB) for media server optimization
- **All flags are self-documenting**: Check `lib/defaults.nix` for all available options
