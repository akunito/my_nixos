---
id: docs.proxmox-lxc
summary: Guide to managing Proxmox LXC containers using a Base + Override pattern. Explains how to create and install new container profiles while keeping configuration DRY.
tags: [proxmox, lxc, virtualization, profiles, modularity, dry]
related_files:
  - profiles/LXC-base-config.nix
  - profiles/proxmox-lxc/**
  - flake.LXC.nix
---

# Proxmox LXC Profiles

This repository supports a modular configuration for NixOS LXC containers on Proxmox. It uses a **Base + Override** pattern to keep configurations DRY while allowing multiple containers to have different hostnames and specific settings.

## Prerequisites

- Proxmox LXC container created with `nesting=1` (required for Docker).
- NixOS installed in the LXC container (e.g., using the NixOS LXC template).

## Architecture

1. **[LXC-base-config.nix](file:///home/akunito/.dotfiles/profiles/LXC-base-config.nix)**: Contains all common settings:
   - Shared system packages (CLI tools, Docker, etc.).
   - Network settings (same DNS, firewall ports 3000/3001).
   - User settings (`akunito`, SSH keys, Zsh config).
   - NFS client mounts.
2. **Profile-specific Override**: A small `.nix` file in `profiles/` that imports the base and overrides specific fields (usually `hostname`).
3. **Flake Entry Point**: A `flake.<PROFILE>.nix` file in the root directory that points to the override file.

## Usage

### 1. Installation

To install a container using the default `LXC` profile:

```bash
cd ~/.dotfiles
./install.sh . LXC -s -u
```

### 2. Creating a New Container Profile

If you want a container named `myserver`:

1.  **Create the configuration override**:
    Create `profiles/myserver-config.nix`:
    ```nix
    let
      base = import ./LXC-base-config.nix;
    in
    {
      systemSettings = base.systemSettings // {
        hostname = "myserver";
        installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles myserver -s -u";
        systemStateVersion = "25.11";
      };
      userSettings = base.userSettings // {
        homeStateVersion = "25.11";
      };
    }
    ```

2.  **Create the flake entry point**:
    Create `flake.myserver.nix`:
    ```nix
    {
      description = "Flake for myserver LXC";
      outputs = inputs@{ self, ... }:
        let
          base = import ./lib/flake-base.nix;
          profileConfig = import ./profiles/myserver-config.nix;
        in
          base { inherit inputs self profileConfig; };

      inputs = {
        nixpkgs.url = "nixpkgs/nixos-unstable";
        nixpkgs-stable.url = "nixpkgs/nixos-25.11";
        home-manager-unstable.url = "github:nix-community/home-manager/master";
        home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs";
        home-manager-stable.url = "github:nix-community/home-manager/release-25.11";
        home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";
        blocklist-hosts = {
          url = "github:StevenBlack/hosts";
          flake = false;
        };
      };
    }
    ```

3.  **Run the installation**:
    ```bash
    ./install.sh . myserver -s -u
    ```

## Specific Configurations

- **GPU**: `gpuType` is set to `"none"`. This ensures standard monitoring tools (like `btop`) are installed without AMD/Intel specific drivers that are not needed in LXC.
- **Modularity**: The profile logic lives in `profiles/proxmox-lxc/`, which includes:
  - `base.nix`: Core system configuration (LXC virtualization module, common services).
  - `configuration.nix`: Top-level system entry point.
  - `home.nix`: User-level Home-Manager configuration.
