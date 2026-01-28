# keyd Caps Lock to Hyper Key Debugging Plan

## Problem Statement

**Issue**: Logitech keyboard's Caps Lock key is not being remapped to Hyper key (C-A-M = Control+Alt+Meta) by keyd, while Keychron keyboard works correctly.

**Expected Behavior**: 
- Pressing Caps Lock on Logitech should send Control+Alt+Meta (held down while Caps Lock is pressed)
- Sway keybindings using `${hyper}` (defined as `Mod4+Control+Mod1`) should work
- Keybindings like `Caps Lock + Q` and `Caps Lock + W` should trigger Sway commands

**Current Behavior**:
- Logitech keyboard sends normal Caps Lock signal (not remapped)
- OR sends modifiers but they toggle (down then immediately up) instead of staying held

## System Configuration

### Keyboards
1. **Keychron Keychron K11 Max** (Device ID: `3434:0ab3:0a145bbb`)
   - **Status**: ✅ WORKING
   - **Reason**: Firmware-level remapping already sends C-A-M directly
   - **Behavior**: Sends Control+Alt+Meta directly, no keyd remapping needed

2. **Logitech Wireless Keyboard PID:4075** (Device ID: `046d:4075:2cc03d0c`)
   - **Status**: ❌ NOT WORKING
   - **Issue**: Sends standard Caps Lock keycode, needs keyd remapping
   - **Expected**: keyd should remap Caps Lock to C-A-M

### Sway Configuration
- **Hyper key definition**: `hyper = "Mod4+Control+Mod1"` (line 5 in `user/wm/sway/default.nix`)
- **Keybindings**: All use `${hyper}` variable (e.g., `"${hyper}+Q"`, `"${hyper}+W"`)
- **Expected**: `Mod4+Control+Mod1` = Super+Control+Alt = Meta+Control+Alt

### keyd Configuration

**Source File**: `system/wm/keyd.nix`
- **Current config** (as of latest attempt):
  ```nix
  capslock = "layer(hyper:C-A-M)";
  ```
  With layer definition:
  ```nix
  "hyper:C-A-M" = {
    # Layer definition
  };
  ```

**Deployed Config**: `/etc/keyd/default.conf`
- **Current content** (as of last check):
  ```
  [ids]
  *
  
  [main]
  capslock=hyper
  ```
- **Note**: There's a mismatch! Source file has `layer(hyper:C-A-M)` but deployed has `hyper`

### keyd Service Status
- **Status**: ✅ Active and running
- **PID**: 91035 (as of last check)
- **Logitech keyboard**: ✅ Matched by keyd
  - Log entry: `DEVICE: match    046d:4075:2cc03d0c  /etc/keyd/default.conf        (Logitech Wireless Keyboard PID:4075)`

## Debugging Evidence

### keyd Monitor Output (When `C-A-M` was configured)

When pressing Caps Lock on Logitech keyboard, keyd monitor showed:
```
[MONITOR] keyd virtual keyboard	0fac:0ade:bea394c0	leftshift down
[MONITOR] keyd virtual keyboard	0fac:0ade:bea394c0	leftcontrol down
[MONITOR] keyd virtual keyboard	0fac:0ade:bea394c0	m down
[MONITOR] keyd virtual keyboard	0fac:0ade:bea394c0	m up
[MONITOR] keyd virtual keyboard	0fac:0ade:bea394c0	leftalt up
[MONITOR] keyd virtual keyboard	0fac:0ade:bea394c0	leftshift up
[MONITOR] keyd virtual keyboard	0fac:0ade:bea394c0	leftcontrol up
[MONITOR] keyd virtual keyboard	0fac:0ade:bea394c0	leftalt down
```

**Analysis**:
- ❌ Wrong modifiers: Sending `leftshift`, `leftcontrol`, `m` (letter), `leftalt` instead of `leftcontrol`, `leftalt`, `leftmeta`
- ❌ **Root Cause**: `M` in `C-A-M` was interpreted as letter "m" instead of Meta modifier
- ❌ Toggle behavior: Keys go down then immediately up (not held)
- ❌ Missing `leftmeta` (Super key)
- ✅ **Fix Identified**: Use `meta` instead of `M` in layer definition

### Terminal Output When Testing

When pressing `Caps Lock + Q` and `Caps Lock + W`:
- Output: `9;8u9;8uwq9;8uwq9;8uwq`
- This suggests escape sequences or raw keycodes being sent

### evtest Results

- **Device**: `/dev/input/event259` (Logitech Wireless Keyboard PID:4075)
- **Status**: Device is grabbed by keyd (expected)
- **Caps Lock keycode**: `KEY_CAPSLOCK` (event code 58) - standard keycode
- **Note**: evtest couldn't see raw events because keyd has the device grabbed

