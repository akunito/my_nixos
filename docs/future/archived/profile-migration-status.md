# Profile Migration Status

**Date**: 2025-01-02  
**Status**: Analysis Complete  
**Purpose**: Track migration progress from old flake structure to new refactored structure

## Summary

- **Total Profiles**: 10
- **Fully Migrated**: 1 (10%)
- **Partially Migrated**: 1 (10%)
- **Pending Migration**: 8 (80%)

## Migration Status

### ✅ Fully Migrated Profiles

#### DESK
- **Status**: ✅ Complete
- **Flake File**: `flake.DESK.nix` (33 lines)
- **Config File**: `profiles/DESK-config.nix` ✅
- **Uses Base Module**: ✅ Yes
- **Notes**: Fully migrated and tested. Serves as the reference implementation.

### ⚠️ Partially Migrated Profiles

#### HOME
- **Status**: ⚠️ Partial
- **Flake File**: `flake.HOME.nix` (579 lines) - **Still old structure**
- **Config File**: `profiles/HOME-config.nix` ✅ (exists but not used)
- **Uses Base Module**: ❌ No
- **Notes**: Config file was created but flake file was never refactored to use it. Needs flake file update to complete migration.

### ⏳ Pending Migration Profiles

#### LAPTOP
- **Status**: ⏳ Pending
- **Flake File**: `flake.LAPTOP.nix` (713 lines)
- **Config File**: ❌ Missing
- **Uses Base Module**: ❌ No
- **Complexity**: ~271 unique settings
- **Profile Directory**: `personal`
- **Hostname**: `nixolaptopaku`
- **Notes**: Laptop configuration with power management features

#### WSL
- **Status**: ⏳ Pending
- **Flake File**: `flake.WSL.nix` (497 lines)
- **Config File**: ❌ Missing
- **Uses Base Module**: ❌ No
- **Complexity**: ~190 unique settings
- **Profile Directory**: `wsl`
- **Hostname**: `nixosdiego`
- **Notes**: Windows Subsystem for Linux configuration. Smaller than others.

#### VMDESK
- **Status**: ⏳ Pending
- **Flake File**: `flake.VMDESK.nix` (701 lines)
- **Config File**: ❌ Missing
- **Uses Base Module**: ❌ No
- **Complexity**: ~265 unique settings
- **Profile Directory**: `personal`
- **Hostname**: `nixosdesk`
- **Notes**: Virtual machine desktop configuration

#### VMHOME
- **Status**: ⏳ Pending
- **Flake File**: `flake.VMHOME.nix` (636 lines)
- **Config File**: ❌ Missing
- **Uses Base Module**: ❌ No
- **Complexity**: ~244 unique settings
- **Profile Directory**: `homelab`
- **Hostname**: `nixosLabaku`
- **Notes**: Virtual machine homelab configuration

#### AGA
- **Status**: ⏳ Pending
- **Flake File**: `flake.AGA.nix` (707 lines)
- **Config File**: ❌ Missing
- **Uses Base Module**: ❌ No
- **Complexity**: ~274 unique settings
- **Profile Directory**: `personal`
- **Hostname**: `nixosaga`
- **Notes**: Aga's system configuration

#### AGADESK
- **Status**: ⏳ Pending
- **Flake File**: `flake.AGADESK.nix` (736 lines)
- **Config File**: ❌ Missing
- **Uses Base Module**: ❌ No
- **Complexity**: ~271 unique settings
- **Profile Directory**: `personal`
- **Hostname**: `nixosaga`
- **Notes**: Aga's desktop configuration. Largest file.

#### YOGAAKU
- **Status**: ⏳ Pending
- **Flake File**: `flake.YOGAAKU.nix` (680 lines)
- **Config File**: ❌ Missing
- **Uses Base Module**: ❌ No
- **Complexity**: ~253 unique settings
- **Profile Directory**: `personal`
- **Hostname**: `yogaaku`
- **Notes**: Yoga laptop configuration

