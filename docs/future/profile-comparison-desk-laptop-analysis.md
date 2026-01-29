# Profile Comparison: DESK vs LAPTOP_L15 vs LAPTOP_YOGAAKU

## Date: 2026-01-28

## Overview

This document provides a comprehensive analysis of the differences between three key profiles in the NixOS configuration hierarchy:
- **DESK**: Primary desktop (AMD GPU, gaming, development, AI)
- **LAPTOP_L15**: Modern Intel laptop with full development setup
- **LAPTOP_YOGAAKU**: Older Lenovo Yoga laptop with reduced features

## Inheritance Hierarchy

```
lib/defaults.nix (global defaults)
    │
    ▼
Personal Profile
    │
    ▼
DESK-config.nix (base for all desktop/laptop configs)
    │
    ▼
LAPTOP-base.nix (laptop-specific settings)
    │
    ├─► LAPTOP_L15-config.nix (modern laptop)
    └─► LAPTOP_YOGAAKU-config.nix (older laptop)
```

**Key Insight**: Both laptops inherit from DESK through LAPTOP-base.nix, meaning they get all desktop features plus laptop-specific enhancements.

## Quick Reference Table

| Category | DESK | LAPTOP_L15 | LAPTOP_YOGAAKU |
|----------|------|------------|----------------|
| **Machine Type** | Desktop | Modern Laptop | Older Laptop (Lenovo Yoga) |
| **Hostname** | nixosaku | nixolaptopaku | nixosyogaaku |
| **GPU** | AMD (RX 7800 XT) | Intel | Intel |
| **Boot Mode** | UEFI | UEFI | BIOS (legacy) |
| **Rust Overlay** | false | true | false |
| **Performance Profile** | Desktop (aggressive) | Laptop (conservative) | Laptop (conservative) |
| **TLP Power Management** | false | true | true |
| **Battery Thresholds** | N/A | 75%-80% | 75%-80% |
| **Sway + Plasma6** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Stylix Theming** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Theme** | ashes | ashes | io |
| **NFS Mounts** | 7 mounts (media, library, emulators) | 3 mounts (same as DESK) | 4 mounts (different server) |
| **Backups** | Enabled (6hr cycle) | Enabled (6hr cycle) | Disabled |
| **Development Tools** | Full suite | Full suite | Enabled (fewer tools) |
| **AI Packages** | Enabled (lmstudio, ollama-rocm) | Disabled | Disabled |
| **Gaming** | Full (Steam, Star Citizen, emulators) | Disabled | Disabled |
| **Sunshine Streaming** | Enabled | Enabled | Disabled |
| **Printer** | Enabled | Enabled | Disabled |
| **ZSH Hostname Color** | Magenta | Cyan | Default (blue in base) |
| **Certificates** | Yes (custom CA) | Yes (custom CA) | None |
| **Sudo Timeout** | 180 min | 180 min | 180 min |

## Detailed Comparison by Category

### 1. Machine Identity & Hardware

#### DESK
- **Hostname**: `nixosaku`
- **GPU Type**: `amd` (RX 7800 XT with LACT driver)
- **Boot Mode**: UEFI
- **Performance**: `enableDesktopPerformance = true` (aggressive I/O, CPU scheduling)
- **Power Management**: `power-profiles-daemon` (desktop profiles)
- **Monitors**: 4 monitors (3x 4K + 1x portrait, kanshi config)
- **Kernel Modules**: `xpadneo` (Xbox controller)

#### LAPTOP_L15
- **Hostname**: `nixolaptopaku`
- **GPU Type**: `intel`
- **Boot Mode**: UEFI
- **Performance**: `enableLaptopPerformance = true` (battery-friendly I/O, conservative scheduling)
- **Power Management**: TLP (battery charge thresholds 75%-80%)
- **Monitors**: Single laptop screen (portable)
- **Kernel Modules**: None (minimal)
- **Lid Behavior**: All ignored (docked usage)

#### LAPTOP_YOGAAKU
- **Hostname**: `nixosyogaaku`
- **GPU Type**: `intel`
- **Boot Mode**: **BIOS/Legacy** (older hardware)
- **GRUB Device**: `/dev/sda` (required for BIOS boot)
- **Performance**: `enableLaptopPerformance = true`
- **Power Management**: TLP (battery charge thresholds 75%-80%)
- **Monitors**: Single laptop screen
- **Kernel Modules**: `cpufreq_powersave`, `xpadneo` (Xbox controller support)
- **Lid Behavior**: Default (inherited from base)

