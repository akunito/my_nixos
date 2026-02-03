---
id: infrastructure.overview
summary: Public infrastructure overview with architecture diagram and component descriptions
tags: [infrastructure, architecture, proxmox, lxc, monitoring, homelab]
related_files: [profiles/LXC*-config.nix, system/app/*.nix, docs/proxmox-lxc.md]
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

## Main LAN (192.168.8.0/24)

### Proxmox VE Hypervisor (192.168.8.82)

The Proxmox server hosts all LXC containers running NixOS:

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
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                           │
│  │  LXC_plane  │ │LXC_liftcraft│ │LXC_portfolio│                           │
│  │192.168.8.86 │ │192.168.8.87 │ │192.168.8.88 │                           │
│  │             │ │             │ │             │                           │
│  │ • Plane     │ │ • LeftyWork │ │ • Portfolio │                           │
│  │   (project  │ │   out Test  │ │   Website   │                           │
│  │   mgmt)     │ │             │ │             │                           │
│  └─────────────┘ └─────────────┘ └─────────────┘                           │
│                                                                             │
│  Storage: LUKS-encrypted LVM pools + NFS mounts from TrueNAS               │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Network Devices

| Device | IP | Description |
|--------|-----|-------------|
| Personal WiFi AP | 192.168.8.2 | UniFi AP for main network |
| USW-Aggregation | 192.168.8.180 | 10G aggregation switch |
| USW-24-G2 | 192.168.8.181 | 24-port managed switch |
| nixosaku Desktop | DHCP | Primary workstation |

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
- Wildcard certificate via DNS-01 challenge
- Certificates shared to other containers via Proxmox bind mount

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
│  │                       Nginx                                 │ │
│  │            SSL termination + reverse proxy                  │ │
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

### VPN (WireGuard)

- External VPS acts as WireGuard hub
- Home network accessible via tunnel (172.26.5.0/24)
- Remote access to all internal services

### Cloudflare Tunnel

Selected services exposed via Cloudflare:
- Plane (project management)
- LeftyWorkout (training app)
- Portfolio (personal website)
- WireGuard UI

All traffic encrypted end-to-end, no ports exposed to internet.

---

## Traffic Flow

### Local Access (*.local.akunito.com)

```
Browser → pfSense DNS → NPM (192.168.8.102:443) → nginx-proxy (192.168.8.80:443) → Service
                ↓                    ↓                        ↓
           Resolves to          HTTPS/TLS              Host-based routing
          192.168.8.102     (Let's Encrypt)           via VIRTUAL_HOST
```

### External Access (*.akunito.com)

```
Browser → Cloudflare → cloudflared tunnel → NPM → nginx-proxy → Service
                ↓
          CDN caching + WAF
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
                └─► LXC_mailer-config.nix
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
| 07:00 | LXC_HOME, LXC_monitoring |
| 07:05 | LXC_proxy |
| 07:15 | LXC_plane |
| 07:25 | LXC_liftcraftTEST |
| 07:30 | LXC_portfolioprod |
| 07:35 | LXC_mailer |

Updates are staggered to prevent simultaneous service disruption.

---

## Related Documentation

- [Proxmox LXC Guide](../proxmox-lxc.md) - LXC container setup on Proxmox
- [LXC Deployment](../lxc-deployment.md) - Deploying NixOS to LXC
- [Grafana & Alerting](../setup/grafana-dashboards-alerting.md) - Monitoring configuration
- [Git-Crypt Secrets](../security/git-crypt.md) - Secrets management
- [Profile Feature Flags](../profile-feature-flags.md) - NixOS profile configuration
