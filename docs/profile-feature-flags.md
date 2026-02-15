---
id: docs.profile-feature-flags
summary: Guide to creating and using feature flags for profile-specific module enabling. Explains the pattern of setting defaults to false and enabling features only in specific profiles.
tags: [profiles, feature-flags, modules, nixos, home-manager, configuration, best-practices]
related_files:
  - lib/defaults.nix
  - profiles/DESK-config.nix
  - profiles/LAPTOP-config.nix
key_files:
  - lib/defaults.nix
  - profiles/*-config.nix
activation_hints:
  - When creating a new module that should only be enabled for specific profiles
  - When adding a new feature that shouldn't be enabled by default
  - When deciding whether to enable a module in a profile
---

# Profile Feature Flags Pattern

## Overview

When creating a new module or feature that should only be enabled for specific profiles (like DESK or LAPTOP), use the **feature flag pattern**: set the feature to `false` by default in `lib/defaults.nix`, and enable it only in the profiles that need it.

## Why Use Feature Flags?

- **Opt-in by default**: Features are disabled unless explicitly enabled
- **Profile-specific control**: Each profile can independently enable/disable features
- **Clear intent**: Makes it obvious which profiles use which features
- **Easy maintenance**: Centralized defaults with profile overrides

## Pattern Structure

### Step 1: Define Default in `lib/defaults.nix`

Add your feature flag to the appropriate settings section (`systemSettings` or `userSettings`) with a default value of `false`:

```nix
# In lib/defaults.nix

systemSettings = {
  # ... other settings ...
  
  # New feature - disabled by default
  newFeatureEnable = false;
};

# OR for user-level features:

userSettings = {
  # ... other settings ...
  
  # New user feature - disabled by default
  newUserFeatureEnable = false;
};
```

### Step 2: Use the Flag in Your Module

In your module file, conditionally enable the feature based on the flag:

```nix
# In user/app/newfeature/newfeature.nix

{ config, pkgs, lib, systemSettings, ... }:

{
  # Only enable if the flag is set to true
  programs.newFeature = lib.mkIf systemSettings.newFeatureEnable {
    enable = true;
    # ... configuration ...
  };
}
```

### Step 3: Enable in Specific Profiles

In the profile configuration files (e.g., `profiles/DESK-config.nix`), override the default to enable the feature:

```nix
# In profiles/DESK-config.nix

{
  systemSettings = {
    # ... other settings ...
    
    # Enable new feature for DESK profile
    newFeatureEnable = true;
  };
}
```

## Real-World Examples

### Example 1: NixVim (User Module)

**Default (disabled):**
```nix
# lib/defaults.nix
userSettings = {
  nixvimEnabled = false;  # Disabled by default
};
```

**Profile override (enabled for DESK and LAPTOP):**
```nix
# profiles/DESK-config.nix
systemSettings = {
  nixvimEnabled = true;  # Enable for desktop
};

# profiles/LAPTOP-config.nix
systemSettings = {
  nixvimEnabled = true;  # Enable for laptop
};
```

**Module usage:**
```nix
# user/app/nixvim/nixvim.nix
{ config, pkgs, lib, systemSettings, ... }:

{
  programs.nixvim = lib.mkIf systemSettings.nixvimEnabled {
    enable = true;
    # ... configuration ...
  };
}
```

### Example 2: SwayFX for DESK (System Module)

**Default (disabled):**
```nix
# lib/defaults.nix
systemSettings = {
  enableSwayForDESK = false;  # Disabled by default
};
```

**Profile override (enabled only for DESK):**
```nix
# profiles/DESK-config.nix
systemSettings = {
  enableSwayForDESK = true;  # Only enable for DESK profile
};
```

**Module usage:**
```nix
# user/wm/sway/default.nix
{ lib, systemSettings, ... }:

{
  imports = lib.optionals (systemSettings.enableSwayForDESK == true) [
    ./swayfx-config.nix
    # ... other Sway modules ...
  ];
}
```

### Example 3: Multiple Feature Flags

**Defaults:**
```nix
# lib/defaults.nix
systemSettings = {
  aichatEnable = false;
  lmstudioEnabled = false;
  sunshineEnable = false;
  sambaEnable = false;
};
```

**Profile-specific enabling:**
```nix
# profiles/DESK-config.nix
systemSettings = {
  aichatEnable = true;      # Enable for desktop
  lmstudioEnabled = true;   # Enable for desktop
  sunshineEnable = true;    # Enable for desktop
  sambaEnable = true;       # Enable for desktop
};

# profiles/LAPTOP-config.nix
systemSettings = {
  aichatEnable = true;      # Enable for laptop
  sunshineEnable = true;    # Enable for laptop
  # lmstudioEnabled = false; # Not needed on laptop (uses default)
  # sambaEnable = false;     # Not needed on laptop (uses default)
};
```

## Naming Conventions

Use consistent naming patterns for feature flags:

- **Boolean flags**: Use `featureNameEnable` or `featureNameEnabled`
  - `aichatEnable`
  - `nixvimEnabled`
  - `sunshineEnable`
  - `sambaEnable`

- **Be consistent**: Choose one pattern (`Enable` vs `Enabled`) and stick with it, or follow existing patterns in the codebase

## Best Practices

### 1. Always Default to `false`

✅ **Good:**
```nix
systemSettings = {
  newFeatureEnable = false;  # Opt-in by default
};
```

❌ **Bad:**
```nix
systemSettings = {
  newFeatureEnable = true;  # Don't enable by default
};
```

### 2. Use Descriptive Names

✅ **Good:**
```nix
enableSwayForDESK = true;  # Clear what it does and where
```

❌ **Bad:**
```nix
sway = true;  # Too vague
```

### 3. Document in Profile Configs

Add comments explaining why a feature is enabled/disabled:

```nix
# profiles/DESK-config.nix
systemSettings = {
  # Enable SwayFX as second WM option alongside Plasma6
  enableSwayForDESK = true;
  
  # Enable NixVim for Cursor IDE-like experience
  nixvimEnabled = true;
  
  # Disable Samba on laptop (not needed)
  sambaEnable = false;
};
```

### 4. Use `lib.mkIf` for Conditional Enabling

✅ **Good:**
```nix
programs.newFeature = lib.mkIf systemSettings.newFeatureEnable {
  enable = true;
  # ... config ...
};
```

❌ **Bad:**
```nix
programs.newFeature = {
  enable = systemSettings.newFeatureEnable;  # Less clear
  # ... config ...
};
```

### 5. Group Related Flags

Keep related feature flags together in the defaults file:

```nix
# lib/defaults.nix
systemSettings = {
  # AI/ML Features
  aichatEnable = false;
  lmstudioEnabled = false;
  
  # Gaming Features
  sunshineEnable = false;
  gamemodeEnable = false;
  
  # Network Features
  sambaEnable = false;
  wireguardEnable = false;
};
```

## Common Patterns

### Pattern 1: Import Conditional Modules

```nix
# user/wm/sway/default.nix
{ lib, systemSettings, ... }:

{
  imports = lib.optionals systemSettings.enableSwayForDESK [
    ./swayfx-config.nix
    ./waybar.nix
  ];
}
```

### Pattern 2: Conditional Service/Program

```nix
# user/app/newfeature/newfeature.nix
{ config, pkgs, lib, systemSettings, ... }:

{
  programs.newFeature = lib.mkIf systemSettings.newFeatureEnable {
    enable = true;
    settings = {
      # ... configuration ...
    };
  };
}
```

### Pattern 3: Conditional Package Installation

```nix
# In profile config
systemSettings = {
  newFeatureEnable = true;
};

# In module
{ config, pkgs, lib, systemSettings, ... }:

{
  home.packages = lib.optionals systemSettings.newFeatureEnable [
    pkgs.newFeaturePackage
  ];
}
```

## When to Use Feature Flags

**Use feature flags when:**
- ✅ Feature should be opt-in (not enabled by default)
- ✅ Feature is only needed on specific profiles
- ✅ Feature has significant dependencies or overhead
- ✅ Feature is experimental or optional

**Don't use feature flags when:**
- ❌ Feature is core functionality needed everywhere
- ❌ Feature is always enabled (just configure it directly)
- ❌ Feature is a small, lightweight addition

## Migration Example

If you have an existing module that's always enabled and want to make it profile-specific:

**Before:**
```nix
# user/app/oldfeature/oldfeature.nix
{ config, pkgs, ... }:

{
  programs.oldFeature = {
    enable = true;  # Always enabled
    # ... config ...
  };
}
```

**After:**
```nix
# Step 1: Add flag to lib/defaults.nix
systemSettings = {
  oldFeatureEnable = false;  # Disable by default
};

# Step 2: Update module
# user/app/oldfeature/oldfeature.nix
{ config, pkgs, lib, systemSettings, ... }:

{
  programs.oldFeature = lib.mkIf systemSettings.oldFeatureEnable {
    enable = true;  # Only if flag is true
    # ... config ...
  };
}

# Step 3: Enable in specific profiles
# profiles/DESK-config.nix
systemSettings = {
  oldFeatureEnable = true;  # Enable for DESK
};
```

## Related Documentation

- [Configuration Guide](configuration.md) - General configuration patterns
- [Profiles Documentation](profiles.md) - Profile system overview
- [User Modules Guide](user-modules/README.md) - Creating user-level modules
- [System Modules Guide](system-modules/README.md) - Creating system-level modules
