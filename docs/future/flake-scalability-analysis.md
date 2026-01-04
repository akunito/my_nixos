# Flake Profile Scalability Analysis

**Date**: 2025-01-XX  
**Status**: Analysis Only - No Implementation  
**Purpose**: Analyze scalability issues with multiple flake profile files and propose solutions

## Executive Summary

You currently maintain **10+ flake profile files** (`flake.*.nix`), each ~750 lines, with significant duplication. Only ~5-10% of each file contains profile-specific values, while ~90-95% is identical across all profiles. This creates maintenance burden, risk of inconsistencies, and scalability issues as more profiles are added.

## Current State Analysis

### File Structure

Each `flake.PROFILE.nix` file contains:

1. **Flake Structure** (~50 lines) - Identical across all profiles
   - `description`
   - `outputs` function signature
   - `inputs` definition
   - Output structure (`homeConfigurations`, `nixosConfigurations`, `packages`, `apps`)

2. **System Settings** (~350 lines) - Mostly shared
   - Common: timezone, locale, boot mode defaults, security defaults, network defaults
   - Profile-specific: hostname, IP addresses, drive configurations, some feature flags

3. **User Settings** (~100 lines) - Mostly shared
   - Common: email, theme defaults, editor defaults, package lists structure
   - Profile-specific: username, dotfilesDir, some package selections

4. **Package Configuration** (~150 lines) - Mostly identical
   - `pkgs`, `pkgs-stable`, `pkgs-unstable` configuration
   - `nixpkgs-patched` setup
   - `lib` and `home-manager` selection logic

5. **Inputs** (~100 lines) - Identical across all profiles
   - All flake inputs (nixpkgs, home-manager, hyprland, etc.)

### Duplication Metrics

**Estimated duplication**:
- **~90-95% identical** across all flake files
- **~5-10% profile-specific** (hostname, IPs, drives, some flags)

**Maintenance impact**:
- Adding a new input requires updating 10+ files
- Changing common defaults requires updating 10+ files
- Risk of forgetting to update some profiles
- Difficult to ensure consistency

### What Varies Between Profiles

**System-Specific Values** (typically ~20-30 unique values per profile):
- `hostname` - Unique per system
- `profile` - Profile directory name
- `gpuType` - Hardware-specific (amd/intel/nvidia)
- `kernelModules` - Hardware-specific modules
- `ipAddress` / `wifiIpAddress` - Network configuration
- `nameServers` - DNS configuration
- `allowedTCPPorts` / `allowedUDPPorts` - Firewall rules
- `disk*_*` - Drive mount configurations (0-7 disks per profile)
- `nfsMounts` / `nfsAutoMounts` - NFS configurations
- `authorizedKeys` - SSH keys (may vary)
- `pkiCertificates` - Certificate paths
- Backup settings (scripts, schedules, users)
- Some feature flags (backup enable/disable, etc.)

**User-Specific Values** (typically ~5-10 unique values per profile):
- `username` - System user
- `dotfilesDir` - Path to dotfiles
- `email` - User email
- `gitUser` / `gitEmail` - Git configuration
- Some package selections (may vary by profile)
- Some feature flags

**Hardware-Specific**:
- `gpuType` - Determines some package selections
- `kernelModules` - Hardware-specific modules
- Drive configurations - Vary significantly

## Problem Statement

### Core Issues

1. **Maintenance Burden**
   - Changes to common structure require updating 10+ files
   - High risk of inconsistencies
   - Time-consuming to keep all profiles in sync

2. **Scalability**
   - Adding new profiles requires copying ~750 lines
   - Adding new inputs requires updating all profiles
   - Not sustainable as profile count grows

3. **Error-Prone**
   - Easy to forget updating some profiles
   - Typos can cause silent failures
   - Difficult to verify all profiles are consistent

