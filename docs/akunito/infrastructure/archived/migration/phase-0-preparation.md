---
id: infrastructure.migration.phase-0
summary: "Migration preparation, LXC_HOME to TrueNAS, DB fallback"
tags: [infrastructure, migration, truenas, docker]
date: 2026-02-23
status: published
---

# Phase 0 + 0.5 + 0.6: Migration Preparation

## Phase 0: Pre-Migration Bug Fixes and Planning

### Status: 90% (VPS ordered, all critical bugs fixed)

Before starting the migration, several blocking issues were identified and resolved.

### Bug Fixes

| ID | Severity | Issue | Resolution |
|----|----------|-------|------------|
| CRIT-001 | Critical | Prometheus scrape targets hardcoded to old IPs | Updated all targets in NixOS config to use Tailscale IPs |
| HIGH-001 | High | NPM certificates expiring on Proxmox LXC | Migrated NPM to TrueNAS with fresh ACME certs |
| HIGH-003 | High | Docker compose files not version-controlled | Moved all compose files to dotfiles repo under system/app/docker-compose/ |
| MED-001 | Medium | Grafana dashboards not backed up | Exported all dashboards as JSON, stored in dotfiles |
| MED-002 | Medium | Uptime Kuma monitors not documented | Exported monitor list, documented in service docs |
| LOW-001 | Low | Stale DNS records in pfSense | Cleaned up DNS overrides for decommissioned services |

### VPS Order

- **Provider**: Netcup
- **Plan**: RS 4000 G12
- **Specs**: 12 cores, 32GB RAM, 1TB NVMe SSD
- **Location**: Nuremberg, Germany
- **OS**: Debian initially (replaced with NixOS in Phase 1)

### Pre-Migration Checklist

- [x] Inventory all LXC containers and their services
- [x] Document all DNS records (internal + external)
- [x] Document all Cloudflare tunnel routes
- [x] Export Prometheus recording rules and alert rules
- [x] Export Grafana dashboards
- [x] Verify backup integrity for all databases
- [x] Order VPS and confirm specs
- [x] Plan IP allocation for Tailscale and WireGuard

---

## Phase 0.5: LXC_HOME Docker Services to TrueNAS

### Status: COMPLETE

Migrated all Docker services from LXC_HOME (Proxmox LXC container at 192.168.8.80) to TrueNAS SCALE. This eliminated the largest Proxmox container and moved services closer to their storage.

### Motivation

- LXC_HOME was running 11+ Docker containers on a Proxmox LXC with NFS-mounted storage from TrueNAS
- Double network hop: client -> Proxmox -> LXC -> NFS mount -> TrueNAS
- Running Docker directly on TrueNAS eliminates one hop and uses local ZFS storage
- Media stack benefits from ZFS hardlinks (TRaSH Guides unified /data structure)

### ZFS Dataset Layout

Created dedicated ZFS datasets on `ssdpool` for Docker container configs and data:

```
ssdpool/
  docker/
    media/           # Media stack configs (Sonarr, Radarr, etc.)
    homelab/         # Homelab service configs (Calibre, EmulatorJS)
    npm/             # Nginx Proxy Manager data
    cloudflared/     # Cloudflare tunnel config
    tailscale/       # Tailscale state
    exporters/       # Monitoring exporter configs
    uptime-kuma/     # Uptime Kuma data

hddpool/
  media/
    data/
      torrents/      # Download directory (qBittorrent)
        books/
        movies/
        music/
        tv/
      media/         # Library directory (Jellyfin)
        books/
        movies/
        music/
        tv/
```

### Data Layout: Unified /data Structure (TRaSH Guides)

The media stack follows the TRaSH Guides recommended structure for hardlinks and atomic moves. All media lives under a single dataset (`hddpool/media/data`) so hardlinks work across the entire tree:

```
/data
  /torrents          # qBittorrent downloads here
    /movies
    /tv
    /music
    /books
  /media             # Jellyfin/Sonarr/Radarr library here
    /movies
    /tv
    /music
    /books
```

When Sonarr/Radarr import a completed download, they create a hardlink from `/data/torrents/tv/show.mkv` to `/data/media/tv/Show Name/Season 01/show.mkv`. This means:

- No extra disk space used for the "copy"
- Seeding continues from the torrents directory
- Deletion of either path does not affect the other (until both are removed)
- Only works within a single ZFS dataset (hardlinks cannot cross dataset boundaries)

### Migration Process

1. **Prepared TrueNAS Docker environment**
   - Enabled Docker (Apps) on TrueNAS SCALE
   - Created ZFS datasets listed above
   - Configured Docker daemon with log rotation and storage driver settings

2. **Mounted zvol locally for SSD-to-SSD copy**
   - Created a temporary zvol on ssdpool
   - Mounted it on the TrueNAS host
   - Used rsync to copy all container configs from LXC_HOME (via NFS) to local ZFS datasets
   - This avoided network bottleneck for the initial bulk copy

3. **Deployed Docker compose projects**
   - Created compose files for each project (see below)
   - Configured environment variables and volume mounts to use ZFS datasets
   - Started services and verified functionality

4. **DNS and proxy cutover**
   - Updated pfSense DNS overrides to point at TrueNAS IP (192.168.20.200)
   - Updated NPM upstream targets
   - Verified all services accessible via their domain names

5. **Shut down LXC_HOME**
   - Stopped all Docker containers on LXC_HOME
   - Shut down the LXC container
   - Verified no services were affected
   - LXC_HOME remains available for rollback but is not running

