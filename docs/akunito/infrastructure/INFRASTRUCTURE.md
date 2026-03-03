---
id: infrastructure.overview
summary: "Infrastructure overview: VPS + TrueNAS + pfSense architecture"
tags: [infrastructure, architecture, vps, truenas, pfsense, docker]
date: 2026-02-23
status: published
---

# Infrastructure Overview

## Architecture

```
INTERNET
    |
    +---> Cloudflare CDN/DNS (*.akunito.com)
    |         |
    |         v
    |   [Netcup VPS - RS 4000 G12, Nuremberg]
    |     NixOS, LUKS encrypted, rootless Docker
    |     15 containers + native services (DB, monitoring, mail)
    |         |
    |         | Tailscale mesh (100.x.x.x) + WireGuard backup (172.26.5.x)
    |         v
    +---> [pfSense 192.168.8.1]  (firewall, DNS, WireGuard peer)
              |
              +---> [TrueNAS 192.168.20.200]  (storage + media Docker)
              |       15 containers, 6 compose projects
              |       Sleep: 23:00-11:00 (S3 suspend, RTC wake)
              |
              +---> [DESK 192.168.8.96]  (workstation)
              +---> [Laptops]  (X13, YOGA, A)

DECOMMISSIONED (Feb 2026):
  - Proxmox (192.168.8.82) — SHUT DOWN
  - Hetzner VPS (91.211.27.37) — CANCELLED
  - All akunito LXC containers — STOPPED
```

## Nodes

### VPS (Netcup RS 4000 G12)

| Property | Value |
|----------|-------|
| Specs | 12 AMD EPYC 9645 cores, 32GB DDR5 ECC, 1TB NVMe, 2.5 Gbps |
| Location | Nuremberg datacenter, ~22ms from Warsaw |
| Cost | ~32.49 EUR/mo (incl. VAT) |
| Public IP | 159.195.32.28 |
| Tailscale IP | 100.64.0.6 |
| WireGuard IP | 172.26.5.155 |
| SSH | Port 56777 (VPN-only) |
| NixOS Profile | VPS_PROD |
| Encryption | LUKS full-disk, initrd SSH unlock on port 2222 |

**Docker containers (16, rootless)**: portfolio, liftcraft, plane, matrix-synapse, element-web, matrix-redis, miniflux, miniflux-ai, nextcloud, nextcloud-cron, syncthing, obsidian-remote, uptime-kuma, unifi-network-app, unifi-mongodb, cloudflared

**NixOS native services**: PostgreSQL 17 (plane, liftcraft, matrix, miniflux, vaultwarden), MariaDB 11, Redis 7, Vaultwarden, Prometheus, Grafana, Postfix relay, Headscale, fail2ban, node-exporter, blackbox-exporter, snmp-exporter, graphite-exporter, postgres-exporter, mysqld-exporter, redis-exporter

### TrueNAS SCALE (192.168.20.200)

| Property | Value |
|----------|-------|
| RAM | 62GB DDR4 ECC UDIMM |
| CPU | AMD Ryzen 5 5600G |
| NICs | 2x Intel X520 SFP+ (bond0 LACP), 1x RTL8125B 2.5GbE (WOL) |
| Pools | ssdpool (2x 1TB NVMe), hddpool (2x 8TB HDD mirror) |
| VLAN 20 | 192.168.20.200 (bond0) |
| LAN | 192.168.8.200 (enp10s0) |
| NPM macvlan | 192.168.20.201 |

**Docker containers (19, 7 compose projects)**:
1. **tailscale** — subnet router (192.168.8.0/24 + 192.168.20.0/24)
2. **cloudflared** — remote access to *.local.akunito.com
3. **npm** — reverse proxy (macvlan 192.168.20.201)
4. **media** (9): jellyfin, sonarr, radarr, bazarr, prowlarr, jellyseerr, qbittorrent, gluetun, flaresolverr
5. **homelab** (2): calibre-web-automated, emulatorjs
6. **exporters** (4): exportarr-sonarr/radarr/prowlarr/bazarr
7. **uptime-kuma** — home monitoring

**Sleep schedule**: Awake 11:00-23:00, Suspended 23:00-11:00 (S3 + RTC alarm)

### pfSense (192.168.8.1)