#### ORIGINAL
- **Status**: ⏳ Pending (Historical Reference)
- **Flake File**: `flake.ORIGINAL.nix` (320 lines)
- **Config File**: ❌ Missing
- **Uses Base Module**: ❌ No
- **Complexity**: Unknown (smaller file)
- **Profile Directory**: `personal`
- **Hostname**: `snowfire`
- **Notes**: Historical reference configuration. May not need migration if not actively used.

## Migration Statistics

### File Size Reduction
- **Before Migration**: ~700 lines per profile
- **After Migration**: ~30 lines per profile
- **Reduction**: ~95% code reduction per profile

### Code Duplication
- **Before**: ~90-95% duplication across profiles
- **After**: Common code in `lib/flake-base.nix` and `lib/defaults.nix`
- **Profile Configs**: Only unique overrides (~30-50 lines each)

## Migration Priority Recommendations

### High Priority (Active Use)
1. **HOME** - Complete partial migration (just needs flake file update)
2. **LAPTOP** - Active laptop configuration
3. **WSL** - Smaller file, good candidate for quick migration

### Medium Priority
4. **VMDESK** - Virtual machine desktop
5. **VMHOME** - Virtual machine homelab
6. **AGADESK** - Aga's desktop (largest file)

### Low Priority
7. **AGA** - Aga's system
8. **YOGAAKU** - Yoga laptop
9. **ORIGINAL** - Historical reference (may skip if not used)

## Migration Steps (Per Profile)

For each pending profile:

1. **Read the original flake file** to identify unique values
2. **Create `profiles/PROFILE-config.nix`** with only overrides:
   - Extract profile-specific `systemSettings` overrides
   - Extract profile-specific `userSettings` overrides
   - Convert `systemPackages` to function format: `pkgs: pkgs-unstable: [ ... ]`
   - Convert `homePackages` to function format: `pkgs: pkgs-unstable: [ ... ]`
3. **Refactor `flake.PROFILE.nix`** to use base module:
   ```nix
   {
     description = "Flake description";
     outputs = inputs@{ self, ... }:
       let
         base = import ./lib/flake-base.nix;
         profileConfig = import ./profiles/PROFILE-config.nix;
       in
         base { inherit inputs self profileConfig; };
     inputs = {
       # Profile-specific inputs (if any)
       # Common inputs handled in base
     };
   }
   ```
4. **Test with `nix flake check --impure`**
5. **Verify `install.sh` works** (should work without changes)

## Special Considerations

### HOME Profile
- Has `systemStable` in `userSettings` instead of `systemSettings` (inconsistency)
- Already handled in `lib/flake-base.nix` (checks both locations)
- Config file exists but flake file needs update

### Profile-Specific Inputs
- **hyprland**: Only needed for profiles using Hyprland (DESK, etc.)
- **rust-overlay**: Set `useRustOverlay = true` in profile config if needed
- **nixos-hardware**: Only needed for specific hardware profiles

### Package Lists
- Must be functions: `pkgs: pkgs-unstable: [ ... ]`
- Allows access to both stable and unstable packages
- Evaluated in `lib/flake-base.nix`

## Benefits After Full Migration

- **Maintenance**: Update common code in one place
- **Consistency**: Single source of truth for defaults
- **Scalability**: Easy to add new profiles
- **Code Reduction**: ~95% reduction per profile file
- **Clarity**: Profile configs show only what's unique

## Next Steps

1. ✅ Complete HOME migration (update flake file)
2. ⏳ Migrate LAPTOP (good test case)
3. ⏳ Migrate WSL (smaller, simpler)
4. ⏳ Migrate remaining profiles systematically

## References

- Migration guide: `docs/future/flake-refactoring-migration.md`
- Verification results: `docs/future/migration-verification-results.md`
- Base module: `lib/flake-base.nix`
- Defaults: `lib/defaults.nix`
- Reference implementation: `flake.DESK.nix` + `profiles/DESK-config.nix`

