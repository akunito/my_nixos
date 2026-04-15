---
id: infrastructure.services.truenas-docker
summary: "TrueNAS Docker services: media, NPM, monitoring"
tags: [infrastructure, truenas, docker, media]
date: 2026-02-23
status: published
---

# TrueNAS Docker Services

## Overview

TrueNAS SCALE runs ~21 Docker containers using a hybrid root + rootless Docker setup at `/mnt/ssdpool/docker/compose/`.

| Property | Value |
|----------|-------|
| Host | 192.168.20.200 (VLAN 20), 192.168.8.200 (LAN) |
| SSH | `ssh -A akunito@192.168.20.200` |
| Docker root | /mnt/ssdpool/docker/ |
| Compose root | /mnt/ssdpool/docker/compose/ |

## Compose Projects (Startup Order)

### Root Docker (sudo docker — NET_ADMIN required)

#### 1. tailscale

VPN subnet router (`--net=host`, NET_ADMIN). Advertises 192.168.8.0/24 + 192.168.20.0/24 to Headscale mesh.

#### 2. vpn-media (2 containers)

| Container | Port | Notes |
|-----------|------|-------|
| gluetun | — | VPN tunnel (NET_ADMIN + /dev/net/tun) |
| qbittorrent | 8085 | Via gluetun network namespace |

### Rootless Docker (DOCKER_HOST=unix:///run/user/1000/docker.sock)

#### 3. cloudflared

Cloudflare tunnel for remote access to `*.local.akunito.com` services. Token in `.env`. Outbound-only — no host network needed.

#### 4. npm (Nginx Proxy Manager)

Reverse proxy on bridge networking (192.168.20.200). Ports 80/81/443. Connected to `media_default` Docker network for container DNS resolution.

> **Migrated Mar 2026**: Previously used macvlan (192.168.20.201). Moved to bridge as part of rootless Docker migration.

#### 5. media (7 containers)

| Container | Port | Notes |
|-----------|------|-------|
| jellyfin | 8096 | Media server, /data:ro, GPU passthrough |
| sonarr | 8989 | TV automation |
| radarr | 7878 | Movie automation |
| bazarr | 6767 | Subtitles |
| prowlarr | 9696 | Indexer management |
| jellyseerr | 5055 | Request management |
| solvearr | 8191 | Captcha solver |

**Storage**: All media containers mount `ssdpool/media` as `/data` — ONE ZFS dataset with both media and torrents as plain dirs. Hardlinks work for Sonarr/Radarr imports.

#### 6. homelab (0 of 8 enabled — all migrated to VPS)

All services migrated to VPS. Compose project kept for NPM `homelab_default` network connectivity.

**Migrated**: calibre-web (Mar 2026), romm (Feb 2026), nextcloud, syncthing, obsidian-remote, redis-local

#### 7. exporters (4 containers)

Exportarr instances for Sonarr, Radarr, Prowlarr, Bazarr. Scraped by VPS Prometheus via Tailscale.

#### 8. monitoring (2 containers)

| Container | Port | Notes |
|-----------|------|-------|
| node-exporter | 9100 | Host metrics for Prometheus |
| cadvisor | 8081 | Rootless Docker container metrics |

Scraped by VPS Prometheus via Tailscale/WireGuard.

## NOT Auto-Started

- **unifi** — fallback controller (manual start only, VPS runs primary)
- **pihole** — deleted
- **gameservers** — not deployed

## Storage Layout

| Dataset | Content |
|---------|---------|
| ssdpool/docker/compose/ | Docker compose files |
| ssdpool/docker/jellyfin | Jellyfin config/metadata |
| ssdpool/docker/qbittorrent | qBittorrent config |
| ssdpool/docker/npm | NPM data + certs |
| ssdpool/docker/calibre-web | Calibre-Web config |
| ssdpool/docker/emulatorjs | EmulatorJS config |
| ssdpool/docker/tailscale | Tailscale state |
| ssdpool/library | Ebooks (~413GB) |
| ssdpool/emulators | ROMs (~55GB) |
| ssdpool/media | Movies, TV, music + torrents |
| ssdpool/vps-backups | VPS restic databases (critical) |
| ssdpool/workstation_backups | Workstation restic backups |
| extpool/downloads | Game downloads |
| extpool/vps-backups | VPS restic services, libraries, nextcloud |

## Sleep Schedule

- **Awake**: 11:00 - 23:00 (cron ID=8: suspend at 23:00, RTC wake at 11:00)
- **Suspended**: 23:00 - 11:00 (S3 suspend-to-RAM)
- Pools stay unlocked during S3
- **Pre-suspend**: systemd service (`docker-pre-suspend.service`) gracefully stops all containers (prevents stale state)
- **Post-resume**: systemd service (`docker-post-resume.service`) starts all containers in order (10s network settle delay)
- Script: `/home/akunito/docker-suspend-hook.sh` (deployed by startup script)
- Log: `/var/log/docker-suspend-hook.log`
- All backups scheduled within 11:00-23:00 window

## Management

```bash
# Status
ssh -A akunito@192.168.20.200 "sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | sort"

# Compose projects
ssh -A akunito@192.168.20.200 "sudo docker compose ls -a"

# Startup script
bash /home/akunito/.dotfiles/scripts/truenas-docker-startup.sh

# WOL / suspend
bash /home/akunito/.dotfiles/scripts/truenas-wol.sh [--check|--suspend]
```

## Related

- [TrueNAS Storage](truenas.md)
- [Proxy Stack](proxy-stack.md)
- [Homelab Stack](homelab-stack.md)