- Intel 82599 quad SFP+ (ix0-ix3), Intel I225 WAN (igc0)
- LAN (ix0), STORAGE_VLAN (ix0.100 = 192.168.20.0/24), GUEST (ix0.200)
- Bridge: ix2 + ix3 to LAN (STP enabled)
- WireGuard backup tunnel to VPS (172.26.5.0/24)
- DNS: `*.local.akunito.com` → 192.168.20.201

## Service Catalog

### VPS Services (*.akunito.com)

| Service | Domain | Port |
|---------|--------|------|
| Plane | plane.akunito.com | 3000 |
| Matrix Synapse | matrix.akunito.com | 8008 |
| Element Web | element.akunito.com | 8088 |
| Nextcloud | nextcloud.akunito.com | 8089 |
| Miniflux | freshrss.akunito.com | 8084 |
| miniflux-ai | — (internal) | 8085 |
| Syncthing | syncthing.akunito.com | 8384 |
| Obsidian | obsidian.akunito.com | — |
| Portfolio | info.akunito.com | — |
| LiftCraft | leftyworkout-test.akunito.com | 3001 |
| UniFi | unifi.akunito.com | — |
| Grafana | grafana.akunito.com | — |
| Headscale | headscale.akunito.com | 8080 |
| Uptime Kuma | status.akunito.com | 3009 |

### TrueNAS Services (*.local.akunito.com)

| Service | Domain | Port |
|---------|--------|------|
| Jellyfin | jellyfin.local.akunito.com | 8096 |
| Sonarr | sonarr.local.akunito.com | 8989 |
| Radarr | radarr.local.akunito.com | 7878 |
| Prowlarr | prowlarr.local.akunito.com | 9696 |
| Bazarr | bazarr.local.akunito.com | 6767 |
| Jellyseerr | jellyseerr.local.akunito.com | 5055 |
| Calibre-Web | calibre.local.akunito.com | 8083 |
| EmulatorJS | emulatorjs.local.akunito.com | 3000 |
| qBittorrent | qbt.local.akunito.com | 8080 |
| Uptime Kuma | uptime.local.akunito.com | 3001 |

## Traffic Flow

**External access**: Internet → Cloudflare → cloudflared (VPS or TrueNAS) → localhost service

**Local access**: Client → pfSense DNS → TrueNAS NPM (192.168.20.201) → service

**VPN**: Tailscale mesh (primary) + WireGuard tunnel (backup, VPS ↔ pfSense)

## Backup Schedule

| Job | Schedule | Source | Target |
|-----|----------|--------|--------|
| DB dumps (pg/mysql/redis) | Hourly | VPS /var/backup/ | VPS local |
| Restic databases | Every 2h (18:00-22:30) | VPS dumps | TrueNAS hddpool |
| Restic services | Daily 09:00 | VPS Docker volumes | TrueNAS hddpool |
| Restic nextcloud | Daily 10:00 | VPS nextcloud data | TrueNAS hddpool |
| TrueNAS→VPS config | Daily 18:30 | TrueNAS configs | VPS |
| ZFS replication | Daily 21:00 | ssdpool | hddpool |
| TrueNAS suspend | Daily 23:00 | — | RTC wake at 11:00 |

## Sleep Schedule

- **Awake**: 11:00 - 23:00 daily
- **Suspended**: 23:00 - 11:00 (S3 suspend-to-RAM, RTC alarm wake)
- ZFS pools remain unlocked during S3 (data in RAM)
- Docker services auto-resume after wake
- WOL from S3 unreliable (r8169 driver limitation)

## Related Docs

- [VPS Services](services/vps-services.md)
- [TrueNAS Docker Services](services/truenas-services.md)
- [Database & Redis](services/database-redis.md)
- [Proxy Stack](services/proxy-stack.md)
- [Monitoring Stack](services/monitoring-stack.md)
- [Homelab Stack](services/homelab-stack.md)
- [Matrix](services/matrix.md)
- [Tailscale/Headscale](services/tailscale-headscale.md)
- [Uptime Kuma](services/kuma.md)
- [pfSense](services/pfsense.md)
- [Network Switching](services/network-switching.md)
- [TrueNAS Storage](services/truenas.md)
- [Migration Docs](migration/README.md)
