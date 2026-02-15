# Debug Instrumentation Analysis

**Date**: 2026-01-XX  
**Status**: Complete Analysis  
**Purpose**: Document all debugging instrumentation found in codebase for removal/conditionalization

---

## Executive Summary

This document provides a comprehensive analysis of all debugging instrumentation found in the codebase. The analysis identified **37+ JSON debug log statements**, **verbose mode flags**, and **debug file creation** across multiple files. All instrumentation appears to be left over from development/debugging sessions and should be removed or made conditional.

---

## Findings by File

### 1. `user/wm/sway/default.nix` - Extensive JSON Logging

**Total Instances**: 37+ JSON log statements + 2 simple DEBUG echo statements

#### JSON Logging Categories

**Category A: Daemon Startup/Crash (Hypothesis ID: "A")**
- **Purpose**: Track daemon startup, immediate crashes, and verification
- **Locations**: Lines 606-607, 690-701, 710-712, 750-758, 767-777, 810-812, 836-837, 847-848, 892-898, 903-905, 910-916
- **Count**: ~15 instances
- **Impact**: High - Logs on every daemon start/restart

**Category B: Health Monitor (Hypothesis ID: "B")**
- **Purpose**: Track daemon health monitoring, restarts, and recovery
- **Locations**: Lines 1060-1063, 1066-1071, 1128-1130, 1136-1138, 1143-1145, 1157-1159, 1171-1173, 1186-1188, 1190-1192, 1198-1200, 1209-1211
- **Count**: ~11 instances
- **Impact**: High - Logs every 30 seconds during health checks

**Category C: Waybar-Specific Issues (Hypothesis ID: "C")**
- **Purpose**: Debug Waybar startup issues, SwayFX IPC, environment checks
- **Locations**: Lines 552-555, 616-621, 631-644, 767-777, 810-812, 836-837, 847-848
- **Count**: ~8 instances
- **Impact**: Medium - Only logs for waybar daemon

**Category D: Waybar Instance Checking (Hypothesis ID: "D")**
- **Purpose**: Track waybar instance detection and cleanup
- **Locations**: Line 480
- **Count**: 1 instance
- **Impact**: Medium - Logs during waybar startup

**Simple DEBUG Echo Statements**:
- **Location**: Lines 16-17
- **Purpose**: Log theme variable execution
- **Impact**: Low - Only logs during Sway startup

#### Log File Location
All JSON logs write to: `/home/akunito/.dotfiles/.cursor/debug.log`

#### Log Format
```json
{
  "timestamp": <unix_timestamp_ms>,
  "location": "<component>:<function>",
  "message": "<description>",
  "data": { ... },
  "hypothesisId": "A|B|C|D",
  "sessionId": "debug-session",
  "runId": "run1"
}
```

#### Performance Impact
- **Disk I/O**: 37+ write operations per daemon lifecycle
- **CPU**: JSON serialization and date formatting on every log
- **Disk Space**: Log file grows continuously (no rotation)
- **Frequency**: 
  - Startup: ~15 logs per daemon
  - Health Monitor: ~11 logs every 30 seconds
  - Waybar-specific: ~8 logs per waybar start

---

### 2. `system/wm/plasma6.nix` - SDDM Verbose Mode

**Location**: Lines 64-67, 157

**Type**: `set -x` verbose mode + debug log file

**Details**:
- `set -x` enables bash command tracing (prints every command before execution)
- All output redirected to `/tmp/sddm-rotation.log`
- Wrapped in `# #region agent log` / `# #endregion` comments
- Extensive echo statements for debugging monitor detection (lines 69-157)

**Impact**: 
- **Startup Time**: Verbose mode adds overhead to SDDM startup
- **Disk I/O**: Logs every command execution during monitor rotation
- **Disk Space**: Log file in `/tmp` (cleared on reboot, but can grow during session)

**Conditional**: Only enabled on DESK system (hostname: nixosaku)

---

### 3. `user/style/stylix.nix` - Debug Configuration File

**Location**: Lines 17-24

**Type**: Debug configuration file creation

**Details**:
```nix
home.file.".stylix-debug.log".text = ''
  stylixEnabled: ${toString systemSettings.stylixEnable}
  userSettings.wm: ${userSettings.wm}
  systemSettings.enableSwayForDESK: ${toString systemSettings.enableSwayForDESK}
  stylix.targets.qt.enable: true
  stylix.targets.gtk.enable: true
'';
```

**Impact**: 
- **Disk Space**: Creates a small debug file in home directory
- **Maintenance**: File persists and may become outdated
- **Low Impact**: Minimal, but unnecessary in production

