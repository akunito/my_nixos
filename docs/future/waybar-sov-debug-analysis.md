# Waybar and Sov Startup Failure - Comprehensive Debug Analysis

**Date**: 2026-01-07  
**Issue**: Neither waybar, waybar dock, nor sov are starting after system rebuild and Sway session restart  
**Status**: Critical - All three components failing

---

## Executive Summary

After the latest changes to the daemon-manager script (adding pipe detection and enhanced error logging), waybar, waybar dock, and sov are all failing to start. The logs indicate "successful" startup, but the processes are not actually running. This document contains all findings, root cause analysis, and proposed solutions.

---

## Current System State

### Process Status
- **Waybar**: NOT running (only swaybar - SwayFX's internal bar - is running)
- **Waybar Dock**: NOT running (no second waybar instance visible)
- **Sov**: NOT running (only tail processes for log files are running, no actual sov process)

### Log Files Status
- Waybar error logs: **Missing** (no `/tmp/daemon-*/bin/waybar-stderr.log` files found)
- Sov error logs: **Empty** (`/tmp/'daemon-sov.*-t 500-stderr.log'` exists but is empty)
- Sov stdout logs: **Empty** (`/tmp/'daemon-sov.*-t 500-stdout.log'` exists but is empty)
- Sov pipe: **Missing** (`/tmp/sovpipe` does not exist)

### Configuration Files
- Waybar config: ✅ Exists at `/home/akunito/.config/waybar/config`
- Waybar CSS: ✅ Exists at `/home/akunito/.config/waybar/style.css`
- Waybar binary: ✅ Exists at `/nix/store/g2r7rc3p1d6m36d5y1ja53rkranfgxwr-waybar-0.14.0/bin/waybar`

---

## Log Analysis

### Journalctl Logs (Last 10 minutes)

**Key Findings**:

1. **Waybar Startup**:
   ```
   Jan 07 03:03:09 ERROR: Daemon process died immediately (PID: 201648, pattern: /bin/waybar). No error log available.
   Jan 07 03:03:10 Daemon started successfully: /bin/waybar (started PID: 201648, actual PID: 201387, verified after 0.5s)
   ```
   - **Problem**: The log says "started successfully" but PID mismatch (201648 vs 201387)
   - **Problem**: Error log says "No error log available" - log file wasn't created
   - **Problem**: Process 201387 doesn't exist anymore (checked via `ps aux`)

2. **Sov Startup**:
   ```
   Jan 07 03:03:16 Starting daemon: sov.*-t 500 (command: rm -f /tmp/sovpipe && mkfifo /tmp/sovpipe && ...)
   Jan 07 03:03:16 Detected pipe in command, using bash: sov.*-t 500
   Jan 07 03:03:16 Daemon start command executed, PID: 203872 (pattern: sov.*-t 500, has_pipe: true)
   Jan 07 03:03:17 ERROR: Daemon process died immediately (PID: 203872, pattern: sov.*-t 500). Error:
   Jan 07 03:03:17 Daemon started successfully: sov.*-t 500 (started PID: 203872, actual PID: 201740, verified after 0.5s)
   ```
   - **Problem**: Error log is empty (no error message captured)
   - **Problem**: PID mismatch (203872 vs 201740)
   - **Problem**: Process 201740 doesn't exist anymore
   - **Problem**: Only tail processes are running: `tail -f /tmp/daemon-sov.*-t 500-stdout.log` and `tail -f /tmp/daemon-sov.*-t 500-stderr.log`

3. **Log File Naming Issue**:
   ```
   /tmp/'daemon-sov.*-t 500-stderr.log'
   /tmp/'daemon-sov.*-t 500-stdout.log'
   ```
   - **Problem**: Filenames contain quotes and special characters (`.*`)
   - **Problem**: Pattern contains regex characters that are being interpreted literally in filenames
   - **Problem**: Shell escaping issues when accessing these files

---

## Root Cause Analysis

### Issue 1: Log File Path Construction with Special Characters

**Location**: `user/wm/sway/default.nix` lines 458-460

**Problem**:
```bash
STDOUT_LOG="/tmp/daemon-''${PATTERN}-stdout.log"
STDERR_LOG="/tmp/daemon-''${PATTERN}-stderr.log"
```

When `PATTERN` contains special characters like `sov.*-t 500`, the filename becomes:
- `/tmp/daemon-sov.*-t 500-stdout.log` (with literal `.*` and space)

**Issues**:
1. Shell glob expansion: `.*` might be expanded by the shell
2. Spaces in filename: Requires quoting, but quotes are being added incorrectly
3. Pattern matching characters: `.*` is regex, not a valid filename character

**Evidence**:
- Log files exist with quotes: `/tmp/'daemon-sov.*-t 500-stderr.log'`
- Empty error logs suggest the process can't write to these files
- Manual test shows waybar works when run directly (not through daemon-manager)

### Issue 2: Process Tracking with `exec` Command

**Location**: `user/wm/sway/default.nix` lines 464, 467

**Problem**:
```bash
nohup sh -c "exec $COMMAND" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
DAEMON_PID=$!
```

**Issues**:
1. `exec` replaces the shell process, so `$!` captures the shell PID, not the actual command PID
2. If the command fails immediately, the shell process dies and we lose track
3. The verification step (line 493) uses `pgrep` which finds a different PID than `$!`

**Evidence**:
- Logs show PID mismatch: "started PID: 201648, actual PID: 201387"
- Process 201387 doesn't exist (already died)
- Manual test without `exec` works: `nohup sh -c "waybar ..." &` keeps process alive

### Issue 3: Pipe Command Execution in Background

**Location**: `user/wm/sway/default.nix` line 464

**Problem**:
```bash
nohup bash -c "exec $COMMAND" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
```

For sov command: `rm -f /tmp/sovpipe && mkfifo /tmp/sovpipe && tail -f /tmp/sovpipe | sov -t 500`

**Issues**:
1. `exec` with a pipe command: `exec` replaces the shell, but pipes need the shell to coordinate
2. Background execution: `nohup` + `&` + `exec` creates a complex process tree
3. Pipe creation timing: `mkfifo` might complete, but `tail` might start before the pipe is ready
4. Process tracking: The PID captured is the shell, but the actual processes are `tail` and `sov`

**Evidence**:
- Only `tail` processes are running, not `sov`
- Pipe doesn't exist (`/tmp/sovpipe` missing)
- Error log is empty (process died before writing)

### Issue 4: Tail Processes for Log Monitoring

**Location**: `user/wm/sway/default.nix` lines 485-486

**Problem**:
```bash
(tail -f "$STDOUT_LOG" 2>/dev/null | systemd-cat -t "sway-daemon-''${PATTERN}" -p info &) || true
(tail -f "$STDERR_LOG" 2>/dev/null | systemd-cat -t "sway-daemon-''${PATTERN}" -p err &) || true
```

**Issues**:
1. These background processes never exit (they're tailing files that might not exist)
2. They're using the same problematic `$PATTERN` variable with special characters
3. If log files don't exist or have wrong names, `tail` hangs waiting for files

**Evidence**:
- Only tail processes are running for sov: `tail -f /tmp/daemon-sov.*-t 500-stdout.log`
- These processes are orphaned and never cleaned up

### Issue 5: Pattern Matching for Process Verification

**Location**: `user/wm/sway/default.nix` line 493

**Problem**:
```bash
if ${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" > /dev/null 2>&1; then
```

For pattern `sov.*-t 500`:
- `pgrep -f "sov.*-t 500"` uses regex matching
- But the actual command is: `tail -f /tmp/sovpipe | sov -t 500`
- The pattern might match `tail` instead of `sov`

**Evidence**:
- Logs show "Daemon started successfully" but only tail processes are found
- Pattern `sov.*-t 500` might be matching the wrong process

---

## Proposed Solutions

### Solution 1: Sanitize Pattern for Log File Names

**Problem**: Special characters in `PATTERN` break log file paths

**Fix**: Create a sanitized version of the pattern for use in filenames

**Implementation**:
```nix
# In daemon-manager script, add:
# Sanitize pattern for use in filenames (replace special chars with underscores)
PATTERN_SANITIZED=$(echo "$PATTERN" | tr -d '.*+?^$[](){}|' | tr ' ' '_' | tr '/' '_')
STDOUT_LOG="/tmp/daemon-''${PATTERN_SANITIZED}-stdout.log"
STDERR_LOG="/tmp/daemon-''${PATTERN_SANITIZED}-stderr.log"
```

**Location**: `user/wm/sway/default.nix` lines 458-460

**Benefits**:
- Safe filenames without special characters
- No shell glob expansion issues
- Easier to access and debug

---

### Solution 2: Remove `exec` from Daemon Startup

**Problem**: `exec` replaces the shell process, breaking PID tracking

**Fix**: Remove `exec` and let the shell manage the process

**Implementation**:
```bash
# OLD (broken):
nohup sh -c "exec $COMMAND" >"$STDOUT_LOG" 2>"$STDERR_LOG" &

# NEW (fixed):
nohup sh -c "$COMMAND" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
```

**Location**: `user/wm/sway/default.nix` lines 464, 467

**Benefits**:
- Shell process stays alive, proper PID tracking
- Process tree is clearer
- Errors are captured correctly

**Trade-offs**:
- Slight overhead of shell process (negligible)
- Process tree shows shell + command (acceptable)

---

### Solution 3: Fix Pipe Command Execution

**Problem**: `exec` with pipe commands doesn't work correctly

**Fix**: For pipe commands, don't use `exec`, and ensure proper process group

**Implementation**:
```bash
if [ "$HAS_PIPE" = "true" ]; then
  # Pipe command - use bash without exec, run in subshell for proper pipe handling
  nohup bash -c "$COMMAND" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
else
  # Simple command - use sh without exec
  nohup sh -c "$COMMAND" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
fi
```

**Location**: `user/wm/sway/default.nix` lines 462-468

**Benefits**:
- Pipes work correctly
- Process tracking is accurate
- All processes in pipe are managed

---

### Solution 4: Improve Process Verification

**Problem**: PID mismatch and false positives in verification

**Fix**: Verify the actual command process, not just pattern match

**Implementation**:
```bash
# After starting daemon, wait a moment then verify
sleep 0.5
# Check if the started PID is still alive and matches the pattern
if kill -0 $DAEMON_PID 2>/dev/null; then
  # Process is alive, verify it matches our pattern
  if ${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" | grep -q "^$DAEMON_PID$"; then
    log "Daemon started successfully: $PATTERN (PID: $DAEMON_PID)" "info"
    DAEMON_STARTED=true
  else
    # PID exists but doesn't match pattern - might be wrong process
    log "WARNING: Started PID $DAEMON_PID doesn't match pattern $PATTERN" "warning"
  fi
else
  # Process died - check error logs
  if [ -f "$STDERR_LOG" ]; then
    ERROR_OUTPUT=$(cat "$STDERR_LOG" 2>/dev/null | head -20 | tr '\n' ' ')
    log "ERROR: Daemon process died immediately (PID: $DAEMON_PID, pattern: $PATTERN). Error: $ERROR_OUTPUT" "err"
  fi
fi
```

**Location**: `user/wm/sway/default.nix` lines 472-499

**Benefits**:
- Accurate process verification
- Better error reporting
- Catches PID mismatches

---

### Solution 5: Fix Log File Tail Processes

**Problem**: Tail processes hang and use problematic filenames

**Fix**: Only start tail processes if log files exist, and use sanitized names

**Implementation**:
```bash
# Only start tail processes if log files exist and are non-empty
if [ -f "$STDOUT_LOG" ] && [ -s "$STDOUT_LOG" ]; then
  (tail -f "$STDOUT_LOG" 2>/dev/null | systemd-cat -t "sway-daemon-''${PATTERN_SANITIZED}" -p info &) || true
fi
if [ -f "$STDERR_LOG" ] && [ -s "$STDERR_LOG" ]; then
  (tail -f "$STDERR_LOG" 2>/dev/null | systemd-cat -t "sway-daemon-''${PATTERN_SANITIZED}" -p err &) || true
fi
```

**Location**: `user/wm/sway/default.nix` lines 484-486

**Benefits**:
- No orphaned tail processes
- Cleaner process tree
- Better resource usage

---

### Solution 6: Improve Pattern Matching for Sov

**Problem**: Pattern `sov.*-t 500` might match wrong processes

**Fix**: Use more specific pattern or match by command line

**Implementation**:
```nix
# In daemons list, change sov pattern:
{
  name = "sov";
  command = "rm -f /tmp/sovpipe && mkfifo /tmp/sovpipe && ${pkgs.coreutils}/bin/tail -f /tmp/sovpipe | ${pkgs.sov}/bin/sov -t 500";
  pattern = "sov -t 500";  # More specific - matches actual sov command with args
  match_type = "full";  # NixOS wrapper
  # ...
}
```

**Location**: `user/wm/sway/default.nix` line 211

**Benefits**:
- More accurate process matching
- Less likely to match wrong processes
- Clearer intent

---

## Implementation Plan

### Phase 1: Critical Fixes (Must Do)

1. **Fix log file naming** (Solution 1)
   - Add pattern sanitization
   - Update all log file path references
   - Test with patterns containing special characters

2. **Remove `exec` from daemon startup** (Solution 2)
   - Remove `exec` from both bash and sh commands
   - Update process tracking logic
   - Verify PID tracking works correctly

3. **Fix pipe command execution** (Solution 3)
   - Ensure pipe commands work without `exec`
   - Test sov startup specifically
   - Verify pipe creation and process coordination

### Phase 2: Improvements (Should Do)

4. **Improve process verification** (Solution 4)
   - Add PID validation
   - Better error reporting
   - Catch PID mismatches

5. **Fix log tail processes** (Solution 5)
   - Only start tails if files exist
   - Use sanitized pattern names
   - Clean up orphaned processes

### Phase 3: Refinements (Nice to Have)

6. **Improve pattern matching** (Solution 6)
   - Make sov pattern more specific
   - Review all patterns for accuracy
   - Test pattern matching with actual processes

---

## Testing Plan

After implementing fixes:

1. **Rebuild system**: `./install.sh ~/.dotfiles "DESK"`
2. **Restart Sway session**: Log out and back in
3. **Verify waybar**: `pgrep -f "/bin/waybar"` should show waybar process
4. **Verify waybar dock**: Check for second waybar instance (dock bar)
5. **Verify sov**: `pgrep -f "sov.*-t 500"` should show sov process
6. **Verify sov pipe**: `test -p /tmp/sovpipe && echo "Pipe exists"` should succeed
7. **Test sov keybinding**: Press Hyper+Tab, should toggle workspace overview
8. **Check logs**: `journalctl --user -t sway-daemon-mgr | tail -50` should show successful startups
9. **Check error logs**: `/tmp/daemon-*-stderr.log` files should exist and be readable
10. **Verify no orphaned processes**: `ps aux | grep tail | grep daemon` should show minimal tail processes

---

## Risk Assessment

### High Risk
- **Removing `exec`**: Might change process behavior, but testing shows it's necessary
- **Pattern sanitization**: Must ensure all pattern references are updated

### Medium Risk
- **Log file changes**: Need to ensure all log file accesses use sanitized names
- **Process verification changes**: Might affect other daemons

### Low Risk
- **Tail process cleanup**: Only affects logging, not core functionality
- **Pattern matching improvements**: Only affects sov, well-isolated

---

## Additional Notes

### Why Waybar Works Manually But Not Via Daemon-Manager

Manual test shows waybar works:
```bash
nohup sh -c "/nix/store/.../waybar -c /home/akunito/.config/waybar/config" >/tmp/test-stdout.log 2>/tmp/test-stderr.log &
```

But daemon-manager fails. The difference is:
1. Manual test doesn't use `exec`
2. Manual test uses simple log file names
3. Manual test doesn't have pattern matching issues

### Why Sov Fails Specifically

Sov has additional complexity:
1. Pipe command requires bash
2. Multiple processes (tail + sov)
3. Named pipe creation timing
4. Pattern contains regex characters

The combination of all these issues makes sov particularly fragile.

---

## Conclusion

The root causes are:
1. **Log file naming with special characters** - breaks file access
2. **`exec` command breaking PID tracking** - causes false positives
3. **Pipe command execution issues** - sov can't start correctly
4. **Process verification logic** - doesn't catch actual failures
5. **Orphaned tail processes** - resource leak

All fixes are straightforward and low-risk. The primary fix is removing `exec` and sanitizing log file names.

---

## References

- **Daemon Manager Script**: `user/wm/sway/default.nix` lines 264-507
- **Daemon Definitions**: `user/wm/sway/default.nix` lines 167-261
- **Waybar Configuration**: `user/wm/sway/waybar.nix`
- **Sov Configuration**: `user/wm/sway/default.nix` lines 1154-1233

---

**Document Status**: Ready for review and implementation  
**Next Steps**: User to review and approve plan before implementation

