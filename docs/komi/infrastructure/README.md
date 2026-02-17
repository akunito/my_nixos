---
id: komi.infrastructure.index
summary: Index of all Komi infrastructure documentation
tags: [komi, infrastructure, index]
related_files: [docs/komi/infrastructure/**]
date: 2026-02-17
status: published
---

# Komi Infrastructure Documentation

Documentation for Komi's LXC infrastructure running on Proxmox (192.168.8.3).

## Container Inventory

| CTID | Profile | IP | Cores | RAM | Disk | Purpose |
|------|---------|-----|-------|-----|------|---------|
| 110 | KOMI_LXC_database | 192.168.8.10 | 2 | 4 GB | 30 GB | PostgreSQL & Redis |
| 111 | KOMI_LXC_mailer | 192.168.8.11 | 1 | 1 GB | 10 GB | SMTP relay & Uptime Kuma |
| 112 | KOMI_LXC_monitoring | 192.168.8.12 | 2 | 2 GB | 20 GB | Grafana & Prometheus |
| 113 | KOMI_LXC_proxy | 192.168.8.13 | 1 | 1 GB | 10 GB | Cloudflare tunnel & NPM |
| 114 | KOMI_LXC_tailscale | 192.168.8.14 | 1 | 1 GB | 8 GB | Tailscale subnet router |

**Total resources**: 7 cores, ~9 GB RAM, 78 GB disk

## Guides

| Document | Description |
|----------|-------------|
| [komi-lxc-overview.md](komi-lxc-overview.md) | Master overview: deployment order, architecture, IP scheme |
| [komi-database-setup.md](komi-database-setup.md) | PostgreSQL + Redis setup, user/database creation, backups |
| [komi-proxy-setup.md](komi-proxy-setup.md) | Cloudflare tunnel + NPM + ACME certificate setup |
| [komi-mailer-setup.md](komi-mailer-setup.md) | SMTP2GO relay + Uptime Kuma monitoring |
| [komi-monitoring-setup.md](komi-monitoring-setup.md) | Grafana dashboards, Prometheus targets, alerting |
| [komi-headscale-setup.md](komi-headscale-setup.md) | VPS headscale deployment + client registration |
| [komi-cloudflare-guide.md](komi-cloudflare-guide.md) | Domain setup, Cloudflare account, tunnel creation |

## Quick Access

- **SSH**: `ssh admin@192.168.8.{10-14}`
- **Deploy all**: `./deploy.sh --komi --all`
- **Deploy one**: `./deploy.sh --profile KOMI_LXC_database`
- **List servers**: `./deploy.sh --komi --list`

## Network Migration Note

These containers currently use `192.168.8.x` addresses (akunito's network). Once setup is complete, they will be migrated to `192.168.1.x` (Komi's home network). See the deployment plan for migration steps.
