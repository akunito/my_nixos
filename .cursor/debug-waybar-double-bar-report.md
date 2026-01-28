# Waybar Double Top Bar Debug Report

**Date**: $(date)
**Status**: CONFIRMED - 2 waybar instances running
**Plan Reference**: `debug_duplicate_waybar_instances_ac359028.plan.md`

## Current State

### Running Processes
```
PID 3700: /nix/store/g2r7rc3p1d6m36d5y1ja53rkranfgxwr-waybar-0.14.0/bin/waybar -l info -c /home/akunito/.config/waybar/config
PID 3720: /nix/store/g2r7rc3p1d6m36d5y1ja53rkranfgxwr-waybar-0.14.0/bin/waybar -l info -c /home/akunito/.config/waybar/config
```

**Count**: 2 waybar instances (both identical commands, same store path)

### Configuration
- **Pattern**: `^${pkgs.waybar}/bin/waybar` (anchored pattern)
- **Match Type**: `full` (uses `pgrep -f`)
- **Command**: `${pkgs.waybar}/bin/waybar -l info -c ${config.xdg.configHome}/waybar/config`

## Issues Confirmed (Matching Plan)

### Issue 1: Pattern Check Bug ✅ CONFIRMED

**Location**: `user/wm/sway/default.nix` line 324

**Current Code**:
```bash
if echo "$PATTERN" | grep -q "waybar -c"; then
```

**Test Results**:
- Pattern: `^/nix/store/g2r7rc3p1d6m36d5y1ja53rkranfgxwr-waybar-0.14.0/bin/waybar`
- Check: `grep -q "waybar -c"` → **DOES NOT MATCH**
- Check: `grep -q "/bin/waybar"` → **MATCHES** ✅

**Impact**: 
- Cleanup block (lines 321-359) **NEVER EXECUTES**
- Old waybar processes from previous rebuilds are not killed
- Duplicate instances accumulate

**Plan Fix**: Change to `grep -q "/bin/waybar"` (Phase 1)

### Issue 2: Store Path Extraction Bug ✅ CONFIRMED

**Location**: `user/wm/sway/default.nix` line 344

**Current Code**:
```bash
CURRENT_STORE_PATH=$(echo "$PATTERN" | sed 's|/bin/waybar.*||')
```

**Test Results**:
- Pattern: `^/nix/store/g2r7rc3p1d6m36d5y1ja53rkranfgxwr-waybar-0.14.0/bin/waybar`
- Current method result: `^/nix/store/g2r7rc3p1d6m36d5y1ja53rkranfgxwr-waybar-0.14.0` ❌ (includes `^` anchor)
- Plan method result: `/nix/store/g2r7rc3p1d6m36d5y1ja53rkranfgxwr-waybar-0.14.0` ✅ (correct)

**Impact**:
- Store path includes `^` anchor, won't match actual process command lines
- Even if cleanup runs, it can't identify old store paths correctly

**Plan Fix**: Use `dirname` approach with `cut` (Phase 2)

### Issue 3: Cleanup Logic Not Using safe_kill ✅ CONFIRMED

**Location**: `user/wm/sway/default.nix` lines 336, 351

**Current Code**:
```bash
kill -9 "$OLD_PID" 2>/dev/null || true
kill -9 "$WB_PID" 2>/dev/null || true
```

**Impact**:
- Direct `kill -9` without safety checks
- Violates Sway Daemon safe kill guidelines (should filter `$$` and `$PPID`)
- No centralized safety logic

**Plan Fix**: Create `safe_kill_pid` wrapper function (Phase 3)

## Root Cause Analysis

1. **Primary Cause**: Pattern check bug (line 324) prevents cleanup code from running
   - Pattern is `^${pkgs.waybar}/bin/waybar` (new format)
   - Check is for `"waybar -c"` (old format)
   - Mismatch causes cleanup to never execute

2. **Secondary Cause**: Store path extraction bug (line 344) would fail even if cleanup ran
   - Extracted path includes `^` anchor
   - Won't match actual process command lines
   - Cleanup logic would skip old processes

3. **Tertiary Cause**: Direct `kill -9` without safety checks
   - Violates Sway Daemon guidelines
   - Potential self-termination risk (though low in this case)

## Plan Alignment

### ✅ Plan Correctly Identifies All Issues

1. **Phase 1**: Fix pattern check from `"waybar -c"` to `"/bin/waybar"` ✅
2. **Phase 2**: Fix store path extraction using `dirname` approach ✅
3. **Phase 3**: Create `safe_kill_pid` wrapper function ✅
4. **Phase 4**: Verify lock file mechanism (already compliant) ✅
5. **Phase 5**: Add diagnostic logging ✅

### ✅ Plan Includes Critical Safety Guards

1. Store path validation (prevents false matches with legacy patterns)
2. Function scope requirements (`safe_kill_pid` in helper section)
3. Logging function verification
4. Pattern specificity notes

## Verification Tests

### Test 1: Pattern Matching
```bash
# Current pattern check (FAILS)
echo "^/nix/store/.../bin/waybar" | grep -q "waybar -c"  # → false

# Plan pattern check (PASSES)
echo "^/nix/store/.../bin/waybar" | grep -q "/bin/waybar"  # → true
```

### Test 2: Store Path Extraction
```bash
# Current method (BROKEN)
PATTERN="^/nix/store/.../bin/waybar"
CURRENT_STORE_PATH=$(echo "$PATTERN" | sed 's|/bin/waybar.*||')
# Result: "^/nix/store/..." (includes anchor, won't match)

# Plan method (CORRECT)
CLEAN_EXEC=$(echo "$PATTERN" | cut -d' ' -f1 | sed 's/^\^//')
CURRENT_STORE_PATH=$(dirname $(dirname "$CLEAN_EXEC"))
# Result: "/nix/store/..." (correct, no anchor)
```

## Recommendations

1. **IMMEDIATE**: Implement Phase 1 (pattern check fix) - this will enable cleanup code to run
2. **HIGH PRIORITY**: Implement Phase 2 (store path extraction) - ensures cleanup works correctly
3. **MEDIUM PRIORITY**: Implement Phase 3 (`safe_kill_pid`) - follows Sway Daemon guidelines
4. **LOW PRIORITY**: Implement Phase 5 (diagnostic logging) - helps future debugging

## Next Steps

1. Review this debug report
2. Confirm plan is accurate
3. Proceed with implementation following the plan phases
4. Test after each phase to verify fixes

