---
author: Akunito
title: NixOS Configuration Repository
description: Modular, hierarchical NixOS configuration with centralized software management
---

# NixOS Configuration Repository

A **modular, hierarchical** NixOS configuration system with **centralized software management** and profile inheritance. Built on Nix flakes for reproducible, declarative system configuration across desktops, laptops, servers, and containers.

## 📐 Architecture Overview

### Configuration Hierarchy & Inheritance

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        lib/defaults.nix                                   │
│                   (Global defaults & feature flags)                       │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
         ▼                       ▼                       ▼
    ┌─────────┐           ┌──────────┐          ┌──────────┐
    │Personal │           │ Homelab  │          │   LXC    │
    │ Profile │           │ Profile  │          │  Base    │
    └────┬────┘           └─────┬────┘          └────┬─────┘
         │                      │                    │
         │                      │                    │
         │                      │                    │
         ▼                      ▼                    ▼
    ┌────────────┐         ┌────────┐     ┌────────────────────┐
    │   DESK     │         │VMHOME  │     │ LXC_HOME           │
    │ (Desktop)  │         │(Server)│     │ LXC_plane          │
    └──────┬─────┘         └────────┘     │ LXC_portfolioprod  │
           │                              │ LXC_mailer         │
           │                              │ LXC_liftcraftTEST  │
           │                              │ LXC_monitoring     │
           │                              │ LXC_proxy          │
           │                              └────────────────────┘
           │
    ┌──────┴───────────────┬──────────────┐
    │                      │              │
    ▼                      ▼              ▼
┌────────┐          ┌──────────┐    ┌──────────┐
│DESK_AGA│          │DESK_VMDESK│   │  LAPTOP  │
│ (Desk) │          │   (VM)    │   │   Base   │
└────────┘          └──────────┘    └─────┬────┘
                                         │
                                         ├─────────────┬─────────────┐
                                         ▼             ▼             ▼
                                     ┌────────┐  ┌────────────┐  ┌─────────┐
                                     │LAPTOP  │  │  LAPTOP    │  │LAPTOP   │
                                     │  L15   │  │  YOGAAKU   │  │  AGA    │
                                     └────────┘  └────────────┘  └─────────┘

Legend:
  └──► Inherits from
  │    Profile hierarchy
  ┌──┐ Specific machine configuration
