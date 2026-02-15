# Fix Home Manager "install is deprecated alias for add" Warning

## Problem Analysis

During home-manager activation, you see this warning:

```
warning: 'install' is a deprecated alias for 'add'
```

**Root Cause:**
- Home Manager internally uses `nix profile install` to manage user packages via the Nix profile system
- Nix has deprecated `nix profile install` in favor of `nix profile add` (as of Nix 2.20+)
- This warning comes from **Nix itself**, triggered when home-manager's activation script calls `nix profile install`
- The warning appears during the `installPackages` activation step when home-manager manages your `home.packages`

**Why it happens:**
- Home Manager's activation script (`installPackages` step) uses `nix profile install` internally
- Even though you're using `home-manager/master` (latest), the code may still use the deprecated command
- This is a known issue in home-manager that will be fixed when they update their code to use `nix profile add`
- The warning is **harmless** - functionality is not affected

## Impact

- **Severity:** Low - This is just a warning, not an error
- **Functionality:** Home Manager works correctly despite the warning
- **User Experience:** Warning clutters the output but doesn't affect functionality

## Solution Options

### Option 1: Update Flake Lock (Recommended First Step)

The warning might be from an older cached version. Try updating the flake lock to get the latest home-manager code:

```bash
cd ~/.dotfiles
nix flake update home-manager-unstable
```

Then rebuild:

```bash
./install.sh ~/.dotfiles "DESK"
```

This ensures you have the absolute latest home-manager code that may have already fixed this issue.

**Note:** If the warning persists after updating, it means home-manager hasn't updated their code yet to use `nix profile add`.

### Option 2: Wait for Home Manager Update (Best Long-term Solution)

This is a known issue in home-manager that will be fixed in a future update. Since you're already using `home-manager/master`, you'll automatically get the fix when it's merged.

**What to do:**
- Continue using your current setup (warning is harmless)
- Periodically update the flake: `nix flake update home-manager-unstable`
- The warning will disappear once home-manager updates their activation code to use `nix profile add`

**Check for updates:**
- Monitor home-manager GitHub issues/PRs for this fix
- Search for issues mentioning "nix profile install deprecated" or "install is deprecated alias"

### Option 3: Suppress Warning (Not Recommended)

You could suppress the warning, but this is **not recommended** as it may hide other important warnings:

```bash
# This would require modifying install.sh to filter stderr
# Not recommended - may hide other important warnings
```

**Why not recommended:**
- Suppresses all warnings, not just this one
- May hide important information
- Doesn't fix the root cause
- Goes against best practices

## Current Configuration

- **Home Manager Source:** `github:nix-community/home-manager/master` (latest unstable)
- **Installation Method:** `nix run home-manager/master -- switch --flake $SCRIPT_DIR#user` (in install.sh line 949)
- **Warning Location:** During `installPackages` activation step when home-manager manages `home.packages`
- **Nix Version:** Likely 2.20+ (which deprecated `nix profile install`)

## Technical Details

The warning occurs because:
1. Home Manager's activation script calls `nix profile install <package>` for each package in `home.packages`
2. Nix 2.20+ deprecated `nix profile install` in favor of `nix profile add`
3. Nix emits the deprecation warning when it sees the old command
4. Home Manager hasn't updated their code yet to use `nix profile add`

**Where the fix needs to happen:**
- In home-manager's source code (activation script)
- Not in your configuration
- Will be fixed when home-manager updates their code

## Verification

After applying a fix, verify the warning is gone:

```bash
./install.sh ~/.dotfiles "DESK"
# Look for the warning in the output
# Should not see: warning: 'install' is a deprecated alias for 'add'
```

## Implementation Checklist

### Recommended Approach (Update Flake Lock)

- [ ] Update home-manager flake: `cd ~/.dotfiles && nix flake update home-manager-unstable`
- [ ] Rebuild: `./install.sh ~/.dotfiles "DESK"`
- [ ] Verify warning is gone in the output
- [ ] If warning persists, it's a known issue that will be fixed in future home-manager update

### Alternative (Monitor for Fix)

- [ ] Check home-manager GitHub for issues/PRs about this warning
- [ ] Continue using current setup (warning is harmless)
- [ ] Wait for home-manager to update their code
- [ ] Warning will automatically disappear when home-manager is updated

## References

- [Nix Profile Documentation](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-profile.html)
- [Home Manager GitHub](https://github.com/nix-community/home-manager)
- [Nix Profile Deprecation](https://github.com/NixOS/nix/pull/XXXX) - Check for deprecation notice

## Notes

- This warning does not affect functionality
- Home Manager continues to work correctly
- The warning is cosmetic and will be resolved when home-manager updates
- No action is strictly required, but updating the flake lock is recommended

