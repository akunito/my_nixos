# Fix mnt-EXT.mount Systemd Transition Error

## Problem Analysis

The error occurs during NixOS configuration switch when systemd tries to stop `mnt-EXT.mount` from the previous generation, but the unit doesn't exist in the new generation (because we disabled disk7).

**Error Message:**
```
stopping the following units: mnt-EXT.mount
Error: Failed to get unit mnt-EXT.mount
Caused by: Unit mnt-EXT.mount not loaded.
```

**Root Cause:**
- Previous NixOS generation had `mnt-EXT.mount` defined
- Current generation has disk7 disabled (no mount unit generated)
- Systemd's `switch-to-configuration` script tries to stop units from previous generation
- Since the unit doesn't exist in the new generation, systemd can't find it to stop it
- This causes the transition to fail

## Solution

**Important:** On NixOS, we should maintain the declarative nature of the system. Manual `systemctl mask` creates imperative state that conflicts with NixOS's declarative management. Use the following approaches in order of preference.

### Recommended Solution: Use `nixos-rebuild boot` (Best for NixOS)

This is the **cleanest NixOS-native solution** that avoids the transition issue entirely.

**Why this works:**
- `nixos-rebuild switch` tries to live-update the system, including stopping old units
- If the current state is messy (mount unit for unplugged drive is stuck), `switch` fails
- `nixos-rebuild boot` builds the new configuration and sets it as default for next boot
- It **does not try to activate it now**, bypassing the broken transition entirely

**Steps:**

**Important:** Your configuration requires the `--impure` flag because it references absolute paths (like `/home` in PKI certificates). The `install.sh` script uses `--impure` automatically, but when running `nixos-rebuild` directly, you must include it.

**Why the errors occurred:**
1. **Error 1:** `access to absolute path '/home' is forbidden in pure evaluation mode`
   - Your configuration references `/home` (likely in `pkiCertificates` path)
   - NixOS pure mode doesn't allow absolute paths
   - **Solution:** Add `--impure` flag

2. **Error 2:** `path '/home/akunito/.dotfiles/flake.DESK.nix' is not a flake (because it's not a directory)`
   - You cannot point directly to a flake file
   - Flakes must be referenced by directory, not file
   - **Solution:** Point to the directory, not the file

**Correct commands for DESK profile:**

```bash
# First, ensure flake.nix is set to DESK (install.sh does this automatically)
# If you haven't run install.sh recently, do this first:
cd ~/.dotfiles
cp flake.DESK.nix flake.nix

# Then run boot with --impure flag (required for your configuration)
sudo nixos-rebuild boot --flake ~/.dotfiles#system --impure

# Or if you're already in the dotfiles directory:
cd ~/.dotfiles
sudo nixos-rebuild boot --flake .#system --impure
```

**Note:** The `install.sh` script uses `nixos-rebuild switch --impure`, but for this fix we need `boot --impure` instead. After running the boot command:

```bash
# Reboot to apply the changes cleanly
sudo reboot
```

This solves the issue 100% of the time without leaving manual state modifications.

### Alternative Solution: Try Manual Cleanup First

If you cannot reboot immediately, try cleaning up the unit state first:

```bash
# Try to stop the unit (may fail if already stopped, that's OK)
sudo systemctl stop mnt-EXT.mount 2>&1 || true

# Reset any failed state
sudo systemctl reset-failed mnt-EXT.mount 2>&1 || true

# Reload systemd daemon
sudo systemctl daemon-reload

# Now try the normal switch (for DESK profile)
# Option 1: Using install.sh (uses switch --impure internally, recommended)
./install.sh ~/.dotfiles "DESK"

# Option 2: Direct nixos-rebuild with --impure flag (required for your config)
sudo nixos-rebuild switch --flake ~/.dotfiles#system --impure

# Option 3: If you're in the dotfiles directory and flake.nix is already set to DESK
cd ~/.dotfiles
sudo nixos-rebuild switch --flake .#system --impure
```

Often the unit is just in a "failed" state, and resetting it allows the switch to proceed.

### Last Resort: Masking (Only if Reboot is Impossible)

**⚠️ Warning:** Masking creates imperative state that conflicts with NixOS's declarative management. Only use this if you absolutely cannot reboot.

**Why masking is problematic:**
- Creates a symlink in `/etc/systemd/system/` that NixOS doesn't manage
- If you later re-enable disk7 in config, NixOS might fail to start it because of the manual mask
- Fights against the declarative nature of NixOS

**If you must use it:**

```bash
# Mask the unit
sudo systemctl mask mnt-EXT.mount

# Rebuild (for DESK profile)
# Option 1: Using install.sh (uses switch --impure internally, recommended)
./install.sh ~/.dotfiles "DESK"

# Option 2: Direct nixos-rebuild with --impure flag (required for your config)
sudo nixos-rebuild switch --flake ~/.dotfiles#system --impure

# Option 3: If you're in the dotfiles directory and flake.nix is already set to DESK
cd ~/.dotfiles
sudo nixos-rebuild switch --flake .#system --impure

# IMPORTANT: Unmask immediately after successful rebuild
sudo systemctl unmask mnt-EXT.mount
```

