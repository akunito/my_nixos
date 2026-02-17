---
id: komi.infrastructure.lxc-overview
summary: Master overview of Komi's LXC infrastructure
tags: [komi, infrastructure, lxc, proxmox, overview]
related_files: [profiles/KOMI_LXC*]
date: 2026-02-17
status: published
---

# Komi LXC Infrastructure Overview

## Architecture

Komi's infrastructure runs on a Proxmox host (192.168.8.3) with 8 cores, 16 GB RAM, and ~404 GB encrypted LUKS storage. Five LXC containers provide core services.

```
                    Internet
                       │
                 [Cloudflare Tunnel]
                       │
              ┌────────┴────────┐
              │  komi-proxy     │  192.168.8.13  (CTID 113)
              │  NPM + ACME    │
              └───────┬────────┘
                      │ reverse proxy
         ┌────────────┼────────────┐
         │            │            │
   ┌─────┴─────┐ ┌───┴───┐  ┌────┴────┐
   │ komi-     │ │ komi- │  │ komi-   │
   │ monitoring│ │mailer │  │database │
   │ .12       │ │ .11   │  │ .10     │
   └───────────┘ └───────┘  └─────────┘
        CTID 112    CTID 111    CTID 110

   ┌────────────┐
   │ komi-      │
   │ tailscale  │  192.168.8.14  (CTID 114)
   │ (mesh VPN) │
   └────────────┘
```

## Deployment Order

Deploy in this order (dependencies first):

1. **KOMI_LXC_database** (192.168.8.10) — No dependencies, other services need it
2. **KOMI_LXC_mailer** (192.168.8.11) — Email notifications for all services
3. **KOMI_LXC_proxy** (192.168.8.13) — Cloudflare tunnel + reverse proxy
4. **KOMI_LXC_monitoring** (192.168.8.12) — Needs all targets running to scrape
5. **KOMI_LXC_tailscale** (192.168.8.14) — Independent, deploy anytime

## Container Details

### KOMI_LXC_database (CTID 110)
- **Services**: PostgreSQL 17, Redis
- **Ports**: 5432 (PostgreSQL), 6379 (Redis), 9100/9187/9121 (exporters)
- **Resources**: 2 cores, 4 GB RAM, 30 GB disk
- **Backups**: Hourly + daily, stored at `/mnt/backups`

### KOMI_LXC_mailer (CTID 111)
- **Services**: Postfix SMTP relay (Docker), Uptime Kuma (Docker)
- **Ports**: 25 (SMTP), 3001 (Kuma), 9100/9092 (exporters)
- **Resources**: 1 core, 1 GB RAM, 10 GB disk

### KOMI_LXC_monitoring (CTID 112)
- **Services**: Grafana, Prometheus (native NixOS modules)
- **Ports**: 3002 (Grafana), 9090 (Prometheus), 80/443 (nginx)
- **Resources**: 2 cores, 2 GB RAM, 20 GB disk
- **Scrapes**: All other KOMI_LXC containers

### KOMI_LXC_proxy (CTID 113)
- **Services**: cloudflared (native), Nginx Proxy Manager (Docker), ACME certs
- **Ports**: 80/443 (NPM), 81 (NPM admin), 9100/9092 (exporters)
- **Resources**: 1 core, 1 GB RAM, 10 GB disk

### KOMI_LXC_tailscale (CTID 114)
- **Services**: Tailscale subnet router (native)
- **Ports**: 41641/UDP (Tailscale), 9100 (exporter)
- **Resources**: 1 core, 1 GB RAM, 8 GB disk
- **Routes**: Advertises 192.168.8.0/24 (will change to 192.168.1.0/24)

## SSH Access

All containers use user `admin`:
```bash
ssh admin@192.168.8.10  # database
ssh admin@192.168.8.11  # mailer
ssh admin@192.168.8.12  # monitoring
ssh admin@192.168.8.13  # proxy
ssh admin@192.168.8.14  # tailscale
```

