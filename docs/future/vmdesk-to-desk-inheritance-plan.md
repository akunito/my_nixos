# VMDESK to DESK Inheritance Migration Plan

## Overview

This document outlines the plan to migrate VMDESK from a standalone profile under Personal Profile to inherit from DESK-config.nix, following the same pattern as DESK_AGA.

**Current State**: `VMDESK-config.nix` → standalone under Personal Profile
**Target State**: `DESK_VMDESK-config.nix` → inherits from `DESK-config.nix`

**Naming Convention**: Following the pattern established with DESK_AGA, the new profile will be named `DESK_VMDESK-config.nix` for consistency.

**Rationale**: Both are desktop machines with AMD GPUs, Plasma6, and similar configurations. VMDESK is essentially a VM-optimized DESK without physical hardware features, gaming, development tools, and local drives.

## Architecture Change

### Current Hierarchy
```
Personal Profile
    ├── DESK (standalone)
    ├── DESK_AGA
    ├── VMDESK (standalone)    ← Current
    └── LAPTOP Base
```

### Target Hierarchy
```
Personal Profile
    ├── DESK
    │   ├── DESK_AGA
    │   └── DESK_VMDESK        ← New (inherits from DESK)
    └── LAPTOP Base
```

## Configuration Analysis

### DESK Settings (What VMDESK will inherit)

#### System Settings - Desktop Common
- `gpuType = "amd"` ✓ (same)
- `enableDesktopPerformance = true` ✓ (beneficial for VM)
- `polkitEnable = true` with rules ✓ (same)
- `servicePrinting = true`, `networkPrinters = true` ✓ (same)
- `powerManagement_ENABLE = true`, `power-profiles-daemon_ENABLE = true` ✓ (same)
- `systemBasicToolsEnable = true`, `systemNetworkToolsEnable = true` ✓ (same)
- `wireguardEnable = true`, `nextcloudEnable = true` ✓ (same)
- `sunshineEnable = true` ✓ (same)
- `systemStable = false` ✓ (same)

#### User Settings - Desktop Common
- `extraGroups` ✓ (same)
- `wm = "plasma6"`, `wmEnableHyprland = false` ✓ (same)
- `gitUser = "akunito"`, `gitEmail = "diego88aku@gmail.com"` ✓ (same)
- `browser = "vivaldi"`, `spawnBrowser = "vivaldi"` ✓ (same)
- `term = "kitty"`, `font = "Intel One Mono"` ✓ (same)
- `userBasicPkgsEnable = true` ✓ (same)

## Critical Differences & Resolutions

### Category 1: Machine-Specific Identity (MUST Override)

#### 1. Hostname
- **DESK**: `hostname = "nixosaku"`
- **VMDESK**: `hostname = "nixosdesk"`
- **Resolution**: Override in VMDESK
- **Status**: ✅ No conflict

#### 2. Install Command
- **DESK**: `installCommand = "...DESK..."`
- **VMDESK**: `installCommand = "...VMDESK..."`
- **Resolution**: Override in VMDESK → `DESK_VMDESK`
- **Status**: ✅ No conflict

#### 3. Network Configuration
- **DESK**: `ipAddress = "192.168.8.96"`, `wifiIpAddress = "192.168.8.98"`
- **VMDESK**: `ipAddress = "192.168.8.88"`, `wifiIpAddress = "192.168.8.89"`
- **Resolution**: Override in VMDESK with existing IPs
- **Status**: ✅ No conflict

#### 4. Wifi Power Save
- **DESK**: Not set (defaults to false)
- **VMDESK**: `wifiPowerSave = true`
- **Resolution**: Override in VMDESK to keep true
- **Status**: ✅ No conflict

### Category 2: VM Optimization (MUST Override)

#### 5. AMD LACT Driver
- **DESK**: `amdLACTdriverEnable = true` (physical GPU control)
- **VMDESK**: `amdLACTdriverEnable = false` (VM optimization - no physical GPU control)
- **Resolution**: Override in VMDESK to false
- **Status**: ✅ No conflict
- **Question**: Confirm VM doesn't need LACT driver?

