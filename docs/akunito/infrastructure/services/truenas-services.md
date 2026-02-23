---
id: infrastructure.services.truenas-docker
summary: "TrueNAS Docker services: media, NPM, monitoring"
tags: [infrastructure, truenas, docker, media]
date: 2026-02-23
status: published
---

# TrueNAS Docker Services

## Overview

TrueNAS SCALE runs 19 Docker containers across 7 compose projects at `/mnt/ssdpool/docker/compose/`.

| Property | Value |
|----------|-------|
| Host | 192.168.20.200 (VLAN 20), 192.168.8.200 (LAN) |
| SSH | `ssh truenas_admin@192.168.20.200` |
| Docker root | /mnt/ssdpool/docker/ |
| Compose root | /mnt/ssdpool/docker/compose/ |

## Compose Projects (Startup Order)

### 1. tailscale

VPN subnet router (`--net=host`). Advertises 192.168.8.0/24 + 192.168.20.0/24 to Headscale mesh.

### 2. cloudflared

Cloudflare tunnel for remote access to `*.local.akunito.com` services. Token in `.env`.

### 3. npm (Nginx Proxy Manager)

Reverse proxy on macvlan network (192.168.20.201). Ports 80/81/443. Connected to `homelab_default`, `media_default`, `uptime-kuma_default` Docker networks for container DNS resolution.

### 4. media (9 containers)

| Container | Port | Notes |
|-----------|------|-------|
| jellyfin | 8096 | Media server, /data:ro |
| sonarr | 8989 | TV automation |
| radarr | 7878 | Movie automation |
| bazarr | 6767 | Subtitles |
| prowlarr | 9696 | Indexer management |
| jellyseerr | 5055 | Request management |
| qbittorrent | 8080 | Via gluetun VPN |
| gluetun | — | VPN tunnel for downloads |
| flaresolverr | 8191 | Captcha solver |

**Storage**: All media containers mount `hddpool/media` as `/data` — ONE ZFS dataset with both media and torrents as plain dirs. Hardlinks work for Sonarr/Radarr imports.

### 5. homelab (2 of 8 enabled)

| Container | Port | Notes |
|-----------|------|-------|
| calibre-web-automated | 8083 | Ebook library (ssdpool/library ~413GB) |
| emulatorjs | 3000 | Browser emulator (ssdpool/emulators ~55GB) |

**NOT started**: nextcloud, syncthing, freshrss, obsidian-remote, redis-local (all migrated to VPS)

### 6. exporters (4 containers)

Exportarr instances for Sonarr, Radarr, Prowlarr, Bazarr. Scraped by VPS Prometheus via Tailscale.

### 7. uptime-kuma

Port 3001. Independent home monitoring — watches VPS services from outside. SMTP via VPS Tailscale (100.64.0.6:25).

## NOT Started

- **unifi** — running on VPS (unifi.akunito.com)
- **pihole** — deleted
- **monitoring** — legacy, replaced by VPS Prometheus
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
| hddpool/media | Movies, TV, music + torrents (~5.3TB) |
| hddpool/vps-backups | VPS restic repos |

## Sleep Schedule

- **Awake**: 11:00 - 23:00 (cron ID=8: suspend at 23:00, RTC wake at 11:00)
- **Suspended**: 23:00 - 11:00 (S3 suspend-to-RAM)
- Pools stay unlocked during S3
- Docker services auto-resume after wake
- All backups scheduled within 11:00-23:00 window

## Management

```bash
# Status
ssh truenas_admin@192.168.20.200 "sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | sort"

# Compose projects
ssh truenas_admin@192.168.20.200 "sudo docker compose ls -a"

# Startup script
bash /home/akunito/.dotfiles/scripts/truenas-docker-startup.sh

# WOL / suspend
bash /home/akunito/.dotfiles/scripts/truenas-wol.sh [--check|--suspend]
```

## Related

- [TrueNAS Storage](truenas.md)
- [Proxy Stack](proxy-stack.md)
- [Homelab Stack](homelab-stack.md)
