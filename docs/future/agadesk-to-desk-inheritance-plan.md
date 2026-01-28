# AGADESK to DESK Inheritance Migration Plan

## Overview

This document outlines the plan to migrate AGADESK from a standalone profile under Personal Profile to inherit from DESK-config.nix, following the same pattern as LAPTOP profiles inherit from LAPTOP-base.nix.

**Current State**: `AGADESK-config.nix` → standalone under Personal Profile
**Target State**: `DESK_AGA-config.nix` → inherits from `DESK-config.nix`

**Naming Convention**: Following the pattern established with LAPTOP profiles (LAPTOP_L15, LAPTOP_YOGAAKU, LAPTOP_AGA), the new profile will be named `DESK_AGA-config.nix` for consistency.

**Rationale**: Both are desktop machines with AMD GPUs, gaming setups, and similar configurations. AGADESK is essentially a simplified DESK without multi-monitor setup and development tools.

## Architecture Change

### Current Hierarchy
```
Personal Profile
    ├── DESK (standalone)
    ├── AGADESK (standalone)    ← Current
    └── LAPTOP Base
```

### Target Hierarchy
```
Personal Profile
    ├── DESK
    │   └── DESK_AGA           ← New (inherits from DESK)
    └── LAPTOP Base
```

## Configuration Analysis

### DESK Settings (What AGADESK will inherit)

#### System Settings - Desktop Common
- `gpuType = "amd"` ✓ (same)
- `enableDesktopPerformance = true` ✓ (same)
- `amdLACTdriverEnable = true` ✓ (same)
- `kernelModules = [ "xpadneo" ]` ✓ (same)
- `polkitEnable = true` with rules ✓ (same)
- `servicePrinting = true`, `networkPrinters = true` ✓ (same)
- `powerManagement_ENABLE = true`, `power-profiles-daemon_ENABLE = true` ✓ (same)
- `systemBasicToolsEnable = true`, `systemNetworkToolsEnable = true` ✓ (same)
- `sambaEnable = true`, `sunshineEnable = true`, `wireguardEnable = true` ✓ (same)
- `nextcloudEnable = true`, `appImageEnable = true`, `xboxControllerEnable = true` ✓ (same)
- `gamemodeEnable = true` ✓ (same)
- `systemStable = false` ✓ (same)
- NFS mounts (disk3, disk4, disk5) ✓ (same targets, different options)

#### User Settings - Desktop Common
- `extraGroups` ✓ (same)
- `wm = "plasma6"`, `wmEnableHyprland = false` ✓ (same)
- `gitUser = "akunito"`, `gitEmail = "diego88aku@gmail.com"` ✓ (same)
- `browser = "vivaldi"`, `spawnBrowser = "vivaldi"` ✓ (same)
- `term = "kitty"`, `font = "Intel One Mono"` ✓ (same)
- `fileManager = "dolphin"` ✓ (same)
- `userBasicPkgsEnable = true` ✓ (same)
- `gamesEnable = true` ✓ (same)

## Critical Differences & Resolutions

### Category 1: Machine-Specific Identity (MUST Override)

#### 1. Hostname
- **DESK**: `hostname = "nixosaku"`
- **AGADESK**: `hostname = "nixosaga"`
- **Resolution**: Override in AGADESK

#### 2. Install Command
- **DESK**: `installCommand = "...DESK..."`
- **AGADESK**: `installCommand = "...AGADESK..."`
- **Resolution**: Override in AGADESK

#### 3. Network Configuration
- **DESK**: `ipAddress = "192.168.8.96"`, `wifiIpAddress = "192.168.8.98"`
- **AGADESK**: `ipAddress = "192.168.8.xxx"`, `wifiIpAddress = "192.168.8.xxx"` (placeholders)
- **Resolution**: Override in AGADESK with actual IPs

#### 4. SSH Authorized Keys
- **DESK**: 2 keys (ed25519 only)
- **AGADESK**: 3 keys (includes RSA key)
- **Resolution**: Override in AGADESK to keep all 3 keys

### Category 2: User Identity (MUST Override)

#### 5. Username
- **DESK**: `username = "akunito"`
- **AGADESK**: `username = "aga"`
- **Resolution**: Override in AGADESK

#### 6. User Name
- **DESK**: `name = "akunito"`
- **AGADESK**: `name = "aga"`
- **Resolution**: Override in AGADESK

