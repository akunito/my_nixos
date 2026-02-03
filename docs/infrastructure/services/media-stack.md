---
id: infrastructure.services.media
summary: Media stack services - Jellyfin, Sonarr, Radarr, Prowlarr, Bazarr, Jellyseerr, qBittorrent
tags: [infrastructure, media, docker, jellyfin, arr, plex-alternative]
related_files: [profiles/LXC_HOME-config.nix]
---

# Media Stack

Media automation and streaming services running on LXC_HOME (192.168.8.80) in the `media_mediarr-net` Docker network.

---

## Network Configuration

- **Docker Network**: `media_mediarr-net` (172.21.0.0/16)
- **Reverse Proxy**: nginx-proxy (172.21.0.10, shared with homelab_home-net)
- **VPN Gateway**: gluetun (172.21.0.2) for torrent traffic

---

## Services

### Jellyfin (Media Server)

| Property | Value |
|----------|-------|
| Container | jellyfin |
| Internal IP | 172.21.0.4 |
| Internal Port | 8096 |
| Domain | jellyfin.local.akunito.com |

**Storage Mounts**:
- `/mnt/NFS_media/movies` - Movie library (from TrueNAS)
- `/mnt/NFS_media/tv` - TV show library (from TrueNAS)
- `/mnt/NFS_media/music` - Music library (from TrueNAS)
- `/mnt/DATA_4TB/jellyfin/config` - Configuration & metadata

**Key Features**:
- Open-source media streaming
- Hardware transcoding (if available)
- Multiple user profiles
- Mobile & TV apps

---

### Jellyseerr (Request Management)

| Property | Value |
|----------|-------|
| Container | jellyseerr |
| Internal IP | 172.21.0.8 |
| Internal Port | 5055 |
| Domain | jellyseerr.local.akunito.com |

**Key Features**:
- User-friendly request interface for movies/TV
- Integrates with Sonarr/Radarr
- Notification support
- User management

---

### Sonarr (TV Show Automation)

| Property | Value |
|----------|-------|
| Container | sonarr |
| Internal IP | 172.21.0.7 |
| Internal Port | 8989 |
| Domain | sonarr.local.akunito.com |

**Storage Mounts**:
- `/mnt/NFS_media/tv` - TV library
- `/mnt/DATA_4TB/downloads` - Download directory

**Integrations**:
- Prowlarr for indexer management
- qBittorrent for downloads
- Jellyfin for library updates

---

### Radarr (Movie Automation)

| Property | Value |
|----------|-------|
| Container | radarr |
| Internal IP | 172.21.0.6 |
| Internal Port | 7878 |
| Domain | radarr.local.akunito.com |

**Storage Mounts**:
- `/mnt/NFS_media/movies` - Movie library
- `/mnt/DATA_4TB/downloads` - Download directory

**Integrations**:
- Prowlarr for indexer management
- qBittorrent for downloads
- Jellyfin for library updates

---

### Prowlarr (Indexer Manager)

| Property | Value |
|----------|-------|
| Container | prowlarr |
| Internal IP | 172.21.0.5 |
| Internal Port | 9696 |
| Domain | prowlarr.local.akunito.com |

**Key Features**:
- Centralized indexer management
- Syncs indexers to Sonarr/Radarr
- FlareSolverr integration for protected sites

---

### Bazarr (Subtitle Automation)

| Property | Value |
|----------|-------|
| Container | bazarr |
| Internal IP | 172.21.0.9 |
| Internal Port | 6767 |
| Domain | bazarr.local.akunito.com |

**Key Features**:
- Automatic subtitle downloads
- Multiple subtitle providers
- Integrates with Sonarr/Radarr

---

### FlareSolverr (CAPTCHA Solver)

| Property | Value |
|----------|-------|
| Container | flaresolverr |
| Internal IP | 172.21.0.3 |
| Internal Port | 8191 |
| Domain | Not exposed (internal only) |

**Purpose**: Solves Cloudflare and other anti-bot challenges for Prowlarr indexers.

---

### qBittorrent (Torrent Client)

| Property | Value |
|----------|-------|
| Container | qbittorrent |
| Network | Via gluetun VPN container |
| Web UI Port | 8085 |
| Domain | qbittorrent.local.akunito.com |

**VPN Configuration**:
- All traffic routed through gluetun VPN
- Kill switch enabled
- No direct internet access

**Storage Mounts**:
- `/mnt/DATA_4TB/downloads` - Download directory
- `/mnt/DATA_4TB/qbittorrent/config` - Configuration

---

### Gluetun (VPN Gateway)

| Property | Value |
|----------|-------|
| Container | gluetun |
| Internal IP | 172.21.0.2 |
| Ports | 8085 (qBittorrent UI), 6881 (torrent) |

**Purpose**: VPN tunnel for qBittorrent traffic.

**Features**:
- Automatic port forwarding (if supported by VPN)
- Kill switch (no traffic leaks)
- Health checks

---

## Data Flow

```
User Request → Jellyseerr
                  │
                  ▼
         Sonarr / Radarr
                  │
                  ▼
            Prowlarr ──► FlareSolverr
                  │
                  ▼
     qBittorrent (via gluetun VPN)
                  │
                  ▼
         Download Complete
                  │
                  ▼
    Sonarr/Radarr Import & Rename
                  │
                  ▼
     Bazarr ──► Fetch Subtitles
                  │
                  ▼
        Jellyfin Library Update
```

---

## Docker Compose Location

Media services are defined in:
```
LXC_HOME:~/.homelab/media/docker-compose.yml
```

---

## Maintenance Commands

```bash
# SSH to LXC_HOME
ssh akunito@192.168.8.80

# View media stack containers
docker ps --filter "network=media_mediarr-net" --format 'table {{.Names}}\t{{.Status}}'

# View media network containers
docker network inspect media_mediarr-net --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{println}}{{end}}'

# Restart media stack
cd ~/.homelab/media && docker compose restart

# Check VPN connectivity
docker exec gluetun wget -qO- https://ipinfo.io

# View qBittorrent logs
docker logs -f qbittorrent
```

---

## Troubleshooting

### qBittorrent Not Accessible
1. Check gluetun VPN connection: `docker logs gluetun`
2. Verify VPN health: `docker exec gluetun wget -qO- https://ipinfo.io`
3. Check kill switch status

### Indexers Failing in Prowlarr
1. Verify FlareSolverr is running: `docker logs flaresolverr`
2. Check FlareSolverr URL in Prowlarr settings (http://flaresolverr:8191)

### Media Not Appearing in Jellyfin
1. Check file permissions on NFS mounts
2. Trigger library scan in Jellyfin
3. Verify Sonarr/Radarr download paths match Jellyfin library paths

---

## Related Documentation

- [INFRASTRUCTURE.md](../INFRASTRUCTURE.md) - Overall infrastructure
- [INFRASTRUCTURE_INTERNAL.md](../INFRASTRUCTURE_INTERNAL.md) - Detailed internal docs
- [homelab-stack.md](./homelab-stack.md) - Core homelab services