---

### 4. `install.sh` - Commented Debug Flag

**Location**: Line 5

**Type**: Commented out `set -x`

**Details**:
```bash
# set -x # enable for output debugging
```

**Impact**: None - Already disabled, informational only

---

### 5. `user/app/doom-emacs/doom.org` and `init.el` - Debugger Statements

**Location**: Multiple locations (found via grep)

**Type**: Emacs Lisp `debugger` statements

**Details**: Found in Emacs configuration files

**Impact**: Unknown - May be intentional for Emacs debugging workflow. Requires manual review to determine if intentional.

---

## Dependency Analysis

### Debug Log File Dependencies

**Searched for references to**:
- `.cursor/debug.log`
- `.stylix-debug.log`
- `/tmp/sddm-rotation.log`

**Results**:
- ✅ **No scripts depend on debug log files**
- ✅ **No documentation references debug log files**
- ✅ **No other code reads from debug log files**

**Conclusion**: Debug log files are write-only and safe to remove.

---

## Categorization by Priority

### High Priority (Remove/Make Conditional)

1. **JSON Logging in `user/wm/sway/default.nix`** (37+ instances)
   - **Impact**: Performance (disk I/O, CPU), Disk Space
   - **Frequency**: High (every daemon start, every 30s health check)
   - **Recommendation**: Remove or make conditional via environment variable

2. **SDDM Verbose Mode in `system/wm/plasma6.nix`** (`set -x`)
   - **Impact**: Startup Time, Disk I/O
   - **Frequency**: Every SDDM startup
   - **Recommendation**: Remove or make conditional

### Medium Priority (Remove)

3. **SDDM Debug Log File** (`/tmp/sddm-rotation.log`)
   - **Impact**: Disk Space, Maintenance
   - **Frequency**: Every SDDM startup
   - **Recommendation**: Remove debug logging (keep functional echo statements if needed)

### Low Priority (Remove)

4. **Theme Variables DEBUG Echo** (`user/wm/sway/default.nix` lines 16-17)
   - **Impact**: Minimal (2 echo statements)
   - **Frequency**: Every Sway startup
   - **Recommendation**: Remove

5. **Stylix Debug File** (`user/style/stylix.nix` lines 17-24)
   - **Impact**: Minimal (small file creation)
   - **Frequency**: Every Home Manager switch
   - **Recommendation**: Remove

### Informational (No Action Needed)

6. **Commented Debug Flag** (`install.sh` line 5)
   - **Impact**: None
   - **Recommendation**: Keep as-is (already disabled)

7. **Emacs Debugger Statements** (`doom-emacs` files)
   - **Impact**: Unknown
   - **Recommendation**: Manual review required

---

## Detailed Removal Plan

### File 1: `user/wm/sway/default.nix`

#### Action: Remove or Make Conditional

**Option A: Complete Removal** (Recommended for production)
- Remove all `# #region agent log` / `# #endregion` blocks (37+ instances)
- Remove JSON echo statements
- Remove simple DEBUG echo statements (lines 16-17)
- **Estimated Lines Removed**: ~150-200 lines

**Option B: Make Conditional** (Recommended for development)
- Add environment variable check: `if [ -n "$SWAY_DEBUG_LOGGING" ]; then ... fi`
- Wrap all agent log regions in conditional
- Keep code structure for future debugging
- **Estimated Lines Modified**: ~200 lines

**Specific Locations to Remove/Modify**:
1. Lines 15-17: Simple DEBUG echo statements
2. Lines 479-481: Waybar instance checking
3. Lines 551-555: SwayFX not ready
4. Lines 605-607: Daemon start
5. Lines 615-621: Waybar environment checks
6. Lines 631-644: Waybar socket checks
7. Lines 690-701: Immediate crash logging
8. Lines 710-712: Process alive check
9. Lines 750-758: Verification checks
10. Lines 767-777: Waybar post-verification
11. Lines 810-812: Waybar crash timing
12. Lines 836-837: Waybar crash details
13. Lines 847-848: Waybar healthy
14. Lines 892-898: Config validation
15. Lines 903-905: Config missing
16. Lines 910-916: CSS file checks
17. Lines 1060-1063: Health monitor waybar running
18. Lines 1066-1071: Health monitor waybar not found
19. Lines 1128-1130: Health monitor waybar down
20. Lines 1136-1138: Restart limit
21. Lines 1143-1145: Daemon down
22. Lines 1157-1159: Restart attempt
23. Lines 1171-1173: Restart success
24. Lines 1186-1188: Restart failed
25. Lines 1190-1192: Restart failed (generic)
26. Lines 1198-1200: Restart command failed
27. Lines 1209-1211: Daemon healthy