```

### Centralized Software Management

```
┌────────────────────────────────────────────────────────────────┐
│              Profile Configuration File                         │
│              (e.g., DESK-config.nix)                           │
├────────────────────────────────────────────────────────────────┤
│  systemSettings = {                                            │
│    hostname = "nixosaku";                                      │
│    systemPackages = [...];  # Profile-specific only            │
│                                                                 │
│    ╔════════════════════════════════════════════════════╗      │
│    ║ SOFTWARE & FEATURE FLAGS - Centralized Control    ║      │
│    ╠════════════════════════════════════════════════════╣      │
│    ║ # Package Modules                                  ║      │
│    ║ systemBasicToolsEnable = true;                     ║      │
│    ║ systemNetworkToolsEnable = true;                   ║      │
│    ║                                                     ║      │
│    ║ # Desktop & Theming                                ║      │
│    ║ enableSwayForDESK = true;                          ║      │
│    ║ stylixEnable = true;                               ║      │
│    ║                                                     ║      │
│    ║ # System Services                                  ║      │
│    ║ sambaEnable = true;                                ║      │
│    ║ sunshineEnable = true;                             ║      │
│    ║ wireguardEnable = true;                            ║      │
│    ║                                                     ║      │
│    ║ # Development & AI                                 ║      │
│    ║ developmentToolsEnable = true;                     ║      │
│    ║ aichatEnable = true;                               ║      │
│    ╚════════════════════════════════════════════════════╝      │
│  };                                                             │
│                                                                 │
│  userSettings = {                                              │
│    homePackages = [...];  # Profile-specific only              │
│                                                                 │
│    ╔════════════════════════════════════════════════════╗      │
│    ║ SOFTWARE & FEATURE FLAGS (USER) - Centralized      ║      │
│    ╠════════════════════════════════════════════════════╣      │
│    ║ # Package Modules (User)                           ║      │
│    ║ userBasicPkgsEnable = true;                        ║      │
│    ║ userAiPkgsEnable = true;   # DESK only             ║      │
│    ║                                                     ║      │
│    ║ # Gaming & Entertainment                           ║      │
│    ║ protongamesEnable = true;                          ║      │
│    ║ starcitizenEnable = true;                          ║      │
│    ║ steamPackEnable = true;                            ║      │
│    ╚════════════════════════════════════════════════════╝      │
│  };                                                             │
└────────────────────────────────────────────────────────────────┘
```

## 🎯 Core Principles

### 1. Hierarchical Configuration
- **Base profiles** define common settings (DESK as desktop base, LAPTOP-base.nix for laptop-specific, LXC-base-config.nix for containers)
- **Specific profiles** inherit and override only what's unique
- **Global defaults** in `lib/defaults.nix` provide sensible starting points
- **LAPTOP Base inherits from DESK** - laptops get desktop features + laptop-specific settings (TLP, battery, etc.)

### 2. Centralized Software Control
All software is controlled through **centralized flag sections**:
- Grouped by topic (Package Modules, Desktop, Services, Development, Gaming)
- Single source of truth per profile
- Easy to see exactly what's enabled at a glance

### 3. Modular Package System
Software organized into **4 core package modules**:

| Module | Flag | Contents |
|--------|------|----------|
| `system/packages/system-basic-tools.nix` | `systemBasicToolsEnable` | vim, wget, zsh, rsync, cryptsetup, etc. |
| `system/packages/system-network-tools.nix` | `systemNetworkToolsEnable` | nmap, traceroute, dnsutils, etc. |
| `user/packages/user-basic-pkgs.nix` | `userBasicPkgsEnable` | Browsers, office, communication apps |
| `user/packages/user-ai-pkgs.nix` | `userAiPkgsEnable` | lmstudio, ollama-rocm |

### 4. Profile Types

#### Personal Profiles
Full-featured desktop/laptop configurations with GUI applications:
- **DESK** - Primary desktop (AMD GPU, gaming, development, AI)
  - **DESK_AGA** - Secondary desktop (inherits from DESK, simplified - no development/AI, limited gaming)
  - **DESK_VMDESK** - VM desktop (inherits from DESK, development enabled, no gaming/AI, Sway + Plasma6)
  - **LAPTOP Base** - Laptop common settings (inherits from DESK + adds TLP, battery management, laptop-specific features)
    - **LAPTOP_L15** - Intel laptop with development tools
    - **LAPTOP_YOGAAKU** - Older laptop, reduced features
    - **LAPTOP_AGA** - Minimal laptop with basic tools

#### Server Profiles
Headless server configurations:
- **VMHOME** - Homelab server (Docker, NFS, no GUI)

#### Container Profiles
LXC containers for Proxmox with centralized deployment:
- **LXC-base-config.nix** - Common container settings (passwordless sudo, Docker, SSH)
- **LXC_HOME**, **LXC_plane**, **LXC_portfolioprod**, **LXC_mailer**, **LXC_liftcraftTEST** - Production services
- **Centralized deployment** via `deploy-lxc.sh` interactive script

#### Specialized Profiles
- **WSL** - Windows Subsystem for Linux minimal setup
- **Work** - Work-focused configuration (no games/personal tools)

## 🚀 Quick Start

### Installation

```bash
# Clone repository
git clone https://github.com/akunito/nixos-config.git ~/.dotfiles
cd ~/.dotfiles

# Interactive installation
./install.sh ~/.dotfiles PROFILE

# Silent installation
./install.sh ~/.dotfiles PROFILE -s

