---
author: Akunito
title: NixOS Configuration Repository
description: Modular, hierarchical NixOS configuration with centralized software management
---

# NixOS Configuration Repository

A **modular, hierarchical** NixOS configuration system with **centralized software management** and profile inheritance. Built on Nix flakes for reproducible, declarative system configuration across desktops, laptops, VPS, containers, and macOS.

## Architecture Overview

### Infrastructure (Post-Migration Feb 2026)

```
                          ┌─────────────────────────────────────┐
                          │          Cloudflare Tunnel           │
                          │  *.akunito.com → VPS localhost       │
                          └──────────────┬──────────────────────┘
                                         │
     ┌───────────────────────────────────┼───────────────────────────────┐
     │                                   │                               │
     ▼                                   ▼                               ▼
┌─────────────┐                 ┌────────────────┐              ┌──────────────┐
│  VPS_PROD   │                 │   TrueNAS      │              │   pfSense    │
│  (Netcup)   │◄──Tailscale──► │  192.168.20.200 │              │ 192.168.8.1  │
│ 100.64.0.6  │   + WireGuard  │  VLAN 100       │              │  Router/FW   │
├─────────────┤                 ├────────────────┤              ├──────────────┤
│ Headscale   │                 │ Media Stack    │              │ DNS Resolver │
│ PostgreSQL  │   Restic/SFTP   │ (Sonarr, etc.) │              │ WireGuard    │
│ Grafana     │ ──────────────► │ NPM Proxy      │              │ Tailscale    │
│ Prometheus  │    Backups      │ Cloudflared    │              │ DHCP/NAT     │
│ Docker x15  │                 │ Monitoring     │              │ Firewall     │
│ Postfix     │                 │ Docker x19     │              └──────────────┘
│ Cloudflared │                 └────────────────┘
│ LUKS Encrypt│
└─────────────┘
     ▲
     │ Tailscale Mesh
     ▼
┌──────────────────────────────────────────────────┐
│  Client Devices: DESK, LAPTOP_X13, LAPTOP_YOGA,  │
│  LAPTOP_A, Phone, MACBOOK-KOMI                    │
└──────────────────────────────────────────────────┘
```

### Configuration Hierarchy & Inheritance

```
┌──────────────────────────────────────────────────────────────────────┐
│                        lib/defaults.nix                              │
│                   (Global defaults & feature flags)                  │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
       ┌───────────────┬───────┼────────┬────────────────┬─────────────┐
       │               │       │        │                │             │
       ▼               ▼       ▼        ▼                ▼             ▼
  ┌─────────┐   ┌──────────┐ ┌────┐ ┌────────┐  ┌───────────┐  ┌──────────┐
  │Personal │   │ Homelab  │ │VPS │ │ KOMI   │  │  Darwin   │  │   WSL    │
  │ Profile │   │ Profile  │ │Base│ │LXC Base│  │  (macOS)  │  │(Standalone)│
  └────┬────┘   └────┬─────┘ └──┬─┘ └───┬────┘  └─────┬─────┘  └──────────┘
       │              │          │       │              │
       ▼              ▼          ▼       ▼              ▼
  ┌────────┐    ┌────────┐  ┌────────┐ ┌──────────┐ ┌───────────┐
  │  DESK  │    │VMHOME  │  │VPS_PROD│ │KOMI_LXC_ │ │MACBOOK-   │
  │(Desktop)│   │(Server)│  │(Netcup)│ │database  │ │  KOMI     │
  └───┬────┘    └────────┘  └────────┘ │mailer    │ └───────────┘
      │                                 │monitoring│
      ├──────────┬──────────┐           │proxy     │
      ▼          ▼          ▼           │tailscale │
  ┌──────┐ ┌─────────┐ ┌────────┐      └──────────┘
  │DESK_A│ │DESK_    │ │ LAPTOP │
  │      │ │ VMDESK  │ │  Base  │
  └──────┘ └─────────┘ └───┬────┘
                            │
                ┌───────────┼───────────┐
                ▼           ▼           ▼
           ┌────────┐ ┌────────┐ ┌─────────┐
           │LAPTOP  │ │LAPTOP  │ │ LAPTOP  │
           │  X13   │ │  YOGA  │ │    A    │
           └────────┘ └────────┘ └─────────┘

Legend:
  └──> Inherits from
  │    Profile hierarchy
  ┌──┐ Specific machine configuration
```