#### 7. Dotfiles Directory
- **DESK**: `dotfilesDir = "/home/akunito/.dotfiles"`
- **AGADESK**: `dotfilesDir = "/home/aga/.dotfiles"`
- **Resolution**: Override in AGADESK

### Category 3: Security & Certificates (MUST Override)

#### 8. Rust Overlay
- **DESK**: `useRustOverlay = false`
- **AGADESK**: `useRustOverlay = true`
- **Resolution**: Override in AGADESK
- **Question**: Does AGADESK actually need rust-overlay? If not, can adopt DESK's false.

#### 9. FUSE Allow Other
- **DESK**: `fuseAllowOther = true`
- **AGADESK**: `fuseAllowOther = false`
- **Resolution**: Override in AGADESK
- **Question**: Why is DESK true and AGADESK false? Security preference?

#### 10. PKI Certificates
- **DESK**: `pkiCertificates = [ /home/akunito/.myCA/ca.cert.pem ]`
- **AGADESK**: `pkiCertificates = [ ]`
- **Resolution**: Override in AGADESK
- **Question**: Does AGADESK need certificates? If not, keep override.

#### 11. Sudo Timeout
- **DESK**: `sudoTimestampTimeoutMinutes = 180`
- **AGADESK**: Not set (defaults to system default)
- **Resolution**: AGADESK can inherit DESK's 180 minutes
- **Question**: Should AGADESK have same extended sudo timeout as DESK?

### Category 4: Drives & Storage (MUST Override)

#### 12. Local Drives
- **DESK**: Has disk1 (/mnt/2nd_NVME, encrypted), disk2 (NTFS), disk6 (NTFS), disk7 (disabled)
- **AGADESK**: No local drives beyond system
- **Resolution**: AGADESK doesn't override, won't mount DESK's drives (device UUIDs won't match)

#### 13. NFS Mount Options
- **DESK**: Detailed options `"noatime,rsize=1048576,wsize=1048576,nfsvers=4.2,tcp,hard,intr,timeo=600"`
- **AGADESK**: Simple options `"noatime"`
- **Resolution**: Override in AGADESK to keep simple options
- **Question**: Would AGADESK benefit from DESK's optimized NFS settings?

### Category 5: Desktop Environment (MUST Override)

#### 14. Sway/SwayFX & Monitors
- **DESK**: Extensive Sway/SwayFX setup with 4-monitor configuration, kanshi profiles
- **AGADESK**: No Sway, only Plasma6
- **Resolution**: Override in AGADESK:
  - `enableSwayForDESK = false`
  - `stylixEnable = false` (or keep true if using Stylix)
  - `swwwEnable = false`
  - No monitor config needed

#### 15. SDDM Multi-Monitor Fixes
- **DESK**: Has `sddmForcePasswordFocus`, `sddmBreezePatchedTheme`, `sddmSetupScript` for portrait monitor
- **AGADESK**: Doesn't set these
- **Resolution**: AGADESK doesn't override, inherits DESK's settings (won't break anything if monitors don't match)

### Category 6: Backup & Shell (OPTIONAL Override)

#### 16. Shell History Sync
- **DESK**: `atuinAutoSync = true`
- **AGADESK**: Not set (defaults to false)
- **Resolution**: AGADESK inherits true (better consistency)
- **Question**: Should AGADESK have Atuin sync enabled?

#### 17. Home Backup
- **DESK**: `homeBackupEnable = true`, `homeBackupCallNextEnabled = false`
- **AGADESK**: Not set
- **Resolution**: AGADESK inherits backup settings
- **Question**: Should AGADESK have backups enabled like DESK?

### Category 7: Development Tools (MUST Override)

#### 18. Development Flags
- **DESK**: `developmentToolsEnable = true`, `aichatEnable = true`, `nixvimEnabled = true`, `lmstudioEnabled = true`
- **AGADESK**: All not set (defaults to false)
- **Resolution**: Override in AGADESK to explicitly disable:
  - `developmentToolsEnable = false`
  - `aichatEnable = false`
  - `nixvimEnabled = false`
  - `lmstudioEnabled = false`

### Category 8: System Packages (MUST Override)

#### 19. Python Package
- **DESK**: `systemPackages = [ ]` (empty)
- **AGADESK**: `systemPackages = [ pkgs.python313Full ]`
- **Resolution**: Override in AGADESK to keep python313Full

### Category 9: User Packages (MUST Override)

#### 20. Home Packages
- **DESK**: `[ pkgs.clinfo ]`
- **AGADESK**: `[ pkgs-unstable.kdePackages.kcalc, pkgs.clinfo, pkgs.kdePackages.dolphin ]`
- **Resolution**: Override in AGADESK to keep kcalc and dolphin (clinfo can be inherited or kept)