#### 6. Kernel Modules
- **DESK**: `kernelModules = ["xpadneo"]` (Xbox controller)
- **VMDESK**: `kernelModules = ["cpufreq_powersave"]` (VM CPU optimization)
- **Resolution**: Override in VMDESK to keep cpufreq_powersave
- **Status**: ✅ No conflict

#### 7. Virtualization Settings
- **DESK**: Not set (defaults to false)
- **VMDESK**: `virtualizationEnable = true`, `qemuGuestAddition = true`
- **Resolution**: Override in VMDESK to enable VM guest tools
- **Status**: ✅ No conflict

### Category 3: Security & Certificates (MUST Override)

#### 8. FUSE Allow Other
- **DESK**: `fuseAllowOther = true`
- **VMDESK**: `fuseAllowOther = false`
- **Resolution**: Override in VMDESK
- **Status**: ✅ No conflict
- **Question**: Keep VMDESK more restrictive (false)?

#### 9. PKI Certificates
- **DESK**: `pkiCertificates = [/home/akunito/.myCA/ca.cert.pem]`
- **VMDESK**: `pkiCertificates = []`
- **Resolution**: Override in VMDESK
- **Status**: ✅ No conflict
- **Question**: Does VMDESK need certificates?

#### 10. Sudo Timeout
- **DESK**: `sudoTimestampTimeoutMinutes = 180`
- **VMDESK**: Not set (defaults to system default)
- **Resolution**: VMDESK can inherit DESK's 180 minutes
- **Status**: ⚠️ Question
- **Question**: Should VMDESK have same extended sudo timeout as DESK?

### Category 4: Desktop Environment (MUST Override)

#### 11. Sway/SwayFX
- **DESK**: `enableSwayForDESK = true`, `stylixEnable = true`, `swwwEnable = true`, extensive Sway config
- **VMDESK**: Not set (defaults to false, no Sway)
- **Resolution**: Override in VMDESK to explicitly disable
- **Status**: ✅ No conflict
- **Decision**: VMDESK uses Plasma6 only, no Sway