### Centralized Software Management

```
┌────────────────────────────────────────────────────────────────┐
│              Profile Configuration File                        │
│              (e.g., DESK-config.nix)                           │
├────────────────────────────────────────────────────────────────┤
│  systemSettings = {                                            │
│    hostname = "nixosaku";                                      │
│    systemPackages = [...];  # Profile-specific only            │
│                                                                │
│    ╔════════════════════════════════════════════════════╗      │
│    ║ SOFTWARE & FEATURE FLAGS - Centralized Control    ║      │
│    ╠════════════════════════════════════════════════════╣      │
│    ║ # Package Modules                                 ║      │
│    ║ systemBasicToolsEnable = true;                    ║      │
│    ║ systemNetworkToolsEnable = true;                  ║      │
│    ║                                                   ║      │
│    ║ # Desktop & Theming                               ║      │
│    ║ enableSwayForDESK = true;                         ║      │
│    ║ stylixEnable = true;                              ║      │
│    ║                                                   ║      │
│    ║ # System Services                                 ║      │
│    ║ sambaEnable = true;                               ║      │
│    ║ sunshineEnable = true;                            ║      │
│    ║ wireguardEnable = true;                           ║      │
│    ║                                                   ║      │
│    ║ # Development & AI                                ║      │
│    ║ developmentToolsEnable = true;                    ║      │
│    ║ aichatEnable = true;                              ║      │
│    ╚════════════════════════════════════════════════════╝      │
│  };                                                            │
│                                                                │
│  userSettings = {                                              │
│    homePackages = [...];  # Profile-specific only              │
│                                                                │
│    ╔════════════════════════════════════════════════════╗      │
│    ║ SOFTWARE & FEATURE FLAGS (USER) - Centralized     ║      │
│    ╠════════════════════════════════════════════════════╣      │
│    ║ # Package Modules (User)                          ║      │
│    ║ userBasicPkgsEnable = true;                       ║      │
│    ║ userAiPkgsEnable = true;   # DESK only            ║      │
│    ║                                                   ║      │
│    ║ # Gaming & Entertainment                          ║      │
│    ║ protongamesEnable = true;                         ║      │
│    ║ starcitizenEnable = true;                         ║      │
│    ║ steamPackEnable = true;                           ║      │
│    ╚════════════════════════════════════════════════════╝      │
│  };                                                            │
└────────────────────────────────────────────────────────────────┘
```

## Core Principles

### 1. Hierarchical Configuration
- **Base profiles** define common settings (DESK for desktops, LAPTOP-base.nix for laptops, VPS-base-config.nix for VPS, KOMI_LXC-base-config.nix for Komi containers)
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
  - **DESK_A** - Secondary desktop (inherits from DESK, simplified)
  - **DESK_VMDESK** - VM desktop (inherits from DESK, development enabled)
  - **LAPTOP Base** - Laptop common settings (inherits from DESK + adds TLP, battery management)
    - **LAPTOP_X13** - AMD laptop with development tools
    - **LAPTOP_YOGA** - Older laptop, reduced features
    - **LAPTOP_A** - Minimal laptop with basic tools

#### Server Profiles
Headless server configurations:
- **VMHOME** - Homelab server (Docker, NFS, no GUI)

#### VPS Profile
Production VPS with full-stack services:
- **VPS_PROD** - Netcup RS 4000 G12 (Docker, PostgreSQL, Grafana, Prometheus, Headscale, Cloudflared, LUKS encryption, WireGuard)
  - Inherits from **VPS-base-config.nix**

#### Komi Container Profiles
LXC containers on Komi's Proxmox (192.168.1.x):
- **KOMI_LXC-base-config.nix** - Common container settings (passwordless sudo, Docker, SSH)
- **KOMI_LXC_database**, **KOMI_LXC_mailer**, **KOMI_LXC_monitoring**, **KOMI_LXC_proxy**, **KOMI_LXC_tailscale**