### Category 10: Theme & Appearance (MUST Override)

#### 21. Theme
- **DESK**: `theme = "ashes"`
- **AGADESK**: `theme = "miramare"`
- **Resolution**: Override in AGADESK to keep miramare
- **Question**: Should AGADESK use same theme as DESK (ashes)?

#### 22. ZSH Prompt
- **DESK**: `%F{magenta}%m` (magenta hostname)
- **AGADESK**: `%F{blue}%m` (blue hostname)
- **Resolution**: Override in AGADESK to keep blue hostname for visual distinction

### Category 11: Gaming Flags (MUST Override)

#### 23. Gaming Package Flags
- **DESK**: Has all gaming flags enabled (protongamesEnable, starcitizenEnable, GOGlauncherEnable, dolphinEmulatorPrimehackEnable, rpcs3Enable)
- **AGADESK**: Only has `gamesEnable = true` and `steamPackEnable = true`
- **Resolution**: Override in AGADESK to explicitly disable unwanted gaming packages:
  - `protongamesEnable = false`
  - `starcitizenEnable = false`
  - `GOGlauncherEnable = false`
  - `dolphinEmulatorPrimehackEnable = false`
  - `rpcs3Enable = false`
  - Keep: `gamesEnable = true`, `steamPackEnable = true`

### Category 12: AI Packages (MUST Override)

#### 24. AI Package Flag
- **DESK**: `userAiPkgsEnable = true`
- **AGADESK**: `userAiPkgsEnable = false`
- **Resolution**: Override in AGADESK to keep false

### Category 13: Other Features (MUST Override)

#### 25. Star Citizen Modules
- **DESK**: Not explicitly set (defaults to false in flags, but starcitizenEnable = true)
- **AGADESK**: `starCitizenModules = false`
- **Resolution**: Keep override in AGADESK (explicit false)

#### 26. Vivaldi Patch
- **DESK**: Not explicitly set
- **AGADESK**: `vivaldiPatch = false`
- **Resolution**: Keep override in AGADESK

#### 27. Wifi Power Save
- **DESK**: Not explicitly set (desktop likely wired)
- **AGADESK**: `wifiPowerSave = true`
- **Resolution**: Keep override in AGADESK

#### 28. Resolved Enable
- **DESK**: `resolvedEnable = false`
- **AGADESK**: `resolvedEnable = false`
- **Resolution**: Same ✓

## Summary of Overrides Required

### System Settings Overrides (AGADESK-specific)
```nix
hostname = "nixosaga";
installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles AGADESK -s -u";
ipAddress = "192.168.8.xxx";  # Actual IP
wifiIpAddress = "192.168.8.xxx";  # Actual IP
wifiPowerSave = true;
authorizedKeys = [ /* 3 keys including RSA */ ];

# Disable Sway/SwayFX (AGADESK uses Plasma6 only)
enableSwayForDESK = false;
swwwEnable = false;
# stylixEnable = false;  # IF you want to disable Stylix

# NFS: Keep simple mount options
nfsMounts = [ /* simpler options */ ];

# Development: Explicitly disable
developmentToolsEnable = false;
aichatEnable = false;
nixvimEnabled = false;
lmstudioEnabled = false;

# System packages: Add Python
systemPackages = pkgs: pkgs-unstable: [
  pkgs.python313Full
];

# Other flags
starCitizenModules = false;
vivaldiPatch = false;
```

### User Settings Overrides (AGADESK-specific)
```nix
username = "aga";
name = "aga";
dotfilesDir = "/home/aga/.dotfiles";

theme = "miramare";  # Or adopt "ashes" from DESK

# Home packages: Add calculator and Dolphin
homePackages = pkgs: pkgs-unstable: [
  pkgs-unstable.kdePackages.kcalc
  pkgs.clinfo
  pkgs.kdePackages.dolphin
];

# AI: Disable
userAiPkgsEnable = false;

# Gaming: Limited set
protongamesEnable = false;
starcitizenEnable = false;
GOGlauncherEnable = false;
dolphinEmulatorPrimehackEnable = false;
rpcs3Enable = false;
# Keep: gamesEnable = true, steamPackEnable = true

# ZSH: Blue hostname
zshinitContent = ''
  PROMPT=" ◉ %U%F{magenta}%n%f%u@%U%F{blue}%m%f%u:%F{yellow}%~%f
  %F{green}→%f "
  ...
'';
```

