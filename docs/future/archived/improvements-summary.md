# Quick Improvements Summary

**Date**: 2025-01-XX  
**Purpose**: Quick reference for immediate improvements

## Top 5 Quick Wins

### 1. Profile Validation in install.sh ⚡

**Problem**: No validation that `flake.PROFILE.nix` exists before trying to copy it.

**Quick Fix**: Add validation at start of `install.sh`:
```sh
# After PROFILE is set
if [ ! -f "$SCRIPT_DIR/flake.$PROFILE.nix" ]; then
    echo "Error: Profile flake file not found: flake.$PROFILE.nix"
    echo "Available profiles:"
    ls -1 "$SCRIPT_DIR"/flake.*.nix 2>/dev/null | sed 's/.*flake\.\(.*\)\.nix/\1/' | sed 's/^/  - /'
    exit 1
fi
```

**Impact**: Immediate error feedback, shows available profiles.

---

### 2. Auto-Discover Available Profiles 📋

**Problem**: Users must know profile names in advance.

**Quick Fix**: Add profile listing function:
```sh
list_available_profiles() {
    local SCRIPT_DIR=$1
    echo "Available profiles:"
    ls -1 "$SCRIPT_DIR"/flake.*.nix 2>/dev/null | \
        sed 's/.*flake\.\(.*\)\.nix/\1/' | \
        sed 's/^/  - /' | \
        grep -v "^  - nix$"  # Exclude main flake.nix
}

# Show if profile not provided
if [ $# -lt 2 ]; then
    echo "Error: PROFILE parameter is required"
    list_available_profiles "$SCRIPT_DIR"
    exit 1
fi
```

**Impact**: Better UX, self-documenting.

---

### 3. Username Auto-Detection 🔍

**Problem**: Hardcoded username in flake files.

**Quick Fix**: Auto-detect and inject in `install.sh`:
```sh
# Auto-detect username
DETECTED_USER=$(whoami)
DETECTED_HOME=$(eval echo ~$DETECTED_USER)

# Before copying flake, inject username
sed -i "s/username = \".*\";/username = \"$DETECTED_USER\";/" "$SCRIPT_DIR/flake.$PROFILE.nix"
sed -i "s|dotfilesDir = \".*\";|dotfilesDir = \"$SCRIPT_DIR\";|" "$SCRIPT_DIR/flake.$PROFILE.nix"
```

**Impact**: Works on any system without manual editing.

---

### 4. Better Error Messages 💬

**Problem**: Generic error messages don't help debug.

**Quick Fix**: Add context to errors:
```sh
switch_flake_profile_nix() {
    local SCRIPT_DIR=$1
    local PROFILE=$2
    
    if [ ! -f "$SCRIPT_DIR/flake.$PROFILE.nix" ]; then
        echo "Error: Profile flake not found: flake.$PROFILE.nix"
        echo "Current directory: $SCRIPT_DIR"
        echo "Looking for: flake.$PROFILE.nix"
        exit 1
    fi
    
    # Backup and replace
    if [ -f "$SCRIPT_DIR/flake.nix" ]; then
        mv "$SCRIPT_DIR/flake.nix" "$SCRIPT_DIR/flake.nix.bak"
        echo "Backed up existing flake.nix to flake.nix.bak"
    fi
    
    cp "$SCRIPT_DIR/flake.$PROFILE.nix" "$SCRIPT_DIR/flake.nix"
    echo "Switched to profile: $PROFILE"
}
```

**Impact**: Easier debugging, clearer feedback.

---

### 5. Pre-Installation Checks ✅

**Problem**: Installation fails mid-way due to missing prerequisites.

**Quick Fix**: Add validation function:
```sh
pre_install_checks() {
    local SCRIPT_DIR=$1
    local PROFILE=$2
    
    echo "Running pre-installation checks..."
    
    # Check Nix is installed
    if ! command -v nix &> /dev/null; then
        echo "Error: Nix is not installed"
        exit 1
    fi
    
    # Check flake file exists
    if [ ! -f "$SCRIPT_DIR/flake.$PROFILE.nix" ]; then
        echo "Error: Profile flake not found"
        exit 1
    fi
    
    # Check profile directory exists
    local PROFILE_DIR=$(grep -oP 'profile = "\K[^"]+' "$SCRIPT_DIR/flake.$PROFILE.nix" | head -1)
    if [ ! -d "$SCRIPT_DIR/profiles/$PROFILE_DIR" ]; then
        echo "Warning: Profile directory not found: profiles/$PROFILE_DIR"
    fi
    
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        echo "Warning: Sudo access required for system rebuild"
    fi
    
    echo "Pre-installation checks passed ✓"
}
```

**Impact**: Catch issues early, better user experience.

---

## Medium-Term Improvements

### 6. Profile Registry File

Create `profiles/registry.toml` or `profiles/registry.nix`:
```toml
[profiles.DESK]
flake_file = "flake.DESK.nix"
profile_dir = "personal"
hostname = "nixosaku"
description = "Desktop computer configuration"

[profiles.HOME]
flake_file = "flake.HOME.nix"
profile_dir = "homelab"
hostname = "nixosHome"
description = "Home server configuration"
```

**Benefits**: Single source of truth, validation, documentation.

---

### 7. Dry-Run Mode

Add `--dry-run` flag:
```sh
if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN MODE - No changes will be made"
    echo "Would copy: flake.$PROFILE.nix → flake.nix"
    echo "Would rebuild system with profile: $PROFILE"
    exit 0
fi
```

**Benefits**: Safe testing, validation without risk.

---

### 8. Installation Rollback

Save generation before install:
```sh
# Before rebuild
CURRENT_GENERATION=$(nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -1 | awk '{print $1}')
echo "Current generation: $CURRENT_GENERATION"

# After rebuild, if failed, rollback
if [ $? -ne 0 ]; then
    echo "Installation failed, rolling back..."
    sudo nixos-rebuild switch --rollback
    exit 1
fi
```

**Benefits**: Safety net, quick recovery.

---

## Implementation Order

1. **Week 1**: Quick wins 1-5 (validation, error messages, auto-detection)
2. **Week 2**: Profile registry (improvement 6)
3. **Week 3**: Dry-run mode (improvement 7)
4. **Week 4**: Rollback system (improvement 8)

## Testing Checklist

After each improvement:
- [ ] Test with existing profiles
- [ ] Test error cases (missing files, invalid profiles)
- [ ] Test on different systems
- [ ] Update documentation
- [ ] Test silent mode still works

## Notes

- Keep backward compatibility
- All changes should work with existing workflow
- Document new features in `docs/installation.md`
- Consider creating `CHANGELOG.md` for tracking improvements

