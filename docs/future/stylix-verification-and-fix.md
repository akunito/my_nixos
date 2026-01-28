# Stylix Configuration Verification and Fix

## Date: 2026-01-28

## Summary

Verified that **all Stylix configurations are properly controlled by the `stylixEnable` flag**. Found one issue: **DESK_AGA** should disable Stylix but currently inherits it enabled from DESK.

## Current Stylix Import Mechanism

### System-Level (profiles/work/configuration.nix:57)
```nix
++ lib.optional systemSettings.stylixEnable ../../system/style/stylix.nix
```

### User-Level (profiles/work/home.nix:37)
```nix
++ lib.optional systemSettings.stylixEnable ../../user/style/stylix.nix
```

### Icon Theme (profiles/work/home.nix:86-89)
```nix
gtk.iconTheme = lib.mkIf (systemSettings.stylixEnable == true) {
  package = pkgs.papirus-icon-theme;
  name = if (config.stylix.polarity == "dark") then "Papirus-Dark" else "Papirus-Light";
};
```

**✅ Conclusion**: Stylix modules are conditionally imported based on `stylixEnable` flag. The flag controls everything properly.

## Profile Analysis

### Profiles with Sway + Plasma6 (Stylix ENABLED) ✅

| Profile | enableSwayForDESK | stylixEnable | Status |
|---------|-------------------|--------------|--------|
| DESK | true | true | ✅ Correct |
| DESK_VMDESK | true (inherits) | true (inherits) | ✅ Correct |
| LAPTOP Base | true | true | ✅ Correct |
| LAPTOP_L15 | true (inherits) | true (inherits) | ✅ Correct |
| LAPTOP_YOGAAKU | true (inherits) | true (inherits) | ✅ Correct |
| LAPTOP_AGA | true (inherits) | true (inherits) | ✅ Correct |

### Profiles with Plasma6 Only (Stylix should be DISABLED) ❌

| Profile | enableSwayForDESK | stylixEnable | Status |
|---------|-------------------|--------------|--------|
| **DESK_AGA** | false | **true (inherits)** | ❌ **INCORRECT** |

## Issue Details

### DESK_AGA Profile

**File**: `profiles/DESK_AGA-config.nix`

**Current Configuration (lines 41-43)**:
```nix
# Desktop Environment - Override from DESK
enableSwayForDESK = false;
swwwEnable = false;
# stylixEnable inherits true from DESK (for theming)
```

**Problem**: Comment indicates it inherits `stylixEnable = true` from DESK, but DESK_AGA uses **Plasma6 only** (no Sway). Stylix should be completely disabled for Plasma6-only profiles to:
1. Avoid conflicts with Plasma 6's native theming system
2. Prevent unnecessary theme file generation (qt5ct, GTK configs)
3. Let Plasma manage all Qt/GTK theming
4. Reduce system complexity and potential theme conflicts

**Why This Matters**:
- Stylix is designed for Sway/tiling window managers
- Plasma 6 has its own comprehensive theming system
- Having both creates conflicts and unnecessary overhead
- User explicitly disabled Sway for DESK_AGA (Plasma6-only use case)

## Fix Implementation

### Step 1: Update DESK_AGA-config.nix

**Add explicit override** in the "Desktop Environment" section:

```nix
# ============================================================================
# DESKTOP ENVIRONMENT - Override from DESK
# ============================================================================
# Disable Sway/SwayFX - DESK_AGA uses Plasma6 only
enableSwayForDESK = false;
swwwEnable = false;
stylixEnable = false; # Override - Plasma6 only, no Stylix (Plasma has its own theming)
```

### Step 2: Update Comment

**Change from**:
```nix
# stylixEnable inherits true from DESK (for theming)
```

**To**:
```nix
stylixEnable = false; # Override - Plasma6 only, no Stylix (Plasma has its own theming)
```

### Step 3: Verify

Run `nix flake check` to ensure configuration is valid.

## Expected Behavior After Fix

### DESK_AGA (Plasma6 only)
- ❌ No Stylix modules loaded
- ❌ No qt5ct/qt6ct files generated
- ❌ No GTK theme files from Stylix
- ✅ Plasma 6 manages all Qt/GTK theming natively
- ✅ Clean, conflict-free theming
- ✅ Breeze theme in Plasma applications

### DESK (Sway + Plasma6)
- ✅ Stylix enabled for Sway sessions
- ✅ Stylix containment prevents leakage into Plasma
- ✅ Both environments work independently

### DESK_VMDESK (Sway + Plasma6 VM)
- ✅ Stylix enabled for Sway sessions
- ✅ VM benefits from same dual-WM setup as DESK

## Benefits of Fix

1. **Clarity**: Explicit override makes intent clear (Plasma6-only = no Stylix)
2. **Performance**: Reduces unnecessary package installations and file generation
3. **Maintainability**: Follows established pattern (disable Stylix when only Plasma6)
4. **Theme Consistency**: Plasma6 fully owns its theming without Stylix interference
5. **Correctness**: Aligns configuration with actual usage (no Sway = no Stylix)

## Testing Checklist

After implementing fix:

- [ ] Build DESK_AGA profile successfully (`nix flake check`)
- [ ] Verify no Stylix packages installed on DESK_AGA
- [ ] Check Plasma 6 theming works natively (Breeze, etc.)
- [ ] Confirm no qt5ct/qt6ct files in `~/.config/` on DESK_AGA
- [ ] Verify GTK apps use Plasma settings (not Stylix)
- [ ] Ensure Plasma color schemes work properly

## Files Involved

- `profiles/DESK_AGA-config.nix` - Add explicit `stylixEnable = false` override

## Conclusion

**Status**: ✅ Stylix flag verification PASSED - all imports are conditional

**Issue Found**: ❌ DESK_AGA incorrectly inherits `stylixEnable = true`

**Fix Required**: 🔧 Add explicit override `stylixEnable = false` to DESK_AGA

**Complexity**: Low - single-line override addition

**Risk**: Minimal - disabling Stylix for Plasma6-only profile is correct behavior
