---
id: user-modules.plasma6
summary: Plasma 6 configuration integration for NixOS/Home Manager with export/import and symlink-based mutability.
tags: [plasma6, kde, desktop, home-manager, configuration]
related_files:
  - user/wm/plasma6/**
  - system/wm/plasma6.nix
  - docs/user-modules/plasma6.md
key_files:
  - user/wm/plasma6/plasma6.nix
  - system/wm/plasma6.nix
  - docs/user-modules/plasma6.md
activation_hints:
  - If changing KDE Plasma 6 behavior, config export/import, or PAM/KWallet interactions in Plasma sessions
---

# Plasma 6 Desktop Configuration

Complete guide to configuring KDE Plasma 6 desktop environment.

## Table of Contents

- [Overview](#overview)
- [Configuration Files](#configuration-files)
- [Exporting Configuration](#exporting-configuration)
- [Importing Configuration](#importing-configuration)
- [Symlink Management](#symlink-management)
- [User-Specific Configurations](#user-specific-configurations)
- [Troubleshooting](#troubleshooting)

## Overview

This configuration integrates KDE Plasma 6 settings into the NixOS/Home Manager setup, allowing you to version control your desktop configuration while maintaining the ability to make runtime changes.

### Features

- Version-controlled Plasma settings
- User-specific configuration support
- Mutable configuration files (via symlinks)
- Automatic integration with install script
- Easy backup and restore

## Configuration Files

Plasma 6 configuration files are located in:

```
user/wm/plasma6/
├── plasma6.nix          # Home Manager module
├── _export_homeDotfiles.sh  # Export script
├── _remove_homeDotfiles.sh  # Remove script
├── _check_directories.sh   # Check script
└── readme.md            # This file
```

### Source Directory Structure

Configuration files are stored in a source directory (default: `~/.dotfiles-plasma-config/source/`) and symlinked to the home directory.

```
~/.dotfiles-plasma-config/
├── source/
│   └── USERNAME/        # User-specific configs
│       ├── kded6/
│       ├── kwinrc
│       └── ...
└── userDotfiles/       # Temporary directory for removal
```

## Exporting Configuration

### If You've Been Using Plasma

If you already have Plasma configured and want to save your settings:

1. **Run the export script**:
   ```sh
   cd user/wm/plasma6
   ./_export_homeDotfiles.sh
   ```

2. **This will**:
   - Copy all Plasma dotfiles from `$HOME` to `~/.dotfiles-plasma-config/source`
   - Preserve your current configuration
   - Allow you to version control your settings

3. **Note**: You may need to overwrite or remove existing files in the source directory if you've exported before.

### During Installation

Note: `install.sh` does not currently prompt to export Plasma dotfiles. Use the export script manually (`./_export_homeDotfiles.sh`) when you want to capture your current Plasma state.

## Importing Configuration

### Setting Up Plasma Settings Directory

If you want to use any directory to set up your Plasma settings:

1. **Remove existing home dotfiles**:
   ```sh
   cd user/wm/plasma6
   ./_remove_homeDotfiles.sh
   ```

   This uses `~/.dotfiles-plasma-config/userDotfiles` or adjusts the variable in `plasma6.nix`.

2. **After removal**, you can run `install.sh` or build home-manager.

### How It Works

The `plasma6.nix` module creates symlinks from `$HOME` Plasma dotfiles to the source directory:

```nix
home.file.".local/share/kded6/".source = ./. + builtins.toPath ("/" + userSettings.username + "/kded6");
```

This allows:
- Configuration files to be mutable (can be edited at runtime)
- Changes to persist across Home Manager rebuilds
- Easy version control of settings

## Symlink Management

### Creating Symlinks

The `plasma6.nix` module automatically creates symlinks for:

- `.local/share/kded6/` - KDE daemon configuration
- `.config/kwinrc` - KWin window manager settings
- Other Plasma configuration files

### User-Specific Paths

The module uses `userSettings.username` to support different users/computers:

```nix
source = ./. + builtins.toPath ("/" + userSettings.username + "/kded6");
```

**Important**: If you've imported your Plasma dotfiles to `/source`, you must rename or copy the directory to match your username:

```sh
# If your username is "akunito"
mv ~/.dotfiles-plasma-config/source/oldname ~/.dotfiles-plasma-config/source/akunito
```

## User-Specific Configurations

### Multiple Users/Computers

The configuration supports different profiles for different users or computers:

```
~/.dotfiles-plasma-config/source/
├── akunito/    # Configurations for akunito user
│   ├── kded6/
│   └── kwinrc
└── aga/        # Configurations for aga user
    ├── kded6/
    └── kwinrc
```

### Matching Username

The `plasma6.nix` file expects the directory name to match `userSettings.username`:

```nix
source = ./. + builtins.toPath ("/" + userSettings.username + "/kded6");
```

Make sure your exported configuration directory matches your username.

## NixOS - Home Manager Source (Immutable Files)

### Important Note

Remember that `install.sh` runs on Git, so you must commit first to get the latest changes in home-manager.

### Sourcing Directories

We can source under `/home` any directory or file from our Git repo or any other location.

**Note**: These files will be overwritten if you reinstall home-manager as they are under `/nix/store/result/.....` If you want to keep their changes, you need another approach (see symlink method above).

### Source a Directory

The directory might need to contain at least one file to avoid failures:

```nix
home.file.".local/share/kded6/".source = ./. + builtins.toPath ("/" + userSettings.username + "/kded6");
home.file.".local/share/kded6/".recursive = true;
```

- `home.file.".local/share/kded6/"` represents `$HOME/.local/share/kded6/`
- `recursive` generates symlinks for each file inside the directory
- `source` contains the path to the directory in the Git repo
- Files under `/nix/store/result` are **immutable**

### Source a File

With variable from flake.nix:

```nix
home.file.".config/kwinrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kwinrc");
```

Or hardcoded:

```nix
home.file.".config/kwinrc".source = ./username/kwinrc;
```

## NixOS - Home Manager Link Dotfiles

### Use Case

Link Plasma dotfiles that contain all settings into the project, but keep them mutable so user changes persist and can be uploaded to the repo when needed.

### Solution: Symlinks

Instead of using `home.file.source` (which makes files immutable), create symlinks:

1. Files remain mutable
2. Changes persist across Home Manager rebuilds
3. Changes can be committed to the repository
4. Easy to manage and version control

This is what `plasma6.nix` does automatically.

## Troubleshooting

### Configuration Not Applying

**Problem**: Plasma settings don't match the source files.

**Solutions**:
1. Check symlinks: `ls -la ~/.config/kwinrc`
2. Verify source directory exists
3. Check username matches: `echo $USER`
4. Rebuild home-manager: `aku sync user`

### Symlinks Broken

**Problem**: Symlinks point to wrong location.

**Solutions**:
1. Remove broken symlinks
2. Rebuild home-manager
3. Verify source directory path
4. Check `userSettings.username` in flake

### Changes Not Persisting

**Problem**: Configuration changes are lost after rebuild.

**Solutions**:
1. Verify you're editing the source files, not symlinks
2. Check symlink target: `readlink ~/.config/kwinrc`
3. Ensure using symlink method, not source method
4. Commit changes to Git

### Export Script Fails

**Problem**: Export script doesn't work.

**Solutions**:
1. Check source directory permissions
2. Verify Plasma is installed
3. Check if files exist in `$HOME`
4. Run script with appropriate permissions

## Best Practices

### 1. Version Control

- Commit Plasma configuration files to Git
- Document custom settings
- Keep user-specific configs separate

### 2. Regular Backups

- Export configuration regularly
- Commit changes to Git
- Keep backups of important settings

### 3. Testing

- Test configuration changes incrementally
- Verify settings apply correctly
- Check after Home Manager rebuilds

### 4. Documentation

- Document custom Plasma settings
- Explain why certain configurations exist
- Keep notes on user-specific customizations

## Related Documentation

- [User Modules Guide](../user-modules.md) - User-level modules
- [Configuration Guide](../configuration.md) - Configuration management
- [Plasma 6 README](../../user/wm/plasma6/readme.md) - Original documentation

