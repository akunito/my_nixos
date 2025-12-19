# Profiles Guide

Guide to understanding and using system profiles in this NixOS configuration.

## Table of Contents

- [What are Profiles?](#what-are-profiles)
- [Available Profiles](#available-profiles)
- [Profile Structure](#profile-structure)
- [Creating a New Profile](#creating-a-new-profile)
- [Switching Profiles](#switching-profiles)
- [Profile Comparison](#profile-comparison)

## What are Profiles?

Profiles are pre-configured system templates that define what software and settings should be installed for different use cases. Each profile consists of:

- **`configuration.nix`** - System-level configuration
- **`home.nix`** - User-level configuration (Home Manager)
- **`README.org`** - Profile-specific documentation

Profiles allow you to:
- Maintain different configurations for different machines
- Share common configurations across machines
- Quickly set up new systems with known-good configurations

## Available Profiles

### Personal Profile

**Location**: `profiles/personal/`

**Use Case**: Personal laptop or desktop computer

**Features**:
- Full desktop environment (Plasma 6)
- Gaming applications
- Social applications
- Development tools
- Secondary drive mounting
- Full multimedia support

**Best For**: Your main personal computer

**Note**: This profile includes secondary drive mounting via `system/hardware/drives.nix`. It may fail if drives are not found - disable or adjust as needed. This profile is functionally identical to the work profile but includes extra things like games and social apps.

### Work Profile

**Location**: `profiles/work/`

**Use Case**: Work laptop or desktop

**Features**:
- Focused productivity setup
- No gaming applications
- No social media applications
- Professional development tools
- Minimal distractions

**Best For**: Work computers where you want to stay focused

**Note**: Functionally identical to personal profile but excludes games and social apps. This is the work profile, including all the things needed to be efficient for various tasks, and **not** including distracting things such as games and social apps!

### Homelab Profile

**Location**: `profiles/homelab/`

**Use Case**: Server or homelab system

**Features**:
- Server-optimized configuration
- SSH server enabled
- Docker support
- Virtualization support
- NFS server/client
- Minimal desktop environment (if any)
- Power management for 24/7 operation

**Best For**: Home servers, NAS systems, homelab infrastructure

**Security Note**: ⚠️ **CHANGE THE SSH KEYS** in `configuration.nix` before using!

**Note**: This is a template system configuration to be installed as a homelab/server.

### Worklab Profile

**Location**: `profiles/worklab/`

**Use Case**: Work server or small servers at work

**Features**:
- Same as homelab profile
- Pre-configured with work SSH keys
- Work-specific network settings

**Best For**: Small servers at work locations

**Security Note**: ⚠️ **CHANGE THE SSH KEYS** in `configuration.nix` before using!

### WSL Profile

**Location**: `profiles/wsl/`

**Use Case**: Windows Subsystem for Linux

**Features**:
- Minimal NixOS installation
- Emacs configuration
- Essential CLI tools (ranger, etc.)
- LibreOffice (runs better than on Windows)
- Uses [NixOS-WSL](https://github.com/nix-community/NixOS-WSL)

**Best For**: Using NixOS tools on Windows systems

**Note**: The `nixos-wsl` directory is taken directly from [NixOS-WSL](https://github.com/nix-community/NixOS-WSL) and patched slightly to allow it to run with the unstable channel of nixpkgs.

### Nix-on-Droid Profile

**Location**: `profiles/nix-on-droid/`

**Use Case**: Android devices

**Features**:
- Minimal mobile-optimized configuration
- Emacs support
- Essential CLI tools
- Uses [nix-on-droid](https://github.com/nix-community/nix-on-droid)

**Best For**: Running NixOS tools on Android devices

**Note**: Essentially just Emacs and some CLI apps for running NixOS tools on Android devices.

## Profile Structure

Each profile directory contains:

```
profiles/PROFILE/
├── configuration.nix    # System-level configuration
├── home.nix             # User-level configuration
└── README.md             # Profile documentation
```

**Note**: Profile-specific README.md files are available in each profile directory. See [profiles/README.md](../../profiles/README.md) for an overview.

### Configuration.nix

System-level configuration that imports modules from `system/`:

```nix
{ config, pkgs, systemSettings, userSettings, ... }:

{
  imports = [
    ../../system/app/docker.nix
    ../../system/hardware/drives.nix
    ../../system/security/sshd.nix
    # ... more imports
  ];
  
  # Profile-specific system settings
}
```

### Home.nix

User-level configuration that imports modules from `user/`:

```nix
{ config, pkgs, userSettings, systemSettings, ... }:

{
  imports = [
    ../../user/app/git/git.nix
    ../../user/wm/plasma6/plasma6.nix
    # ... more imports
  ];
  
  # Profile-specific user settings
}
```

## Creating a New Profile

### Step 1: Create Profile Directory

```sh
mkdir -p profiles/MYPROFILE
```

### Step 2: Create Configuration Files

Copy from an existing profile as a template:

```sh
cp profiles/personal/configuration.nix profiles/MYPROFILE/
cp profiles/personal/home.nix profiles/MYPROFILE/
```

### Step 3: Create Flake File

Create `flake.MYPROFILE.nix`:

```nix
{
  description = "Flake for MYPROFILE";

  outputs = inputs@{ self, ... }:
    let
      systemSettings = {
        profile = "MYPROFILE";  # Must match directory name
        # ... your settings
      };
      # ... rest of flake configuration
    in {
      # ... outputs
    };
}
```

### Step 4: Customize Configuration

Edit `profiles/MYPROFILE/configuration.nix` and `profiles/MYPROFILE/home.nix` to add/remove modules and settings specific to your profile.

### Step 5: Test Profile

```sh
cp flake.MYPROFILE.nix flake.nix
phoenix sync
```

## Switching Profiles

### Using Install Script

```sh
./install.sh ~/.dotfiles "MYPROFILE"
```

This automatically:
1. Copies `flake.MYPROFILE.nix` → `flake.nix`
2. Rebuilds the system

### Manual Switch

```sh
# 1. Copy flake file
cp flake.MYPROFILE.nix flake.nix

# 2. Rebuild
phoenix sync
```

## Profile Comparison

| Feature | Personal | Work | Homelab | Worklab | WSL | Nix-on-Droid |
|---------|----------|------|---------|---------|-----|--------------|
| Desktop Environment | ✅ Plasma 6 | ✅ Plasma 6 | ❌ Minimal | ❌ Minimal | ❌ | ❌ |
| Gaming Apps | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Social Apps | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Development Tools | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Docker | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| Virtualization | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| SSH Server | Optional | Optional | ✅ | ✅ | ❌ | ❌ |
| NFS Server | Optional | Optional | ✅ | ✅ | ❌ | ❌ |
| Emacs | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

## Profile Inheritance

Some profiles inherit from others:

- **Work** profile imports **Personal** profile (but excludes games/social apps)
- **Worklab** profile uses **Homelab** base configuration (`base.nix`)

This allows sharing common configurations while maintaining differences.

**Note**: The personal and work profiles are functionally identical (the work profile is actually imported into the personal profile). The only difference is that the personal profile has a few extra things like gaming and social apps. Similarly, the homelab and worklab profiles are functionally identical (they both utilize the `base.nix` file). The only difference is that they have different preinstalled SSH keys.

## Best Practices

### 1. Keep Profiles Focused

Each profile should have a clear purpose. Don't create profiles for minor variations.

### 2. Share Common Configurations

Use the module system to share common configurations across profiles rather than duplicating code.

### 3. Document Profile-Specific Settings

Add comments in `configuration.nix` and `home.nix` explaining why certain modules are included or excluded.

### 4. Test Before Committing

Always test a profile on a test system or VM before using it on production systems.

### 5. Version Control Profiles

Keep all profiles in version control so you can:
- Track changes over time
- Roll back if needed
- Share configurations across machines

## Related Documentation

- [Configuration Guide](configuration.md) - Understanding configuration structure
- [Installation Guide](installation.md) - Installing with a specific profile
- [System Modules](system-modules.md) - Available system modules
- [User Modules](user-modules.md) - Available user modules

