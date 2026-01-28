# Desktop to Laptop Migration - COMPLETED

**Status: IMPLEMENTED** (2026-01-28)

## Summary

Successfully migrated the rich DESK configuration (Sway, Stylix, performance tuning) to laptop profiles through a scalable feature flag architecture.

## Changes Made

### Phase 1: Hostname Checks Refactored to Feature Flags

1. **lib/defaults.nix** - Added new flags:
   - `enableDesktopPerformance = false`
   - `enableLaptopPerformance = false`

2. **system/hardware/io-scheduler.nix** - Refactored:
   - Replaced `hostname == "nixosaku"` checks with `systemSettings.enableDesktopPerformance`
   - Replaced `hostname == "nixolaptopaku"` checks with `systemSettings.enableLaptopPerformance`

3. **system/hardware/performance.nix** - Refactored:
   - Same pattern as io-scheduler.nix

4. **Profile Updates**:
   - DESK-config.nix: Added `enableDesktopPerformance = true`
   - AGADESK-config.nix: Added `enableDesktopPerformance = true`
   - LAPTOP-config.nix: Added `enableLaptopPerformance = true`
   - YOGAAKU-config.nix: Added `enableLaptopPerformance = true`

### Phase 2: LAPTOP-base.nix Structure Created

1. **profiles/LAPTOP-base.nix** - NEW file with shared laptop settings:
   - `enableLaptopPerformance = true`
   - `enableSwayForDESK = true` (using existing flag, no rename)
   - `stylixEnable = true`
   - `swwwEnable = true`
   - `TLP_ENABLE = true`
   - `powerManagement_ENABLE = false`
   - Common polkit rules
   - Common packages

2. **profiles/LAPTOP-config.nix** - Refactored:
   - Imports from LAPTOP-base.nix
   - Uses `//` attribute set merge for overrides
   - Extends systemPackages and homePackages using function composition

3. **profiles/YOGAAKU-config.nix** - Refactored:
   - Imports from LAPTOP-base.nix
   - Machine-specific overrides (BIOS boot, different NFS, etc.)
   - Fixed broken `fonts` reference to pkgs (removed)

## Decisions Made

| Decision | Answer |
|----------|--------|
| Rename `enableSwayForDESK` to `enableSway`? | **NO** - Use existing flag directly |
| Want Sway on LAPTOP? | **YES** |
| Need LAPTOP-base.nix? | **YES** |
| Refactor hostname checks to flags? | **YES** |
| Accept git rollback as safety? | **YES** |

## Verification Results

```
✓ nix flake check --no-build - PASSED
✓ DESK profile dry-run build - PASSED
✓ LAPTOP profile evaluation - PASSED (inherits all base settings)
✓ YOGAAKU profile evaluation - PASSED (inherits all base settings)
```

## Files Modified/Created

| File | Action |
|------|--------|
| lib/defaults.nix | MODIFIED - Added flags |
| system/hardware/io-scheduler.nix | MODIFIED - Use flags |
| system/hardware/performance.nix | MODIFIED - Use flags |
| profiles/DESK-config.nix | MODIFIED - Added flag |
| profiles/AGADESK-config.nix | MODIFIED - Added flag |
| profiles/LAPTOP-config.nix | MODIFIED - Inheritance |
| profiles/YOGAAKU-config.nix | MODIFIED - Inheritance |
| profiles/LAPTOP-base.nix | CREATED |

## Next Steps

1. Apply changes on DESK: `sudo nixos-rebuild switch --flake .#DESK`
2. Verify Sway works on DESK
3. Test on LAPTOP when available
4. Test on YOGAAKU when available

## Rollback Strategy

```bash
git reset --hard HEAD~1
sudo nixos-rebuild switch --flake .#DESK
```
