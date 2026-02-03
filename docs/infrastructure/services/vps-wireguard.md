---
id: infrastructure.services.vps
summary: VPS WireGuard server - VPN hub, WGUI, Cloudflare tunnel, nginx, monitoring
tags: [infrastructure, vps, wireguard, vpn, cloudflare, nginx, monitoring]
related_files: [system/app/prometheus-node-exporter.nix]
---

# VPS WireGuard Server

External VPS acting as WireGuard VPN hub and hosting external monitoring services. Located on Hetzner infrastructure.

---

## Overview

| Property | Value |
|----------|-------|
| **OS** | Ubuntu 24.04 LTS (Linux 6.8.0-55-generic) |
| **Provider** | Hetzner |
| **SSH Access** | `ssh -p 56777 root@172.26.5.155` |
| **WireGuard IP** | 172.26.5.155/24 (server) |
| **Repository** | `git@github.com:akunito/vps_wg.git` |
| **Git-crypt Key** | `/root/.git-crypt-key` |

---

## Architecture Overview

```
                              INTERNET
                                  │
          ┌───────────────────────┴───────────────────────┐
          │                                               │
          ▼                                               ▼
  ┌───────────────┐                            ┌───────────────────┐
  │  Cloudflare   │                            │   Direct Access   │
  │  Tunnel/CDN   │                            │   (SSH, WireGuard)│
  └───────┬───────┘                            └─────────┬─────────┘
          │                                              │
          │ HTTPS Tunnel                                 │ Ports: 56777, 51820
          ▼                                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       VPS (172.26.5.155)                                    │
│                                                                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │  WireGuard  │ │    WGUI     │ │    nginx    │ │ node_exporter│          │
│  │   Server    │ │  (Web UI)   │ │  (reverse)  │ │  (metrics)  │           │
│  │  :51820/udp │ │  127.0.0.1  │ │  :80/:443   │ │   :9100     │           │
│  │             │ │    :5000    │ │             │ │             │           │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘           │
│                                                                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                           │
│  │ cloudflared │ │ Uptime Kuma │ │   Postfix   │                           │
│  │  (tunnel)   │ │  (external) │ │   (relay)   │                           │
│  │  systemd    │ │   :3001     │ │  127.0.0.1  │                           │
│  │             │ │             │ │    :25      │                           │
│  └─────────────┘ └─────────────┘ └─────────────┘                           │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                                  │ WireGuard Tunnel (172.26.5.0/24)
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    pfSense (192.168.8.1)                                    │
│                    Home Network Gateway                                      │
│                    WireGuard Peer: 172.26.5.1                               │
│                    Allowed IPs: 192.168.8.0/24                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Services

### WireGuard VPN Server

**Purpose**: Central VPN hub for remote access to home network

**Configuration**:
- **Interface**: wg0
- **Server IP**: 172.26.5.155/24, fd86:ea04:1111::155/64 (dual-stack)
- **Listen Port**: 51820/udp
- **MTU**: 1280

**Connected Peers**:

| Peer | Allowed IPs | Purpose |
|------|-------------|---------|
| pfSense (Home) | 192.168.8.0/24, 172.26.5.1/32 | Home network gateway |
| Diego MacBook | 172.26.5.90/32 | Remote laptop |
| Diego Phone | 172.26.5.95/32 | Mobile device |
| Nixos VM Desk | 172.26.5.78/32 | Test VM |

**Sysctl Optimizations**:
```
net.ipv4.ip_forward = 1
net.ipv4.conf.all.src_valid_mark = 1
```

---

### WireGuard UI (WGUI)

**Purpose**: Web-based WireGuard peer management

**Configuration**:
- **Binary**: `/opt/wireguard-ui/wireguard-ui`
- **Bind Address**: 127.0.0.1:5000 (localhost only)
- **Service**: `wireguard-ui-daemon.service`
- **External Access**: https://wgui.akunito.com (via nginx + Cloudflare)

**Systemd Service**:
```ini
[Unit]
Description=WireGuard UI Daemon
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/wireguard-ui
ExecStart=/opt/wireguard-ui/wireguard-ui
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

---

### Cloudflare Tunnel

**Purpose**: Zero-trust external access without exposing ports

**Configuration**:
- **Service**: `cloudflared.service` (systemd)
- **Token Location**: Stored in systemd service file or environment
- **Exposed Services**:
  - `wgui.akunito.com` → 127.0.0.1:5000 (WireGuard UI)
  - `status.akunito.com` → 127.0.0.1:3001 (Uptime Kuma)

**Traffic Flow**:
```
Client → Cloudflare → cloudflared tunnel → nginx → backend service
```

---

### nginx Reverse Proxy