### Docker Compose Projects on TrueNAS

#### 1. Media Stack (`media/docker-compose.yml`)

9 containers for the complete media automation pipeline:

| Container | Image | Purpose | Ports |
|-----------|-------|---------|-------|
| jellyfin | jellyfin/jellyfin | Media server | 8096 |
| sonarr | linuxserver/sonarr | TV show management | 8989 |
| radarr | linuxserver/radarr | Movie management | 7878 |
| prowlarr | linuxserver/prowlarr | Indexer management | 9696 |
| bazarr | linuxserver/bazarr | Subtitle management | 6767 |
| jellyseerr | fallenbagel/jellyseerr | Request management | 5055 |
| qbittorrent | linuxserver/qbittorrent | Torrent client | 8080 |
| flaresolverr | flaresolverr/flaresolverr | Cloudflare bypass | 8191 |
| recyclarr | recyclarr/recyclarr | Quality profile sync | -- |

All containers share the unified `/data` volume mount for hardlink support.

#### 2. Homelab Stack (`homelab/docker-compose.yml`)

| Container | Image | Purpose | Ports |
|-----------|-------|---------|-------|
| calibre-web | linuxserver/calibre-web | E-book library | 8083 |
| emulatorjs | linuxserver/emulatorjs | Browser-based emulation | 3000, 80 |

#### 3. NPM (`npm/docker-compose.yml`)

| Container | Image | Purpose | Ports |
|-----------|-------|---------|-------|
| npm | jc21/nginx-proxy-manager | Reverse proxy | 80, 443, 81 |

Handles local ingress for all TrueNAS-hosted services. SSL certificates via ACME DNS challenge (Cloudflare).

#### 4. Cloudflared (`cloudflared/docker-compose.yml`)

| Container | Image | Purpose | Ports |
|-----------|-------|---------|-------|
| cloudflared | cloudflare/cloudflared | Tunnel endpoint | -- |

Routes external traffic to local services via Cloudflare tunnel. Configured with tunnel token stored in compose environment.

#### 5. Tailscale (`tailscale/docker-compose.yml`)

| Container | Image | Purpose | Ports |
|-----------|-------|---------|-------|
| tailscale | tailscale/tailscale | Subnet router | -- |

Acts as a Tailscale subnet router for the TrueNAS network (192.168.20.0/24), allowing Tailscale clients to reach TrueNAS services without direct network access.

#### 6. Exporters (`exporters/docker-compose.yml`)

| Container | Image | Purpose | Ports |
|-----------|-------|---------|-------|
| node-exporter | prom/node-exporter | Host metrics | 9100 |
| cadvisor | gcr.io/cadvisor/cadvisor | Container metrics | 8088 |
| graphite-exporter | prom/graphite-exporter | TrueNAS graphite metrics | 9108, 2003 |
| snmp-exporter | prom/snmp-exporter | Network device metrics | 9116 |

Prometheus scrapes these exporters from the monitoring stack.

#### 7. Uptime Kuma (`uptime-kuma/docker-compose.yml`)

| Container | Image | Purpose | Ports |
|-----------|-------|---------|-------|
| uptime-kuma | louislam/uptime-kuma | Local status monitoring | 3001 |

Monitors local homelab services. Separate from the VPS Uptime Kuma instance which monitors public services.

---

## Phase 0.6: Tailscale on TrueNAS + Database Fallback

### Status: PARTIAL

#### Tailscale on TrueNAS: DONE

The Tailscale Docker container on TrueNAS was deployed and configured as a subnet router. This provides:

- Remote access to all TrueNAS services via Tailscale
- Subnet routing for 192.168.20.0/24 (TrueNAS VLAN)
- Approved in Headscale admin as a subnet router
- No need for direct VPN configuration on TrueNAS host OS

#### Database Fallback: SKIPPED

The original plan included setting up a PostgreSQL fallback on TrueNAS in case the VPS database became unavailable. This was skipped because:

- VPS runs its own PostgreSQL instances per service (Plane, Matrix)
- Services that need databases have them co-located as Docker containers
- TrueNAS is not suitable as a database host (optimized for storage, not compute)
- Backup strategy covers database recovery (pg_dump to ZFS snapshots)

---

## Lessons Learned

1. **ZFS hardlinks require single dataset** -- initially created separate datasets for torrents and media, which broke hardlinks. Consolidated into `hddpool/media/data` with subdirectories.

2. **Docker on TrueNAS SCALE** -- TrueNAS SCALE uses a custom Docker/Kubernetes integration. Running plain Docker compose required disabling the built-in Apps system and using Docker directly.

3. **NPM migration** -- certificate data must be migrated alongside NPM database. Without the cert files, NPM generates new certs and existing proxy hosts fail until reissued.

4. **Tailscale subnet router** -- required `--advertise-routes` and approval in Headscale. The Docker container needs `NET_ADMIN` capability and `net.ipv4.ip_forward=1`.

5. **Rsync over NFS vs local copy** -- copying configs via NFS (LXC_HOME -> TrueNAS) was slow (~30MB/s). Mounting a temporary zvol and copying locally was significantly faster (~500MB/s).

---

## Related Documents

- [Phase 1: VPS Base Setup](phase-1-vps-base.md)
- [Migration Index](README.md)
- [TrueNAS SSD Migration](../truenas-migration-complete.md) (separate hardware event)