# With user sync
./install.sh ~/.dotfiles PROFILE -s -u
```

**Available Profiles:**
- `DESK` - Primary desktop
- `LAPTOP_L15` - Intel laptop
- `LAPTOP_YOGAAKU` - Older laptop
- `AGA` - Minimal laptop
- `AGADESK` - Secondary desktop
- `VMHOME` - Homelab server
- `VMDESK` - VM desktop
- `WSL` - Windows Subsystem for Linux
- `LXC_HOME`, `LXC_plane`, `LXC_portfolioprod`, `LXC_mailer`, `LXC_liftcraftTEST`, `LXC_monitoring`, `LXC_proxy` - LXC containers

### Daily Usage

```bash
# Synchronize system and user
aku sync

# Update flake inputs
aku update

# Update and synchronize
aku upgrade

# Garbage collect
aku gc        # Interactive selection
aku gc 30d    # Delete >30 days old
aku gc full   # Delete everything unused
```

### LXC Container Deployment

Deploy NixOS configurations to multiple Proxmox LXC containers from a single command:

```bash
# Interactive menu - select containers with arrow keys
./deploy-lxc.sh

# Deploy to all containers at once
./deploy-lxc.sh --all

# Deploy to specific containers
./deploy-lxc.sh --profile LXC_HOME --profile LXC_plane
```

**Interactive Controls:**
- `↑/↓` Navigate servers
- `Space` Toggle selection
- `Enter` Deploy to selected
- `a` Select all | `n` Deselect all | `q` Quit

The script automatically syncs each container with the main branch and runs the install script with passwordless sudo. See [docs/lxc-deployment.md](docs/lxc-deployment.md) for full documentation.

## 📋 Configuration Examples

### Example 1: Creating a New Desktop Profile

```nix
# profiles/MYDESK-config.nix
{
  systemSettings = {
    hostname = "mydesk";
    profile = "personal";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles MYDESK -s -u";
    gpuType = "nvidia";

    systemPackages = pkgs: pkgs-unstable: [
      # Add profile-specific packages here
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Package Modules ===
    systemBasicToolsEnable = true;
    systemNetworkToolsEnable = true;

    # === Desktop Environment & Theming ===
    stylixEnable = true;

    # === System Services & Features ===
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = true;

    # === Development Tools & AI ===
    developmentToolsEnable = true;
  };

  userSettings = {
    username = "myuser";
    theme = "ashes";
    wm = "plasma6";

    homePackages = pkgs: pkgs-unstable: [
      # Add user-specific packages here
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
    # ============================================================================

    # === Package Modules (User) ===
    userBasicPkgsEnable = true;
    userAiPkgsEnable = false;

    # === Gaming & Entertainment ===
    protongamesEnable = false;
    steamPackEnable = false;
  };
}
```

### Example 2: Creating a Laptop Profile with Base Inheritance

```nix
# profiles/MYLAPTOP-config.nix
let
  base = import ./LAPTOP-base.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "mylaptop";
    profile = "personal";
    gpuType = "intel";

    systemPackages = pkgs: pkgs-unstable: [
      pkgs.tldr  # Add laptop-specific tool
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================
    systemBasicToolsEnable = true;
    systemNetworkToolsEnable = true;
    sunshineEnable = false;  # Disable on laptop
    developmentToolsEnable = true;
  };

  userSettings = base.userSettings // {
    username = "myuser";

    homePackages = pkgs: pkgs-unstable: [
      pkgs.kdePackages.dolphin
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
    # ============================================================================
    userBasicPkgsEnable = true;
    userAiPkgsEnable = false;  # No AI on laptop
  };
}
```

### Example 3: Creating an LXC Container Profile

```nix
# profiles/LXC_myservice-config.nix
let
  base = import ./LXC-base-config.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "lxc-myservice";
    ipAddress = "192.168.1.100";

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================
    systemBasicToolsEnable = true;
    systemNetworkToolsEnable = false;  # Minimal container
    # All services disabled
  };

  userSettings = base.userSettings // {
    # Inherit all user settings from base
  };
}
```

## 🔧 Software Management

### How It Works

1. **Package modules** contain grouped software (basic tools, networking, user apps, AI)
2. **Feature flags** enable/disable entire modules
3. **Centralized sections** in profile configs control all software
4. **Profile-specific packages** added to systemPackages/homePackages lists

### Enabling/Disabling Software

Edit your profile config file (e.g., `profiles/DESK-config.nix`):

```nix
# In systemSettings section:
# ============================================================================
# SOFTWARE & FEATURE FLAGS - Centralized Control
# ============================================================================