**Purpose**: SSL termination and routing for VPS services

**Status**: Native installation (not Docker)

**SSL Certificates**: Let's Encrypt (`/etc/letsencrypt/live/akunito.com/`)

**Sites Configuration** (`/etc/nginx/sites-enabled/`):

| Domain | Backend | SSL |
|--------|---------|-----|
| status.akunito.com | 127.0.0.1:3001 (Uptime Kuma) | Let's Encrypt |
| wgui.akunito.com | 127.0.0.1:5000 (WireGuard UI) | Let's Encrypt |
| Default (IP) | Return 444 (close connection) | Self-signed |

---

### Uptime Kuma (External)

**Purpose**: External monitoring of Cloudflare-exposed services

**Configuration**:
- **Container**: `uptime-kuma` (Docker, host network)
- **Port**: 3001
- **Data**: `/opt/postfix-relay/uptime-kuma-data/`
- **Access**: https://status.akunito.com

**Monitored Services**:
- Plane (plane.akunito.com)
- Portfolio (info.akunito.com)
- LeftyWorkout (leftyworkout-test.akunito.com)
- WireGuard UI (wgui.akunito.com)
- External endpoints accessible from internet

---

### Postfix Relay

**Purpose**: SMTP relay for VPS services (alerts, notifications)

**Configuration**:
- **Container**: `postfix-relay` (Docker, host network)
- **Hostname**: `vps-relay.akunito.com`
- **Relay Host**: `mail.smtp2go.com:443` (TLS wrapper)
- **Auth**: `homelab@akunito.com`
- **Security**: Localhost only (127.0.0.1), inet_interfaces=127.0.0.1

---

### Node Exporter (Prometheus)

**Purpose**: Export system metrics for monitoring

**Configuration**:
- **Port**: 9100
- **Interface**: All (accessible from WireGuard tunnel)
- **Scraped By**: LXC_monitoring Prometheus

**Monitored Metrics**:
- CPU, memory, disk usage
- Network throughput
- WireGuard interface statistics

---

## Network & Firewall

### UFW Rules

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 56777 | TCP | Any | SSH (non-standard port) |
| 51820 | UDP | Any | WireGuard VPN |
| 80 | TCP | Any | HTTP (nginx redirect) |
| 443 | TCP | Any | HTTPS (nginx) |
| 9100 | TCP | 172.26.5.0/24 | Node Exporter (WG only) |
| 3001 | TCP | localhost/IPv6 | Uptime Kuma |
| 5000 | TCP | localhost | WireGuard UI |
| 25 | TCP | localhost | Postfix |

### Listening Ports Summary

```bash
# TCP
56777  - SSH (all interfaces)
443    - nginx HTTPS (all interfaces)
80     - nginx HTTP (all interfaces)
5000   - WireGuard UI (127.0.0.1 only)
3001   - Uptime Kuma (IPv6)
25     - Postfix (127.0.0.1 only)
9100   - Node Exporter (all interfaces)

# UDP
51820  - WireGuard (all interfaces)
```

---

## Directory Structure

```
/root/
├── vps_wg/                    # Main repository (git-crypt encrypted)
│   ├── wireguard/             # WireGuard configurations
│   │   ├── wg0.conf           # Server config
│   │   └── peers/             # Peer configs
│   ├── docker-compose.yml     # Docker services
│   ├── nginx/                 # nginx site configs
│   ├── scripts/               # Maintenance scripts
│   │   ├── backup.sh
│   │   └── health-check.sh
│   └── .gitattributes         # git-crypt patterns
│
├── .git-crypt-key             # Repository encryption key
│
/opt/
├── wireguard-ui/
│   └── wireguard-ui           # WGUI binary
│
├── postfix-relay/
│   ├── docker-compose.yml     # Postfix + Uptime Kuma
│   └── uptime-kuma-data/      # Kuma persistent data
│
/etc/
├── wireguard/
│   └── wg0.conf               # Active WireGuard config
│
├── nginx/
│   └── sites-enabled/         # Active nginx sites
│       ├── status.akunito.com
│       ├── wgui.akunito.com
│       └── default
│
└── letsencrypt/
    └── live/akunito.com/      # SSL certificates
```

---

## Monitoring Integration

### Prometheus Targets (on LXC_monitoring)

The VPS is monitored via node_exporter accessible through the WireGuard tunnel:

```yaml
# In prometheus-node-exporter.nix
{
  job_name = "vps";
  static_configs = [{
    targets = ["172.26.5.155:9100"];
    labels = { instance = "vps"; };
  }];
}
```

### ICMP Monitoring

The VPS is monitored via blackbox exporter for ping availability:

