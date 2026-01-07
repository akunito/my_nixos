# Sov Segmentation Fault Analysis

**Date**: 2026-01-07  
**Issue**: Sov crashes with segmentation fault (exit code 139) when executed  
**Status**: Confirmed - Bug in Sov binary, not configuration issue

---

## Executive Summary

Sov (Sway Overview v0.94) crashes immediately upon execution with a segmentation fault during Wayland initialization. This is a **bug in the Sov binary itself**, not a configuration or integration issue. The crash occurs in `ku_view_get_subview` during `ku_wayland_init`.

---

## Root Cause Analysis

### Crash Details

**Stack Trace** (from `journalctl`):
```
#0  0x000055a47d44fd11 ku_view_get_subview (/nix/store/.../sov-0.94/bin/sov + 0x14d11)
#1  0x000055a47d44454f gen_init (/nix/store/.../sov-0.94/bin/sov + 0x954f)
#2  0x000055a47d45745f ku_wayland_init (/nix/store/.../sov-0.94/bin/sov + 0x1c45f)
#3  0x000055a47d4430c2 main (/nix/store/.../sov-0.94/bin/sov + 0x80c2)
```

**Exit Code**: 139 (Segmentation fault)

**Location**: Wayland initialization phase (`ku_wayland_init` → `gen_init` → `ku_view_get_subview`)

### Environment Verification

✅ **Wayland Environment**: `WAYLAND_DISPLAY=wayland-1` (correct)  
✅ **Runtime Directory**: `XDG_RUNTIME_DIR=/run/user/1000` (correct)  
✅ **Wayland Libraries**: Linked correctly (`libwayland-client.so.0`, `libwayland-cursor.so.0`, `libwayland-egl.so.1`)  
✅ **Config File**: Exists at `~/.config/sov/config` with valid content  
✅ **Binary Path**: `/nix/store/.../sov-0.94/bin/sov` (exists and executable)

### Why This Is Not a Configuration Issue

1. **Crash occurs before config is read**: The crash happens during Wayland initialization, before Sov would read its config file
2. **Consistent crash location**: All crashes occur at the same point (`ku_view_get_subview`)
3. **No error messages**: Sov crashes silently without any error output (typical of segfaults)
4. **Workspace overview tools are simple**: They should just execute and display - no complex setup needed

---

## Why Waybar Works Now

The fix that made Waybar work was **removing `exec` from the nohup commands** in `daemon-manager`:

**Before** (broken):
```bash
nohup sh -c "exec $COMMAND" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
```

**After** (working):
```bash
nohup sh -c "$COMMAND" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
```

**Why this matters**:
- `exec` replaces the shell process with the command
- If the process crashes immediately, the shell is gone and PID tracking fails
- Without `exec`, the shell stays alive and can properly track the child process
- This allows the daemon-manager to detect crashes and report errors correctly

**Additional improvements**:
- Pattern sanitization for log filenames (prevents invalid paths)
- Tail processes check file existence before starting (prevents orphaned processes)

---

## Proper Implementation for Sov

### Current Implementation (Correct)

```nix
# In keybindings
"${hyper}+Tab" = "exec ${pkgs.sov}/bin/sov";
```

**This is the correct approach** - Sov is a one-shot tool that should be executed directly via keybinding. No wrapper is needed.

### Why Wrappers Are Not the Solution

1. **Sov crashes before any wrapper logic runs**: The crash happens during Wayland initialization, so wrapper checks (config, IPC, etc.) are irrelevant
2. **Wrappers add complexity without benefit**: If Sov crashes, a wrapper can't fix it
3. **Standard practice**: One-shot tools like Sov should be called directly via `exec` in keybindings

---

## Solutions

### Option 1: Wait for Sov Fix (Recommended)

The bug appears to be in Sov v0.94. Options:
- Check if there's a newer version of Sov available
- Report the bug to the Sov maintainer (Milan Toth)
- Check Sov's GitHub issues for known problems with SwayFX

### Option 2: Use Alternative Workspace Overview Tools

If Sov cannot be fixed, consider alternatives:
- **Rofi in window mode**: `rofi -show window` (already installed)
- **SwayFX native**: Check if SwayFX has built-in workspace overview
- **Other Wayland overview tools**: Research alternatives compatible with SwayFX

### Option 3: Temporary Workaround

If Sov is critical, you could:
- Try running Sov with different options (e.g., `sov -v` for verbose mode)
- Check if there's a different build of Sov available
- Use an older version of Sov if available

---

## Testing

To verify if Sov is fixed in the future:

```bash
# Test Sov execution
sov

# Check exit code
echo $?  # Should be 0 if working, 139 if still crashing

# Check for core dumps
journalctl --user | grep -i "sov.*dumped core"
```

---

## References

- **Sov GitHub**: https://github.com/milgra/sov (if available)
- **Sov Author**: Milan Toth (www.milgra.com)
- **NixOS Package**: `pkgs.sov` (version 0.94)
- **Core Dump Logs**: `journalctl --user | grep -i sov`

---

## Conclusion

Sov's crash is a **binary bug**, not a configuration issue. The current implementation (direct `exec` in keybinding) is correct. No wrapper is needed. The solution is to either:
1. Wait for a Sov fix
2. Use an alternative workspace overview tool
3. Report the bug to Sov's maintainer

The keybinding should remain as `exec ${pkgs.sov}/bin/sov` - this is the proper NixOS way to call one-shot tools.

