# Debug Instrumentation Removal Plan

**Date**: 2026-01-XX  
**Status**: Ready for Implementation  
**Related**: See `debug-instrumentation-analysis.md` for full analysis

---

## Overview

This document provides a step-by-step removal plan for all debug instrumentation found in the codebase. Each item includes specific file locations, line numbers, and exact code to remove.

---

## Removal Checklist

- [ ] Remove JSON logging from `user/wm/sway/default.nix` (37+ instances)
- [ ] Remove DEBUG echo statements from `user/wm/sway/default.nix` (2 instances)
- [ ] Remove SDDM verbose mode from `system/wm/plasma6.nix`
- [ ] Remove Stylix debug file from `user/style/stylix.nix`
- [ ] Test system after changes
- [ ] Verify no regressions

---

## File 1: `user/wm/sway/default.nix`

### Section 1.1: Remove Simple DEBUG Echo Statements

**Location**: Lines 15-17

**Current Code**:
```nix
    # DEBUG: Log to debug file
    echo "DEBUG: set-sway-theme-vars executed - QT_QPA_PLATFORMTHEME=$QT_QPA_PLATFORMTHEME GTK_THEME=$GTK_THEME" >> /home/akunito/.dotfiles/.cursor/debug.log
    echo "DEBUG: dbus-update-activation-environment completed" >> /home/akunito/.dotfiles/.cursor/debug.log
```

**Action**: Remove lines 15-17

**After Removal**:
```nix
    dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP QT_QPA_PLATFORMTHEME GTK_THEME GTK_APPLICATION_PREFER_DARK_THEME
  '';
```

---

### Section 1.2: Remove JSON Logging Blocks

All JSON logging blocks follow this pattern:
```bash
# #region agent log
echo "{...JSON...}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
# #endregion
```

**Action**: Remove each block entirely (including region markers)

#### Block 1: Waybar Instance Checking
- **Location**: Lines 479-481
- **Remove**: Lines 479-481

#### Block 2: SwayFX Not Ready
- **Location**: Lines 551-555
- **Remove**: Lines 551-555

#### Block 3: Daemon Start
- **Location**: Lines 605-607
- **Remove**: Lines 605-607

#### Block 4: Waybar Environment Check (Not Set)
- **Location**: Lines 615-617
- **Remove**: Lines 615-617

#### Block 5: Waybar Environment Check (Set)
- **Location**: Lines 619-621
- **Remove**: Lines 619-621

#### Block 6: Waybar Socket Found
- **Location**: Lines 631-633
- **Remove**: Lines 631-633

#### Block 7: Waybar Socket Not Found
- **Location**: Lines 636-638
- **Remove**: Lines 636-638

#### Block 8: SwayFX Process Not Found
- **Location**: Lines 642-644
- **Remove**: Lines 642-644

#### Block 9: Waybar Immediate CSS Crash
- **Location**: Lines 690-692
- **Remove**: Lines 690-692

#### Block 10: Immediate Crash (with CSS errors false)
- **Location**: Lines 694-696
- **Remove**: Lines 694-696

#### Block 11: Immediate Crash (generic)
- **Location**: Lines 699-701
- **Remove**: Lines 699-701

#### Block 12: Immediate Crash (no logs)
- **Location**: Lines 705-707
- **Remove**: Lines 705-707

#### Block 13: Process Alive
- **Location**: Lines 710-712
- **Remove**: Lines 710-712

#### Block 14: Verification Success
- **Location**: Lines 750-752
- **Remove**: Lines 750-752

#### Block 15: Verification Check (not found)
- **Location**: Lines 756-758
- **Remove**: Lines 756-758

#### Block 16: Waybar Pre-Check
- **Location**: Lines 766-768
- **Remove**: Lines 766-768

#### Block 17: Waybar CSS Errors
- **Location**: Lines 776-778
- **Remove**: Lines 776-778

#### Block 18: Waybar Crash Timing
- **Location**: Lines 810-812
- **Remove**: Lines 810-812

#### Block 19: Waybar Crash (detailed)
- **Location**: Lines 835-837
- **Remove**: Lines 835-837

#### Block 20: Waybar Crash (no logs)
- **Location**: Lines 839-841
- **Remove**: Lines 839-841

#### Block 21: Waybar Healthy
- **Location**: Lines 846-848
- **Remove**: Lines 846-848

#### Block 22: Config Validation Failed
- **Location**: Lines 892-894
- **Remove**: Lines 892-894

#### Block 23: Config Valid
- **Location**: Lines 896-898
- **Remove**: Lines 896-898

#### Block 24: Config Missing
- **Location**: Lines 903-905
- **Remove**: Lines 903-905

#### Block 25: CSS Exists
- **Location**: Lines 914-916
- **Remove**: Lines 914-916

#### Block 26: Health Monitor - Waybar Running
- **Location**: Lines 1060-1063
- **Remove**: Lines 1060-1063

#### Block 27: Health Monitor - Waybar Not Found
- **Location**: Lines 1066-1071
- **Remove**: Lines 1066-1071

#### Block 28: Health Monitor - Waybar Down Detected
- **Location**: Lines 1128-1130
- **Remove**: Lines 1128-1130

#### Block 29: Restart Limit
- **Location**: Lines 1136-1138
- **Remove**: Lines 1136-1138

#### Block 30: Daemon Down
- **Location**: Lines 1143-1145
- **Remove**: Lines 1143-1145

#### Block 31: Restart Attempt
- **Location**: Lines 1157-1159
- **Remove**: Lines 1157-1159

#### Block 32: Restart Success
- **Location**: Lines 1171-1173
- **Remove**: Lines 1171-1173

