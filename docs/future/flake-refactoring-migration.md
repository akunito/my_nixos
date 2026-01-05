# Flake Profile Refactoring - Migration Guide

## Overview

The flake profile refactoring has been successfully implemented to eliminate code duplication across multiple `flake.*.nix` files. The new structure reduces each profile file from ~750 lines to ~30 lines while maintaining full backward compatibility.

## Completed Work

### ✅ Base Infrastructure

1. **`lib/defaults.nix`** - Contains all common default values for `systemSettings` and `userSettings`
2. **`lib/flake-base.nix`** - Base flake module that handles:
   - Input management
   - Package configuration (stable/unstable)
   - Output generation
   - Merging defaults with profile-specific overrides
   - Font computation based on systemStable
   - Package list evaluation (supports functions)

### ✅ Migrated Profiles

1. **DESK** - Fully migrated and tested
2. **HOME** - Fully migrated and tested (handles systemStable in userSettings)

### ✅ Testing

- Flake evaluation passes for both DESK and HOME profiles
- `install.sh` compatibility maintained (no changes needed)
- Backward compatibility preserved

## Migration Pattern

Each profile now follows this structure:

### Profile Config File (`profiles/PROFILE-config.nix`)

Contains only profile-specific overrides:

```nix
{
  # Optional: Flag to use rust-overlay
  useRustOverlay = false;
  
  systemSettings = {
    hostname = "unique-hostname";
    profile = "profile-name";
    gpuType = "amd"; # or "intel" or "nvidia"
    # ... only differences from defaults
  };
  
  userSettings = {
    username = "username";
    # ... only differences from defaults
  };
}
```

### Flake File (`flake.PROFILE.nix`)

Minimal wrapper (~20-30 lines):

```nix
{
  description = "Flake description";

  outputs = inputs@{ self, ... }:
    let
      base = import ./lib/flake-base.nix;
      profileConfig = import ./profiles/PROFILE-config.nix;
    in
      base { inherit inputs self; } profileConfig;

  inputs = {
    # Only profile-specific inputs (if any)
    # Common inputs are handled in base module
    nixpkgs.url = "nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "nixpkgs/nixos-25.11";
    # ... other inputs
  };
}
```

## Remaining Profiles to Migrate

The following profiles still need migration (follow the same pattern):

- [ ] LAPTOP
- [ ] WSL
- [ ] VMDESK
- [ ] VMHOME
- [ ] AGADESK
- [ ] AGA
- [ ] YOGAAKU
- [ ] ORIGINAL (optional - historical reference)

## Migration Steps

For each remaining profile:

1. **Read the original flake file** to identify unique values
2. **Create `profiles/PROFILE-config.nix`** with only overrides
3. **Refactor `flake.PROFILE.nix`** to use base module
4. **Test with `nix flake check --no-build`**
5. **Verify `install.sh` works** (should work without changes)

## Key Differences to Note

### Package Lists

Package lists should be functions that receive `pkgs` and `pkgs-unstable`:

```nix
systemPackages = pkgs: pkgs-unstable: [
  pkgs.vim
  pkgs-unstable.some-package
  # ...
];
```

### systemStable Location

- Most profiles: `systemSettings.systemStable`
- HOME profile: `userSettings.systemStable` (inconsistency handled in base module)

### Input Variations

- **hyprland**: Only in profiles that use it (DESK, etc.)
- **rust-overlay**: Set `useRustOverlay = true` in profile config if needed
- **nixos-hardware**: Only in profiles that need it (HOME, etc.)

## Benefits Achieved

- **85-90% code reduction** in profile files
- **Single source of truth** for common settings
- **Easy to add new profiles** (just create config file)
- **Consistent structure** across all profiles
- **Backward compatible** - `install.sh` works unchanged

## Testing Checklist

For each migrated profile:

- [ ] `nix flake check --no-build` passes
- [ ] Profile-specific settings are preserved
- [ ] Package lists evaluate correctly
- [ ] Fonts computed correctly based on systemStable
- [ ] `install.sh` can discover and use the profile

## Notes

- The base module handles font computation automatically based on `systemStable`
- Package lists can be functions (recommended) or static lists
- All common inputs are available in the base module
- Profile-specific inputs should be added to the flake file's `inputs` section

## Future Improvements

Potential enhancements (not yet implemented):

1. Extract package lists to separate files for even better organization
2. Create profile templates for common patterns
3. Add validation for required profile settings
4. Generate profile configs from a template