### Optionally Review/Simplify
- `useRustOverlay = true` - Does AGADESK need this?
- `fuseAllowOther = false` - Why different from DESK?
- `pkiCertificates = []` - Does AGADESK need certs?
- `sudoTimestampTimeoutMinutes` - Should inherit 180 from DESK?
- `atuinAutoSync` - Should AGADESK have shell sync?
- `homeBackupEnable` - Should AGADESK have backups?
- NFS mount options - Should use DESK's optimized settings?

## Migration Procedure

### Phase 1: Prepare New Configuration File

1. **Create DESK_AGA-config.nix with inheritance from DESK**
   ```nix
   # DESK_AGA Profile Configuration (nixosaga)
   # Inherits from DESK-config.nix with machine-specific overrides

   let
     base = import ./DESK-config.nix;
   in
   {
     useRustOverlay = true;  # Override if needed

     systemSettings = base.systemSettings // {
       # Machine-specific overrides
       hostname = "nixosaga";
       installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles DESK_AGA -s -u";
       ipAddress = "...";
       # ... other overrides
     };

     userSettings = base.userSettings // {
       # User-specific overrides
       username = "aga";
       name = "aga";
       dotfilesDir = "/home/aga/.dotfiles";
       # ... other overrides
     };
   }
   ```

2. **Add all necessary overrides** from summary above

### Phase 2: Update Flake Reference

1. **Rename flake file**: `flake.AGADESK.nix` → `flake.DESK_AGA.nix`
   ```bash
   git mv flake.AGADESK.nix flake.DESK_AGA.nix
   ```

2. **Update flake.DESK_AGA.nix import path**:
   ```nix
   profileConfig = import ./profiles/DESK_AGA-config.nix;  # Updated path
   ```

### Phase 3: Update Documentation

1. **Update README.md diagram**:
   ```
   DESK
       └── DESK_AGA    ← Add this
   ```

2. **Update profile documentation** to reflect DESK_AGA inherits from DESK

### Phase 4: Test & Verify

#### Pre-Migration Checklist
- [ ] Backup AGADESK system configuration
- [ ] Note current generation number
- [ ] Create git backup branch: `git checkout -b backup-before-desk-aga-migration`
- [ ] Document current working state

#### Migration Steps
1. **Create DESK_AGA-config.nix** with inheritance and all overrides
2. **Rename flake**: `flake.AGADESK.nix` → `flake.DESK_AGA.nix`
3. **Update flake import path** to point to DESK_AGA-config.nix
4. **Remove old AGADESK-config.nix** after successful migration
5. **Verify flake check**: `nix flake check`
6. **Test build**: `nix build .#nixosConfigurations.system.config.system.build.toplevel`

#### Post-Migration Verification
- [ ] System builds successfully
- [ ] Flake check passes
- [ ] Sway is NOT installed/configured
- [ ] Plasma6 works
- [ ] Theme is "miramare" (or "ashes" if changed)
- [ ] Username "aga" correct
- [ ] Network IPs correct
- [ ] NFS mounts work
- [ ] Python313Full installed
- [ ] Steam works
- [ ] Home packages correct (kcalc, dolphin, clinfo)
- [ ] Development tools NOT installed
- [ ] AI packages NOT installed
- [ ] Advanced gaming (Lutris, etc.) NOT installed

### Phase 5: Deploy

```bash
cd /home/aga/.dotfiles
./install.sh /home/aga/.dotfiles DESK_AGA -s -u
```

## Questions for User to Resolve - ✓ RESOLVED

Before implementation, please clarify:

1. **useRustOverlay = true** - Does AGADESK actually need Rust overlay? Can we use false like DESK?
   - ✅ **RESOLVED**: Use `false` (follow DESK)

2. **fuseAllowOther = false** - Why is AGADESK false while DESK is true? Security preference or no need?
   - ✅ **RESOLVED**: Keep `false` (DESK_AGA override)

3. **pkiCertificates = []** - Does AGADESK need CA certificates? Can stay empty?
   - ✅ **RESOLVED**: Keep `[]` (empty - no certificates needed)

4. **sudoTimestampTimeoutMinutes** - Should AGADESK inherit DESK's 180-minute timeout for convenience?
   - ✅ **RESOLVED**: Inherit from DESK (180 minutes)

5. **atuinAutoSync = true** - Should AGADESK have shell history sync enabled like DESK?
   - ✅ **RESOLVED**: Override to `false` for DESK_AGA