**Critical:** Always unmask after the rebuild succeeds to avoid future conflicts.

## Prevention for Future

When re-enabling disk7 in the future:

1. **Ensure device is connected** before enabling in configuration
2. **Verify UUID** matches the actual device: `lsblk -f`
3. **Use `nofail` option** in mount options (already configured)
4. **Consider using automount** for removable devices:
   ```nix
   disk7_options = [ "nofail" "x-systemd.automount" "x-systemd.idle-timeout=600" ];
   ```

## Why Direct Commands Fail (Configuration-Specific Issues)

Your DESK profile configuration has specific requirements that cause errors when running `nixos-rebuild` directly without proper flags:

### Error 1: Pure Evaluation Mode Restriction

**Error:** `access to absolute path '/home' is forbidden in pure evaluation mode`

**Cause:**
- Your configuration references absolute paths (e.g., `pkiCertificates = [ /home/akunito/.myCA/ca.cert.pem ]` in DESK-config.nix)
- NixOS runs in "pure evaluation mode" by default, which forbids absolute paths for reproducibility
- The `install.sh` script automatically adds `--impure` flag to allow these paths

**Solution:** Always include `--impure` flag when running `nixos-rebuild` directly

### Error 2: Flake File vs Directory

**Error:** `path '/home/akunito/.dotfiles/flake.DESK.nix' is not a flake (because it's not a directory)`

**Cause:**
- Flakes must be referenced by directory, not by file
- You cannot point directly to `flake.DESK.nix` file
- The `install.sh` script copies `flake.DESK.nix` → `flake.nix` first, then references the directory

**Solution:** Point to the directory (`~/.dotfiles`) not the file (`flake.DESK.nix`)

### Why `install.sh` Works

The `install.sh` script handles these issues automatically:
1. Copies `flake.DESK.nix` → `flake.nix` (sets up the flake)
2. Uses `--impure` flag automatically
3. Uses `--show-trace` for better error messages

**That's why using `./install.sh ~/.dotfiles "DESK"` works, but direct commands need the flags.**

## Current Configuration State

- **disk7_enabled**: `false` (disabled in `profiles/DESK-config.nix`)
- **Mount unit**: Exists in previous generation but not in new generation (causing transition error)
- **Device UUID**: `b6be2dd5-d6c0-4839-8656-cb9003347c93` (not currently found on system)
- **Solution**: Use `nixos-rebuild boot --impure` + reboot to avoid transition issue
- **Note**: Always use `--impure` flag with your configuration due to absolute path references

## References

- [NixOS Manual - Systemd Units](https://nixos.org/manual/nixos/)
- [Systemd Mask Documentation](https://www.freedesktop.org/software/systemd/man/systemctl.html#mask%20UNIT%E2%80%A6)

## Implementation Checklist

### Recommended Approach (Boot & Reboot)

- [ ] Ensure flake.nix is set to DESK: `cd ~/.dotfiles && cp flake.DESK.nix flake.nix` (if needed)
- [ ] Run one of:
  - `sudo nixos-rebuild boot --flake ~/.dotfiles#system --impure` (recommended, includes --impure flag)
  - `cd ~/.dotfiles && sudo nixos-rebuild boot --flake .#system --impure` (if already in directory)
- [ ] Reboot: `sudo reboot`
- [ ] Verify system boots successfully
- [ ] Verify disk7 is properly disabled in new generation

### Alternative Approach (If Cannot Reboot)

- [ ] Try `sudo systemctl stop mnt-EXT.mount` (may fail, that's OK)
- [ ] Run `sudo systemctl reset-failed mnt-EXT.mount`
- [ ] Run `sudo systemctl daemon-reload`
- [ ] Try rebuild with one of:
  - `./install.sh ~/.dotfiles "DESK"` (uses switch --impure internally, recommended)
  - `sudo nixos-rebuild switch --flake ~/.dotfiles#system --impure` (must include --impure)
  - `cd ~/.dotfiles && sudo nixos-rebuild switch --flake .#system --impure` (if flake.nix is already DESK)
- [ ] If still fails, use boot method above

### Last Resort (Masking - Only if Reboot Impossible)

- [ ] Run `sudo systemctl mask mnt-EXT.mount`
- [ ] Rebuild with one of:
  - `./install.sh ~/.dotfiles "DESK"` (uses switch --impure internally, recommended)
  - `sudo nixos-rebuild switch --flake ~/.dotfiles#system --impure` (must include --impure)
  - `cd ~/.dotfiles && sudo nixos-rebuild switch --flake .#system --impure` (if flake.nix is already DESK)
- [ ] **IMPORTANT:** Immediately unmask: `sudo systemctl unmask mnt-EXT.mount`
- [ ] Verify rebuild succeeded