4. **Code Quality**
   - Violates DRY (Don't Repeat Yourself) principle
   - Makes refactoring difficult
   - Harder to review changes

### Real-World Scenarios

**Scenario 1: Adding a new flake input**
- Current: Edit 10+ flake files, add input, update references
- Risk: Forget to update one profile, inconsistent state

**Scenario 2: Changing default timezone**
- Current: Edit 10+ flake files
- Risk: Miss one profile, inconsistent behavior

**Scenario 3: Updating package configuration logic**
- Current: Edit 10+ flake files, ensure identical changes
- Risk: Introduce inconsistencies, bugs

**Scenario 4: Adding a new profile**
- Current: Copy ~750 lines, modify ~30-40 values
- Risk: Copy errors, missing updates

## Solution Approaches

### Approach 1: Shared Configuration Module

**Concept**: Extract common settings to a shared Nix module, import in each flake.

**Structure**:
```
flake-base.nix          # Common flake structure
flake-defaults.nix       # Default systemSettings and userSettings
flake.PROFILE.nix        # Profile-specific overrides only
```

**Implementation**:
- Create `flake-base.nix` with common structure
- Create `flake-defaults.nix` with default values
- Each `flake.PROFILE.nix` imports base and overrides only differences

**Pros**:
- ✅ Single source of truth for common settings
- ✅ Profile files become much smaller (~50-100 lines)
- ✅ Easy to update common settings
- ✅ Native Nix approach (no external tools)
- ✅ Type-safe (Nix evaluates everything)

**Cons**:
- ⚠️ Still need to maintain 10+ profile files (but much smaller)
- ⚠️ Need to understand Nix module system well
- ⚠️ Merge/override logic can be complex

**Complexity**: Medium  
**Maintenance Reduction**: ~80-90%

---

### Approach 2: Template-Based Generation

**Concept**: Single template file with placeholders, generate flake files from template.

**Structure**:
```
flake.template.nix       # Template with {{PLACEHOLDERS}}
profiles/registry.toml   # Profile-specific values
scripts/generate-flakes.sh # Generation script
```

**Implementation**:
- Template file with `{{HOSTNAME}}`, `{{PROFILE}}`, etc.
- Registry file contains profile-specific values
- Script generates `flake.PROFILE.nix` from template + registry

**Pros**:
- ✅ Single source of truth (template)
- ✅ Profile files are generated (don't edit directly)
- ✅ Easy to regenerate all profiles
- ✅ Can validate template syntax
- ✅ Clear separation of common vs profile-specific

**Cons**:
- ⚠️ Requires external generation step
- ⚠️ Generated files in git (or need to ignore)
- ⚠️ Template syntax can be complex
- ⚠️ Less "Nix-native" approach

**Complexity**: Medium-High  
**Maintenance Reduction**: ~90-95%

---

### Approach 3: Single Flake with Profile Selection

**Concept**: One `flake.nix` that accepts profile as input, generates configuration dynamically.

**Structure**:
```
flake.nix                # Single flake with profile selection
profiles/config/         # Profile-specific config files (JSON/TOML/Nix)
  DESK.nix
  HOME.nix
  ...
```

**Implementation**:
- Single `flake.nix` reads profile config
- Profile configs contain only differences
- Flake merges defaults + profile-specific

**Pros**:
- ✅ Single flake file to maintain
- ✅ Profile configs are minimal
- ✅ Very scalable
- ✅ Easy to add new profiles

**Cons**:
- ⚠️ Requires refactoring existing workflow
- ⚠️ Profile selection logic in flake
- ⚠️ May need to change how install.sh works
- ⚠️ More complex flake logic

**Complexity**: High  
**Maintenance Reduction**: ~95%+

---

### Approach 4: Nix Function-Based Generation

**Concept**: Nix function that takes profile config and generates flake outputs.

**Structure**:
```
lib/make-flake.nix      # Function to generate flake outputs
lib/defaults.nix         # Default configurations
profiles/DESK.nix        # Profile config (minimal)
profiles/HOME.nix        # Profile config (minimal)
flake.nix                # Calls make-flake for each profile
```

**Implementation**:
- `make-flake` function takes profile name and config
- Each profile file contains only overrides
- `flake.nix` calls `make-flake` for each profile

**Pros**:
- ✅ Very Nix-native approach
- ✅ Type-safe and evaluated
- ✅ Profile configs are minimal
- ✅ Single function to maintain common logic

**Cons**:
- ⚠️ Requires significant refactoring
- ⚠️ More complex initial setup
- ⚠️ Need to understand Nix functions well

**Complexity**: High  
**Maintenance Reduction**: ~90-95%

---

### Approach 5: Hybrid: Shared Module + Minimal Profiles

**Concept**: Combine Approach 1 and 3 - shared module with minimal profile overrides.

**Structure**:
```
lib/flake-base.nix       # Common flake structure
lib/defaults.nix         # Default systemSettings/userSettings
profiles/DESK-config.nix # Only profile-specific overrides
flake.DESK.nix           # Minimal: imports base + config
```

**Implementation**:
- Base module contains all common logic
- Defaults contain common values
- Profile configs contain only differences
- Profile flakes import and merge

**Pros**:
- ✅ Best of both worlds
- ✅ Minimal profile files
- ✅ Single source for common code
- ✅ Native Nix approach
- ✅ Maintains current workflow

**Cons**:
- ⚠️ Still have 10+ profile files (but tiny)
- ⚠️ Need to understand merge logic

**Complexity**: Medium  
**Maintenance Reduction**: ~85-90%

---

## Detailed Comparison

| Approach | Complexity | Maintenance Reduction | Workflow Change | Nix-Native | Scalability |
|----------|-----------|---------------------|----------------|------------|-------------|
| 1. Shared Module | Medium | 80-90% | Minimal | ✅ Yes | Good |
| 2. Template Generation | Medium-High | 90-95% | Medium | ⚠️ Partial | Excellent |
| 3. Single Flake | High | 95%+ | High | ✅ Yes | Excellent |
| 4. Function-Based | High | 90-95% | High | ✅ Yes | Excellent |
| 5. Hybrid | Medium | 85-90% | Minimal | ✅ Yes | Good |

## Recommended Approach

### Primary Recommendation: **Approach 5 (Hybrid)**

**Rationale**:
1. **Balanced**: Good maintenance reduction without major workflow changes
2. **Nix-Native**: Uses Nix's module system properly
3. **Backward Compatible**: Can maintain current `install.sh` workflow
4. **Incremental**: Can migrate gradually, one profile at a time
5. **Familiar**: Similar to existing module structure

**Structure**:
```
lib/
  flake-base.nix          # Common flake structure (inputs, outputs, pkgs config)
  defaults.nix             # Default systemSettings and userSettings
  
profiles/
  DESK-config.nix         # Profile-specific overrides only
  HOME-config.nix
  LAPTOP-config.nix
  ...
  
flake.DESK.nix            # ~20-30 lines: imports base + config
flake.HOME.nix            # ~20-30 lines: imports base + config
```

**Migration Path**:
1. Extract common structure to `lib/flake-base.nix`
2. Extract defaults to `lib/defaults.nix`
3. Create profile configs with only differences
4. Update profile flakes to import and merge
5. Test each profile
6. Remove old duplicated code

### Alternative: **Approach 1 (Shared Module)** if simpler is preferred

**Rationale**:
- Simpler to implement
- Less refactoring required
- Still provides significant maintenance reduction
- Easier to understand

## Implementation Considerations

### Common Challenges

1. **Merge Logic**
   - How to merge defaults with overrides?
   - Deep merge vs shallow merge?
   - List concatenation vs replacement?

2. **Type Safety**
   - Ensuring profile configs match expected structure
   - Validating profile-specific values
   - Catching errors early

3. **Backward Compatibility**
   - Maintaining `install.sh` workflow
   - Ensuring existing profiles still work
   - Gradual migration path

4. **Documentation**
   - Documenting new structure
   - Explaining how to add new profiles
   - Migration guide

### Migration Strategy

**Phase 1: Preparation**
- Analyze all profiles to identify truly common values
- Document what varies between profiles
- Create test cases

**Phase 2: Extract Common Code**
- Create base module with common structure
- Extract defaults
- Test with one profile first

**Phase 3: Migrate Profiles**
- Migrate one profile at a time
- Test each migration
- Verify functionality

**Phase 4: Cleanup**
- Remove duplicated code
- Update documentation
- Update scripts if needed

## Questions to Answer Before Implementation

1. **What truly varies?**
   - Need detailed analysis of all 10+ profiles
   - Identify all unique values
   - Categorize by type (hardware, network, user, etc.)

2. **Merge strategy?**
   - How to handle nested structures?
   - How to handle lists (append vs replace)?
   - How to handle optional values?

3. **Workflow preferences?**
   - Keep current `install.sh` workflow?
   - Willing to change how profiles are selected?
   - Prefer generated files or Nix-native?

4. **Migration timeline?**
   - Can migrate gradually?
   - Need all profiles working during migration?
   - Can tolerate temporary duplication?

## Next Steps

1. **Detailed Analysis** (if needed):
   - Compare all 10+ flake files side-by-side
   - Create matrix of what varies
   - Identify all common patterns

2. **Proof of Concept**:
   - Implement chosen approach for 1-2 profiles
   - Test thoroughly
   - Validate maintenance reduction

3. **Full Migration Plan**:
   - Detailed step-by-step plan
   - Testing strategy
   - Rollback plan

4. **Documentation**:
   - Update installation docs
   - Create migration guide
   - Document new structure

## Conclusion

The current approach of maintaining 10+ nearly identical flake files is not scalable. The recommended **Hybrid approach (Approach 5)** provides the best balance of:
- Maintenance reduction (~85-90%)
- Minimal workflow changes
- Nix-native implementation
- Incremental migration path

This would reduce each profile file from ~750 lines to ~20-30 lines, with common code maintained in shared modules.

## Related Documentation

- [Improvements Analysis](improvements-analysis.md) - Previous analysis
- [Configuration Guide](../configuration.md) - Current configuration structure
- [Profiles Guide](../profiles.md) - Profile documentation