6. **homeBackupEnable = true** - Should AGADESK have automated backups enabled like DESK?
   - ✅ **RESOLVED**: Don't enable (not needed for DESK_AGA)

7. **NFS mount options** - Should AGADESK use DESK's optimized NFS settings (rsize=1048576, wsize=1048576, etc.) or keep simple "noatime"?
   - ✅ **RESOLVED**: Disable NFS completely for DESK_AGA (no NFS mounts)

8. **theme = "miramare"** - Keep AGADESK's theme or adopt DESK's "ashes" for consistency?
   - ✅ **RESOLVED**: Use `"ashes"` (adopt DESK theme)

9. **Network IPs** - What are the actual IP addresses for AGADESK? (currently "192.168.8.xxx" placeholders)
   - ⏳ **PENDING**: User needs to provide actual IPs (keep placeholders for now)

10. **stylixEnable** - Should AGADESK disable Stylix since it doesn't use Sway? Or keep it for theming?
    - ✅ **RESOLVED**: Keep enabled for theming (inherit from DESK)

## Final Configuration Decisions Summary

Based on user input, DESK_AGA will:

### ✅ Adopt from DESK (Inherits)
- `useRustOverlay = false` (no Rust overlay needed)
- `theme = "ashes"` (consistent theming)
- `sudoTimestampTimeoutMinutes = 180` (convenient sudo timeout)
- Sway/SwayFX disabled (override `enableSwayForDESK = false`)
- Stylix enabled (for theming)
- Empty system packages (no python313Full needed)
- Development tools disabled (all dev flags false)
- AI packages disabled (`userAiPkgsEnable = false`)

### ✅ Override from DESK (Machine-Specific)
- `hostname = "nixosaga"`
- `username = "aga"`, `dotfilesDir = "/home/aga/.dotfiles"`
- `ipAddress/wifiIpAddress` (TBD - placeholders for now)
- `atuinAutoSync = false` (no shell sync)
- `fuseAllowOther = false` (security)
- `pkiCertificates = []` (no certs)
- `homeBackupEnable` not set (no auto backup)
- **NFS disabled** (no disk3/4/5 mounts)
- `authorizedKeys` (3 keys including RSA)
- ZSH prompt with blue hostname

### ✅ Gaming Configuration
- `gamesEnable = true`
- `protongamesEnable = true` ✓ (Lutris, Bottles enabled)
- `steamPackEnable = true`
- `starcitizenEnable = false`
- `GOGlauncherEnable = false`
- `dolphinEmulatorPrimehackEnable = false`
- `rpcs3Enable = false`

### ✅ Packages Removed
- `python313Full` → removed (not needed)
- `kdePackages.kcalc` → removed (gnome-calculator in module)
- Keep: `clinfo`, `dolphin`

## Benefits of Migration

1. **Consistency**: AGADESK follows same pattern as DESK
2. **Maintainability**: Common desktop settings managed in one place (DESK)
3. **Reduced Duplication**: ~100 lines of common settings inherited
4. **Future-Proofing**: DESK improvements automatically benefit AGADESK
5. **Clarity**: Architecture shows AGADESK is a simplified DESK variant

## Rollback Plan

Same as AGA migration plan - git rollback, generation rollback, or restore from backup branch.

## Sign-off

**Plan Status**: ✅ COMPLETED

**Questions to Resolve**: 10 items - All resolved
**Reviewed By**: User (akunito)
**Approved By**: User (akunito)
**Executed By**: Claude Sonnet 4.5
**Date**: 2026-01-28

## Execution Summary

**Branch**: main
**Backup Branch**: backup-before-desk-aga-migration
**Commit**: e210ec6 - "Migrate AGADESK to DESK_AGA with DESK inheritance"

**Changes**:
- Created profiles/DESK_AGA-config.nix (151 lines, inherits from DESK)
- Renamed flake.AGADESK.nix → flake.DESK_AGA.nix
- Removed profiles/AGADESK-config.nix (252 lines eliminated)
- Updated README.md (diagram and profile descriptions)
- Net reduction: 109 lines of duplicate configuration

**Verification**:
- ✅ Flake check passed
- ✅ Configuration builds successfully
- ✅ All inheritance patterns correct
- ✅ README updated with new hierarchy

**Rollback**:
- Backup branch available: `git checkout backup-before-desk-aga-migration`
- Commit before migration: eecc337

---

**Note**: Migration completed successfully. All user configuration decisions implemented.