```yaml
# Targets in prometheus-blackbox.nix
- vps (external IP from secrets)
- wireguard_tunnel (172.26.5.155)
```

### Grafana Dashboards

- Node Exporter Full dashboard includes VPS metrics
- Network dashboard shows WireGuard tunnel throughput

---

## Maintenance Commands

```bash
# SSH to VPS
ssh -p 56777 root@172.26.5.155

# Clone/unlock repository
cd /root
git clone git@github.com:akunito/vps_wg.git
git-crypt unlock /root/.git-crypt-key

# WireGuard commands
wg show                        # Show WireGuard status
systemctl status wg-quick@wg0  # Check service status
wg-quick down wg0 && wg-quick up wg0  # Restart WireGuard

# WireGuard UI
systemctl status wireguard-ui-daemon
journalctl -u wireguard-ui-daemon -f

# Cloudflare tunnel
systemctl status cloudflared
journalctl -u cloudflared -f

# nginx
systemctl status nginx
nginx -t                       # Test configuration
systemctl reload nginx

# Docker services (Uptime Kuma, Postfix)
cd /opt/postfix-relay
docker compose ps
docker compose logs -f

# Node exporter
curl http://localhost:9100/metrics | head -50
```

---

## Troubleshooting

### WireGuard Connection Issues

1. **Check WireGuard service**: `systemctl status wg-quick@wg0`
2. **Verify peers**: `wg show` (check latest handshake times)
3. **Test from peer**: `ping 172.26.5.155`
4. **Check UFW**: `ufw status` (ensure 51820/udp allowed)

### WGUI Not Accessible

1. **Check service**: `systemctl status wireguard-ui-daemon`
2. **Verify binding**: `ss -tlnp | grep 5000`
3. **Check nginx**: `nginx -t && systemctl status nginx`
4. **Check Cloudflare tunnel**: `systemctl status cloudflared`

### Uptime Kuma Issues

1. **Check container**: `docker ps | grep uptime-kuma`
2. **View logs**: `docker logs uptime-kuma`
3. **Verify port**: `ss -tlnp | grep 3001`

### Node Exporter Not Scraped

1. **Check service**: `curl http://172.26.5.155:9100/metrics`
2. **Verify firewall**: UFW must allow 9100 from WireGuard subnet
3. **Check Prometheus targets**: `curl http://192.168.8.85:9090/api/v1/targets`

---

## Recovery Procedures

### Fresh VPS Setup

1. **Install base packages**:
   ```bash
   apt update && apt install -y wireguard docker.io docker-compose git git-crypt nginx certbot
   ```

2. **Clone and unlock repository**:
   ```bash
   cd /root
   git clone git@github.com:akunito/vps_wg.git
   # Copy git-crypt key from secure backup
   git-crypt unlock /root/.git-crypt-key
   ```

3. **Setup WireGuard**:
   ```bash
   cp vps_wg/wireguard/wg0.conf /etc/wireguard/
   systemctl enable --now wg-quick@wg0
   ```

4. **Setup WGUI**:
   ```bash
   # Download latest wireguard-ui binary to /opt/wireguard-ui/
   # Copy systemd service file
   systemctl enable --now wireguard-ui-daemon
   ```

5. **Setup Docker services**:
   ```bash
   cd /opt/postfix-relay
   docker compose up -d
   ```

6. **Setup nginx**:
   ```bash
   cp vps_wg/nginx/* /etc/nginx/sites-enabled/
   certbot --nginx  # Or restore certs from backup
   systemctl restart nginx
   ```

7. **Setup Cloudflare tunnel**:
   ```bash
   # Install cloudflared
   # Configure tunnel token in systemd service
   systemctl enable --now cloudflared
   ```

### Restore from Backup

The git repository contains all configuration. Key files to restore manually:
- `/root/.git-crypt-key` (from secure offline backup)
- SSL certificates (can regenerate with certbot)
- WireGuard private key (in encrypted repo or backup)

---

## Security Considerations

- SSH on non-standard port (56777)
- WGUI bound to localhost only (external access via Cloudflare tunnel)
- Postfix localhost-only (no external mail relay)
- Node Exporter accessible only via WireGuard tunnel
- UFW enabled with minimal rules
- All sensitive configs in git-crypt encrypted repository

---

## Related Documentation

- [INFRASTRUCTURE.md](../INFRASTRUCTURE.md) - Overall infrastructure
- [INFRASTRUCTURE_INTERNAL.md](../INFRASTRUCTURE_INTERNAL.md) - Detailed internal configs
- [proxy-stack.md](./proxy-stack.md) - Homelab proxy (similar Cloudflare setup)
- [monitoring-stack.md](./monitoring-stack.md) - Prometheus/Grafana setup
