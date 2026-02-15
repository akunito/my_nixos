---
id: infrastructure.services.homelab
summary: Homelab stack services - Nextcloud, Syncthing, FreshRSS, Calibre-Web, EmulatorJS
tags: [infrastructure, homelab, docker, nextcloud, syncthing]
related_files: [profiles/LXC_HOME-config.nix]
---

# Homelab Stack

Core self-hosted services running on LXC_HOME (192.168.8.80) in the `homelab_home-net` Docker network.

---

## Network Configuration

- **Docker Network**: `homelab_home-net` (172.18.0.0/16)
- **Reverse Proxy**: nginx-proxy (172.18.0.11)
- **SSL Certificates**: Shared from LXC_proxy via `/mnt/shared-certs/`

---

## Services

### Nextcloud (Cloud Storage & Collaboration)

| Property | Value |
|----------|-------|
| Container | nextcloud-app |
| Internal IP | 172.18.0.9 |
| Internal Port | 80 |
| Domain | nextcloud.local.akunito.com |
| Database | MariaDB (nextcloud-db, 172.18.0.4:3306) |
| Cache | Redis (nextcloud-redis, 172.18.0.8:6379) |
| Cron | nextcloud-cron (172.18.0.10) |

**Storage Mounts**:
- `/mnt/DATA_4TB/nextcloud/data` - User files
- `/mnt/DATA_4TB/nextcloud/config` - Configuration

**Key Features**:
- File sync and share
- Calendar & contacts (CalDAV/CardDAV)
- Collaborative document editing
- Mobile app support

---

### Syncthing (P2P File Sync)

| Property | Value |
|----------|-------|
| Container | syncthing-app |
| Internal IP | 172.18.0.2 |
| Web UI Port | 8384 |
| Sync Port | 22000 |
| Domain | syncthing.local.akunito.com |

**Direct Ports** (bypassing proxy for sync traffic):
- 22000/tcp - Sync protocol
- 21027/udp - Discovery

**Storage**:
- `/mnt/DATA_4TB/syncthing` - Synced folders

**Key Features**:
- Decentralized file sync
- No cloud dependency
- Device-to-device encryption

---

### FreshRSS (RSS Reader)

| Property | Value |
|----------|-------|
| Container | freshrss-app |
| Internal IP | 172.18.0.6 |
| Internal Port | 80 |
| Domain | freshrss.local.akunito.com |

**Storage**:
- `/mnt/DATA_4TB/freshrss/data` - Database & config

**Key Features**:
- Self-hosted RSS aggregator
- Multiple user support
- API for mobile apps (Fever, Google Reader API)

---

### Calibre-Web (E-Book Library)

| Property | Value |
|----------|-------|
| Container | calibre-web-automated |
| Internal IP | 172.18.0.7 |
| Internal Port | 8083 |
| Domain | books.local.akunito.com |

**Storage Mounts**:
- `/mnt/NFS_library/books` - Calibre library (from TrueNAS)
- `/mnt/DATA_4TB/calibre-web/config` - Configuration

**Key Features**:
- Web-based e-book reader
- OPDS catalog for e-readers
- Send to Kindle functionality
- Automatic metadata fetching

---

### EmulatorJS (Browser-Based Emulators)

| Property | Value |
|----------|-------|
| Container | emulatorjs |
| Internal IP | 172.18.0.5 |
| Internal Port | 3000 |
| Domain | emulators.local.akunito.com |

**Storage Mounts**:
- `/mnt/NFS_emulators/roms` - ROM files (from TrueNAS)
- `/mnt/DATA_4TB/emulatorjs/data` - Configuration & saves

**Supported Systems**:
- Nintendo (NES, SNES, N64, GB, GBA, DS)
- Sony (PS1)
- Sega (Genesis, Game Gear)
- And many more via RetroArch cores

---

## Obsidian Remote (Internal Only)

| Property | Value |
|----------|-------|
| Container | obsidian-remote |
| Internal IP | 172.18.0.3 |
| Ports | 3000-3001 |
| Domain | Not exposed (internal use) |

**Purpose**: Remote Obsidian vault access for specific use cases.

---

## Docker Compose Location

All homelab services are defined in:
```
LXC_HOME:~/.homelab/docker-compose.yml
```

Environment files (git-crypt encrypted):
```
LXC_HOME:~/.homelab/env/
```

---

## Maintenance Commands

```bash
# SSH to LXC_HOME
ssh akunito@192.168.8.80

# View running containers
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# View homelab network containers
docker network inspect homelab_home-net --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{println}}{{end}}'

# Restart all homelab services
cd ~/.homelab && docker compose restart

# View logs
docker logs -f nextcloud-app
docker logs -f syncthing-app
```

---

## Related Documentation

- [INFRASTRUCTURE.md](../INFRASTRUCTURE.md) - Overall infrastructure
- [INFRASTRUCTURE_INTERNAL.md](../INFRASTRUCTURE_INTERNAL.md) - Detailed internal docs
- [proxy-stack.md](./proxy-stack.md) - Reverse proxy configuration