# Enable/disable package modules
systemBasicToolsEnable = true;      # Keep basic tools
systemNetworkToolsEnable = false;   # Disable networking tools

# Enable/disable system services
sambaEnable = true;                 # Enable Samba
sunshineEnable = false;             # Disable game streaming

# In userSettings section:
# ============================================================================
# SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
# ============================================================================

userBasicPkgsEnable = true;         # Keep user apps
userAiPkgsEnable = false;           # Disable AI packages

protongamesEnable = false;          # Disable gaming
```

### Adding Custom Packages

```nix
# In profile config
systemSettings = {
  systemPackages = pkgs: pkgs-unstable: [
    # Profile-specific system packages
    pkgs.my-custom-tool
  ];
};

userSettings = {
  homePackages = pkgs: pkgs-unstable: [
    # Profile-specific user packages
    pkgs-unstable.my-custom-app
  ];
};
```

## 📚 Documentation

### Quick Navigation

- **Installation Guide**: [docs/installation.md](docs/installation.md)
- **Profile Details**: [docs/profiles.md](docs/profiles.md)
- **System Modules**: [docs/system-modules.md](docs/system-modules.md)
- **User Modules**: [docs/user-modules.md](docs/user-modules.md)
- **Scripts Reference**: [docs/scripts.md](docs/scripts.md)
- **Keybindings**: [docs/keybindings.md](docs/keybindings.md)

### Documentation System

This repository uses a **Router + Catalog** system:

- **Router (quick lookup)**: [`docs/00_ROUTER.md`](docs/00_ROUTER.md) - Find topics fast
- **Catalog (browse all)**: [`docs/01_CATALOG.md`](docs/01_CATALOG.md) - Complete listing
- **Navigation guide**: [`docs/navigation.md`](docs/navigation.md) - **Start here**

## 🏗️ Project Structure

```
.dotfiles/
├── flake.nix                 # Main flake (imports specific profile flakes)
├── flake.*.nix               # Profile-specific flakes (DESK, LAPTOP_L15, etc.)
├── lib/
│   └── defaults.nix          # Global defaults and feature flags
├── profiles/
│   ├── personal/             # Personal profile templates
│   │   ├── configuration.nix # System config (imports work/configuration.nix)
│   │   └── home.nix          # User config (imports work/home.nix)
│   ├── work/                 # Work profile templates
│   ├── homelab/              # Server profile templates
│   ├── DESK-config.nix       # Desktop configuration
│   ├── LAPTOP-base.nix       # Laptop base (inherited by L15, YOGAAKU)
│   ├── LAPTOP_L15-config.nix # Specific laptop config
│   ├── LXC-base-config.nix   # LXC container base
│   └── ...
├── system/
│   ├── app/                  # System-level applications
│   ├── hardware/             # Hardware configuration
│   ├── packages/             # Package modules
│   │   ├── system-basic-tools.nix
│   │   └── system-network-tools.nix
│   ├── security/             # Security modules
│   └── wm/                   # Window manager system config
├── user/
│   ├── app/                  # User applications
│   │   ├── development/      # Development tools
│   │   └── games/            # Gaming applications
│   ├── packages/             # User package modules
│   │   ├── user-basic-pkgs.nix
│   │   └── user-ai-pkgs.nix
│   ├── shell/                # Shell configurations
│   ├── wm/                   # Window manager user config
│   └── style/                # Theming and styling
├── themes/                   # 55+ base16 themes
├── docs/                     # Comprehensive documentation
└── scripts/                  # Utility scripts
```

## ✨ Features

### Desktop Environments
- **Plasma 6** - KDE Plasma with Wayland
- **SwayFX** - Wayland compositor with effects
- **Hyprland** - Dynamic tiling Wayland compositor
- **Stylix** - System-wide theming with 55+ base16 themes

### System Features
- **Automated Maintenance** - Generation cleanup, Docker container handling
- **Remote LUKS Unlock** - SSH server on boot for encrypted drives
- **NFS Client/Server** - Network file system support
- **QEMU/KVM Virtualization** - Full VM support with bridged networking
- **Automated Backups** - Restic-based with SystemD timers
- **Power Management** - Profile-specific TLP configurations
- **LXC Centralized Deployment** - Deploy to multiple containers with one command

### Development Tools
- **NixVim** - Neovim configured like Cursor IDE
- **Multiple IDEs** - VSCode, Cursor, Windsurf
- **AI Tools** - LM Studio, Ollama, aichat CLI
- **Cloud Tools** - Azure CLI, Cloudflare Tunnel
- **Languages** - Rust, Python, Go, Node.js

### Gaming Support
- **Steam** - Native Steam client
- **Proton** - Lutris, Bottles, Heroic launcher
- **Emulators** - Dolphin (Primehack), RPCS3
- **Star Citizen** - Kernel optimizations

## 🛠️ Maintenance

### Common Tasks

```bash
# Update system
aku upgrade