## Attempted Solutions

### Attempt 1: `capslock = "C-A-M"`
- **Config**: `capslock = "C-A-M";`
- **Result**: ❌ FAILED
- **Issue**: Sending wrong modifiers (`leftshift`, `leftcontrol`, `m`, `leftalt`) and toggling instead of holding

### Attempt 2: `capslock = "leftcontrol+leftalt+leftmeta"`
- **Config**: `capslock = "leftcontrol+leftalt+leftmeta";`
- **Result**: ❌ FAILED
- **Issue**: Invalid syntax, keyd ignored it, keyboard sent normal Caps Lock

### Attempt 3: `capslock = "hyper"`
- **Config**: `capslock = "hyper";`
- **Result**: ❌ FAILED
- **Issue**: Keyboard still sending normal Caps Lock signal

### Attempt 4: `capslock = "layer(hyper:C-A-M)"`
- **Config**: 
  ```nix
  capslock = "layer(hyper:C-A-M)";
  "hyper:C-A-M" = { };
  ```
- **Result**: ❌ FAILED (current state)
- **Issue**: Keyboard still sending normal Caps Lock signal
- **Note**: Config mismatch - source file has this, but deployed config shows `hyper`

## Key Findings

1. **keyd IS matching the Logitech keyboard**: Logs confirm device match
2. **keyd service IS running**: Service is active and enabled
3. **Config syntax issues**: Multiple syntax attempts have failed
4. **Config deployment mismatch**: Source file and deployed config don't match
5. **Wrong modifiers being sent**: When `C-A-M` was working, it sent wrong keys
6. **Toggle vs Hold**: Modifiers toggle instead of staying held down

## Root Cause Analysis

### CRITICAL FLAW IDENTIFIED: Deployment Mismatch (Priority Zero)

**The Problem**: 
- Source file (`system/wm/keyd.nix`) has `layer(hyper:C-A-M)` 
- Deployed config (`/etc/keyd/default.conf`) shows `hyper`
- **Implication**: Configuration changes are NOT being applied to the system

**Why This Matters**:
- Cannot debug syntax if the code isn't reaching the machine
- NixOS `/etc/keyd/default.conf` is a symlink to Nix store
- If it contains old values, either:
  1. `nixos-rebuild` didn't finish properly
  2. `system/wm/keyd.nix` is **not imported** in the active profile/flake

**Status**: 🔴 **CONFIRMED - BLOCKING ISSUE**

### Syntax Issues Identified

#### Issue 1: `M` is Ambiguous
- **Evidence**: Monitor output showed `m down` (letter 'm', not Meta)
- **Cause**: In keyd, single letter `M` in `C-A-M` was interpreted as the letter "m"
- **Fix**: Use explicit names: `meta` or `super` instead of `M`
- **Status**: 🔴 **CONFIRMED - Syntax Error**

#### Issue 2: Incorrect Layer Syntax
- **Problem**: Attempted `layer(hyper:C-A-M)` in the binding line
- **Correct Pattern**: 
  - Binding: `capslock = "layer(hyper)"`
  - Layer definition: `[hyper:C-A-meta]` (in section header, not in binding)
- **Status**: 🔴 **CONFIRMED - Syntax Error**

### Hypotheses (Updated Priority)

#### Hypothesis A: Config Not Applied (PRIORITY ZERO)
- **Theory**: NixOS rebuild isn't properly updating `/etc/keyd/default.conf` OR file not imported
- **Evidence**: Source file shows `layer(hyper:C-A-M)` but deployed shows `hyper`
- **Status**: 🔴 **CONFIRMED - BLOCKING**
- **Action Required**: Verify imports chain in flake.nix

#### Hypothesis B: Syntax Errors (PRIORITY ONE)
- **Theory**: Using `M` instead of `meta`, incorrect layer syntax
- **Evidence**: Monitor showed `m down` (letter), wrong modifiers sent
- **Status**: 🔴 **CONFIRMED - Syntax Errors Identified**
- **Action Required**: Fix syntax using `meta` and correct layer pattern

#### Hypothesis C: keyd Version/Feature Issue
- **Theory**: keyd version might not support the syntax we're trying
- **Evidence**: None yet
- **Status**: ⚪ **UNTESTED** (test after fixing deployment and syntax)

## Next Steps (Corrected Priority Order)

### Step 1: Verify NixOS Imports (PRIORITY ZERO - Must Fix First)

**Goal**: Ensure `system/wm/keyd.nix` is actually being read by the active profile

