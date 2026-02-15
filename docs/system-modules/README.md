---
id: system-modules
summary: Complete reference for system-level NixOS modules — app, hardware, security, WM, and utility modules
tags: [system-modules, nixos, configuration, modules]
related_files: [system/**/*.nix]
date: 2026-02-15
status: published
---

# System Modules Guide

Complete reference for system-level NixOS modules in this configuration.

## Sub-documents

| Doc | Description |
|-----|-------------|
| [app-modules.md](app-modules.md) | Docker, Virtualization, Flatpak, Steam, Gamemode, Samba, AppImage |
| [hardware-modules.md](hardware-modules.md) | Drives, Power, Kernel, Bluetooth, Printing, OpenGL, Xbox, NFS, SystemD, Time |
| [security-wm-utils.md](security-wm-utils.md) | SSH, Firewall, Sudo, Polkit, Restic, GPG, Fail2ban, WM modules, keyd, aku wrapper |

## Overview

System modules are located in the `system/` directory and provide system-level configuration. They are imported in profile `configuration.nix` files and receive variables via `specialArgs`.

### Module Import Syntax

```nix
imports = [ import1.nix
            import2.nix
          ];
```

### Module Structure

```nix
{ lib, systemSettings, pkgs, userSettings, authorizedKeys ? [], ... }:

{
  services.example.enable = lib.mkIf systemSettings.exampleEnable true;
}
```

## Module Categories

| Category | Path | Description |
|----------|------|-------------|
| Application | `system/app/` | System-level app configs requiring services or privileges |
| Hardware | `system/hardware/` | Hardware-specific configs, drivers, kernel modules |
| Security | `system/security/` | SSH, firewall, encryption, access control |
| Window Manager | `system/wm/` | System-level WM and desktop environment config |
| Utility | `system/bin/` | System utilities and wrapper scripts |

## Using Modules

### Importing in configuration.nix

```nix
imports = [
  ../../system/app/docker.nix
  ../../system/hardware/drives.nix
  ../../system/security/sshd.nix
];
```

### Conditional Enabling

```nix
services.docker.enable = lib.mkIf systemSettings.dockerEnable true;
```

### Variables from flake.nix

Common attribute sets passed to system modules via `specialArgs`:
- `userSettings` - Settings for the normal user
- `systemSettings` - Settings for the system
- `inputs` - Flake inputs
- `pkgs-stable` - Stable versions of packages

**Related Documentation**: See [system/README.md](../../system/README.md) for directory-level documentation.
