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

For DESK profile, use one of these commands:

```bash
# Option 1: Direct nixos-rebuild with DESK flake file (recommended)
sudo nixos-rebuild boot --flake ~/.dotfiles#system

# Option 2: If you're in the dotfiles directory and flake.nix is already set to DESK
cd ~/.dotfiles
sudo nixos-rebuild boot --flake .#system

# Option 3: Explicitly specify the DESK flake file
sudo nixos-rebuild boot --flake ~/.dotfiles/flake.DESK.nix#system
```

**Note:** The `install.sh` script uses `nixos-rebuild switch`, but for this fix we need `boot` instead. After running the boot command:

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
# Option 1: Using install.sh (uses switch internally)
./install.sh ~/.dotfiles "DESK"

# Option 2: Direct nixos-rebuild with DESK flake file
sudo nixos-rebuild switch --flake ~/.dotfiles#system

# Option 3: If you're in the dotfiles directory and flake.nix is already set to DESK
sudo nixos-rebuild switch --flake .#system
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
# Option 1: Using install.sh (uses switch internally)
./install.sh ~/.dotfiles "DESK"

# Option 2: Direct nixos-rebuild with DESK flake file
sudo nixos-rebuild switch --flake ~/.dotfiles#system

# Option 3: If you're in the dotfiles directory and flake.nix is already set to DESK
sudo nixos-rebuild switch --flake .#system

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

## Current Configuration State

- **disk7_enabled**: `false` (disabled in `profiles/DESK-config.nix`)
- **Mount unit**: Exists in previous generation but not in new generation (causing transition error)
- **Device UUID**: `b6be2dd5-d6c0-4839-8656-cb9003347c93` (not currently found on system)
- **Solution**: Use `nixos-rebuild boot` + reboot to avoid transition issue

## References

- [NixOS Manual - Systemd Units](https://nixos.org/manual/nixos/)
- [Systemd Mask Documentation](https://www.freedesktop.org/software/systemd/man/systemctl.html#mask%20UNIT%E2%80%A6)

## Implementation Checklist

### Recommended Approach (Boot & Reboot)

- [ ] Run one of:
  - `sudo nixos-rebuild boot --flake ~/.dotfiles#system` (recommended for DESK profile)
  - `sudo nixos-rebuild boot --flake ~/.dotfiles/flake.DESK.nix#system` (explicit DESK flake)
  - `cd ~/.dotfiles && sudo nixos-rebuild boot --flake .#system` (if flake.nix is already DESK)
- [ ] Reboot: `sudo reboot`
- [ ] Verify system boots successfully
- [ ] Verify disk7 is properly disabled in new generation

### Alternative Approach (If Cannot Reboot)

- [ ] Try `sudo systemctl stop mnt-EXT.mount` (may fail, that's OK)
- [ ] Run `sudo systemctl reset-failed mnt-EXT.mount`
- [ ] Run `sudo systemctl daemon-reload`
- [ ] Try rebuild with one of:
  - `./install.sh ~/.dotfiles "DESK"` (uses switch internally)
  - `sudo nixos-rebuild switch --flake ~/.dotfiles#system`
  - `cd ~/.dotfiles && sudo nixos-rebuild switch --flake .#system` (if flake.nix is already DESK)
- [ ] If still fails, use boot method above

### Last Resort (Masking - Only if Reboot Impossible)

- [ ] Run `sudo systemctl mask mnt-EXT.mount`
- [ ] Rebuild with one of:
  - `./install.sh ~/.dotfiles "DESK"` (uses switch internally)
  - `sudo nixos-rebuild switch --flake ~/.dotfiles#system`
  - `cd ~/.dotfiles && sudo nixos-rebuild switch --flake .#system` (if flake.nix is already DESK)
- [ ] **IMPORTANT:** Immediately unmask: `sudo systemctl unmask mnt-EXT.mount`
- [ ] Verify rebuild succeeded