#### Recommendation: **Option A (Complete Removal)** for production, **Option B (Conditional)** if debugging is still needed

---

### File 2: `system/wm/plasma6.nix`

#### Action: Remove Verbose Mode and Debug Logging

**Changes Required**:
1. **Line 64**: Remove `# #region agent log` comment
2. **Line 65**: Remove `LOGFILE="/tmp/sddm-rotation.log"` (or make conditional)
3. **Line 66**: Remove `exec >"$LOGFILE" 2>&1` (or make conditional)
4. **Line 67**: Remove `set -x` (or make conditional)
5. **Line 158**: Remove `# #endregion` comment

**Keep**: Functional echo statements (lines 69-157) that provide useful information, but remove excessive debugging

**Option**: Make verbose mode conditional:
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

**Estimated Lines Removed**: 3-5 lines (if removing completely)

#### Recommendation: **Remove verbose mode and log redirection**, keep functional echo statements

---

### File 3: `user/style/stylix.nix`

#### Action: Remove Debug File Creation

**Changes Required**:
- **Lines 17-24**: Remove entire `home.file.".stylix-debug.log"` block

**Estimated Lines Removed**: 8 lines

#### Recommendation: **Remove completely** - Configuration state can be checked via other means

---

### File 4: `install.sh`

#### Action: No Action Required

**Status**: Already disabled (commented out)

**Recommendation**: **Keep as-is** - May be useful for future debugging

---

### File 5: `user/app/doom-emacs/doom.org` and `init.el`

#### Action: Manual Review Required

**Status**: Requires manual inspection to determine if `debugger` statements are intentional

**Recommendation**: **Manual review** - Emacs debugger statements may be part of development workflow

---

## Implementation Strategy

### Phase 1: High Priority Items (Immediate)

1. Remove JSON logging from `user/wm/sway/default.nix`
2. Remove SDDM verbose mode from `system/wm/plasma6.nix`
3. Test system after changes

### Phase 2: Medium/Low Priority Items

1. Remove Stylix debug file creation
2. Remove theme variables DEBUG echo
3. Clean up any remaining debug instrumentation

### Phase 3: Verification

1. Verify no regressions
2. Check system performance improvements
3. Verify disk space savings
4. Update documentation if needed

---

## Expected Benefits

### Performance Improvements
- **Reduced Disk I/O**: ~37+ fewer write operations per daemon lifecycle
- **Reduced CPU Usage**: No JSON serialization overhead
- **Faster Startup**: SDDM startup without verbose mode overhead

### Disk Space Savings
- **Debug Log Files**: No continuous growth of `.cursor/debug.log`
- **SDDM Log**: No `/tmp/sddm-rotation.log` creation
- **Stylix Debug**: No `.stylix-debug.log` file

### Code Cleanliness
- **Reduced Complexity**: ~200 fewer lines of debug code
- **Easier Maintenance**: Less code to maintain
- **Clearer Intent**: Production code without debug instrumentation

---

## Risk Assessment

### Low Risk
- Removing debug logging has no functional impact
- Debug logs are write-only (no dependencies)
- System functionality remains unchanged

### Medium Risk
- If debugging is still needed, removal makes troubleshooting harder
- **Mitigation**: Make logging conditional instead of removing

### Testing Required
- Test daemon startup after removing JSON logs
- Test SDDM startup after removing verbose mode
- Verify no regressions in daemon management

---

## Recommendations Summary

1. **Immediate Action**: Remove all JSON debug logging from `user/wm/sway/default.nix` (37+ instances)
2. **Immediate Action**: Remove SDDM verbose mode and log redirection from `system/wm/plasma6.nix`
3. **Short-term**: Remove Stylix debug file and theme variable DEBUG echo
4. **Future**: Consider adding conditional debug mode if debugging is still needed
5. **Manual Review**: Check Emacs debugger statements for intentional use

---

## Conclusion

All identified debug instrumentation appears to be left over from development/debugging sessions. The extensive JSON logging (37+ instances) has the highest impact and should be removed first. SDDM verbose mode should also be removed to improve startup performance. Lower priority items can be cleaned up in subsequent phases.

**Total Estimated Impact**:
- **Lines to Remove/Modify**: ~200-250 lines
- **Performance Improvement**: Reduced disk I/O and CPU usage
- **Disk Space Savings**: No continuous log file growth
- **Risk Level**: Low (no functional dependencies)