#### Block 33: Restart Failed (Waybar)
- **Location**: Lines 1186-1188
- **Remove**: Lines 1186-1188

#### Block 34: Restart Failed (generic)
- **Location**: Lines 1190-1192
- **Remove**: Lines 1190-1192

#### Block 35: Restart Command Failed
- **Location**: Lines 1198-1200
- **Remove**: Lines 1198-1200

#### Block 36: Daemon Healthy
- **Location**: Lines 1209-1211
- **Remove**: Lines 1209-1211

**Total Blocks to Remove**: 36 JSON logging blocks + 1 simple DEBUG section = 37 sections

---

## File 2: `system/wm/plasma6.nix`

### Section 2.1: Remove SDDM Verbose Mode and Debug Logging

**Location**: Lines 63-67, 158

**Current Code** (lines 63-67):
```nix
    services.displayManager.sddm.setupScript = ''
      # Redirect all output to log file for debugging
      # #region agent log
      LOGFILE="/tmp/sddm-rotation.log"
      exec >"$LOGFILE" 2>&1
      set -x  # Enable verbose mode to see all commands
```

**Action**: Remove lines 63-64, 65-67 (keep functional echo statements)

**After Removal**:
```nix
    services.displayManager.sddm.setupScript = ''
      # Monitor rotation script for DESK profile
```

**Also Remove**: Line 158 (`# #endregion`)

**Note**: Keep all functional echo statements (lines 69-157) as they provide useful information, but remove the verbose mode and log redirection.

---

## File 3: `user/style/stylix.nix`

### Section 3.1: Remove Stylix Debug File

**Location**: Lines 17-24

**Current Code**:
```nix
  # DEBUG: Log Stylix configuration state
  home.file.".stylix-debug.log".text = ''
    stylixEnabled: ${toString systemSettings.stylixEnable}
    userSettings.wm: ${userSettings.wm}
    systemSettings.enableSwayForDESK: ${toString systemSettings.enableSwayForDESK}
    stylix.targets.qt.enable: true
    stylix.targets.gtk.enable: true
  '';
```

**Action**: Remove lines 17-24

**After Removal**: Remove entire block (no replacement needed)

---

## Implementation Steps

### Step 1: Backup Current Files
```bash
cp user/wm/sway/default.nix user/wm/sway/default.nix.backup
cp system/wm/plasma6.nix system/wm/plasma6.nix.backup
cp user/style/stylix.nix user/style/stylix.nix.backup
```

### Step 2: Remove Debug Instrumentation

1. **Remove from `user/wm/sway/default.nix`**:
   - Remove lines 15-17 (DEBUG echo)
   - Remove all 36 JSON logging blocks (lines listed above)

2. **Remove from `system/wm/plasma6.nix`**:
   - Remove lines 63-64, 65-67 (verbose mode and log redirection)
   - Remove line 158 (`# #endregion`)

3. **Remove from `user/style/stylix.nix`**:
   - Remove lines 17-24 (debug file creation)

### Step 3: Verify Syntax
```bash
# Check Nix syntax
nix-instantiate --parse user/wm/sway/default.nix
nix-instantiate --parse system/wm/plasma6.nix
nix-instantiate --parse user/style/stylix.nix
```

### Step 4: Test System
```bash
# Dry run rebuild
nixos-rebuild build --flake .#DESK

# If successful, apply changes
nixos-rebuild switch --flake .#DESK
```

### Step 5: Verify Functionality
- [ ] Sway daemons start correctly
- [ ] SDDM starts without errors
- [ ] No debug log files are created
- [ ] System performance is normal

---

## Alternative: Conditional Debug Mode

If debugging is still needed, consider making logging conditional:

### Option: Environment Variable Check

**For `user/wm/sway/default.nix`**:
```bash
# At the start of daemon-manager script
if [ -z "$SWAY_DEBUG_LOGGING" ]; then
  # Define empty function
  debug_log() { :; }
else
  # Define actual logging function
  debug_log() {
    echo "$1" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
  }
fi

# Replace all JSON echo statements with:
debug_log "{\"timestamp\":...}"
```

**For `system/wm/plasma6.nix`**:
```nix
services.displayManager.sddm.setupScript = ''
  ${if systemSettings.debugMode then ''
    LOGFILE="/tmp/sddm-rotation.log"
    exec >"$LOGFILE" 2>&1
    set -x
  '' else ''}
  # ... rest of script ...
'';
```

**Recommendation**: Use complete removal for production, conditional mode only if active debugging is needed.

---

## Verification Checklist

After removal, verify:

- [ ] No `.cursor/debug.log` file is created
- [ ] No `/tmp/sddm-rotation.log` file is created
- [ ] No `.stylix-debug.log` file is created
- [ ] Sway daemons start normally
- [ ] SDDM starts without verbose output
- [ ] System performance is unchanged or improved
- [ ] No errors in system logs

---

## Rollback Plan

If issues occur after removal:

1. **Restore from backup**:
   ```bash
   cp user/wm/sway/default.nix.backup user/wm/sway/default.nix
   cp system/wm/plasma6.nix.backup system/wm/plasma6.nix
   cp user/style/stylix.nix.backup user/style/stylix.nix
   ```

2. **Rebuild system**:
   ```bash
   nixos-rebuild switch --flake .#DESK
   ```

3. **Investigate issues** before attempting removal again

---

## Summary

**Total Changes**:
- **Files Modified**: 3
- **Lines Removed**: ~200-250
- **Debug Blocks Removed**: 37
- **Risk Level**: Low (no functional dependencies)

**Expected Benefits**:
- Reduced disk I/O
- Reduced CPU usage
- Faster SDDM startup
- Cleaner codebase
- No continuous log file growth

