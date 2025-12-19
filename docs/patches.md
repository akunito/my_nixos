# Patches Guide

Guide to understanding and using Nixpkgs patches in this configuration.

## Table of Contents

- [Overview](#overview)
- [Why Patches?](#why-patches)
- [Available Patches](#available-patches)
- [Applying Patches](#applying-patches)
- [Creating Patches](#creating-patches)
- [Best Practices](#best-practices)

## Overview

Since this configuration uses `nixpkgs-unstable`, some packages may break or fail to build due to the highly customized, non-standard system. Patches allow quick fixes without waiting for upstream fixes or rolling back everything.

### Patch Location

All patches are stored in the `patches/` directory and applied via the flake configuration.

## Why Patches?

### Reasons for Patching

1. **Quick Fixes**: Fix issues immediately without waiting for upstream
2. **Custom Requirements**: Adapt packages to specific system needs
3. **Unmerged PRs**: Use fixes from pull requests not yet merged
4. **Temporary Workarounds**: Address issues until proper fix is available

### When to Patch

- Package breaks on your system but works elsewhere
- Upstream fix exists but not yet in nixpkgs
- Need custom behavior for your use case
- Temporary workaround needed

### When NOT to Patch

- Issue is already fixed in nixpkgs
- Can use package override instead
- Issue affects many users (should be fixed upstream)
- Patch would break other systems

## Available Patches

### Emacs No Version Check (`patches/emacs-no-version-check.patch`)

**Purpose**: Fixes nix-doom-emacs installation issue

**Problem**: Commit [35ccb9d](https://github.com/NixOS/nixpkgs/commit/35ccb9db3f4f0872f05d175cf53d0e1f87ff09ea) breaks home-manager builds with nix-doom-emacs by preventing home-manager from building.

**Solution**: Patches undo this commit to allow nix-doom-emacs to work.

**Status**: Active

### PCloud Fixes (`patches/pcloudfixes.nix`)

**Purpose**: Fixes for pCloud application

**Status**: Check patch file for details

### Vivaldi Fixes (`patches/vivaldifixes.nix`)

**Purpose**: Fixes for Vivaldi browser

**Status**: Check patch file for details

## Applying Patches

### In Flake Configuration

Patches are applied in the flake file:

```nix
nixpkgs-patched = (import nixpkgs { inherit system; }).applyPatches {
  name = "nixpkgs-patched";
  src = nixpkgs;
  patches = [
    ./patches/emacs-no-version-check.patch
    # ... more patches
  ];
};

# Use patched nixpkgs
pkgs = import nixpkgs-patched { inherit system; };
lib = nixpkgs.lib;
```

### Patch Sources

Patches can be:

1. **Local**: Stored in `patches/` directory
   ```nix
   patches = [ ./patches/my-patch.patch ];
   ```

2. **Remote**: Fetched from URL
   ```nix
   patches = [
     (fetchpatch {
       url = "https://github.com/NixOS/nixpkgs/pull/12345.patch";
       sha256 = "...";
     })
   ];
   ```

### Applying Remote Patches

To use unmerged pull requests:

```nix
patches = [
  (fetchpatch {
    url = "https://github.com/NixOS/nixpkgs/pull/12345.patch";
    sha256 = lib.fakeSha256;  # Will be replaced on first build
  })
];
```

After first build, replace `lib.fakeSha256` with the actual SHA256.

## Creating Patches

### Method 1: From Git Diff

If you have a modified package:

```sh
# 1. Clone nixpkgs
git clone https://github.com/NixOS/nixpkgs.git
cd nixpkgs

# 2. Make your changes
# ... edit files ...

# 3. Create patch
git diff > ../my-patch.patch

# 4. Copy to patches directory
cp ../my-patch.patch ~/.dotfiles/patches/
```

### Method 2: Manual Patch File

Create patch file manually:

```patch
--- a/path/to/file.nix
+++ b/path/to/file.nix
@@ -10,7 +10,7 @@
   version = "1.0.0";
   
   src = fetchFromGitHub {
-    rev = "v1.0.0";
+    rev = "v1.0.1";
     hash = "...";
   };
 }
```

### Method 3: From Pull Request

Download patch from GitHub PR:

```sh
# Get raw patch URL from PR
curl -L "https://github.com/NixOS/nixpkgs/pull/12345.patch" > patches/pr-12345.patch
```

Or use `fetchpatch` directly in flake.

## Best Practices

### 1. Document Patches

Always document why a patch is needed:

```nix
# Patch fixes nix-doom-emacs build issue
# See: https://github.com/NixOS/nixpkgs/commit/35ccb9d
patches = [ ./patches/emacs-no-version-check.patch ];
```

### 2. Keep Patches Minimal

- Only patch what's necessary
- Avoid unrelated changes
- Keep patches focused

### 3. Test Patches

- Test patches before committing
- Verify they don't break other packages
- Test on clean system if possible

### 4. Monitor Upstream

- Check if patch is merged upstream
- Remove patches when no longer needed
- Update patches if upstream changes

### 5. Version Control

- Commit patches to repository
- Document patch purpose in commit message
- Keep patch history

### 6. Patch Maintenance

Regularly review patches:

1. Check if still needed
2. Verify patches still apply
3. Update patches for new nixpkgs versions
4. Remove obsolete patches

## Troubleshooting

### Patch Fails to Apply

**Problem**: Patch doesn't apply to current nixpkgs version.

**Solutions**:
1. Check if patch is still relevant
2. Update patch for new nixpkgs version
3. Check patch format
4. Verify patch file integrity

### Patch Breaks Other Packages

**Problem**: Applying patch breaks unrelated packages.

**Solutions**:
1. Make patch more specific
2. Use package override instead
3. Check patch scope
4. Test incrementally

### Patch Conflicts

**Problem**: Multiple patches conflict.

**Solutions**:
1. Combine patches if possible
2. Apply patches in correct order
3. Resolve conflicts manually
4. Use more specific patches

## Related Documentation

- [Nixpkgs Manual](https://nixos.org/manual/nixpkgs/) - Nixpkgs documentation
- [Configuration Guide](configuration.md) - Flake configuration

**Related Documentation**: See [patches/README.md](../../patches/README.md) for directory-level documentation.

**Note**: The original [patches/README.org](../../patches/README.org) file is preserved for historical reference.

