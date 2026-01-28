# AGA to LAPTOP Base Migration Plan

## Overview

This document outlines the plan to migrate AGA from a standalone profile under Personal Profile to inherit from LAPTOP-base.nix, following the same pattern as LAPTOP_L15 and LAPTOP_YOGAAKU.

**Current State**: `AGA-config.nix` → standalone under Personal Profile
**Target State**: `LAPTOP_AGA-config.nix` → inherits from `LAPTOP-base.nix`

**Configuration Changes**:
- AGA will adopt `theme = "ashes"` from base (previously "io")
- AGA will adopt `polkitEnable = true` from base (previously used sudoCommands)
- AGA will keep Sway/SwayFX disabled (override base's enableSwayForDESK)
- Conflicts reduced from 5 to 3 (Sway, AppImage, Username)

## Architecture Change

### Current Hierarchy
```
lib/defaults.nix
    └── Personal Profile
            ├── DESK
            ├── AGA (standalone)      ← Current
            ├── AGADESK
            ├── LAPTOP Base
            │     ├── LAPTOP_L15
            │     └── LAPTOP_YOGAAKU
            └── VMDESK
```

### Target Hierarchy
```
lib/defaults.nix
    └── Personal Profile
            ├── DESK
            ├── AGADESK
            ├── LAPTOP Base
            │     ├── LAPTOP_L15
            │     ├── LAPTOP_YOGAAKU
            │     └── LAPTOP_AGA       ← New
            └── VMDESK
```

## Configuration Analysis

### LAPTOP-base.nix Settings (What AGA will inherit)

#### System Settings
- `enableLaptopPerformance = true`
- `atuinAutoSync = true`
- **`enableSwayForDESK = true`** ⚠️ **CONFLICT** (AGA doesn't use Sway)
- `stylixEnable = true`
- `swwwEnable = true`
- `powerManagement_ENABLE = false`
- `power-profiles-daemon_ENABLE = false`
- `TLP_ENABLE = true`
- `START_CHARGE_THRESH_BAT0 = 75`
- `STOP_CHARGE_THRESH_BAT0 = 80`
- `wifiPowerSave = true`
- **`polkitEnable = true`** ⚠️ **CONFLICT** (AGA has false)
- `polkitRules` = common rules
- `wireguardEnable = true` ✓ (same)
- **`appImageEnable = true`** ⚠️ **CONFLICT** (AGA has false)
- `nextcloudEnable = true` ✓ (same)
- `gamemodeEnable = true` (not in AGA)
- `systemStable = false` ✓ (same)

#### User Settings
- `extraGroups` = ["networkmanager", "wheel", "input", "dialout"] ✓ (same)
- **`theme = "ashes"`** ⚠️ **CONFLICT** (AGA has "io")
- `wm = "plasma6"` ✓ (same)
- `wmEnableHyprland = false` ✓ (same)
- `browser = "vivaldi"` ✓ (same)
- `spawnBrowser = "vivaldi"` ✓ (same)
- `defaultRoamDir = "Personal.p"` ✓ (same)
- `term = "kitty"` ✓ (same)
- `font = "Intel One Mono"` ✓ (same)
- `fileManager = "dolphin"`
- `gitUser = "akunito"` ✓ (same)
- `gitEmail = "diego88aku@gmail.com"` ✓ (same)
- `zshinitContent` ✓ (same)
- `sshExtraConfig` ✓ (same)

### AGA-config.nix Unique Settings (What needs to be preserved)

#### System Settings - MUST KEEP
1. **Hostname**: `hostname = "nixosaga"`
2. **Profile**: `profile = "personal"`
3. **Install Command**: `installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LAPTOP_AGA -s -u"` (update name)
4. **GPU**: `gpuType = "intel"`
5. **Kernel Modules**: `kernelModules = ["cpufreq_powersave"]`
6. **PKI Certificates**: `pkiCertificates = [ /home/aga/.certificates/ca.cert.pem ]`
7. ~~**Sudo Commands**: Specific sudo configuration for suspend, restic, rsync with NOPASSWD~~ **REMOVED** - Will use polkit rules from base instead
8. ~~**Polkit Override**: `polkitEnable = false` (overrides base's true)~~ **REMOVED** - Will use base's polkitEnable = true
9. **Network**:
   - `ipAddress = "192.168.0.77"`
   - `wifiIpAddress = "192.168.0.78"`
   - `nameServers = ["192.168.8.1", "192.168.8.1"]`
   - `resolvedEnable = false`
10. **Firewall**: Sunshine ports configuration
11. **Printer**: `servicePrinting = false`, `networkPrinters = false`
12. **Power**: Lid behavior settings (suspend on close)
13. **System Packages**: `pkgs.tldr` only
14. **Software Flags**:
    - `systemBasicToolsEnable = true`
    - `systemNetworkToolsEnable = true`
    - `sambaEnable = false`
    - `sunshineEnable = true`
    - `wireguardEnable = true`
    - `nextcloudEnable = true`
    - `appImageEnable = false` (override base)
    - `xboxControllerEnable = false`
    - `aichatEnable = false`
    - `starCitizenModules = false`
    - `vivaldiPatch = true`
15. **Auto Update**: Custom auto-update configuration for aga user

#### User Settings - MUST KEEP
1. **Username**: `username = "aga"` (different from base)
2. **Name**: `name = "aga"`
3. **Email**: `email = ""` (empty)
4. **Dotfiles Dir**: `dotfilesDir = "/home/aga/.dotfiles"`
5. ~~**Theme Override**: `theme = "io"` (overrides base's "ashes")~~ **REMOVED** - Will use base's "ashes" theme
6. **Docker**: `dockerEnable = false`
7. **Virtualization**: `virtualizationEnable = true`, `qemuGuestAddition = false`
8. **Home Packages**: kdePackages.kcalc, vivaldi
9. **Software Flags**:
    - `userBasicPkgsEnable = true`
    - `userAiPkgsEnable = false`

## Critical Conflicts & Resolutions

**Note**: Originally identified 5 conflicts. After review, 2 have been resolved by accepting base defaults:
- ~~Polkit~~ - **RESOLVED**: AGA will use `polkitEnable = true` from base (LAPTOP-base polkit rules already cover suspend, rsync, restic)
- ~~Theme~~ - **RESOLVED**: AGA will use `theme = "ashes"` from base instead of "io"

**Remaining conflicts: 3**

### Conflict 1: Sway/SwayFX Integration
**Issue**: LAPTOP-base has `enableSwayForDESK = true`, but AGA only uses plasma6.

**Resolution**: Override in LAPTOP_AGA-config.nix:
```nix
enableSwayForDESK = false;  # AGA uses plasma6 only
swwwEnable = false;         # Sway-specific wallpaper daemon
```

**Impact**: AGA won't have Sway installed or configured.

### Conflict 2: AppImage Support
**Issue**: LAPTOP-base has `appImageEnable = true`, AGA has `false`.

**Resolution**: Keep override in LAPTOP_AGA-config.nix:
```nix
appImageEnable = false;  # Not needed on AGA
```

### Conflict 3: Username
**Issue**: AGA uses username "aga", not "akunito".

**Resolution**: Specify full user config in LAPTOP_AGA-config.nix:
```nix
username = "aga";
name = "aga";
email = "";
dotfilesDir = "/home/aga/.dotfiles";
```

## Migration Procedure

### Phase 1: Prepare New Configuration File

1. **Create LAPTOP_AGA-config.nix**
   ```nix
   # LAPTOP_AGA Profile Configuration (nixosaga)
   # Inherits from LAPTOP-base.nix with machine-specific overrides

   let
     base = import ./LAPTOP-base.nix;
   in
   {
     useRustOverlay = false;

     systemSettings = base.systemSettings // {
       # [Machine-specific settings from AGA-config.nix]
       # Overrides for base settings
     };

     userSettings = base.userSettings // {
       # [User-specific settings from AGA-config.nix]
       # Overrides for base settings
     };
   }
   ```

2. **Port settings from AGA-config.nix**:
   - Copy all unique machine settings
   - Add overrides for conflicting base settings
   - Preserve all critical settings identified above

### Phase 2: Update Flake Reference

1. **Rename flake.AGA.nix → flake.LAPTOP_AGA.nix**
   ```bash
   git mv flake.AGA.nix flake.LAPTOP_AGA.nix
   ```

2. **Update flake.LAPTOP_AGA.nix**:
   ```nix
   {
     description = "Flake of AGA Laptop (T580)";

     outputs = inputs@{ self, ... }:
       let
         base = import ./lib/flake-base.nix;
         profileConfig = import ./profiles/LAPTOP_AGA-config.nix;  # Updated path
       in
         base { inherit inputs self profileConfig; };

     inputs = {
       # [Keep existing inputs]
     };
   }
   ```

### Phase 3: Update Documentation

1. **Update README.md diagram**:
   ```
   LAPTOP Base
       ├── LAPTOP_L15
       ├── LAPTOP_YOGAAKU
       └── LAPTOP_AGA      ← Add this line
   ```
   Remove AGA from standalone under DESK.

2. **Update profiles documentation**: Add LAPTOP_AGA to laptop profiles list

3. **Update install command references**: Change `AGA` → `LAPTOP_AGA` in docs

### Phase 4: Test & Verify

#### Pre-Migration Checklist
- [ ] Backup current AGA system configuration
- [ ] Note current generation number: `nix-env --list-generations -p /nix/var/nix/profiles/system`
- [ ] Create git backup branch: `git checkout -b backup-before-aga-migration`
- [ ] Document current working state

#### Migration Steps
1. **Create LAPTOP_AGA-config.nix** with all settings from Phase 1
2. **Update flake reference** (Phase 2)
3. **Verify flake check**:
   ```bash
   nix flake check
   ```
4. **Test build without activation**:
   ```bash
   nix build .#nixosConfigurations.system.config.system.build.toplevel
   ```

#### Post-Migration Verification
- [ ] System builds successfully
- [ ] Flake check passes
- [ ] All services start correctly
- [ ] Sway is NOT installed/configured
- [ ] Plasma6 works as before
- [ ] Power management (TLP) works
- [ ] Lid suspend works
- [ ] Network configuration correct (IP addresses)
- [ ] Firewall rules applied (sunshine ports)
- [ ] Polkit permissions work (suspend, restic, rsync without password)
- [ ] Auto-update scripts work
- [ ] Theme is "ashes" (from base)
- [ ] User "aga" settings correct
- [ ] Home packages installed (kcalc, vivaldi)

### Phase 5: Deploy

1. **Apply changes**:
   ```bash
   cd /home/aga/.dotfiles
   ./install.sh /home/aga/.dotfiles LAPTOP_AGA -s -u
   ```

2. **If issues occur**, rollback:
   ```bash
   sudo nixos-rebuild switch --rollback
   # Or
   git checkout backup-before-aga-migration
   ```

## Files to Modify

### Create
- [ ] `profiles/LAPTOP_AGA-config.nix` (new file)

### Rename
- [ ] `flake.AGA.nix` → `flake.LAPTOP_AGA.nix`

### Modify
- [ ] `flake.LAPTOP_AGA.nix` (update import path)
- [ ] `README.md` (update architecture diagram)
- [ ] `docs/profiles.md` (if exists - update profile list)
- [ ] `docs/installation.md` (if AGA is mentioned)

### Remove
- [ ] `profiles/AGA-config.nix` (after successful migration)

## Rollback Plan

### If Build Fails
```bash
# Restore from git
git checkout backup-before-aga-migration
git checkout main

# Or revert specific commits
git revert HEAD
```

### If System Boots but Issues Exist
```bash
# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Or select specific generation
sudo nixos-rebuild switch --rollback --profile-name <generation-number>
```

### If Critical Failure
1. Boot from previous generation (GRUB menu)
2. Restore old configuration:
   ```bash
   cd /home/aga/.dotfiles
   git checkout backup-before-aga-migration
   ./install.sh /home/aga/.dotfiles AGA -s -u
   ```

## Benefits of Migration

1. **Consistency**: AGA follows same pattern as other laptops
2. **Maintainability**: Shared laptop settings in one place
3. **Clarity**: Architecture diagram shows proper inheritance
4. **Reduced Duplication**: Common laptop settings (TLP, power, polkit rules) inherited
5. **Future-Proofing**: Easier to add new laptop profiles

## Potential Issues

### Issue 1: Inherited Settings Break AGA
**Symptom**: Services that shouldn't be installed appear on AGA
**Solution**: Add explicit overrides to disable them in LAPTOP_AGA-config.nix

### Issue 2: Sway/SwayFX Installation Despite Override
**Symptom**: Sway packages installed even with `enableSwayForDESK = false`
**Solution**: Verify override is in systemSettings, not userSettings. Check if other flags enable Sway.

### Issue 3: Theme Not Applied
**Symptom**: Stylix uses "ashes" theme instead of "io"
**Solution**: Ensure `theme = "io"` is in userSettings override, not systemSettings.

### Issue 4: Auto-Update Scripts Fail
**Symptom**: Auto-update timers don't run or fail
**Solution**: Verify paths are correct for "aga" user, not "akunito".

### Issue 5: Polkit Permissions Not Working
**Symptom**: Suspend/restic/rsync commands require password
**Solution**: Verify polkit rules are loaded correctly. Check with `pkaction` and test with user "aga". LAPTOP-base polkit rules should cover these actions.

## Special Considerations

### Sway Exclusion Strategy
Since LAPTOP-base enables Sway by default but AGA doesn't need it:

**Option A: Simple Override** (Recommended)
```nix
systemSettings = base.systemSettings // {
  enableSwayForDESK = false;
  swwwEnable = false;
  # Other settings...
};
```

**Option B: Conditional in Base** (Future improvement)
Could modify LAPTOP-base.nix to make Sway optional:
```nix
# In LAPTOP-base.nix
enableSwayForDESK = true;  # Default, can be overridden
```
Then specific profiles can override to false.

**Recommendation**: Use Option A (simple override) for now. If multiple laptops don't need Sway, reconsider base defaults later.

### Username Handling
Since AGA uses "aga" username (not "akunito"), ensure all user-specific paths are correct:
- `dotfilesDir = "/home/aga/.dotfiles"`
- `autoUserUpdateUser = "aga"`
- PKI certificate path: `/home/aga/.certificates/ca.cert.pem`

## Testing Checklist

### Critical Functionality
- [ ] System boots successfully
- [ ] Plasma6 desktop loads
- [ ] Sway is NOT installed
- [ ] Lid close suspends system
- [ ] Power button suspends system
- [ ] TLP manages power (check `sudo tlp-stat`)
- [ ] Battery thresholds applied (75-80%)
- [ ] WiFi connects and works
- [ ] Network has correct IP addresses
- [ ] Firewall allows sunshine ports
- [ ] SSH works
- [ ] User "aga" can log in
- [ ] Home directory is correct
- [ ] Polkit works for: suspend, restic, rsync (without password)
- [ ] Auto-update timers exist and run
- [ ] Theme is "ashes" (from base)
- [ ] Browser (vivaldi) works
- [ ] Terminal (kitty) works
- [ ] Calculator (kcalc) installed
- [ ] Dolphin file manager works
- [ ] Nextcloud client works
- [ ] WireGuard VPN works
- [ ] Virtualization works
- [ ] Git configured correctly

### Package Verification
```bash
# Check Sway NOT installed
nix-store -q --requisites /run/current-system | grep sway
# Should return nothing

# Check TLP installed
systemctl status tlp

# Check battery thresholds
cat /sys/class/power_supply/BAT0/charge_control_start_threshold
cat /sys/class/power_supply/BAT0/charge_control_end_threshold
# Should show 75 and 80

# Check theme
ls ~/.config/stylix/
# Should contain "ashes" theme files (from base)
```

## Timeline & Execution

**Estimated Time**: 2-3 hours total

1. **Preparation** (30 min): Create backup, document current state
2. **Implementation** (45 min): Create new config, update flake
3. **Testing** (60 min): Build, verify, test all functionality
4. **Documentation** (15 min): Update diagrams and docs
5. **Buffer** (30 min): Handle any issues

**Recommended Schedule**:
- Execute when system downtime is acceptable
- Have physical access to machine (in case of boot issues)
- Keep another device available for documentation reference

## Sign-off

**Plan Status**: ⏳ Awaiting Review

**Reviewed By**: [User]
**Approved By**: [User]
**Executed By**: [Agent/User]
**Date**: [YYYY-MM-DD]

---

**Note**: This is a comprehensive plan. Review carefully before execution. All changes are reversible via git and NixOS generations.