#### macOS / Darwin Profile
- **MACBOOK-KOMI** - macOS with nix-darwin, Homebrew casks, Hammerspoon

#### Specialized Profiles
- **WSL** - Windows Subsystem for Linux minimal setup
- **Work** - Work-focused configuration (no games/personal tools)

## Quick Start

### Installation

```bash
# Clone repository
git clone https://github.com/akunito/nixos-config.git ~/.dotfiles
cd ~/.dotfiles

# Interactive installation
./install.sh ~/.dotfiles PROFILE

# Silent installation with user sync
./install.sh ~/.dotfiles PROFILE -s -u
```

**Available Profiles** (defined in unified `flake.nix`):
- `DESK` - Primary desktop (AMD GPU, gaming, development, AI)
- `DESK_A` - Secondary desktop
- `DESK_VMDESK` - VM desktop
- `LAPTOP_X13` - AMD laptop
- `LAPTOP_A` - Minimal laptop
- `LAPTOP_YOGA` - Older laptop
- `VMHOME` - Homelab server
- `VPS_PROD` - Production VPS (Netcup)
- `WSL` - Windows Subsystem for Linux
- `KOMI_LXC_database`, `KOMI_LXC_mailer`, `KOMI_LXC_monitoring`, `KOMI_LXC_proxy`, `KOMI_LXC_tailscale` - Komi LXC containers
- `MACBOOK-KOMI` - macOS (nix-darwin)

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

### Remote Deployment

Deploy NixOS configurations to remote machines using `deploy.sh` or manual SSH:

```bash
# TUI-based deployment manager (from local machine)
./deploy.sh --profile VPS_PROD

# Manual VPS deployment (passwordless sudo via SSH agent)
ssh -A -p 56777 akunito@<VPS-IP> \
  "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && \
   ./install.sh ~/.dotfiles VPS_PROD -s -u -d"

# Komi LXC deployment (passwordless sudo)
ssh -A admin@<LXC-IP> \
  "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && \
   ./install.sh ~/.dotfiles KOMI_LXC_database -s -u -d -h"

# Physical machines (requires sudo password — run on target)
cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && \
  ./install.sh ~/.dotfiles LAPTOP_X13 -s -u
```

**Key flags:**
- `-s` Silent mode (no prompts)
- `-u` Include user/Home Manager sync
- `-d` Skip Docker handling (keeps containers running)
- `-h` Skip hardware-config regeneration (LXC only)

## Configuration Examples

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

### Example 3: Creating a VPS Profile

```nix
# profiles/MYVPS-config.nix
let
  base = import ./VPS-base-config.nix;
  secrets = import ../secrets/domains.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "myvps";
    envProfile = "MYVPS";

    systemPackages = pkgs: pkgs-unstable: [
      pkgs.postgresql_17
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================
    systemBasicToolsEnable = true;
    systemNetworkToolsEnable = true;
    wireguardEnable = true;
    tailscaleEnable = true;

    # === Database & Services ===
    postgresqlServerEnable = true;
    grafanaEnable = true;
  };

  userSettings = base.userSettings // {
    # Server profiles: minimal user settings
    userBasicPkgsEnable = false;
    userAiPkgsEnable = false;
  };
}
```

## Software Management

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

## Features

### Desktop Environments
- **Plasma 6** - KDE Plasma with Wayland
- **SwayFX** - Wayland compositor with effects
- **Hyprland** - Dynamic tiling Wayland compositor
- **Stylix** - System-wide theming with 55+ base16 themes

### System Features
- **Rootless Docker** - Declarative Docker Compose stacks managed via NixOS
- **Remote LUKS Unlock** - SSH server in initrd for encrypted drives (VPS)
- **Tailscale Mesh VPN** - Self-hosted Headscale control server on VPS
- **WireGuard VPN** - Site-to-site tunnel between home and VPS
- **Declarative Monitoring** - Grafana + Prometheus with alerting
- **Automated Backups** - Restic-based with systemd timers (VPS to TrueNAS via SFTP)
- **Cloudflare Tunnel** - Zero-trust access to services via `*.akunito.com`
- **NFS Client/Server** - Network file system support
- **QEMU/KVM Virtualization** - Full VM support with bridged networking
- **Power Management** - Profile-specific TLP configurations

