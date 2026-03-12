---
id: infrastructure.services.homelab
summary: "Homelab services: split between VPS and TrueNAS"
tags: [infrastructure, homelab, nextcloud, syncthing, media]
date: 2026-02-23
status: published
---

# Homelab Stack

Services split between VPS and TrueNAS after migration (Feb 2026).

## On VPS (Docker, rootless)

| Service | Domain | Notes |
|---------|--------|-------|
| Nextcloud | nextcloud.akunito.com | Cloud storage, ~200GB data |
| Syncthing | syncthing.akunito.com | File sync |
| Miniflux | freshrss.akunito.com | RSS reader (Go, PostgreSQL backend, domain kept for URL stability) |
| miniflux-ai | — (internal) | AI news summaries via Gemini |
| Obsidian-remote | obsidian.akunito.com | Remote Obsidian access |
| UniFi | unifi.akunito.com | Network controller (MongoDB 4.4) |
| Uptime Kuma | status.akunito.com | Public monitoring |
| Finance Tagger | finance.local.akunito.com | Transaction classification UI (Flask + htmx, Tailscale-only) |

### Nextcloud

- Database: MariaDB 11 on VPS localhost
- Redis: db1 on VPS localhost
- Cron: every 5 minutes via nextcloud-cron container
- 2FA: TOTP enabled for all users
- Brute-force protection enabled
- Security headers via NPM
- Previous: LXC_HOME [archived] → TrueNAS → VPS (migrated twice)

### UniFi

- Image: linuxserver/unifi-network-application
- MongoDB 4.4 sidecar container
- Previous: TrueNAS Docker (kept as fallback, not started)

## On TrueNAS (Docker)

| Service | Domain | Data Location |
|---------|--------|---------------|
| Uptime Kuma | uptime.local.akunito.com | Independent VPS watchdog |

**Migrated to VPS**: Calibre-Web (Mar 2026), RomM (Feb 2026). Data accessed via NFS or copied to VPS NVMe.

## Media Stack (TrueNAS only)

| Service | Domain | Port |
|---------|--------|------|
| Jellyfin | jellyfin.local.akunito.com | 8096 |
| Sonarr | sonarr.local.akunito.com | 8989 |
| Radarr | radarr.local.akunito.com | 7878 |
| Bazarr | bazarr.local.akunito.com | 6767 |
| Prowlarr | prowlarr.local.akunito.com | 9696 |
| Jellyseerr | jellyseerr.local.akunito.com | 5055 |
| qBittorrent | qbt.local.akunito.com | 8080 |
| Gluetun | — | VPN for downloads |
| FlareSolverr | — | 8191 |

### Unified /data Structure

All media containers mount `ssdpool/media` as `/data` — ONE ZFS dataset:

```
/mnt/ssdpool/media/
├── movies/          # Existing media
├── tv/              # Existing media
├── music/           # Existing media
└── torrents/        # Downloads
    ├── movies/
    ├── tv/
    └── music/
```

**Hardlinks work** because torrents/ and media/ are on the same ZFS dataset. Sonarr/Radarr imports are instant (no copy, no extra disk space).

## Previous Setup [Archived]

*(Archived: akunito's Proxmox LXC containers were shut down Feb 2026, services migrated to VPS_PROD)*

All homelab services previously ran on LXC_HOME (192.168.8.80, Proxmox). Migrated to TrueNAS in Phase 0.5, then web services moved to VPS in Phase 3. LXC_HOME decommissioned. FreshRSS replaced by Miniflux (Feb 2026). EmulatorJS replaced by RomM (Feb 2026).
