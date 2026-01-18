---
author: Akunito
title: NixOS Configuration Repository
description: Comprehensive NixOS dotfiles configuration for multiple systems and use cases
---

# NixOS Configuration Repository

A comprehensive, modular NixOS configuration repository forked from Librephoenix's setup, enhanced with additional features for different use cases including homelab servers, family laptops, development machines, and more.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Documentation Structure](#documentation-structure)
- [Features](#features)
- [Project Structure](#project-structure)
- [Getting Help](#getting-help)

## Overview

This repository contains a complete NixOS configuration system that supports multiple profiles, system types, and use cases. It uses a modular architecture where system-level and user-level configurations are separated, allowing for easy customization and maintenance across different machines.

### Key Concepts

- **Profiles**: Pre-configured system templates for different use cases (personal, work, homelab, etc.)
- **System Modules**: Low-level system configuration (hardware, security, services)
- **User Modules**: User-level applications and configurations managed via Home Manager
- **Flakes**: Modern Nix package management with reproducible builds
- **Themes**: 55+ base16 themes with system-wide theming via Stylix

## Quick Start

### Installation

For a complete installation guide, see [Installation Documentation](docs/installation.md).

**Quick install:**
```sh
# Interactive mode
./install.sh ~/.dotfiles "PROFILE"

# Silent mode
./install.sh ~/.dotfiles "PROFILE" -s
```

Where `PROFILE` corresponds to a flake file like `flake.HOME.nix`, `flake.DESK.nix`, etc.

### Basic Usage

After installation, use the `phoenix` wrapper script for common operations:

```sh
phoenix sync          # Synchronize system and home-manager
phoenix sync system   # Only synchronize system
phoenix sync user     # Only synchronize home-manager
phoenix update        # Update flake inputs
phoenix upgrade       # Update and synchronize
phoenix gc            # Garbage collect old generations
```

For complete script documentation, see [Scripts Reference](docs/scripts.md).

## Documentation Structure

This repository uses a 3-level documentation structure:

## Navigating Documentation

This repo uses a **Router + Catalog** system to help you find documentation quickly:

- **Router (quick lookup):** `docs/00_ROUTER.md` - Compact table for finding specific topics
- **Catalog (browse all):** `docs/01_CATALOG.md` - Complete listing of all modules and docs
- **Navigation guide:** [`docs/navigation.md`](docs/navigation.md) - **Start here** to learn how to use the Router/Catalog system

**Quick start**: Open [`docs/navigation.md`](docs/navigation.md) to learn how to efficiently find the documentation you need.

## AI agent context (Cursor / other coding agents)

This repo uses a **Router + Catalog** system to keep AI context scoped as docs grow:

- **Router (small, fast):** `docs/00_ROUTER.md` (pick relevant IDs first)
- **Catalog (full listing):** `docs/01_CATALOG.md`
- **How it works / template:** `docs/agent-context.md`
- **Agent instructions:** `AGENTS.md` + scoped `.cursor/rules/*.mdc`

### Level 1: Top-Level (This File)
- Overview and quick start
- Navigation to major topics
- Project structure overview

### Level 2: Major Topics
Located in the `docs/` directory:

- **[Installation](docs/installation.md)** - Complete installation guide, manual and automated procedures
- **[Configuration](docs/configuration.md)** - Flake management, variables, and configuration structure
- **[Profiles](docs/profiles.md)** - Available profiles and how to use them
- **[System Modules](docs/system-modules.md)** - System-level configuration modules
- **[User Modules](docs/user-modules.md)** - User-level applications and configurations
- **[Maintenance & Scripts](docs/maintenance.md)** - Maintenance tasks, scripts, and automation
- **[Scripts Reference](docs/scripts.md)** - Complete documentation for all shell scripts
- **[Keybindings](docs/keybindings.md)** - Complete reference for all keybindings
- **[Security](docs/security.md)** - Security configurations, SSH, encryption, backups
- **[Hardware](docs/hardware.md)** - Hardware-specific configurations, drives, power management
- **[Themes](docs/themes.md)** - Theme system and customization
- **[Patches](docs/patches.md)** - Nixpkgs patches and customizations

### Level 3: Specific Documentation
Detailed guides for specific topics:

**Security**:
- **[LUKS Encryption & Remote Unlocking](docs/security/luks-encryption.md)** - Setting up encrypted drives with SSH unlock
- **[Restic Backups](docs/security/restic-backups.md)** - Automated backup system configuration
- **[Sudo Configuration](docs/security/sudo.md)** - Sudo setup and best practices
- **[Polkit Configuration](docs/security/polkit.md)** - Polkit rules and permissions

**Hardware**:
- **[CPU Power Management](docs/hardware/cpu-power-management.md)** - Kernel modules and CPU governors
- **[Drive Management](docs/hardware/drive-management.md)** - Mounting and managing drives
- **[GPU Monitoring](docs/hardware/gpu-monitoring.md)** - GPU monitoring tools and configuration

**Keybindings**:
- **[Sway Keybindings](docs/keybindings/sway.md)** - Complete SwayFX keybindings reference
- **[Hyprland Keybindings](docs/keybindings/hyprland.md)** - Complete Hyprland keybindings reference

**User Modules**:
- **[Plasma 6 Desktop](docs/user-modules/plasma6.md)** - KDE Plasma 6 configuration
- **[Doom Emacs](docs/user-modules/doom-emacs.md)** - Doom Emacs setup
- **[Ranger](docs/user-modules/ranger.md)** - Terminal file manager
- **[XMonad](docs/user-modules/xmonad.md)** - Tiling window manager
- **[Picom](docs/user-modules/picom.md)** - X11 compositor

And more in respective subdirectories.

**Note**: README.md files are now available in subdirectories alongside the code. Original README.org files are preserved for historical reference. Comprehensive documentation is available in `docs/`.

## Features

### Desktop Environment
- **Plasma 6** - Primary desktop environment (configurable)
- **Hyprland** - Wayland compositor support (alternative)
- **XMonad** - Tiling window manager support

### System Features
- **SSH Server on Boot** - Remote LUKS disk unlocking
- **Automated System Maintenance** - Generation cleanup and optimization
- **Docker Container Management** - Automated handling during system updates
- **QEMU Virtualization** - Full virtualization support with remote management
- **Network Bridge Configuration** - For VM networking
- **Printer Support** - Brother Laser printer drivers and network printing
- **NFS Client/Server** - Network file system support
- **Automated Backups** - Restic-based backup system with SystemD timers
- **Keyboard Remapping** - keyd service for Caps Lock to Hyper key remapping (see [System Modules - keyd](docs/system-modules.md#keyd-systemwmkeydnix))

### Security Features
- **LUKS Encryption** - Full disk encryption with remote unlock capability
- **Firewall Configuration** - Customizable firewall rules
- **SSH Key Management** - Centralized SSH key configuration
- **Polkit Rules** - Fine-grained permission management
- **Sudo/Doas Configuration** - Flexible privilege escalation

### Development & Tools
- **Multiple Programming Languages** - Python, Rust, Go, and more
- **Doom Emacs** - Fully configured Emacs distribution
- **Git Configuration** - Pre-configured git settings
- **Terminal Emulators** - Alacritty and Kitty configurations
- **CLI Tools** - Curated collection of command-line utilities

### Theming
- **55+ Base16 Themes** - System-wide theming via Stylix
- **Dynamic Theme Switching** - Switch themes on-the-fly
- **Consistent Styling** - Unified look across all applications

## Project Structure

```
.dotfiles/
├── README.md                 # This file (Level 1)
├── docs/                     # Level 2 documentation
│   ├── installation.md
│   ├── configuration.md
│   ├── profiles.md
│   ├── system-modules.md
│   ├── user-modules.md
│   ├── maintenance.md
│   ├── security/
│   ├── hardware/
│   └── ...
├── flake.nix                 # Main flake (template)
├── flake.*.nix               # Profile-specific flakes
├── install.sh                # Installation script
├── maintenance.sh            # Maintenance automation
├── profiles/                 # System profiles
│   ├── personal/
│   ├── work/
│   ├── homelab/
│   ├── worklab/
│   ├── wsl/
│   └── nix-on-droid/
├── system/                   # System-level modules
│   ├── app/                  # System applications
│   ├── hardware/             # Hardware configuration
│   ├── security/             # Security settings
│   ├── wm/                   # Window manager setup
│   └── bin/                  # System scripts (phoenix)
├── user/                     # User-level modules
│   ├── app/                  # User applications
│   ├── lang/                 # Programming languages
│   ├── shell/                # Shell configurations
│   ├── wm/                   # Window manager configs
│   └── style/                # User styling
├── themes/                   # Base16 themes
├── patches/                  # Nixpkgs patches
└── assets/                   # Static assets (wallpapers, etc.)
```

## Documentation Standards

This repository follows a **3-level documentation structure** with comprehensive guidelines. See [`.cursorrules`](.cursorrules) for complete documentation standards, including:

- Documentation structure and organization
- Cross-referencing guidelines
- README.org to Markdown conversion
- Temporary documentation handling (`docs/future/`)

## Getting Help

### Common Issues

1. **Installation fails** - Check [Installation Documentation](docs/installation.md) for troubleshooting
2. **Docker containers break boot** - See [Maintenance Documentation](docs/maintenance.md#docker-handling)
3. **SSH unlock not working** - See [LUKS Encryption Guide](docs/security/luks-encryption.md)
4. **Theme not applying** - Check [Themes Documentation](docs/themes.md)

### Resources

- **Original Documentation**: See the "Original Document from Librephoenix" section below for historical context
- **NixOS Wiki**: [nixos.wiki](https://nixos.wiki)
- **Home Manager Manual**: [nix-community.github.io/home-manager](https://nix-community.github.io/home-manager)

---

## Original Document from Librephoenix

The following section contains the original documentation from Librephoenix's repository, preserved for historical context and reference.

### What is this repository?

These are my dotfiles (configuration files) for my NixOS setup(s).

### My Themes

[Stylix](https://github.com/danth/stylix#readme) (and [base16.nix](https://github.com/SenchoPens/base16.nix#readme), of course) is amazing, allowing you to theme your entire system with base16-themes.

Using this I have [55+ themes](./themes) (I add more sometimes) I can switch between on-the-fly. Visit the [themes directory](./themes) for more info and screenshots!

### Install

I wrote some reinstall notes for myself [here (install.md)](./install.md).

TLDR: You should be able to install these dotfiles to a fresh NixOS system. See [Installation Documentation](docs/installation.md) for current installation methods.

**Note**: The original installation command from LibrePhoenix's repository is no longer applicable as this is a fork. Use the installation methods described in the documentation.

Disclaimer: Ultimately, I can't guarantee this will work for anyone other than myself, so *use this at your own discretion*. Also my dotfiles are *highly* opinionated, which you will discover immediately if you try them out.

Potential Errors: I've only tested it working on UEFI with the default EFI mount point of `/boot`. I've added experimental legacy (BIOS) boot support, but it does rely on a quick and dirty script to find the grub device. If you are testing it using some weird boot configuration for whatever reason, try modifying `bootMountPath` (UEFI) or `grubDevice` (legacy BIOS) in `flake.nix` before install, or else it will complain about not being able to install the bootloader.

Note: If you're installing this to a VM, Hyprland won't work unless 3D acceleration is enabled.

Security Disclaimer: If you install or copy my `homelab` or `worklab` profiles, *CHANGE THE PUBLIC SSH KEYS UNLESS YOU WANT ME TO BE ABLE TO SSH INTO YOUR SERVER. YOU CAN CHANGE OR REMOVE THE SSH KEY IN THE RELEVANT CONFIGURATION.NIX*:

- [configuration.nix](./profiles/homelab/configuration.nix) for homelab profile
- [configuration.nix](./profiles/worklab/configuration.nix) for worklab profile

### Modules

Separate Nix files can be imported as modules using an import block:

```nix
imports = [ ./import1.nix
            ./import2.nix
            ...
          ];
```

This conveniently allows configurations to be (*cough cough) *modular* (ba dum, tssss).

I have my modules separated into two groups:

- System-level - stored in the [system directory](./system)
  - System-level modules are imported into configuration.nix, which is what is sourced into [my flake (flake.nix)](./flake.nix)
- User-level - stored in the [user directory](./user) (managed by home-manager)
  - User-level modules are imported into home.nix, which is also sourced into [my flake (flake.nix)](./flake.nix)

More detailed information on these specific modules are in the [system directory](./system) and [user directory](./user) respectively.

### Patches

In some cases, since I use `nixpgs-unstable`, I must patch nixpkgs. This can be done inside of a flake via:

```nix
nixpkgs-patched = (import nixpkgs { inherit system; }).applyPatches {
  name = "nixpkgs-patched";
  src = nixpkgs;
  patches = [ ./example-patch.nix ];
};

# configure pkgs
pkgs = import nixpkgs-patched { inherit system; };

# configure lib
lib = nixpkgs.lib;
```

Patches can either be local or remote, so you can even import unmerged pull requests by using `fetchpatch` and the raw patch url, i.e: <https://github.com/NixOS/nixpkgs/pull/example.patch>.

I currently curate patches local to this repo in the [patches](./patches) directory.

### Profiles

I separate my configurations into [profiles](./profiles) (essentially system templates), i.e:

- [Personal](./profiles/personal) - What I would run on a personal laptop/desktop
- [Work](./profiles/work) - What I would run on a work laptop/desktop (if they let me bring my own OS :P)
- [Homelab](./profiles/homelab) - What I would run on a server or homelab
- [WSL](./profiles/wsl) - What I would run underneath Windows Subsystem for Linux

My profile can be conveniently selected in [my flake.nix](./flake.nix) by setting the `profile` variable.

More detailed information on these profiles is in the [profiles directory](./profiles).

### Nix Wrapper Script

Some Nix commands are confusing, really long to type out, or require me to be in the directory with my dotfiles. To solve this, I wrote a [wrapper script called phoenix](./system/bin/phoenix.nix), which calls various scripts in the root of this directory.

TLDR:

- `phoenix sync` - Synchronize system and home-manager state with config files (essentially `nixos-rebuild switch` + `home-manager switch`)
  - `phoenix sync system` - Only synchronize system state (essentially `nixos-rebuild switch`)
  - `phoenix sync user` - Only synchronize home-manager state (essentially `home-manager switch`)
- `phoenix update` - Update all flake inputs without synchronizing system and home-manager states
- `phoenix upgrade` - Update flake.lock and synchronize system and home-manager states (`phoenix update` + `phoenix sync`)
- `phoenix refresh` - Call synchronization posthooks (mainly to refresh stylix and some dependent daemons)
- `phoenix pull` - Pull changes from upstream git and attempt to merge local changes (I use this to update systems other than my main system)
- `phoenix harden` - Ensure that all "system-level" files cannot be edited by an unprivileged user
- `phoenix soften` - Relax permissions so all dotfiles can be edited by a normal user (use temporarily for git or other operations)
- `phoenix gc` - Garbage collect the system and user nix stores
  - `phoenix gc full` - Delete everything not currently in use
  - `phoenix gc 15d` - Delete everything older than 15 days
  - `phoenix gc 30d` - Delete everything older than 30 days
  - `phoenix gc Xd` - Delete everything older than X days
