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

**Migrated**: calibre-web (Mar 2026), romm (Feb 2026), nextcloud, syncthing, obsidian-remote, redis-local. Calibre and RomM came **back** to the NAS on 2026-09-30 as on-demand stacks (below), in their own compose projects, not in this one.

#### 7. exporters (4 containers)

Exportarr instances for Sonarr, Radarr, Prowlarr, Bazarr. Scraped by VPS Prometheus via Tailscale.

#### 8. monitoring (2 containers)

| Container | Port | Notes |
|-----------|------|-------|
| node-exporter | 9100 | Host metrics for Prometheus |
| cadvisor | 8081 | Rootless Docker container metrics |

Scraped by VPS Prometheus via Tailscale/WireGuard.

## On-demand stacks (OFF by default — AINF-401, 2026-09-30)

Declared in `nasOnDemandDockerProjects` (NAS_PROD profile). Nothing starts them at boot
or after resume; `nas-docker-ondemand-pre-suspend` takes down whichever is running before
the 23:00 suspend. All use `restart: "no"`.

| Name (`nas-svc`) | Containers | Reached at | State on disk |
|---|---|---|---|
| calibre | calibre-web-automated (image pinned by digest) | calibre.akunito.com, calibre.local (NPM → 192.168.20.200:8083) | `/mnt/ssdpool/docker/calibre/{config,ingest}`; library + thumbnails on `/mnt/extpool/library/` |
| romm | romm 5.1.0, romm-db (mariadb 12.2) | emulators.akunito.com, emulators.local (→ :8998) | `/mnt/ssdpool/docker/romm`; ROMs on `/mnt/extpool/library/romm-library` |
| unifi | unifi-app 10.5.67, unifi-db (mongo 8.0 — do not downgrade) | unifi.akunito.com, unifi.local (→ https :8443); inform `100.64.0.1:8080`, STUN `100.64.0.1:3478/udp` | `/mnt/ssdpool/docker/unifi/{db,config,backups}` |
| akucraft-survival | minecraft | `100.64.0.1:25565` (tailnet only) | `compose/gameservers/akucraft-survival/data` |
| akucraft-solo / -creative / -staging | minecraft-solo / minecraft-creative / mc-mca-staging | `:25567` / `:25566` / `:25599` | `compose/gameservers/akucraft-*/data` |

```bash
ssh -A akunito@100.64.0.1 'nas-svc list'              # running | stopped | absent
ssh -A akunito@100.64.0.1 'nas-svc start calibre'     # stop = compose down -t 120
```

From Telegram: `/svc`, `/svc start|stop <name>` in the infra bot (admins, confirm button);
the AkuCraft bot's `/start` and idle-stop drive the game servers. Only reachable while the
NAS is awake (16:00–23:00). Switches keep forwarding without the UniFi controller; no
statistics are collected while it is off.

The libraries are on **extpool**, not ssdpool: ssdpool's 870 EVOs sit behind the LSI SAS3008,
which never passes TRIM to them (the drives lack DRAT/RZAT), and sustained writes there
collapse to 7–20 MB/s (measured 2026-09-30). They are not backed up — re-downloadable.
`gameservers/akucraft-archive/` holds the retired akucraft-web and akucraft-playermap.

Compose templates: `templates/truenas/{calibre,romm,unifi}` and
`templates/truenas/gameservers/akucraft-{survival,solo,creative}` (staging has none: its live
compose carries a literal RCON password).

## Storage Layout

| Dataset | Content |
|---------|---------|
| ssdpool/docker/compose/ | Docker compose files |
| ssdpool/docker/jellyfin | Jellyfin config/metadata |
| ssdpool/docker/qbittorrent | qBittorrent config |
| ssdpool/docker/npm | NPM data + certs |
| ssdpool/docker/{calibre,romm,unifi} | State of the on-demand stacks (configs, mariadb, mongo) |
| ssdpool/docker/_old-2026-03 | Pre-VPS-migration leftovers (calibre-web, romm, unifi-db, emulatorjs), set aside 2026-09-30 |
| ssdpool/docker/tailscale | Tailscale state |
| extpool/library (plain dir in the extpool root dataset) | Calibre library 211 G + thumbnails 50 G, ROMs 43 G |
| ssdpool/media | Movies, TV, music + torrents |
| ssdpool/vps-backups | VPS restic databases (critical) |
| ssdpool/workstation_backups | Workstation restic backups |
| extpool/downloads | Game downloads |
| extpool/vps-backups | VPS restic services, databases, nextcloud, immich |

## Sleep Schedule

- **Awake**: 16:00 - 23:00 (cron ID=8: suspend at 23:00, RTC wake at 16:00)
- **Suspended**: 23:00 - 16:00 (S3 suspend-to-RAM)
- Pools stay unlocked during S3
- **Pre-suspend**: systemd service (`docker-pre-suspend.service`) gracefully stops all containers (prevents stale state)
- **Post-resume**: systemd service (`docker-post-resume.service`) starts all containers in order (10s network settle delay)
- Script: `/home/akunito/docker-suspend-hook.sh` (deployed by startup script)
- Log: `/var/log/docker-suspend-hook.log`
- All backups scheduled within 16:00-23:00 window

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