**Actions**:
1. **Check imports chain**: Verify `flake.nix` -> profile config -> `system/wm/keyd.nix` imports
2. **Test config generation**: 
   - Add a test change to `system/wm/keyd.nix` (e.g., `capslock = "layer(test_layer)"`)
   - Run: `nixos-rebuild build` (builds without switching)
   - Check: Inspect `result/etc/keyd/default.conf` to see if change exists
3. **If not changing**: The file is not imported in the current Flake profile - find the disconnect

**Commands**:
```bash
# Build without switching to test
cd /home/akunito/.dotfiles && sudo nixos-rebuild build --flake .#$(hostname)

# Check generated config
cat result/etc/keyd/default.conf

# Or check what profile is active
hostname
```

### Step 2: Implement Correct keyd Syntax (PRIORITY ONE)

**Goal**: Map CapsLock to a layer that inherits Control, Alt, and Meta using correct syntax

**Correct Nix Config Pattern**:
```nix
services.keyd.keyboards.default.settings = {
  main = {
    # Map CapsLock to the custom 'hyper' layer
    capslock = "layer(hyper)";
    # OR with overload (modifier on hold, escape on tap):
    # capslock = "overload(hyper, esc)";
  };
  "hyper:C-A-meta" = {
    # This section header defines the layer 'hyper' 
    # and tells keyd it inherits Control + Alt + Meta
    # The ":C-A-meta" suffix makes the layer send these modifiers
    # Use "meta" not "M" to avoid ambiguity
  };
};
```

**Key Corrections**:
- ✅ Use `meta` instead of `M` (explicit is better)
- ✅ Define layer in section header: `[hyper:C-A-meta]`
- ✅ Binding line: `capslock = "layer(hyper)"` (not `layer(hyper:C-A-M)`)

### Step 3: Deploy and Monitor (PRIORITY TWO)

**Actions**:
1. Rebuild: `sudo nixos-rebuild switch --flake .#<profile>`
2. Verify: `cat /etc/keyd/default.conf` (must match new config)
3. Restart: `sudo systemctl restart keyd`
4. Debug: `sudo keyd monitor` -> Hold CapsLock + press `q`
5. Expected output:
   - `leftcontrol down`
   - `leftalt down`
   - `leftmeta down`
   - `q down`
   - (modifiers stay down while Caps Lock held)
   - `q up`
   - `leftmeta up`
   - `leftalt up`
   - `leftcontrol up`

### Step 4: Test Sway Keybindings (PRIORITY THREE)

After confirming monitor shows correct behavior:
- Test `Caps Lock + Q` and `Caps Lock + W`
- Should trigger Sway keybindings defined with `${hyper}`

## Commands for Testing

### Check current deployed config:
```bash
cat /etc/keyd/default.conf
```

### Validate config syntax:
```bash
sudo /nix/store/820fi6f0wylfjsl08r2hrjhw3ws7ddxc-keyd-2.6.0/bin/keyd check /etc/keyd/default.conf
```

### Monitor keyd output:
```bash
sudo /nix/store/820fi6f0wylfjsl08r2hrjhw3ws7ddxc-keyd-2.6.0/bin/keyd monitor
```

### Check keyd service status:
```bash
sudo systemctl status keyd
```

### Check keyd logs:
```bash
sudo journalctl -u keyd --since "10 minutes ago" | grep -i logitech
```

### Rebuild and restart:
```bash
cd /home/akunito/.dotfiles && sudo nixos-rebuild switch
sudo systemctl restart keyd
```

## References

- keyd binary location: `/nix/store/820fi6f0wylfjsl08r2hrjhw3ws7ddxc-keyd-2.6.0/bin/keyd`
- keyd version: 2.6.0
- Config file: `/etc/keyd/default.conf`
- Source config: `system/wm/keyd.nix`
- Sway config: `user/wm/sway/default.nix` (line 5: `hyper = "Mod4+Control+Mod1"`)

## Critical Notes

1. **Keychron works because firmware sends C-A-M directly** - no keyd remapping needed
2. **Logitech needs keyd remapping** - sends standard Caps Lock keycode
3. **🔴 PRIORITY ZERO: Config mismatch exists** - source and deployed configs differ
   - This MUST be fixed before debugging syntax
   - Verify imports chain: `flake.nix` -> profile -> `system/wm/keyd.nix`
4. **keyd IS matching the device** - logs confirm this
5. **🔴 Syntax errors identified**:
   - `M` is ambiguous (interpreted as letter 'm', not Meta)
   - Use `meta` instead of `M`
   - Layer syntax: Define in section header `[hyper:C-A-meta]`, not in binding line
6. **Correct pattern**: `capslock = "layer(hyper)"` with `[hyper:C-A-meta]` section header

