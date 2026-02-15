# Investigation: Slow NixOS Rebuild on LAPTOP_L15

## Problem
NixOS rebuild via `install.sh` is extremely slow on LAPTOP_L15.

## Root Causes Identified

### 1. Heavy Compilation Packages (Primary Culprits)

| Feature | Flag | Impact |
|---------|------|--------|
| **NixVim** | `nixvimEnabled = true` | **Highest** - Compiles multiple LSP servers (nixd, lua_ls, pyright, ts_ls), Treesitter grammars, and plugins |
| **Development Tools** | `developmentToolsEnable = true` | **High** - VSCode, Cursor IDE, PowerShell, DBeaver from unstable |
| **Stylix Theming** | `stylixEnable = true` | **Medium** - Applies theme recursively across packages |
| **SwayFX** | `enableSwayForDESK = true` | **Medium** - Compiled window manager with effects |
| **Sunshine** | `sunshineEnable = true` | **Medium** - Heavy remote gaming binary |

### 2. Binary Cache Issues
- Using `nixpkgs/nixos-unstable` - has worse binary cache coverage than stable
- Development tools (VSCode, Cursor, PowerShell, DBeaver) often need compilation from unstable
- No explicit additional binary caches configured

### 3. Rebuild Workflow
- `install.sh` runs system rebuild + home-manager rebuild sequentially
- Each triggers full dependency evaluation

## Relevant Files
- `profiles/LAPTOP_L15-config.nix` - Feature flags (lines 121-127)
- `profiles/LAPTOP-base.nix` - Base laptop settings (lines 15-19)
- `user/app/nixvim/nixvim.nix` - NixVim configuration
- `user/app/development/development.nix` - Dev tools (lines 13-37)

## Quick Diagnostic Steps

1. **Check what's being built** - Run rebuild with verbose output:
   ```bash
   nixos-rebuild switch --flake .#LAPTOP_L15 -v 2>&1 | tee rebuild.log
   ```

2. **Check cache hit rate** - Look for "building" vs "fetching" in output

3. **Identify long-running derivations** - Watch for stuck builds

## Optimization Options

### Option A: Disable Heavy Features (Fastest Impact)
Temporarily disable in `profiles/LAPTOP_L15-config.nix`:
```nix
nixvimEnabled = false;        # Use system neovim instead
developmentToolsEnable = false;  # Install IDEs outside Nix
```

### Option B: Add Binary Caches
Add to configuration:
```nix
nix.settings = {
  substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
  ];
  trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
};
```

### Option C: Use Quick Mode
```bash
./install.sh . LAPTOP_L15 -q  # Skips docker and hardware-config
```

### Option D: Switch to Stable for Dev Tools
Consider using stable nixpkgs for heavy packages that don't need bleeding edge.

## Recommended Immediate Actions

1. Run the rebuild with verbose logging to identify the specific slow derivations
2. Decide which heavy features you actively need
3. Add nix-community cachix for better cache coverage on community packages

## Implementation Plan

### Step 1: Diagnose Current Build (Read-only)
Run verbose rebuild to identify slow derivations:
```bash
nixos-rebuild switch --flake .#LAPTOP_L15 -v 2>&1 | tee /tmp/rebuild.log
```
Then analyze: `grep -E "(building|fetching|waiting)" /tmp/rebuild.log`

### Step 2: Add Binary Caches
Edit `work/configuration.nix` (or appropriate config) to add:
```nix
nix.settings = {
  substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
  ];
  trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
};
```

### Step 3: Review & Disable Heavy Features
In `profiles/LAPTOP_L15-config.nix`, consider:
- `nixvimEnabled = false` - If not actively using nixvim features
- `developmentToolsEnable = false` - Install IDEs outside Nix
- `stylixEnable = false` - If not using custom theming

### Step 4: Test Rebuild
Run rebuild again and compare times.

## Files to Modify
1. `work/configuration.nix` or `lib/defaults.nix` - Add binary caches
2. `profiles/LAPTOP_L15-config.nix` - Disable heavy features (optional)

## Verification
1. Compare rebuild times before/after
2. Check `nix-store -q --references` for reduced dependency count
3. Verify cache hit rate in verbose output (more "fetching", less "building")
