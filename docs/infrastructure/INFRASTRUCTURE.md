---
id: infrastructure.overview
summary: Public infrastructure overview with architecture diagram and component descriptions
tags: [infrastructure, architecture, proxmox, lxc, monitoring, homelab, pfsense, gateway]
related_files: [profiles/LXC*-config.nix, system/app/*.nix, docs/proxmox-lxc.md, docs/infrastructure/services/pfsense.md]
---

# Infrastructure Overview

This document describes the homelab infrastructure architecture, including network topology, LXC containers, services, and monitoring.

---

## Network Architecture

```
                              INTERNET
                                  │
          ┌───────────────────────┴───────────────────────┐
          │                                               │
          ▼                                               ▼
  ┌───────────────┐                            ┌───────────────────┐
  │  Cloudflare   │                            │   VPS (External)  │
  │  CDN + DNS    │                            │   WireGuard Hub   │
  │  *.akunito.com│                            │   172.26.5.0/24   │
  └───────┬───────┘                            └─────────┬─────────┘
          │                                              │
          │ Cloudflare Tunnel                            │ WireGuard
          ▼                                              ▼
  ┌─────────────────────────────────────────────────────────────────┐
  │                     pfSense Firewall                            │
  │                      192.168.8.1                                │
  │            DNS Resolver • NAT • Firewall Rules                  │
  │    *.local.akunito.com → 192.168.8.102 (NPM)                    │
  └─────────────────────────────┬───────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│ 192.168.8.0   │      │ 192.168.9.0   │      │ 192.168.20.0  │
│   Main LAN    │      │   Guest Net   │      │  Storage Net  │
│     HOME      │      │    GUEST      │      │   STORAGE     │
└───────────────┘      └───────────────┘      └───────────────┘
```

---

## pfSense Firewall (192.168.8.1)

Central network gateway providing routing, firewall, DNS, DHCP, VPN, and ad blocking.

| Service | Description |
|---------|-------------|
| **Routing** | Inter-VLAN routing (Main LAN, Guest, Storage) |
| **DNS Resolver** | Unbound with local overrides (`*.local.akunito.com` → 192.168.8.102) |
| **DHCP Server** | IP assignment for all VLANs |
| **Firewall** | Stateful packet filtering, NAT, policy-based routing |
| **WireGuard VPN** | Site-to-site tunnel with VPS (172.26.5.0/24) |
| **OpenVPN Client** | Commercial privacy VPN for specific devices |
| **pfBlockerNG** | DNS blocklists (~17M domains), IP blocklists (~16K IPs) |
| **SNMP** | Metrics export for Prometheus monitoring |

**Key DNS Override**: `*.local.akunito.com` → `192.168.8.102` (LXC_proxy NPM)

**Network Interfaces**:

| Interface | Description | Subnet |
|-----------|-------------|--------|
| ix0 (LAN) | Main LAN | 192.168.8.0/24 |
| igc0 (WAN) | Internet uplink | 192.168.1.x |
| ix0.200 (Guest) | Guest VLAN | 192.168.9.0/24 |
| lagg0 (NAS) | Storage LACP | 192.168.20.0/24 |
| tun_wg0 (WG_VPS) | WireGuard tunnel | 172.26.5.0/24 |
| ovpnc1 | OpenVPN client | 10.100.0.0/21 |

See [pfSense Documentation](./services/pfsense.md) for detailed configuration.

---

## Main LAN (192.168.8.0/24)

### Proxmox VE Hypervisor (192.168.8.82)

The Proxmox server hosts all LXC containers running NixOS.

**Network**: Two bridges - vmbr0 (1G fallback, eno1) and vmbr10 (10G LACP bond0 via USW Aggregation SFP+ 3+4). Most containers use vmbr10 for 10G connectivity. ARP flux prevention via sysctl + route metrics. See [Network Switching](./services/network-switching.md).

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PROXMOX VE (192.168.8.82)                           │
│                                                                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │  LXC_HOME   │ │ LXC_proxy   │ │LXC_monitoring│ │ LXC_mailer  │           │
│  │ 192.168.8.80│ │192.168.8.102│ │192.168.8.85 │ │192.168.8.89 │           │
│  │             │ │             │ │             │ │             │           │
│  │ • Nextcloud │ │ • cloudflared│ │ • Grafana  │ │ • Postfix   │           │
│  │ • Jellyfin  │ │ • NPM       │ │ • Prometheus│ │ • Uptime    │           │
│  │ • Syncthing │ │ • ACME      │ │ • Exporters │ │   Kuma      │           │
│  │ • *arr stack│ │             │ │             │ │             │           │
│  │ • UniFi     │ │             │ │             │ │             │           │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘           │
│                                                                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │  LXC_plane  │ │LXC_liftcraft│ │LXC_portfolio│ │LXC_database │           │
│  │192.168.8.86 │ │192.168.8.87 │ │192.168.8.88 │ │192.168.8.103│           │
│  │             │ │             │ │             │ │             │           │
│  │ • Plane     │ │ • LeftyWork │ │ • Portfolio │ │ • PostgreSQL│           │
│  │   (project  │ │   out Test  │ │   Website   │ │ • Redis     │           │
│  │   mgmt)     │ │             │ │             │ │   (central) │           │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘           │
│                                                                             │
│  ┌─────────────┐                                                            │
│  │ LXC_matrix  │                                                            │
│  │192.168.8.104│                                                            │
│  │             │                                                            │
│  │ • Synapse   │                                                            │
│  │ • Element   │                                                            │
│  │ • Claude Bot│                                                            │
│  └─────────────┘                                                            │
│                                                                             │
│  Storage: LUKS-encrypted LVM pools + NFS mounts from TrueNAS               │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Network Devices

| Device | IP | Description |
|--------|-----|-------------|
| Personal WiFi AP | 192.168.8.2 | UniFi AP for main network |
| USW Aggregation | 192.168.8.180 | 8-port SFP+ 10G aggregation switch |
| USW-24-G2 | 192.168.8.181 | 24-port 1G managed switch + 2x SFP |
| nixosaku Desktop | 192.168.8.96 | Primary workstation (10G LACP bond) |

**Switch Topology**:
```
  USW Aggregation (10G)          USW-24-G2 (1G)
  ┌──────────────────┐           ┌──────────────────┐
  │ SFP+ 3+4 → Proxmox (LACP)  │ RJ45 1-24 → LAN  │
  │ SFP+ 5   → pfSense         │ SFP 1 ◄──────────┤ 1G uplink
  │ SFP+ 6   ────────────────► │                    │
  │ SFP+ 7+8 → DESK (LACP)    │                    │
  └──────────────────┘           └──────────────────┘
```

**LACP Bond Groups**:
| Bond | Switch Ports | Host | Bandwidth |
|------|-------------|------|-----------|
| DESK | SFP+ 7+8 | nixosaku Desktop | 20 Gbps |
| Proxmox | SFP+ 3+4 | Proxmox VE | 20 Gbps |

**DAC Cables**: OFS-DAC-10G-2M (SFP+ passive, 2m)

**Known bottleneck**: USW Aggregation ↔ USW-24-G2 uplink is 1G (USW-24-G2 only has 1G SFP ports). Devices on USW-24-G2 cannot exceed 1 Gbps to 10G devices.

**Performance baselines** (2026-02-12): DESK → Proxmox 6.84 Gbps (single stream), ~9.4 Gbps (4 streams). See [Network Switching](./services/network-switching.md).

---

## LXC Container Overview

### LXC_HOME (192.168.8.80) - Homelab Services

Core self-hosted services running in Docker:

**Homelab Stack**:
- Nextcloud (cloud storage & collaboration)
- Syncthing (P2P file sync)
- FreshRSS (RSS reader)
- Calibre-Web (e-book library)
- EmulatorJS (browser-based game emulators)

**Media Stack**:
- Jellyfin (media server)
- Sonarr/Radarr/Prowlarr/Bazarr (media automation)
- Jellyseerr (request management)
- qBittorrent (torrent client via VPN)

**Network Services**:
- UniFi Controller (network management)
- nginx-proxy (internal reverse proxy)

---

### LXC_proxy (192.168.8.102) - Reverse Proxy & Tunnel

Client-facing entry point for all services:

```
            EXTERNAL ACCESS                    LOCAL ACCESS
                  │                                 │
                  ▼                                 ▼
         ┌───────────────┐                ┌───────────────┐
         │  Cloudflare   │                │    pfSense    │
         │    Tunnel     │                │      DNS      │
         └───────┬───────┘                └───────┬───────┘
                 │                                 │
                 └─────────────┬───────────────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │   LXC_proxy         │
                    │                     │
                    │  ┌───────────────┐  │
                    │  │  cloudflared  │  │  ◄── Cloudflare Tunnel daemon
                    │  └───────────────┘  │
                    │                     │
                    │  ┌───────────────┐  │
                    │  │     NPM       │  │  ◄── Nginx Proxy Manager
                    │  │  (HTTPS:443)  │  │      SSL termination
                    │  └───────────────┘  │
                    │                     │
                    │  ┌───────────────┐  │
                    │  │   acme.sh     │  │  ◄── Let's Encrypt wildcard
                    │  │   DNS-01      │  │      *.local.akunito.com
                    │  └───────────────┘  │
                    │                     │
                    └─────────┬───────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │     LXC_HOME        │
                    │    nginx-proxy      │
                    │   (service routing) │
                    └─────────────────────┘
```

**Key Features**:
- Cloudflare Tunnel for zero-trust external access
- NPM for local access with Let's Encrypt SSL
- Wildcard certificate (`*.local.akunito.com`) via DNS-01 challenge
- Certificates shared to other containers via Proxmox bind mount:
  - LXC_monitoring: `/mnt/shared-certs/` (Grafana & Prometheus SSL)

---

### LXC_monitoring (192.168.8.85) - Prometheus & Grafana

Centralized monitoring for the entire infrastructure:

```
┌─────────────────────────────────────────────────────────────────┐
│                    LXC_monitoring                                │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                      Prometheus                             │ │
│  │                     (port 9090)                            │ │
│  │                                                            │ │
│  │  Scrape Jobs:                                              │ │
│  │  ├── node_exporter (all LXC containers)                    │ │
│  │  ├── cadvisor (Docker container metrics)                   │ │
│  │  ├── blackbox_exporter (HTTP/ICMP probes)                  │ │
│  │  ├── snmp_exporter (pfSense firewall)                      │ │
│  │  └── pve_exporter (Proxmox hypervisor)                     │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                        Grafana                              │ │
│  │                      (port 3002)                           │ │
│  │                                                            │ │
│  │  Dashboards:                                               │ │
│  │  ├── Node Exporter Full (host metrics)                     │ │
│  │  ├── Docker Container Monitoring                           │ │
│  │  ├── Blackbox Exporter (probe results)                     │ │
│  │  └── Proxmox VE (VM/LXC metrics)                          │ │
│  │                                                            │ │
│  │  Alert Rules:                                              │ │
│  │  ├── Service Down (HTTP) - 2min threshold                  │ │
│  │  ├── Network Device Unreachable (ICMP) - 5min              │ │
│  │  ├── High Memory Usage - >90% for 5min                     │ │
│  │  ├── High CPU Usage - >85% for 10min                       │ │
│  │  ├── Disk Space Low - <15% for 5min                        │ │
│  │  └── Container Down - 2min threshold                       │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                       Nginx (443)                           │ │
│  │            SSL termination + reverse proxy                  │ │
│  │     Cert: /mnt/shared-certs/local.akunito.com.*            │ │
│  │     (bind mount from LXC_proxy ACME)                        │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

**Monitored Targets**:
- 6 LXC containers (Node Exporter + cAdvisor)
- 22 HTTP/HTTPS service endpoints
- 8 network devices (ICMP ping)
- pfSense firewall (SNMP)
- Proxmox hypervisor (PVE API)

---

### LXC_mailer (192.168.8.89) - Mail Relay & Uptime Kuma

**Services**:

1. **Postfix Relay**
   - Local SMTP relay for all homelab services
   - Relays to external SMTP provider (SMTP2GO)
   - Accepts mail from 192.168.8.0/24 network

2. **Uptime Kuma**
   - Alternative uptime monitoring
   - Status pages for all services
   - Accessible at http://192.168.8.89:3001

---

### Application Containers

| Container | IP | Purpose | Access |
|-----------|-----|---------|--------|
| LXC_plane | 192.168.8.86 | Plane project management (Jira/Linear alternative) | External |
| LXC_liftcraftTEST | 192.168.8.87 | LeftyWorkout test environment (training app) | External |
| LXC_portfolioprod | 192.168.8.88 | Personal portfolio website (Next.js) | External |
| LXC_database | 192.168.8.103 | Centralized PostgreSQL & Redis | Internal |
| LXC_matrix | 192.168.8.104 | Matrix Synapse, Element Web, Claude Bot | Both |

---

### LXC_database (192.168.8.103) - Centralized Database & Cache

Provides centralized PostgreSQL and Redis for all application containers.

**PostgreSQL Databases**:
| Database | Client Container |
|----------|------------------|
| plane | LXC_plane (192.168.8.86) |
| nextcloud | LXC_HOME (192.168.8.80) |
| liftcraft_test | LXC_liftcraftTEST (192.168.8.87) |
| matrix | LXC_matrix (192.168.8.104) |

**Redis Database Allocation**:
| DB | Service | Purpose |
|----|---------|---------|
| db0 | Plane | Session cache, job queue |
| db1 | Nextcloud | Distributed cache, file locking |
| db2 | LiftCraft TEST | Rails cache, Action Cable |
| db3 | Portfolio | Next.js page cache |
| db4 | Matrix Synapse | Sessions, presence |

See [Database & Redis Documentation](./services/database-redis.md) for connection details and troubleshooting.

---

## Storage Network (192.168.20.0/24)

### TrueNAS (192.168.20.200)

Network Attached Storage providing NFS shares:
- Media storage (movies, TV, music)
- Emulator ROMs
- Book library

Mounted to LXC_HOME via Proxmox bind mounts.

---

## Guest Network (192.168.9.0/24)

Isolated network for guest devices:
- Guest WiFi AP (192.168.9.2)
- No access to main LAN services
- Internet access only

---

## External Access

### VPS WireGuard Server

External VPS (Hetzner, Ubuntu 24.04) acts as the central VPN hub:

```
                              INTERNET
                                  │
          ┌───────────────────────┴───────────────────────┐
          │                                               │
          ▼                                               ▼
  ┌───────────────┐                            ┌───────────────────┐
  │  Cloudflare   │                            │   VPS (Hetzner)   │
  │    Tunnel     │                            │   172.26.5.155    │
  └───────┬───────┘                            └─────────┬─────────┘
          │                                              │
          │ Zero-trust access                            │ WireGuard :51820
          │ wgui.akunito.com                             │
          │ status.akunito.com                           │
          ▼                                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            VPS Services                                     │
│                                                                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │  WireGuard  │ │    WGUI     │ │ Uptime Kuma │ │ node_exporter│          │
│  │   Server    │ │  (mgmt UI)  │ │  (external) │ │  (metrics)  │           │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘           │
│                                                                             │
│  ┌─────────────┐ ┌─────────────┐                                           │
│  │    nginx    │ │ cloudflared │                                           │
│  │   reverse   │ │   tunnel    │                                           │
│  └─────────────┘ └─────────────┘                                           │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                                  │ WireGuard Tunnel (172.26.5.0/24)
                                  ▼
                    ┌─────────────────────────────┐
                    │   pfSense (192.168.8.1)     │
                    │   WireGuard Peer            │
                    │   Allowed: 192.168.8.0/24   │
                    └─────────────────────────────┘
```

**VPS Services**:
| Service | Purpose | Access |
|---------|---------|--------|
| WireGuard Server | VPN hub for remote access | Port 51820/udp |
| WireGuard UI (WGUI) | Peer management interface | https://wgui.akunito.com |
| Uptime Kuma | External service monitoring | https://status.akunito.com |
| nginx | SSL termination & reverse proxy | Let's Encrypt certs |
| Node Exporter | Prometheus metrics | Via WireGuard (172.26.5.155:9100) |
| Postfix Relay | SMTP for VPS alerts | localhost only |

**WireGuard Peers**:
- pfSense (home gateway) - routes to 192.168.8.0/24
- Mobile devices - direct VPN access
- Remote workstations - development access

### Cloudflare Tunnel

**Homelab Services** (via LXC_proxy cloudflared → NPM → LXC_HOME):
- Nextcloud (nextcloud.akunito.com)
- Jellyfin (jellyfin.akunito.com)
- Jellyseerr (jellyseerr.akunito.com)
- FreshRSS (freshrss.akunito.com)
- Calibre (calibre.akunito.com)
- Emulators (emulators.akunito.com)
- Obsidian (obsidian.akunito.com)

**Application Services** (via LXC_proxy cloudflared → direct):
- Plane (plane.akunito.com)
- LeftyWorkout (leftyworkout-test.akunito.com)
- Portfolio (info.akunito.com)

**Monitoring Services** (via Cloudflare Tunnel → LXC_monitoring nginx):
- Grafana (grafana.akunito.com)

**VPS Services** (via VPS cloudflared):
- WireGuard UI (wgui.akunito.com)
- Uptime Kuma (status.akunito.com)

All traffic encrypted end-to-end, no ports exposed to internet (except WireGuard UDP).

---

## Traffic Flow

### Local Access (*.local.akunito.com)

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────────┐     ┌───────────────────┐
│   Browser   │────►│   pfSense   │────►│     LXC_proxy       │────►│     LXC_HOME      │
│             │     │    DNS      │     │  NPM (192.168.8.102)│     │ nginx-proxy :443  │
└─────────────┘     └─────────────┘     └─────────────────────┘     └─────────┬─────────┘
                           │                      │                            │
                           ▼                      ▼                            ▼
                    Resolves domain        SSL termination             VIRTUAL_HOST
                   *.local.akunito.com    (Let's Encrypt cert)         routing to
                    → 192.168.8.102        from shared mount           service container
```

### External Access (*.akunito.com)

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────────┐     ┌───────────────────┐
│  Internet   │────►│  Cloudflare │────►│   cloudflared       │────►│   Application     │
│   Client    │     │   CDN/WAF   │     │   (LXC_proxy)       │     │   Container       │
└─────────────┘     └─────────────┘     └─────────────────────┘     └───────────────────┘
                           │
                           ▼
                    - DDoS protection
                    - CDN caching
                    - SSL certificate
                    - Access policies
```

---

## Service Catalog

### All Services by Access Method

| Service | Container | Local Domain | External Domain | Port |
|---------|-----------|--------------|-----------------|------|
| **Homelab Stack** |||||
| Nextcloud | LXC_HOME | nextcloud.local.akunito.com | - | 443 |
| Syncthing | LXC_HOME | syncthing.local.akunito.com | - | 443 |
| FreshRSS | LXC_HOME | freshrss.local.akunito.com | - | 443 |
| Calibre-Web | LXC_HOME | books.local.akunito.com | - | 443 |
| EmulatorJS | LXC_HOME | emulators.local.akunito.com | - | 443 |
| **Media Stack** |||||
| Jellyfin | LXC_HOME | jellyfin.local.akunito.com | - | 443 |
| Jellyseerr | LXC_HOME | jellyseerr.local.akunito.com | - | 443 |
| Sonarr | LXC_HOME | sonarr.local.akunito.com | - | 443 |
| Radarr | LXC_HOME | radarr.local.akunito.com | - | 443 |
| Prowlarr | LXC_HOME | prowlarr.local.akunito.com | - | 443 |
| Bazarr | LXC_HOME | bazarr.local.akunito.com | - | 443 |
| qBittorrent | LXC_HOME | qbittorrent.local.akunito.com | - | 443 |
| **Network & Management** |||||
| UniFi Controller | LXC_HOME | 192.168.8.206:8443 | - | 8443 |
| NPM Admin | LXC_proxy | 192.168.8.102:81 | - | 81 |
| **Monitoring** |||||
| Grafana | LXC_monitoring | grafana.local.akunito.com | grafana.akunito.com | 443 |
| Prometheus | LXC_monitoring | prometheus.local.akunito.com | - | 443 |
| Uptime Kuma (Internal) | LXC_mailer | 192.168.8.89:3001 | - | 3001 |
| **Applications** |||||
| Plane | LXC_plane | 192.168.8.86:3000 | plane.akunito.com | 3000 |
| Portfolio | LXC_portfolioprod | 192.168.8.88:3000 | info.akunito.com | 3000 |
| LeftyWorkout | LXC_liftcraftTEST | 192.168.8.87:3000/3001 | leftyworkout-test.akunito.com | 3000 |
| **Communication** |||||
| Matrix Synapse | LXC_matrix | matrix.local.akunito.com | matrix.akunito.com | 8008 |
| Element Web | LXC_matrix | element.local.akunito.com | element.akunito.com | 8080 |
| **External (VPS)** |||||
| WireGuard UI | VPS | - | wgui.akunito.com | 443 |
| Uptime Kuma (External) | VPS | - | status.akunito.com | 443 |

---

## Docker Network Isolation

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            LXC_HOME (192.168.8.80)                              │
│                                                                                 │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                        homelab_home-net (172.18.0.0/16)                    │ │
│  │                                                                            │ │
│  │   ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐        │ │
│  │   │nextcloud │ │syncthing │ │ freshrss │ │ calibre  │ │emulatorjs│        │ │
│  │   │ .9       │ │ .2       │ │ .6       │ │ .7       │ │ .5       │        │ │
│  │   └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘        │ │
│  │                                    │                                       │ │
│  │                           ┌────────┴────────┐                              │ │
│  │                           │  nginx-proxy    │                              │ │
│  │                           │  .11 (gateway)  │                              │ │
│  │                           └────────┬────────┘                              │ │
│  └────────────────────────────────────┼───────────────────────────────────────┘ │
│                                       │ (cross-network)                         │
│  ┌────────────────────────────────────┼───────────────────────────────────────┐ │
│  │                        media_mediarr-net (172.21.0.0/16)                   │ │
│  │                                    │                                       │ │
│  │   ┌──────────┐ ┌──────────┐ ┌──────┴───┐ ┌──────────┐ ┌──────────┐        │ │
│  │   │ jellyfin │ │jellyseerr│ │  sonarr  │ │  radarr  │ │ prowlarr │        │ │
│  │   │ .4       │ │ .8       │ │ .7       │ │ .6       │ │ .5       │        │ │
│  │   └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘        │ │
│  │                                                                            │ │
│  │   ┌──────────┐ ┌──────────┐ ┌──────────────────────────────────────┐      │ │
│  │   │  bazarr  │ │flaresolve│ │          gluetun (.2)                │      │ │
│  │   │ .9       │ │ .3       │ │    ┌─────────────────────────┐       │      │ │
│  │   └──────────┘ └──────────┘ │    │   qbittorrent           │       │      │ │
│  │                              │    │   (VPN-tunneled)        │       │      │ │
│  │                              │    └─────────────────────────┘       │      │ │
│  │                              └──────────────────────────────────────┘      │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                        unifi_macvlan (192.168.8.206)                       │ │
│  │   ┌──────────────────────────────────────────────────────────────┐        │ │
│  │   │         unifi-network-application (direct LAN access)        │        │ │
│  │   └──────────────────────────────────────────────────────────────┘        │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## NixOS Profile Architecture

All LXC containers use NixOS with a hierarchical profile system:

```
lib/defaults.nix (global defaults)
        │
        └─► LXC-base-config.nix (common LXC settings)
                │
                ├─► LXC_HOME-config.nix
                ├─► LXC_proxy-config.nix
                ├─► LXC_monitoring-config.nix
                ├─► LXC_plane-config.nix
                ├─► LXC_liftcraftTEST-config.nix
                ├─► LXC_portfolioprod-config.nix
                ├─► LXC_mailer-config.nix
                ├─► LXC_database-config.nix
                └─► LXC_matrix-config.nix
```

**Base Configuration** (inherited by all):
- NixOS stable branch (release-25.11)
- Docker enabled
- SSH with authorized keys
- Prometheus exporters (Node Exporter + cAdvisor)
- Weekly auto-updates (Saturday mornings, staggered)
- Email notification on update failure

---

## Security Architecture

### Network Segmentation
- Main LAN (192.168.8.0/24) - Trusted devices
- Guest Network (192.168.9.0/24) - Isolated guests
- Storage Network (192.168.20.0/24) - NAS only

### Access Control
- All external access via Cloudflare Tunnel (zero-trust)
- Internal services require LAN access or VPN
- SSH key authentication only
- Git-crypt for secrets in all repositories

### Encryption
- LUKS-encrypted storage on Proxmox
- TLS for all HTTP services
- WireGuard for VPN
- Git-crypt for configuration secrets

---

## Auto-Update Schedule

All containers update Saturday mornings (UTC):

| Time | Container |
|------|-----------|
| 06:55 | LXC_database |
| 07:00 | LXC_HOME, LXC_monitoring |
| 07:05 | LXC_proxy |
| 07:15 | LXC_plane |
| 07:25 | LXC_liftcraftTEST |
| 07:30 | LXC_portfolioprod |
| 07:35 | LXC_mailer |
| 07:40 | LXC_matrix |

Updates are staggered to prevent simultaneous service disruption.

---

## Related Documentation

- [pfSense Firewall](./services/pfsense.md) - Gateway, DNS, VPN, and firewall configuration
- [Proxmox LXC Guide](../proxmox-lxc.md) - LXC container setup on Proxmox
- [LXC Deployment](../lxc-deployment.md) - Deploying NixOS to LXC
- [Grafana & Alerting](../setup/grafana-dashboards-alerting.md) - Monitoring configuration
- [Git-Crypt Secrets](../security/git-crypt.md) - Secrets management
- [Profile Feature Flags](../profile-feature-flags.md) - NixOS profile configuration
- [VPS WireGuard Server](./services/vps-wireguard.md) - External VPS documentation
- [Database & Redis](./services/database-redis.md) - Centralized PostgreSQL and Redis services
- [Matrix Server](./services/matrix.md) - Matrix Synapse, Element, and Claude Bot
- [Network Switching](./services/network-switching.md) - 10GbE switching layer, LACP bonds, ARP flux