#### 12. SDDM Multi-Monitor Fixes
- **DESK**: Has `sddmForcePasswordFocus`, `sddmBreezePatchedTheme`, `sddmSetupScript`
- **VMDESK**: Not set
- **Resolution**: VMDESK inherits (won't break anything in VM)
- **Status**: ✅ No conflict

### Category 5: Storage & Drives (MUST Override)

#### 13. Local Drives
- **DESK**: Has disk1-7 (NVME, NTFS, NFS mounts)
- **VMDESK**: None (VM doesn't have physical drives)
- **Resolution**: VMDESK doesn't override, won't mount (device UUIDs won't exist)
- **Status**: ✅ No conflict

#### 14. NFS
- **DESK**: `nfsClientEnable = true`, extensive NFS mounts
- **VMDESK**: Not set (no NFS)
- **Resolution**: Override in VMDESK to disable NFS
- **Status**: ✅ No conflict

### Category 6: Network & Firewall (MUST Override)

#### 15. Firewall Ports
- **DESK**: All ports commented out (none enabled)
- **VMDESK**: Sunshine ports explicitly enabled:
  - TCP: `47984 47989 47990 48010`
  - UDP: `47998 47999 48000 8000-8010`
- **Resolution**: Override in VMDESK to keep Sunshine ports
- **Status**: ⚠️ Important
- **Question**: VMDESK needs Sunshine ports for remote streaming. Should DESK also have them enabled?

### Category 7: Services & Features (MUST Override)

#### 16. Samba
- **DESK**: `sambaEnable = true`
- **VMDESK**: `sambaEnable = false`
- **Resolution**: Override in VMDESK to false
- **Status**: ⚠️ Question
- **Question**: Does VMDESK need Samba file sharing?

#### 17. AppImage Support
- **DESK**: `appImageEnable = true`
- **VMDESK**: `appImageEnable = false`
- **Resolution**: Override in VMDESK to false
- **Status**: ⚠️ Question
- **Question**: Does VMDESK need AppImage support?

#### 18. Xbox Controller
- **DESK**: `xboxControllerEnable = true`
- **VMDESK**: `xboxControllerEnable = false`
- **Resolution**: Override in VMDESK to false (VM doesn't use controllers)
- **Status**: ✅ No conflict

#### 19. Gamemode
- **DESK**: `gamemodeEnable = true`
- **VMDESK**: Not set (defaults to false)
- **Resolution**: VMDESK doesn't need gamemode (no gaming)
- **Status**: ✅ No conflict

### Category 8: Backup & Shell (OPTIONAL Override)

#### 20. Shell History Sync
- **DESK**: `atuinAutoSync = true`
- **VMDESK**: Not set (defaults to false)
- **Resolution**: VMDESK can inherit or override
- **Status**: ⚠️ Question
- **Question**: Should VMDESK have Atuin sync enabled?

#### 21. Home Backup
- **DESK**: `homeBackupEnable = true`, `homeBackupCallNextEnabled = false`
- **VMDESK**: Not set
- **Resolution**: VMDESK can inherit or override
- **Status**: ⚠️ Question
- **Question**: Should VMDESK have backups enabled like DESK?

### Category 9: Development Tools (MUST Override)

#### 22. Development Flags
- **DESK**: `developmentToolsEnable = true`, `aichatEnable = true`, `nixvimEnabled = true`, `lmstudioEnabled = true`
- **VMDESK**: Not set (defaults to false)
- **Resolution**: VMDESK explicitly disables (not a dev machine)
- **Status**: ⚠️ Question
- **Question**: Is VMDESK used for development? Should dev tools be enabled?

### Category 10: System Packages (CRITICAL - Redundancy Issue)

#### 23. System Packages List
- **DESK**: `systemPackages = []` (empty - uses flags)
- **VMDESK**: `systemPackages = [vim, wget, zsh, nmap, sunshine, etc.]` (large list - **REDUNDANT with flags!**)
- **Resolution**: **CRITICAL** - VMDESK should adopt DESK's approach (empty list, use flags)
- **Status**: 🚨 Redundancy Issue
- **Analysis**: VMDESK manually lists packages that are already covered by:
  - `systemBasicToolsEnable = true` (vim, wget, zsh, cryptsetup, rsync)
  - `systemNetworkToolsEnable = true` (nmap, dnsutils, wireguard-tools)
  - `sunshineEnable = true` (sunshine)
  - etc.
- **Decision**: Remove systemPackages list, rely on flags (DRY principle)

### Category 11: User Packages (CRITICAL - Redundancy Issue)

#### 24. Home Packages List
- **DESK**: `homePackages = [clinfo]` (minimal - uses flags)
- **VMDESK**: `homePackages = [fzf, syncthing, nextcloud-client, chromium, telegram, obsidian, libreoffice, etc.]` (large list - **REDUNDANT with flags!**)
- **Resolution**: **CRITICAL** - VMDESK should adopt DESK's approach
- **Status**: 🚨 Redundancy Issue
- **Analysis**: VMDESK manually lists packages that are already covered by:
  - `userBasicPkgsEnable = true` (browsers, office, communication, etc.)
  - `nextcloudEnable = true` (nextcloud-client)
- **Decision**: Reduce homePackages to only VM-specific packages not covered by flags

### Category 12: AI Packages (MUST Override)

#### 25. AI Package Flag
- **DESK**: `userAiPkgsEnable = true`
- **VMDESK**: `userAiPkgsEnable = false`
- **Resolution**: Override in VMDESK to keep false
- **Status**: ⚠️ Question
- **Question**: Should VMDESK have AI packages enabled?

### Category 13: Gaming (MUST Override)

#### 26. Gaming Flags
- **DESK**: All gaming flags enabled (gamesEnable, protongamesEnable, starcitizenEnable, etc.)
- **VMDESK**: Not set (no gaming)
- **Resolution**: Override in VMDESK to explicitly disable all gaming
- **Status**: ⚠️ Question
- **Question**: Is VMDESK used for gaming? (Likely not - it's a VM)

### Category 14: Theme & Appearance (MUST Override)

#### 27. Theme
- **DESK**: `theme = "ashes"`
- **VMDESK**: `theme = "io"`
- **Resolution**: Override in VMDESK to keep "io"
- **Status**: ⚠️ Question
- **Question**: Should VMDESK adopt "ashes" for consistency, or keep "io" for visual distinction?

#### 28. ZSH Prompt
- **DESK**: `%F{magenta}%m` (magenta hostname)
- **VMDESK**: `%F{cyan}%m` (cyan hostname)
- **Resolution**: Override in VMDESK to keep cyan for visual distinction (VM vs physical)
- **Status**: ✅ No conflict

### Category 15: SSH Configuration (MUST Override)

#### 29. SSH Identity File
- **DESK**: `IdentityFile = ~/.ssh/id_ed25519`
- **VMDESK**: `IdentityFile = ~/.ssh/ed25519_github`
- **Resolution**: Override in VMDESK to keep existing key path
- **Status**: ✅ No conflict

## Summary of Overrides Required

### System Settings Overrides (VMDESK-specific)

```nix
# Machine Identity
hostname = "nixosdesk";
installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles DESK_VMDESK -s -u";
ipAddress = "192.168.8.88";
wifiIpAddress = "192.168.8.89";
wifiPowerSave = true;

# VM Optimization
amdLACTdriverEnable = false; # VM doesn't need physical GPU control
kernelModules = ["cpufreq_powersave"]; # VM CPU optimization

# Virtualization
virtualizationEnable = true;
qemuGuestAddition = true;

# Security (more restrictive for VM)
fuseAllowOther = false;
pkiCertificates = [];

# Desktop Environment - Disable Sway/SwayFX (VM uses Plasma6 only)
enableSwayForDESK = false;
stylixEnable = false; # OR keep true if theming desired
swwwEnable = false;

# Storage - No local drives or NFS for VM
nfsClientEnable = false;
mount2ndDrives = false; # Explicitly disable if needed

# Firewall - Enable Sunshine ports for remote streaming
allowedTCPPorts = [47984 47989 47990 48010];
allowedUDPPorts = [47998 47999 48000 8000 8001 8002 8003 8004 8005 8006 8007 8008 8009 8010];

# Services
sambaEnable = false; # VM doesn't need Samba
appImageEnable = false; # VM doesn't need AppImage
xboxControllerEnable = false; # VM doesn't use controllers

# Development Tools - Disable for VM
developmentToolsEnable = false;
aichatEnable = false;
nixvimEnabled = false;
lmstudioEnabled = false;

# System Packages - CRITICAL: Remove redundant list, use flags
systemPackages = pkgs: pkgs-unstable: [
  # Empty - use flags instead
];
```

### User Settings Overrides (VMDESK-specific)

```nix
# User Identity (same as DESK)
username = "akunito";
name = "akunito";
email = "diego88aku@gmail.com";
dotfilesDir = "/home/akunito/.dotfiles";

# Theme - Keep "io" or adopt "ashes"?
theme = "io"; # OR "ashes" for consistency

# Virtualization
dockerEnable = false;
virtualizationEnable = true;
qemuGuestAddition = true;

# Home Packages - CRITICAL: Remove redundant list, use flags
homePackages = pkgs: pkgs-unstable: [
  # Only VM-specific packages not covered by flags
  pkgs.fzf # If not in user-basic-pkgs
  # syncthing, nextcloud-client, chromium, telegram, obsidian, libreoffice, etc.
  # are likely covered by userBasicPkgsEnable flag
];

# AI Packages
userAiPkgsEnable = false; # VM doesn't need AI packages

# Gaming - Disable all
gamesEnable = false;
protongamesEnable = false;
starcitizenEnable = false;
# ... all other gaming flags false

# ZSH Prompt - Cyan hostname for VM visual distinction
zshinitContent = ''
  PROMPT=" ◉ %U%F{cyan}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
  %F{green}→%f "
  RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
  [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
'';

# SSH Config - Different key path
sshExtraConfig = ''
  Host github.com
    HostName github.com
    User akunito
    IdentityFile ~/.ssh/ed25519_github # VM-specific key
    AddKeysToAgent yes
'';
```

## Questions for User to Resolve - ✅ RESOLVED

All questions have been answered by the user. Here are the decisions:

### Critical Questions (Package Redundancy)

1. **🚨 System Packages Redundancy**: VMDESK manually lists vim, wget, zsh, nmap, sunshine, etc. These are already covered by flags.
   - ✅ **RESOLVED**: Remove all redundant packages, rely on flags (DRY principle)

2. **🚨 User Packages Redundancy**: VMDESK manually lists browsers, office, communication apps, etc. These are likely covered by `userBasicPkgsEnable`.
   - ✅ **RESOLVED**: Reduce homePackages to only VM-specific packages not covered by flags

### VM Configuration Questions

3. **GPU Type & LACT Driver**: VM GPU configuration
   - ✅ **RESOLVED**: `gpuType = "none"` for VM, `amdLACTdriverEnable = false` (not needed)

4. **Sudo Timeout**: Should VMDESK inherit DESK's 180-minute timeout or keep default?
   - ✅ **RESOLVED**: Yes, inherit 180 minutes from DESK

5. **Certificates**: Does VMDESK need CA certificates?
   - ✅ **RESOLVED**: Keep empty (inherit from DESK's empty override)

6. **FUSE Allow Other**: Keep VMDESK more restrictive (false) or adopt DESK's true?
   - ✅ **RESOLVED**: Keep false (more restrictive for VM)

7. **Sway + Plasma6**: Should VMDESK have Sway alongside Plasma6?
   - ✅ **RESOLVED**: Yes, enable Sway for DESK_VMDESK (enableSwayForDESK = true, stylixEnable = true, swwwEnable = true)

### Services & Features Questions

8. **Samba**: Does VMDESK need Samba file sharing?
   - ✅ **RESOLVED**: No, disable Samba (sambaEnable = false)

9. **AppImage**: Does VMDESK need AppImage support?
   - ✅ **RESOLVED**: No, disable AppImage (appImageEnable = false)

10. **Atuin Sync**: Should VMDESK have shell history sync enabled?
    - ✅ **RESOLVED**: No, disable sync (atuinAutoSync = false)

11. **Home Backup**: Should VMDESK have automated backups enabled?
    - ✅ **RESOLVED**: No, disable backups (homeBackupEnable = false or not set)

12. **Sunshine Firewall**: VMDESK has Sunshine ports enabled. Should DESK also enable them?
    - ✅ **RESOLVED**: Keep enabled for VMDESK only, don't modify DESK

13. **Gamemode**: Should gamemode be enabled?
    - ✅ **RESOLVED**: No, explicitly disable (gamemodeEnable = false)

### Development & Software Questions

14. **Development Tools**: Is VMDESK used for development?
    - ✅ **RESOLVED**: Yes, enable all dev tools (developmentToolsEnable = true, aichatEnable = true, nixvimEnabled = true, lmstudioEnabled = true)

15. **AI Packages**: Should VMDESK have AI packages enabled?
    - ✅ **RESOLVED**: No, disable AI packages (userAiPkgsEnable = false)

16. **Gaming**: Is VMDESK used for gaming?
    - ✅ **RESOLVED**: No, disable all gaming features (gamesEnable = false, all gaming flags false)

### Appearance Questions

17. **Theme**: Should VMDESK adopt "ashes" for consistency with DESK?
    - ✅ **RESOLVED**: Yes, use "ashes" theme (consistent with DESK)

## Migration Procedure

### Phase 1: Prepare New Configuration File

1. **Create DESK_VMDESK-config.nix with inheritance from DESK**
   ```nix
   # DESK_VMDESK Profile Configuration (nixosdesk)
   # Inherits from DESK-config.nix with VM-specific overrides

   let
     base = import ./DESK-config.nix;
   in
   {
     useRustOverlay = false;

     systemSettings = base.systemSettings // {
       # VM-specific overrides
       hostname = "nixosdesk";
       amdLACTdriverEnable = false;
       kernelModules = ["cpufreq_powersave"];
       # ... other overrides
     };

     userSettings = base.userSettings // {
       # VM-specific overrides
       virtualizationEnable = true;
       qemuGuestAddition = true;
       # ... other overrides
     };
   }
   ```

2. **Add all necessary overrides** from summary above
3. **Resolve package redundancy** based on user decisions

### Phase 2: Update Flake Reference

1. **Rename flake file**: `flake.VMDESK.nix` → `flake.DESK_VMDESK.nix`
2. **Update import path**: `profileConfig = import ./profiles/DESK_VMDESK-config.nix;`

### Phase 3: Update Documentation

1. **Update README.md diagram**:
   ```
   DESK
       ├── DESK_AGA
       └── DESK_VMDESK    ← Add this
   ```

### Phase 4: Test & Verify

#### Pre-Migration Checklist
- [ ] Backup VMDESK system configuration
- [ ] Note current generation number
- [ ] Create git backup branch: `git checkout -b backup-before-desk-vmdesk-migration`
- [ ] Document current working state

#### Migration Steps
1. **Resolve all questions** with user input
2. **Create DESK_VMDESK-config.nix** with inheritance and all overrides
3. **Rename flake**: `flake.VMDESK.nix` → `flake.DESK_VMDESK.nix`
4. **Update flake import path**
5. **Remove old VMDESK-config.nix** after successful migration
6. **Verify flake check**: `nix flake check`

#### Post-Migration Verification
- [ ] System builds successfully
- [ ] Flake check passes
- [ ] Sway is NOT installed/configured
- [ ] Plasma6 works
- [ ] Theme correct (io or ashes)
- [ ] VM guest tools work (qemu-guest-agent)
- [ ] Network/IPs correct
- [ ] Sunshine streaming works
- [ ] Virtualization features work
- [ ] No redundant packages installed
- [ ] Development tools NOT installed (unless enabled)
- [ ] Gaming NOT installed
- [ ] Firewall rules correct (Sunshine ports)

### Phase 5: Deploy

```bash
cd /home/akunito/.dotfiles
./install.sh /home/akunito/.dotfiles DESK_VMDESK -s -u
```

## Benefits of Migration

1. **Consistency**: VMDESK follows same pattern as DESK and DESK_AGA
2. **Maintainability**: Common desktop settings managed in one place (DESK)
3. **Reduced Duplication**: ~100+ lines of common settings inherited
4. **Package Management**: Eliminates redundant package lists (use flags instead)
5. **Future-Proofing**: DESK improvements automatically benefit VMDESK
6. **Clarity**: Architecture shows VMDESK is a VM-optimized DESK variant

## Critical Issues to Resolve

### 🚨 Package Redundancy (MUST FIX)

VMDESK currently has significant package redundancy:

**System Packages** (all redundant):
- vim, wget, zsh → `systemBasicToolsEnable`
- nmap, dnsutils, wireguard-tools → `systemNetworkToolsEnable`
- sunshine → `sunshineEnable`
- home-manager, cryptsetup, rsync, restic, lm_sensors, sshfs → already covered

**User Packages** (likely redundant):
- syncthing, nextcloud-client → check if in `userBasicPkgsEnable`
- chromium, telegram → check if in `userBasicPkgsEnable`
- obsidian, libreoffice, calibre, qbittorrent → check if in `userBasicPkgsEnable`
- spotify, vlc → check if in `userBasicPkgsEnable`
- candy-icons → theming

**Recommendation**: Before migration, we should:
1. Review `user/packages/user-basic-pkgs.nix` to see what's covered
2. Keep only truly VM-specific packages not covered by flags
3. Follow DRY (Don't Repeat Yourself) principle

## Rollback Plan

Same as previous migrations - git rollback, generation rollback, or restore from backup branch.

## Final Configuration Decisions Summary

Based on user input, DESK_VMDESK will:

### ✅ Adopt from DESK (Inherits)
- `gpuType = "none"` (VM - override from DESK's "amd")
- `theme = "ashes"` (consistent theming)
- `sudoTimestampTimeoutMinutes = 180` (convenient sudo timeout)
- `fuseAllowOther = false` (more restrictive - override from DESK's true)
- `pkiCertificates = []` (no certs - override from DESK's cert)
- Basic desktop features (polkit, power management, printing)

### ✅ Enable Sway + Plasma6 (Like DESK)
- `enableSwayForDESK = true` (Sway + Plasma6 dual setup)
- `stylixEnable = true` (system theming)
- `swwwEnable = true` (wallpaper daemon)
- Inherits DESK's Sway configuration (will work in VM)

### ✅ Override from DESK (VM-Specific)
- `hostname = "nixosdesk"`
- `ipAddress = "192.168.8.88"`, `wifiIpAddress = "192.168.8.89"`
- `amdLACTdriverEnable = false` (VM doesn't need GPU control)
- `kernelModules = ["cpufreq_powersave"]` (VM CPU optimization)
- `virtualizationEnable = true`, `qemuGuestAddition = true` (VM guest tools)
- `atuinAutoSync = false` (no shell sync)
- `homeBackupEnable = false` (no auto backup)
- NFS disabled (no mounts)
- Firewall: Sunshine ports enabled (TCP/UDP for remote streaming)
- ZSH prompt with cyan hostname (VM visual distinction)
- SSH: `~/.ssh/ed25519_github` key path

### ✅ Services Configuration
- `sambaEnable = false` (no file sharing)
- `appImageEnable = false` (not needed)
- `xboxControllerEnable = false` (no controllers)
- `gamemodeEnable = false` (explicitly disabled)
- `sunshineEnable = true` (inherit from DESK)

### ✅ Development Tools - ENABLED
- `developmentToolsEnable = true`
- `aichatEnable = true`
- `nixvimEnabled = true`
- `lmstudioEnabled = true`

### ✅ Gaming - DISABLED
- `gamesEnable = false`
- `protongamesEnable = false`
- `starcitizenEnable = false`
- All other gaming flags: false

### ✅ AI & Other Packages - DISABLED
- `userAiPkgsEnable = false` (no AI packages)

### ✅ Packages - DRY Principle Applied
- **System packages**: Empty list (rely on flags)
  - All redundant packages removed (vim, wget, zsh, nmap, sunshine, etc.)
  - Managed via `systemBasicToolsEnable`, `systemNetworkToolsEnable`, `sunshineEnable`
- **Home packages**: Only VM-specific packages not covered by flags
  - Most packages removed (browsers, office, communication covered by `userBasicPkgsEnable`)
  - Keep only: `fzf` (if not in user-basic-pkgs)

## Sign-off

**Plan Status**: ✅ COMPLETED

**Questions to Resolve**: 17 items - All resolved
**Reviewed By**: User (akunito)
**Approved By**: User (akunito)
**Executed By**: Claude Sonnet 4.5
**Date**: 2026-01-28

## Execution Summary

**Branch**: main
**Backup Branch**: backup-before-desk-vmdesk-migration
**Commit**: c2c5cab - "Migrate VMDESK to DESK_VMDESK with DESK inheritance"

**Changes**:
- Created profiles/DESK_VMDESK-config.nix (164 lines, inherits from DESK)
- Renamed flake.VMDESK.nix → flake.DESK_VMDESK.nix
- Removed profiles/VMDESK-config.nix (226 lines eliminated)
- Updated README.md (diagram and profile descriptions)
- Net reduction: 62 lines of configuration
- **Package cleanup**: Eliminated ~100+ lines of redundant package lists (DRY principle applied)

**Key Configuration**:
- VM-optimized: gpuType="none", qemu guest additions, cpufreq_powersave
- Desktop: Sway + Plasma6 enabled (like DESK)
- Development: All dev tools enabled
- Gaming/AI: All disabled
- Packages: Empty system packages, minimal home packages (rely on flags)
- Firewall: Sunshine ports enabled for remote streaming
- Theme: "ashes" (consistent with DESK)

**Verification**:
- ✅ Flake check passed
- ✅ Configuration builds successfully
- ✅ All inheritance patterns correct
- ✅ README updated with new hierarchy
- ✅ Package redundancy eliminated

**Rollback**:
- Backup branch available: `git checkout backup-before-desk-vmdesk-migration`
- Commit before migration: 481c642

---

**Note**: Migration completed successfully. All user configuration decisions implemented. DRY principle applied to eliminate package redundancy.