# Clean old generations
aku gc 30d

# Refresh themes and daemons
aku refresh

# Pull upstream changes
aku pull
```

### Troubleshooting

**Build fails:**
- Check `flake.lock` is up to date: `aku update`
- Verify profile config syntax: `nix flake check`

**Software not appearing:**
- Check flag is enabled in profile config
- Verify module imported in personal/configuration.nix or personal/home.nix
- Rebuild: `aku sync`

**Theme not applying:**
- Run: `aku refresh`
- Check `stylixEnable = true` in profile config

## 🔐 Security Notes

- **SSH Keys**: Change default SSH keys in profile configs before deploying servers
- **LUKS Encryption**: See [docs/security/luks-encryption.md](docs/security/luks-encryption.md)
- **Backups**: Configure Restic in profile config, see [docs/security/restic-backups.md](docs/security/restic-backups.md)

## 📄 License

This configuration is provided as-is for personal use. Based on [Librephoenix's dotfiles](https://github.com/librephoenix/nixos-config).

## 🙏 Credits

Forked from [Librephoenix's NixOS configuration](https://github.com/librephoenix/nixos-config), significantly enhanced with:
- Hierarchical profile inheritance system
- Centralized software management
- Modular package organization
- Extensive documentation
- Multiple machine type support (desktops, laptops, servers, containers)

---

## Additional Resources

### Detailed Documentation
- **[Configuration Guide](docs/configuration.md)** - Flake management and variables
- **[Maintenance Guide](docs/maintenance.md)** - System maintenance and automation
- **[Security Guide](docs/security.md)** - SSH, encryption, backups
- **[Hardware Guide](docs/hardware.md)** - Drives, GPU, power management
- **[Themes Guide](docs/themes.md)** - Theme system and customization
- **[Patches Guide](docs/patches.md)** - Nixpkgs patches

### Specific Topics
- **[LXC Deployment](docs/lxc-deployment.md)** - Centralized container deployment
- **[LUKS Encryption](docs/security/luks-encryption.md)** - Encrypted drives with remote unlock
- **[Restic Backups](docs/security/restic-backups.md)** - Automated backup configuration
- **[CPU Power Management](docs/hardware/cpu-power-management.md)** - Governors and performance
- **[Sway Keybindings](docs/keybindings/sway.md)** - Complete SwayFX keybinding reference
- **[Plasma 6 Setup](docs/user-modules/plasma6.md)** - KDE configuration
- **[Gaming Setup](docs/user-modules/gaming.md)** - Gaming platform configuration

### External Resources
- **[NixOS Manual](https://nixos.org/manual/nixos/stable/)** - Official NixOS documentation
- **[Home Manager Manual](https://nix-community.github.io/home-manager/)** - User environment management
- **[Nix Pills](https://nixos.org/guides/nix-pills/)** - Deep dive into Nix
- **[NixOS Wiki](https://nixos.wiki)** - Community documentation