### Development Tools
- **NixVim** - Neovim configured like Cursor IDE
- **Multiple IDEs** - VSCode, Cursor, Windsurf
- **AI Tools** - LM Studio, Ollama, aichat CLI
- **Cloud Tools** - Azure CLI, Cloudflare Tunnel
- **Languages** - Rust, Python, Go, Node.js

### Gaming Support
- **Steam** - Native Steam client
- **Proton** - Lutris, Bottles, Heroic launcher
- **Emulators** - Dolphin (Primehack), RPCS3, RomM
- **Star Citizen** - Kernel optimizations

## Documentation

### Quick Navigation

- **Installation Guide**: [docs/installation.md](docs/installation.md)
- **Profile Details**: [docs/profiles.md](docs/profiles.md)
- **Infrastructure Overview**: [docs/akunito/infrastructure/INFRASTRUCTURE.md](docs/akunito/infrastructure/INFRASTRUCTURE.md)
- **Keybindings**: [docs/akunito/keybindings.md](docs/akunito/keybindings.md)

### Documentation System

This repository uses a **Router + Catalog** system:

- **Router (quick lookup)**: [`docs/00_ROUTER.md`](docs/00_ROUTER.md) - Find topics fast
- **Catalog (browse all)**: [`docs/01_CATALOG.md`](docs/01_CATALOG.md) - Complete listing
- **Navigation guide**: [`docs/navigation.md`](docs/navigation.md) - Start here

## Project Structure

```
.dotfiles/
├── flake.nix                 # Unified flake with all profiles and inputs
├── flake.lock                # Locked dependency versions (shared by all profiles)
├── .active-profile           # Per-machine active profile name (gitignored)
├── lib/
│   ├── defaults.nix          # Global defaults and feature flags
│   ├── flake-unified.nix     # Generates configurations for all profiles
│   └── flake-base.nix        # Profile builder (per-profile output generation)
├── profiles/
│   ├── personal/             # Personal profile templates
│   ├── work/                 # Work profile templates
│   ├── homelab/              # Server profile templates
│   ├── darwin/               # macOS/nix-darwin templates
│   ├── DESK-config.nix       # Desktop configuration
│   ├── LAPTOP-base.nix       # Laptop base (inherited by X13, YOGA, A)
│   ├── VPS-base-config.nix   # VPS base (inherited by VPS_PROD)
│   ├── VPS_PROD-config.nix   # Production VPS configuration
│   ├── KOMI_LXC-base-config.nix  # Komi LXC container base
│   └── ...
├── system/
│   ├── app/                  # System-level applications
│   ├── hardware/             # Hardware configuration
│   ├── packages/             # Package modules
│   ├── security/             # Security modules
│   └── wm/                   # Window manager system config
├── user/
│   ├── app/                  # User applications
│   ├── packages/             # User package modules
│   ├── shell/                # Shell configurations
│   ├── wm/                   # Window manager user config
│   └── style/                # Theming and styling
├── themes/                   # 55+ base16 themes
├── docs/                     # Comprehensive documentation
├── secrets/                  # Encrypted secrets (git-crypt)
└── scripts/                  # Utility scripts
```

## Maintenance

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

## Security Notes

- **SSH Keys**: Change default SSH keys in profile configs before deploying servers
- **Secrets**: Managed via git-crypt; see [docs/akunito/security.md](docs/akunito/security.md)
- **LUKS Encryption**: See [docs/security/luks-encryption.md](docs/security/luks-encryption.md)
- **Backups**: Configure Restic in profile config, see [docs/security/restic-backups.md](docs/security/restic-backups.md)

## License

This configuration is provided as-is for personal use. Based on [Librephoenix's dotfiles](https://github.com/librephoenix/nixos-config).

## Credits

Forked from [Librephoenix's NixOS configuration](https://github.com/librephoenix/nixos-config), significantly enhanced with:
- Hierarchical profile inheritance system
- Centralized software management
- Multi-architecture support (NixOS, nix-darwin, VPS, LXC)
- Full-stack VPS deployment (Docker, databases, monitoring, VPN)
- Comprehensive documentation with Router/Catalog system
