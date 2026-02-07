# Deploy to LXC Container

Skill for deploying NixOS configurations to LXC containers.

## Usage

Deploy changes to a specific LXC container after committing and pushing.

## Deployment Steps

### 1. Commit and Push Changes First

```bash
git add <files>
git commit -m "message"
git push origin main
```

### 2. Deploy to Container

```bash
# Single container deployment
ssh -A akunito@<IP> "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles <PROFILE> -s -u -q"
```

## Container Reference

| Profile | IP | Description |
|---------|-----|-------------|
| LXC_HOME | 192.168.8.80 | Homelab services |
| LXC_proxy | 192.168.8.102 | Cloudflare tunnel & NPM |
| LXC_plane | 192.168.8.86 | Production container |
| LXC_portfolioprod | 192.168.8.88 | Portfolio service |
| LXC_mailer | 192.168.8.89 | Mail & monitoring |
| LXC_liftcraftTEST | 192.168.8.87 | Test environment |
| LXC_monitoring | 192.168.8.85 | Prometheus & Grafana |
| LXC_database | 192.168.8.103 | PostgreSQL, MariaDB & Redis |

## Examples

### Deploy to LXC_database

```bash
ssh -A akunito@192.168.8.103 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_database -s -u -q"
```

### Deploy to LXC_monitoring

```bash
ssh -A akunito@192.168.8.85 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_monitoring -s -u -q"
```

### Deploy to Multiple Containers

Use the interactive deploy script:

```bash
./deploy-lxc.sh
```

Or deploy to all:

```bash
./deploy-lxc.sh --all
```

Or deploy to specific profiles:

```bash
./deploy-lxc.sh --profile LXC_database --profile LXC_monitoring
```

## Install Script Flags

- `-s` / `--silent`: Silent mode (no startup services)
- `-u` / `--update`: Update mode
- `-q` / `--quick`: Quick mode (skip docker handling and hardware-config generation)

## Troubleshooting

### Rollback Failed Deployment

```bash
ssh -A akunito@<IP> "sudo nixos-rebuild switch --rollback"
```

### Check Service Status After Deploy

```bash
ssh -A akunito@<IP> "systemctl status <service-name>"
```
