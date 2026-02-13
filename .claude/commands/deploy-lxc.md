# Deploy to LXC Container

Skill for deploying NixOS configurations to LXC containers and other machines.

## CRITICAL: Always Use install.sh — NEVER Bare nixos-rebuild

**NEVER** run `git pull && sudo nixos-rebuild switch` on remote machines. This will break because:
- `hardware-configuration.nix` is machine-specific and gitignored; `git pull` could overwrite it with another machine's UUIDs
- `install.sh` handles hardware-config regeneration, file hardening, docker handling, and rollback
- Use `deploy.sh` or the `git fetch && git reset --hard && ./install.sh` pattern ALWAYS

**Flag rules for deploy-servers.conf:**
- **LXC containers**: Use `-d -h` (skip docker + skip hardware — no docker overlay issues, no hardware changes)
- **Laptops/Desktops**: Use NO skip flags — hardware-config MUST be regenerated on physical machines

## Usage

Deploy changes to a specific machine after committing and pushing.

## Deployment Steps

### 1. Commit and Push Changes First

```bash
git add <files>
git commit -m "message"
git push origin main
```

### 2. Deploy

```bash
# Option A: Use deploy.sh (preferred — handles IP probing, git fetch+reset, install.sh)
./deploy.sh --profile <PROFILE>

# Option B: Single LXC container via SSH (passwordless sudo)
ssh -A akunito@<IP> "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles <PROFILE> -s -u -d -h"
```

## Important: LXC vs Physical Machines

**LXC containers** have passwordless sudo configured (see `sudoCommands` in `profiles/LXC-base-config.nix`), so they can be deployed non-interactively via SSH.

**Physical machines (laptops/desktops)** require sudo password authentication. These CANNOT be deployed non-interactively from Claude Code. The user must run the deployment manually:

```bash
ssh -A <user>@<IP>
cd ~/.dotfiles
git fetch origin && git reset --hard origin/main
./install.sh ~/.dotfiles <PROFILE> -s -u
```

## Laptop/Desktop Reference

| Profile | IP | User | Description |
|---------|-----|------|-------------|
| DESK | 192.168.8.96 | akunito | Main desktop |
| LAPTOP_L15 | 192.168.8.92 | akunito | ThinkPad L15 laptop |
| LAPTOP_AGA | 192.168.8.78 | aga | AGA's laptop |

## Container Reference

| Profile | IP | Bridge | Description |
|---------|-----|--------|-------------|
| LXC_HOME | 192.168.8.80 | vmbr10 | Homelab services |
| LXC_proxy | 192.168.8.102 | vmbr10 | Cloudflare tunnel & NPM |
| LXC_plane | 192.168.8.86 | vmbr10 | Production container |
| LXC_portfolioprod | 192.168.8.88 | vmbr10 | Portfolio service |
| LXC_mailer | 192.168.8.89 | vmbr10 | Mail & monitoring |
| LXC_liftcraftTEST | 192.168.8.87 | vmbr10 | Test environment |
| LXC_monitoring | 192.168.8.85 | vmbr10 | Prometheus & Grafana |
| LXC_database | 192.168.8.103 | vmbr10 | PostgreSQL, MariaDB & Redis |
| LXC_matrix | 192.168.8.104 | vmbr10 | Matrix Synapse, Element & Claude Bot |
| LXC_tailscale | 192.168.8.105 | vmbr10 | Tailscale subnet router (mesh VPN) |

All containers use vmbr10 (bond0 LACP 2x10G → USW Aggregation SFP+ 3+4).

## Examples

### Deploy to LXC_database

```bash
ssh -A akunito@192.168.8.103 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_database -s -u -d -h"
```

### Deploy to LXC_monitoring

```bash
ssh -A akunito@192.168.8.85 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_monitoring -s -u -d -h"
```

### Deploy to LXC_matrix

```bash
ssh -A akunito@192.168.8.104 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_matrix -s -u -d -h"
```

### Deploy to LXC_tailscale

```bash
ssh -A akunito@192.168.8.105 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_tailscale -s -u -d -h"
```

### Deploy to LAPTOP_AGA (Manual - requires password)

```bash
ssh -A aga@192.168.8.78
cd ~/.dotfiles
git fetch origin && git reset --hard origin/main
./install.sh ~/.dotfiles LAPTOP_AGA -s -u
```

### Deploy to Multiple Containers

Use the unified deploy script (interactive TUI):

```bash
./deploy.sh
```

Or deploy to all:

```bash
./deploy.sh --all
```

Or deploy to specific profiles:

```bash
./deploy.sh --profile LXC_database --profile LXC_monitoring
```

Or deploy an entire group:

```bash
./deploy.sh --group "LXC Containers"
```

Or preview what would be deployed:

```bash
./deploy.sh --dry-run --all
```

## Install Script Flags

- `-s` / `--silent`: Silent mode (no startup services)
- `-u` / `--update`: Update flake.lock
- `-d` / `--skip-docker`: Skip docker container handling (keeps containers running)
- `-h` / `--skip-hardware`: Skip hardware-configuration.nix generation
- `-q` / `--quick`: Shorthand for `-d -h` (backward compatibility)
- `-f` / `--force`: Bypass ENV_PROFILE safety check (for first-time installs)
- `-n` / `--no-git-update`: Skip repository update/fetch (useful after git-crypt unlock)

## Troubleshooting

### Rollback Failed Deployment

```bash
ssh -A akunito@<IP> "sudo nixos-rebuild switch --rollback"
```

### Check Service Status After Deploy

```bash
ssh -A akunito@<IP> "systemctl status <service-name>"
```