**Key Difference**: YOGAAKU uses **BIOS boot mode** (older hardware), while DESK and L15 use UEFI.

---

### 2. Network Configuration

#### DESK
- **IP Address**: `192.168.8.96` (wired), `192.168.8.98` (wifi)
- **Firewall**: All ports commented out (none enabled)
- **WiFi Power Save**: false (desktop doesn't need power savings)
- **DNS**: `192.168.8.1`

#### LAPTOP_L15
- **IP Address**: `192.168.8.92` (wired), `192.168.8.93` (wifi)
- **Firewall**: No ports enabled
- **WiFi Power Save**: true (battery conservation)
- **DNS**: `192.168.8.1`

#### LAPTOP_YOGAAKU
- **IP Address**: `192.168.8.xxx` (placeholder - needs reservation)
- **Firewall**: No ports enabled
- **WiFi Power Save**: true (battery conservation)
- **DNS**: `192.168.8.1`

**Key Difference**: YOGAAKU has placeholder IPs (not yet configured), while DESK and L15 have static reservations.

---

### 3. Storage & NFS Mounts

#### DESK (7 Disk Mounts)
1. `/mnt/2nd_NVME` - Secondary NVME (ext4)
2. `/mnt/DATA_SATA3` - SATA data drive (NTFS3)
3. `/mnt/NFS_media` - NFS media share (`192.168.20.200`)
4. `/mnt/NFS_emulators` - NFS emulators share
5. `/mnt/NFS_library` - NFS library share
6. `/mnt/DATA` - Additional NTFS data drive
7. `/mnt/EXT` - External drive (temporarily disabled)

**NFS Server**: `192.168.20.200` (homelab NAS)

#### LAPTOP_L15 (3 NFS Mounts)
1. `/mnt/NFS_media` - Same homelab NAS (`192.168.20.200`)
2. `/mnt/NFS_library` - Same homelab NAS
3. `/mnt/NFS_emulators` - Same homelab NAS

**Local Drives**: None (portable machine)

#### LAPTOP_YOGAAKU (4 NFS Mounts - DISABLED)
1. `/mnt/NFS_Books` - Books share (`192.168.8.80` - **different server**)
2. `/mnt/NFS_downloads` - Downloads share
3. `/mnt/NFS_Media` - Media share
4. `/mnt/NFS_Backups` - Backups share (`/mnt/DATA_4TB/backups/akunitoLaptop`)

**NFS Status**: `nfsClientEnable = false` (mounts defined but disabled)
**NFS Server**: `192.168.8.80` (older/different NAS)

**Key Differences**:
- DESK has local drives + NFS mounts
- L15 has NFS-only storage (portable)
- YOGAAKU uses a **different NFS server** (192.168.8.80) with different share paths
- YOGAAKU's NFS is currently **disabled** (older machine, possibly offline)

---

### 4. Security & Authentication

#### DESK
- **FUSE Allow Other**: true (needed for some desktop apps)
- **Certificates**: `/home/akunito/.myCA/ca.cert.pem`
- **Sudo Timeout**: 180 minutes
- **SSH Keys**: 2 keys (ed25519 desktop + laptop)
- **Polkit**: Enabled with extensive rules (NFS mounts, backup tools)

#### LAPTOP_L15
- **FUSE Allow Other**: false (more restrictive)
- **Certificates**: `/home/akunito/.myCA/ca.cert.pem` (same as DESK)
- **Sudo Timeout**: 180 minutes
- **SSH Keys**: 3 keys (RSA + 2x ed25519)
- **Polkit**: Inherited from LAPTOP-base (common laptop rules)

#### LAPTOP_YOGAAKU
- **FUSE Allow Other**: false
- **Certificates**: None (commented out)
- **Sudo Timeout**: 180 minutes
- **SSH Keys**: 3 keys (same as L15)
- **Polkit**: Inherited from LAPTOP-base

**Key Differences**:
- DESK has most permissive security (FUSE, certificates)
- L15 has certificates for corporate/development needs
- YOGAAKU has no certificates (older, personal-use machine)

---

### 5. Backups

#### DESK
- **Home Backup**: Enabled
- **Schedule**: Every 6 hours (`0/6:00:00`)
- **Chain**: No chained backups
- **Description**: "Backup Home Directory with Restic"

#### LAPTOP_L15
- **Home Backup**: Enabled
- **Schedule**: Every 6 hours (`0/6:00:00`)
- **Chain**: No chained backups

#### LAPTOP_YOGAAKU
- **Home Backup**: **Disabled**
- **Reason**: Older machine, possibly not in regular use

**Key Difference**: YOGAAKU has backups disabled (older/secondary machine).

---

### 6. Desktop Environment & Theming

#### DESK
- **Sway + Plasma6**: ✅ Both enabled
- **Stylix**: Enabled
- **Theme**: `ashes`
- **Swww**: Enabled (wallpaper daemon)
- **SDDM**: Multi-monitor fixes (4 monitors, portrait rotation script)
- **ZSH Hostname Color**: Magenta (`%F{magenta}%m`)

#### LAPTOP_L15
- **Sway + Plasma6**: ✅ Both enabled (inherits from LAPTOP-base)
- **Stylix**: Enabled (inherits)
- **Theme**: `ashes` (inherits from LAPTOP-base)
- **Swww**: Enabled (inherits)
- **SDDM**: No custom setup (single monitor)
- **ZSH Hostname Color**: **Cyan** (`%F{cyan}%m`) - **OVERRIDE**

#### LAPTOP_YOGAAKU
- **Sway + Plasma6**: ✅ Both enabled (inherits from LAPTOP-base)
- **Stylix**: Enabled (inherits)
- **Theme**: **`io`** - **OVERRIDE** (different from base's `ashes`)
- **Swww**: Enabled (inherits)
- **SDDM**: No custom setup
- **ZSH Hostname Color**: Blue (`%F{blue}%m`) - inherits from LAPTOP-base

**Key Differences**:
- DESK has complex multi-monitor SDDM setup
- L15 uses cyan hostname (visual distinction from DESK)
- YOGAAKU uses different theme (`io` instead of `ashes`)

---

### 7. System Services & Features

| Feature | DESK | LAPTOP_L15 | LAPTOP_YOGAAKU |
|---------|------|------------|----------------|
| **Basic Tools** | ✅ | ✅ | ✅ |
| **Network Tools** | ✅ | ✅ | ✅ |
| **Samba** | ✅ | ❌ (inherits false) | ❌ Explicit |
| **Sunshine Streaming** | ✅ | ✅ | ❌ Disabled |
| **WireGuard VPN** | ✅ | ✅ (inherits) | ✅ (inherits) |
| **AppImage** | ✅ | ✅ (inherits) | ✅ (inherits) |
| **Xbox Controller** | ✅ | ✅ | ✅ |
| **Nextcloud** | ✅ | ✅ (inherits) | ✅ (inherits) |
| **Printer** | ✅ Network | ✅ Network | ❌ Disabled |
| **Gamemode** | ✅ | ❌ (inherits false) | ❌ (inherits false) |

**Key Differences**:
- DESK has Samba (file sharing for home network)
- YOGAAKU disables Sunshine (older hardware, not powerful enough)
- YOGAAKU disables printer (portable, no regular printer access)

---

### 8. Development Tools

#### DESK
- **Development Tools**: ✅ Enabled
- **AI Chat**: ✅ Enabled (OpenRouter)
- **NixVim**: ✅ Enabled (Cursor-like IDE)
- **LM Studio**: ✅ Enabled (local LLM server)
- **Rust Overlay**: false

#### LAPTOP_L15
- **Development Tools**: ✅ Enabled
- **AI Chat**: ✅ Enabled
- **NixVim**: ✅ Enabled
- **LM Studio**: ❌ Not set (inherits false)
- **Rust Overlay**: **true** (for Rust development)

#### LAPTOP_YOGAAKU
- **Development Tools**: ✅ Enabled
- **AI Chat**: ❌ Not set (inherits false)
- **NixVim**: ❌ Not set (inherits false)
- **LM Studio**: ❌ Not set (inherits false)
- **Rust Overlay**: false

**Key Differences**:
- DESK has full AI/LLM setup (powerful hardware)
- L15 has Rust overlay (modern Rust development laptop)
- YOGAAKU has basic development tools only (older hardware)

---

### 9. Gaming & Entertainment

#### DESK (Full Gaming Setup)
- **Games Enable**: ✅ true
- **Proton Games**: ✅ (Lutris, Bottles, Heroic)
- **Star Citizen**: ✅ (kernel tweaks + tools)
- **GOG Launcher**: ✅ (Heroic)
- **Steam**: ✅ (with proton)
- **Dolphin Emulator (Primehack)**: ✅
- **RPCS3 (PS3)**: ✅
- **Gamemode**: ✅ (performance optimization)

#### LAPTOP_L15
- **Gaming**: All disabled (inherits false from defaults)
- **Reason**: Not a gaming machine

#### LAPTOP_YOGAAKU
- **Gaming**: All disabled (inherits false from defaults)
- **Reason**: Older hardware, not suitable for gaming

**Key Difference**: Only DESK has gaming capabilities (desktop with powerful GPU).

---

### 10. AI & Machine Learning

#### DESK
- **User AI Packages**: ✅ Enabled
- **LM Studio**: ✅ Enabled (local LLM server + MCP)
- **Ollama ROCm**: ✅ Included (AMD GPU support)

#### LAPTOP_L15
- **User AI Packages**: ❌ Disabled
- **Reason**: No discrete GPU, not suitable for local LLMs

#### LAPTOP_YOGAAKU
- **User AI Packages**: ❌ Disabled
- **Reason**: Older hardware, no GPU

**Key Difference**: Only DESK runs local AI/LLM models (AMD GPU with ROCm).

---

### 11. User Packages

#### DESK
- **Basic User Packages**: ✅ Enabled
- **AI Packages**: ✅ Enabled
- **Additional**: `clinfo` (OpenCL diagnostics)

#### LAPTOP_L15
- **Basic User Packages**: ✅ Enabled
- **AI Packages**: ❌ Disabled
- **Additional**: `kdePackages.dolphin` (file manager)

#### LAPTOP_YOGAAKU
- **Basic User Packages**: ✅ Enabled
- **AI Packages**: ❌ Disabled
- **Additional**: `tldr` (system package, not home package)

**Key Difference**: Each profile has minimal additional packages, relying on module flags.

---

### 12. Shell & Terminal

#### DESK
- **ZSH Prompt**: Magenta hostname (`%F{magenta}%m`)
- **Atuin Sync**: ✅ Enabled
- **Terminal**: kitty
- **SSH Key**: `~/.ssh/id_ed25519`

#### LAPTOP_L15
- **ZSH Prompt**: **Cyan hostname** (`%F{cyan}%m`) - **Visual distinction**
- **Atuin Sync**: ✅ Enabled (inherits from LAPTOP-base)
- **Terminal**: kitty
- **SSH Key**: `~/.ssh/id_ed25519`

#### LAPTOP_YOGAAKU
- **ZSH Prompt**: Blue hostname (`%F{blue}%m`) - inherits from LAPTOP-base
- **Atuin Sync**: ✅ Enabled (inherits from LAPTOP-base)
- **Terminal**: kitty
- **SSH Key**: `~/.ssh/id_ed25519`

**Key Difference**: Each profile uses different hostname colors for visual distinction:
- DESK: Magenta (primary desktop)
- L15: Cyan (modern laptop)
- YOGAAKU: Blue (older laptop)

---

### 13. Virtualization

#### DESK
- **Docker**: ❌ false (not set explicitly)
- **Virtualization**: ✅ true (QEMU, virt-manager)
- **QEMU Guest**: false (physical machine)

#### LAPTOP_L15
- **Docker**: ❌ false (inherits)
- **Virtualization**: ✅ true (inherits)
- **QEMU Guest**: false (physical machine)

#### LAPTOP_YOGAAKU
- **Docker**: ❌ false (explicit)
- **Virtualization**: ✅ true
- **QEMU Guest**: **true** (!!!) - **Incorrect configuration**

**Key Issue**: YOGAAKU has `qemuGuestAddition = true` but it's a physical laptop, not a VM. This should be `false`.

---

### 14. Power Management Details

#### DESK
- **TLP**: ❌ Disabled (desktop doesn't need battery management)
- **Power Profiles Daemon**: ✅ Enabled (desktop power profiles)
- **Power Management**: ✅ Enabled
- **Lid Switch**: N/A (desktop)
- **WiFi Power Save**: false (desktop always plugged in)

#### LAPTOP_L15
- **TLP**: ✅ Enabled (battery management)
- **Power Profiles Daemon**: ❌ Disabled (TLP takes over)
- **Power Management**: ❌ Disabled (TLP handles it)
- **Battery Thresholds**: 75%-80% (health preservation)
- **Lid Switch**: All ignored (docked usage)
- **WiFi Power Save**: true (battery conservation)

#### LAPTOP_YOGAAKU
- **TLP**: ✅ Enabled (battery management)
- **Power Profiles Daemon**: ❌ Disabled (TLP takes over)
- **Power Management**: ❌ Disabled (TLP handles it)
- **Battery Thresholds**: 75%-80% (inherited from LAPTOP-base)
- **Lid Switch**: Default behavior (not overridden)
- **WiFi Power Save**: true

**Key Differences**:
- DESK uses power-profiles-daemon (desktop power management)
- Laptops use TLP (comprehensive battery management)
- L15 ignores lid switch (docked/external monitor usage)
- Both laptops use 75%-80% battery thresholds (longevity focus)

---

## Configuration Philosophy Differences

### DESK Philosophy
- **Maximum Performance**: Desktop I/O scheduler, no power savings
- **Full Features**: All gaming, development, AI tools enabled
- **Always-On**: No battery concerns, aggressive settings
- **Multi-Monitor**: Complex display setup with kanshi
- **Home Server Role**: Samba, Sunshine streaming, NFS client
- **Powerful Hardware**: AMD GPU, multiple drives, handles any workload

### LAPTOP_L15 Philosophy
- **Modern Mobile Workstation**: Full development environment on the go
- **Battery Preservation**: TLP, 75%-80% charge limits, conservative I/O
- **Cloud Storage**: NFS mounts for accessing homelab data
- **Docked Usage**: Lid switch ignored, external monitors
- **Development Focus**: Full dev tools, no gaming/AI (no GPU)
- **Professional Tool**: Certificates for corporate/dev work

### LAPTOP_YOGAAKU Philosophy
- **Older Hardware**: BIOS boot, reduced features
- **Minimal Setup**: Basic development, no AI/streaming/gaming
- **Possibly Offline**: Different NFS server (disabled), no backups
- **Secondary Machine**: Lower priority, older software expectations
- **Power Efficient**: TLP enabled, wifi power save
- **Different Theme**: `io` instead of `ashes` (visual distinction)

---

## Inheritance Flow & Override Patterns

### What LAPTOP-base.nix Adds to DESK

```nix
# Laptop-specific additions to DESK base
enableLaptopPerformance = true;      # vs DESK's enableDesktopPerformance
atuinAutoSync = true;                # Shell history sync
enableSwayForDESK = true;            # Inherits Sway support
stylixEnable = true;                 # Inherits theming
swwwEnable = true;                   # Inherits wallpaper daemon
TLP_ENABLE = true;                   # Battery management (DESK has false)
power-profiles-daemon_ENABLE = false; # TLP takes over (DESK has true)
START_CHARGE_THRESH_BAT0 = 75;       # Battery health
STOP_CHARGE_THRESH_BAT0 = 80;        # Battery health
wifiPowerSave = true;                # Power savings (DESK has false)
polkitEnable = true;                 # Inherits with laptop-specific rules
wireguardEnable = true;              # VPN support
appImageEnable = true;               # AppImage support
nextcloudEnable = true;              # Cloud sync
theme = "ashes";                     # Default laptop theme
wm = "plasma6";                      # Window manager
fileManager = "dolphin";             # File manager
```

### What LAPTOP_L15 Overrides from LAPTOP-base

```nix
# Machine-specific overrides
useRustOverlay = true;               # Rust development
hostname = "nixolaptopaku";
gpuType = "intel";
fuseAllowOther = false;              # More restrictive than DESK
pkiCertificates = [ ... ];           # Corporate certificates
sudoTimestampTimeoutMinutes = 180;   # Convenient sudo
homeBackupEnable = true;             # Automated backups
nfsClientEnable = true;              # NFS mounts (3 mounts)
servicePrinting = true;              # Printer support
lidSwitch = "ignore";                # Docked usage
systemNetworkToolsEnable = true;     # Advanced networking
sunshineEnable = true;               # Remote streaming
xboxControllerEnable = true;         # Controller support
developmentToolsEnable = true;       # Full dev suite
aichatEnable = true;                 # AI CLI tool
nixvimEnabled = true;                # Cursor-like IDE
userBasicPkgsEnable = true;          # Standard packages
zshinitContent = "... cyan ...";     # Cyan hostname
```

### What LAPTOP_YOGAAKU Overrides from LAPTOP-base

```nix
# Older hardware overrides
useRustOverlay = false;              # No Rust development
hostname = "nixosyogaaku";
bootMode = "bios";                   # Legacy BIOS boot
grubDevice = "/dev/sda";             # GRUB required for BIOS
gpuType = "intel";
kernelModules = ["cpufreq_powersave", "xpadneo"];
fuseAllowOther = false;
pkiCertificates = [];                # No certificates
homeBackupEnable = false;            # No backups
nfsClientEnable = false;             # NFS disabled
servicePrinting = false;             # No printer
systemNetworkToolsEnable = true;
sunshineEnable = false;              # No streaming (older hardware)
xboxControllerEnable = true;
developmentToolsEnable = true;       # Basic dev tools
theme = "io";                        # Different theme
dockerEnable = false;
virtualizationEnable = true;
qemuGuestAddition = true;            # ERROR: Should be false
userBasicPkgsEnable = true;
```

---

## Issues & Recommendations

### 🚨 Critical Issues

#### 1. YOGAAKU: Incorrect QEMU Guest Configuration
**File**: `profiles/LAPTOP_YOGAAKU-config.nix:147`
```nix
qemuGuestAddition = true; # VM
```

**Problem**: YOGAAKU is a physical laptop, not a VM. This should be `false`.

**Impact**: May install unnecessary QEMU guest tools, waste resources.

**Fix**:
```nix
qemuGuestAddition = false; # Physical laptop (not a VM)
```

#### 2. YOGAAKU: Placeholder Network IPs
**File**: `profiles/LAPTOP_YOGAAKU-config.nix:34-35`
```nix
ipAddress = "192.168.8.xxx";
wifiIpAddress = "192.168.8.xxx";
```

**Problem**: Network configuration incomplete.

**Impact**: Machine may not have stable IP addresses.

**Recommendation**: Either:
- Assign static IPs and update config
- Comment out if using DHCP
- Add comment explaining status

#### 3. YOGAAKU: Different NFS Server (Possibly Offline)
**File**: `profiles/LAPTOP_YOGAAKU-config.nix:47`
```nix
nfsClientEnable = false;
```

**NFS Server**: `192.168.8.80` (different from DESK/L15's `192.168.20.200`)

**Problem**: NFS is defined but disabled. Server IP differs from other machines.

**Recommendation**: Either:
- Remove NFS configuration entirely if not needed
- Update to use same NFS server as other machines
- Document why this machine uses different server

---

### ⚠️ Minor Issues

#### 4. L15: Missing LM Studio Flag
**File**: `profiles/LAPTOP_L15-config.nix`

**Observation**: L15 has full dev tools but doesn't explicitly set `lmstudioEnabled`.

**Impact**: Inherits `false` from defaults, LM Studio not available.

**Recommendation**: Explicitly set to `false` for clarity, or enable if needed.

#### 5. Inconsistent AI Tool Configuration
- DESK: Full AI suite (lmstudio, aichat, nixvim)
- L15: aichat + nixvim only (no lmstudio)
- YOGAAKU: None

**Recommendation**: Consider adding explicit comments explaining AI tool choices:
```nix
# AI Tools - Disabled (no GPU for local LLMs)
# aichatEnable = false;
# lmstudioEnabled = false;
```

---

## Configuration Size & Complexity

### Lines of Configuration

| Profile | Total Lines | Overrides | Percentage of Base |
|---------|------------|-----------|-------------------|
| **DESK** | 440 lines | Base profile | 100% |
| **LAPTOP-base** | 113 lines | +25% | 26% of DESK |
| **LAPTOP_L15** | 157 lines | +39 lines over base | 36% of DESK |
| **LAPTOP_YOGAAKU** | 163 lines | +50 lines over base | 37% of DESK |

**Key Insight**: Laptops achieve 60-70% code reuse through inheritance.

---

## Package Management Strategy

All three profiles follow the **centralized flag-based package management** pattern:

### System Packages
```nix
systemBasicToolsEnable = true;      # vim, wget, rsync, cryptsetup
systemNetworkToolsEnable = true;    # nmap, traceroute, dnsutils
```

### User Packages
```nix
userBasicPkgsEnable = true;         # browsers, office, communication
userAiPkgsEnable = true/false;      # lmstudio, ollama-rocm
```

### Profile-Specific Packages
- **DESK**: `clinfo` (OpenCL diagnostics)
- **L15**: `kdePackages.dolphin` (file manager)
- **YOGAAKU**: `tldr` (quick help)

**Benefits**:
- Minimal duplication
- Clear intent (flags describe purpose)
- Easy to maintain
- Consistent across profiles

---

## Use Case Summary

### DESK: Primary Workstation
**Best For**:
- Gaming (Steam, Star Citizen, emulators)
- AI/ML development (local LLMs with ROCm)
- Content creation (powerful GPU)
- Development (full IDE suite)
- Media server (Samba, NFS client)
- Home automation hub

**Hardware Requirements**:
- Powerful GPU (AMD RX 7800 XT)
- Multiple monitors
- Large storage (local + NFS)
- Always-on availability

---

### LAPTOP_L15: Modern Development Laptop
**Best For**:
- Software development (full dev tools + Rust)
- Remote work (Sunshine streaming, VPN)
- Mobile productivity (battery optimization)
- Professional use (certificates, printing)
- Cloud-connected work (NFS mounts)

**Hardware Requirements**:
- Modern Intel laptop
- Good battery life (75-80% charging)
- WiFi + wired networking
- Dockable (external monitors)

---

### LAPTOP_YOGAAKU: Older Backup Laptop
**Best For**:
- Basic development (older projects)
- Secondary machine
- Testing older hardware compatibility
- Portable backup machine

**Hardware Requirements**:
- Older laptop with BIOS boot
- Basic Intel GPU
- Limited storage
- Potentially offline (no active NFS)

**Current Status**: Possibly not in active use (no backups, disabled NFS, placeholder IPs).

---

## Migration Recommendations

### YOGAAKU Modernization Options

#### Option A: Keep as Minimal Backup
- Fix `qemuGuestAddition = false`
- Remove or update NFS configuration
- Keep backups disabled
- Keep printer disabled
- Keep development tools minimal

#### Option B: Retire Profile
- If machine is no longer used, archive configuration
- Move to `profiles/archive/LAPTOP_YOGAAKU-config.nix`
- Document retirement reason

#### Option C: Upgrade to Current Standards
- Update NFS server to match L15 (`192.168.20.200`)
- Enable backups
- Enable printer (if available)
- Assign static IPs
- Enable more development tools

**Recommendation**: Based on disabled features (backups, NFS, printer, streaming), this machine appears to be in **reduced use**. Consider Option A or B.

---

## Testing Checklist

When making changes to these profiles, verify:

### DESK Testing
- [ ] All 4 monitors detected and configured correctly
- [ ] AMD GPU works (check with `clinfo`)
- [ ] Gaming works (Steam, Lutris, Bottles)
- [ ] AI tools work (lmstudio, ollama with ROCm)
- [ ] NFS mounts accessible
- [ ] Samba shares available
- [ ] Sunshine streaming functional
- [ ] Sway + Plasma6 both work

### LAPTOP_L15 Testing
- [ ] TLP battery management active
- [ ] Battery charges stop at 80%
- [ ] NFS mounts accessible
- [ ] Lid close behavior correct (ignored when docked)
- [ ] Development tools work (Rust, nixvim, aichat)
- [ ] Sunshine streaming works
- [ ] Printer accessible
- [ ] Sway + Plasma6 both work
- [ ] WiFi power saving active

### LAPTOP_YOGAAKU Testing
- [ ] BIOS boot works (GRUB)
- [ ] Basic system functionality
- [ ] Development tools work
- [ ] Theme "io" applies correctly
- [ ] No unnecessary QEMU guest tools installed (after fixing)
- [ ] Sway + Plasma6 both work

---

## Summary

The three profiles demonstrate a well-designed inheritance hierarchy:

1. **DESK** provides the base desktop experience (Sway + Plasma6, theming, desktop services)
2. **LAPTOP-base** adds laptop-specific features (TLP, battery management, power savings)
3. **LAPTOP_L15** is a modern, fully-featured development laptop
4. **LAPTOP_YOGAAKU** is an older, minimal laptop with reduced features

**Code Reuse**: Laptops reuse 60-70% of configuration through inheritance
**Maintainability**: Centralized flag-based package management
**Flexibility**: Each profile can override exactly what it needs
**Consistency**: All three use same theming system, window manager options, and development patterns

**Key Takeaway**: The inheritance pattern successfully reduces duplication while maintaining flexibility for machine-specific needs.
