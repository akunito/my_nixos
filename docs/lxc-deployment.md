---
id: lxc-deployment
summary: Centralized deployment script for managing multiple LXC containers
tags: [lxc, deployment, automation, proxmox, containers]
related_files: [deploy-lxc.sh, profiles/LXC-base-config.nix]
---

# LXC Centralized Deployment

This repository includes a centralized deployment system for managing multiple Proxmox LXC containers running NixOS configurations.

## Overview

The `deploy-lxc.sh` script provides an interactive menu to deploy NixOS configurations to multiple LXC containers simultaneously. Combined with passwordless sudo configuration, this enables fully automated deployments.

## Quick Start

```bash
# Interactive mode - select containers with arrow keys
./deploy-lxc.sh

# Deploy to all containers
./deploy-lxc.sh --all

# Deploy to specific containers
./deploy-lxc.sh --profile LXC_HOME --profile LXC_plane
```

## Components

### 1. Deploy Script (`deploy-lxc.sh`)

Interactive deployment script with:
- Arrow key navigation and space to toggle selection
- Parallel-safe SSH connections with agent forwarding
- Git fetch + reset to sync with main branch
- Automatic install.sh execution with proper flags

**Features:**
- `[Space]` - Toggle server selection
- `[Enter]` - Deploy to selected servers
- `[a]` - Select all servers
- `[n]` - Deselect all servers
- `[q]` - Quit

**CLI Options:**
```bash
./deploy-lxc.sh --all              # Deploy to all without menu
./deploy-lxc.sh --profile NAME     # Deploy to specific profile(s)
./deploy-lxc.sh --help             # Show help
```

### 2. LXC Base Configuration (`profiles/LXC-base-config.nix`)

Common settings inherited by all LXC container profiles:
- Minimal system packages (no GUI)
- Docker support
- SSH key authentication
- Passwordless sudo for automated deployments

### 3. Passwordless Sudo

LXC containers are configured with fully passwordless sudo to enable automated deployments:

```nix
# In LXC-base-config.nix
systemSettings = {
  # Passwordless sudo for automated deployments
  sudoCommands = [
    { command = "ALL"; options = [ "NOPASSWD" "SETENV" ]; }
  ];

  # Make wheel group fully passwordless (needed for sudo -v)
  wheelNeedsPassword = false;
};
```

## Configured Servers

| Profile | IP | Description |
|---------|-----|-------------|
| LXC_HOME | 192.168.8.80 | Homelab services |
| LXC_plane | 192.168.8.86 | Production container |
| LXC_portfolioprod | 192.168.8.88 | Portfolio service |
| LXC_mailer | 192.168.8.89 | Mail & monitoring |
| LXC_liftcraftTEST | 192.168.8.87 | Test environment |

## Adding a New LXC Container

### 1. Create Profile Configuration

```nix
# profiles/LXC_myservice-config.nix
let
  base = import ./LXC-base-config.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "myservice-nixos";

    # Add service-specific packages
    systemPackages = pkgs: pkgs-unstable:
      (base.systemSettings.systemPackages pkgs pkgs-unstable) ++ [
        pkgs.my-service-package
      ];
  };

  userSettings = base.userSettings // {
    # Customize user settings if needed
  };
}
```

### 2. Create Flake File

```nix
# flake.LXC_myservice.nix
# Copy from an existing LXC flake and update the profile import
```

### 3. Add to Deploy Script

Edit `deploy-lxc.sh` and add to the SERVERS array:

```bash
SERVERS=(
  # ... existing servers ...
  "LXC_myservice:192.168.8.XX:My service description"
)
```

### 4. Initial Deployment

For the first deployment, you'll need to manually deploy with password:

```bash
ssh -A akunito@192.168.8.XX "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_myservice -s -u -q"
```

After this, the passwordless sudo config will be active and future deployments via `deploy-lxc.sh` will work without password prompts.

## Deployment Workflow

When you run the deploy script, for each selected server it:

1. **SSH Connection Check** - Verifies the server is reachable
2. **Git Fetch** - Fetches latest changes from origin
3. **Git Reset** - Hard resets to origin/main (discards local changes like flake.lock)
4. **Install Script** - Runs `./install.sh` with `-s -u -q` flags:
   - `-s` (silent) - Non-interactive mode
   - `-u` (update) - Update flake.lock
   - `-q` (quick) - Skip Docker handling and hardware-config generation

## SSH Agent Forwarding

The script uses `-A` flag for SSH to forward your local SSH agent. This allows:
- Git operations on the container to use your SSH keys
- Pulling from private repositories

Ensure your SSH agent has keys loaded:
```bash
ssh-add -l  # Check loaded keys
ssh-add ~/.ssh/id_ed25519  # Add if needed
```

## Troubleshooting

### Password Prompt During Deployment

If you're still prompted for a password:

1. Verify passwordless sudo is configured:
   ```bash
   ssh user@container "sudo -l"
   # Should show: (ALL : ALL) NOPASSWD: ALL
   ```

2. Manually deploy the sudo config once:
   ```bash
   ssh -A user@container "cd ~/.dotfiles && git pull && ./install.sh ..."
   ```

### SSH Connection Fails

- Check if the container is running
- Verify IP address is correct
- Ensure SSH key is in `authorizedKeys` in LXC-base-config.nix

### Git Reset Conflicts

If `git reset --hard` fails:
```bash
ssh user@container "cd ~/.dotfiles && git stash && git fetch origin && git reset --hard origin/main"
```

## Security Considerations

- **Passwordless sudo** is enabled only on LXC containers, not on desktops/laptops
- **SSH key authentication** - password authentication is disabled
- **Agent forwarding** - keys are forwarded but never stored on containers
- **Isolated containers** - each LXC container is isolated in Proxmox
