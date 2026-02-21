# Deploy to LXC Container

Skill for deploying NixOS configurations to LXC containers and other machines.

## CRITICAL: Always Use install.sh — NEVER Bare nixos-rebuild

**NEVER** run `git pull && sudo nixos-rebuild switch` on remote machines. This will break because:
- `hardware-configuration.nix` is machine-specific; `git reset --hard` overwrites it, but `install.sh` regenerates it for the target machine before building
- `install.sh` handles hardware-config regeneration, file hardening, docker handling, and rollback
- Use `deploy.sh` or the `git fetch && git reset --hard && ./install.sh` pattern ALWAYS

**Flag rules for deploy-servers.conf:**
- **LXC containers**: Use `-d -h` (skip docker + skip hardware — no docker overlay issues, no hardware changes)
- **VPS (VPS_PROD)**: Use `-d` only (skip docker). Do NOT use `-h` — hardware-config MUST be regenerated on VPS
- **Laptops/Desktops**: Use NO skip flags — hardware-config MUST be regenerated on physical machines

**ONLY `-h` may be used for LXC containers** — all other machine types (VPS, laptops, desktops) MUST regenerate hardware-config.

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

## Important: LXC vs VPS vs Physical Machines

**LXC containers** have passwordless sudo configured (see `sudoCommands` in `profiles/LXC-base-config.nix`), so they can be deployed non-interactively via SSH. Use `-d -h` flags.

**VPS (VPS_PROD)** has passwordless sudo via SSH agent forwarding. Can be deployed non-interactively via SSH. Use `-d` flag only — do NOT use `-h` because hardware-config MUST be regenerated on VPS (it's a real machine, not an LXC container).

**Physical machines (laptops/desktops)** require sudo password authentication. These CANNOT be deployed non-interactively from Claude Code. The user must run the deployment manually:

```bash
ssh -A <user>@<IP>
cd ~/.dotfiles
git fetch origin && git reset --hard origin/main
./install.sh ~/.dotfiles <PROFILE> -s -u
```

## VPS Reference

| Profile | IPs (VPN) | SSH Port | User | Description |
|---------|-----------|----------|------|-------------|
| VPS_PROD | 100.64.0.6 (TS), 172.26.5.155 (WG) | 56777 | akunito | Netcup RS 4000 G12 (Nuremberg) |

**VPS SSH is VPN-only** — connect via Tailscale or WireGuard, never via public IP.

## Laptop/Desktop Reference

| Profile | IP | User | Description |
|---------|-----|------|-------------|
| DESK | 192.168.8.96 | akunito | Main desktop |
| LAPTOP_X13 | 192.168.8.92 | akunito | ThinkPad L15 laptop |
| LAPTOP_X13 | 192.168.8.92 | akunito | ThinkPad X13 AMD laptop |
| LAPTOP_A | 192.168.8.78 | aga | AGA's laptop |

## Container Reference

| Profile | IP | Bridge | Description |
|---------|-----|--------|-------------|
| LXC_HOME | 192.168.8.80 | vmbr10 | Homelab services |
| LXC_proxy | 192.168.1.102 | vmbr10 | Cloudflare tunnel & NPM |
| LXC_plane | 192.168.8.86 | vmbr10 | Production container |
| LXC_portfolioprod | 192.168.8.88 | vmbr10 | Portfolio service |
| LXC_mailer | 192.168.8.89 | vmbr10 | Mail & monitoring |
| LXC_liftcraftTEST | 192.168.8.87 | vmbr10 | Test environment |
| LXC_monitoring | 192.168.8.85 | vmbr10 | Prometheus & Grafana |
| LXC_database | 192.168.1.103 | vmbr10 | PostgreSQL, MariaDB & Redis |
| LXC_matrix | 192.168.1.104 | vmbr10 | Matrix Synapse, Element & Claude Bot |
| LXC_tailscale | 192.168.1.105 | vmbr10 | Tailscale subnet router (mesh VPN) |

All akunito containers use vmbr10 (bond0 LACP 2x10G → USW Aggregation SFP+ 3+4).

## Komi Container Reference (Proxmox 192.168.1.3)

| Profile | IP | User | Description |
|---------|-----|------|-------------|
| KOMI_LXC_database | 192.168.1.10 | admin | PostgreSQL & Redis (Komi) |
| KOMI_LXC_mailer | 192.168.1.11 | admin | Mail & monitoring (Komi) |
| KOMI_LXC_monitoring | 192.168.1.12 | admin | Prometheus & Grafana (Komi) |
| KOMI_LXC_proxy | 192.168.1.13 | admin | Cloudflare & NPM (Komi) |
| KOMI_LXC_tailscale | 192.168.1.14 | admin | Tailscale router (Komi) |

All Komi containers use vmbr0 on Komi's Proxmox (192.168.1.3).

## Examples

### Deploy to LXC_database

```bash
ssh -A akunito@192.168.1.103 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_database -s -u -d -h"
```

### Deploy to LXC_monitoring

```bash
ssh -A akunito@192.168.8.85 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_monitoring -s -u -d -h"
```

### Deploy to LXC_matrix

```bash
ssh -A akunito@192.168.1.104 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_matrix -s -u -d -h"
```

### Deploy to LXC_tailscale

```bash
ssh -A akunito@192.168.1.105 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_tailscale -s -u -d -h"
```

### Deploy to VPS_PROD (via Tailscale or WireGuard — NO -h flag!)

```bash
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
# Or via WireGuard:
ssh -A -p 56777 akunito@172.26.5.155 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

### Deploy to LAPTOP_A (Manual - requires password)

```bash
ssh -A aga@192.168.8.78
cd ~/.dotfiles
git fetch origin && git reset --hard origin/main
./install.sh ~/.dotfiles LAPTOP_A -s -u
```

### Deploy to KOMI_LXC_database

```bash
ssh -A admin@192.168.1.10 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles KOMI_LXC_database -s -u -d -h"
```

### Deploy to KOMI_LXC_mailer

```bash
ssh -A admin@192.168.1.11 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles KOMI_LXC_mailer -s -u -d -h"
```

### Deploy to KOMI_LXC_monitoring

```bash
ssh -A admin@192.168.1.12 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles KOMI_LXC_monitoring -s -u -d -h"
```

### Deploy to KOMI_LXC_proxy

```bash
ssh -A admin@192.168.1.13 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles KOMI_LXC_proxy -s -u -d -h"
```

### Deploy to KOMI_LXC_tailscale

```bash
ssh -A admin@192.168.1.14 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles KOMI_LXC_tailscale -s -u -d -h"
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
./deploy.sh --group "Komi LXC Containers"
```

Or filter by user:

```bash
./deploy.sh --aku --all      # Deploy all akunito servers
./deploy.sh --komi --all     # Deploy all Komi servers
./deploy.sh --komi --list    # List Komi's servers
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