## LUKS & Autostart

All containers live on encrypted LUKS storage. They do **not** have Proxmox `onboot` enabled. After a reboot, run the LUKS unlock script on the Proxmox host:

```bash
ssh root@192.168.8.3
/root/scripts/unlock_luks.sh
```

This unlocks the LUKS volume and starts containers 110-114.

## Network Migration: 192.168.8.x → 192.168.1.x

Once all containers are set up and working on akunito's network (192.168.8.x), Komi will move the Proxmox to her home network (192.168.1.x). This is the migration checklist:

### IP Mapping

| Current (192.168.8.x) | Target (192.168.1.x) | Host |
|------------------------|----------------------|------|
| 192.168.8.3 | 192.168.1.3 | Proxmox host |
| 192.168.8.10 | 192.168.1.10 | komi-database |
| 192.168.8.11 | 192.168.1.11 | komi-mailer |
| 192.168.8.12 | 192.168.1.12 | komi-monitoring |
| 192.168.8.13 | 192.168.1.13 | komi-proxy |
| 192.168.8.14 | 192.168.1.14 | komi-tailscale |

### Files to Update

1. **Proxmox host** (`/etc/network/interfaces` on 192.168.8.3):
   - Change `address` to `192.168.1.3/24`
   - Change `gateway` to `192.168.1.1`

2. **Proxmox DNS** (`/etc/resolv.conf` on host):
   - Change nameserver to `192.168.1.1`

3. **Container configs** (`/etc/pve/lxc/11{0-4}.conf`):
   - Change `ip=192.168.8.X/24,gw=192.168.8.1` to `ip=192.168.1.X/24,gw=192.168.1.1`

4. **NixOS profiles** (in this repo):
   - `profiles/KOMI_LXC_database-config.nix`: ipAddress, nameServers
   - `profiles/KOMI_LXC_mailer-config.nix`: ipAddress, nameServers
   - `profiles/KOMI_LXC_monitoring-config.nix`: ipAddress, nameServers, all prometheusRemoteTargets, prometheusAppTargets, blackbox targets, PVE host
   - `profiles/KOMI_LXC_proxy-config.nix`: ipAddress, nameServers
   - `profiles/KOMI_LXC_tailscale-config.nix`: ipAddress, nameServers, advertiseRoutes

5. **Deploy config** (`deploy-servers.conf`): Update all 5 Komi container IPs

6. **Documentation**: Update IPs in all `docs/komi/infrastructure/` files

7. **Notification targets**: All profiles reference mailer at `192.168.8.11` → `192.168.1.11`

### Migration Steps

```bash
# 1. SSH to Proxmox while on akunito's network
ssh root@192.168.8.3

# 2. Update Proxmox host networking
nano /etc/network/interfaces  # Change to 192.168.1.3
nano /etc/resolv.conf          # Change to 192.168.1.1

# 3. Update all container configs
for ctid in 110 111 112 113 114; do
  sed -i 's/192.168.8/192.168.1/g' /etc/pve/lxc/${ctid}.conf
done

# 4. Reboot Proxmox (will need physical access or Komi's network to reconnect)
reboot

# 5. From Komi's network: unlock LUKS and start containers
ssh root@192.168.1.3
/root/scripts/unlock_luks.sh

# 6. Update NixOS profiles and deploy
# (Do this from Komi's MacBook on her network)
cd ~/.dotfiles
# Update all profiles with new IPs, commit, push
./deploy.sh --komi --all
```

## Deploy Commands

```bash
# Deploy all Komi containers
./deploy.sh --komi --all

# Deploy specific container
./deploy.sh --profile KOMI_LXC_database

# List Komi's servers
./deploy.sh --komi --list

# Manual single-container deploy
ssh -A admin@192.168.8.10 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles KOMI_LXC_database -s -u -d -h"
```
