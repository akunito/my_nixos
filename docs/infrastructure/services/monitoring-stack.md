---
id: infrastructure.services.monitoring
summary: Monitoring stack - Prometheus, Grafana, exporters, alerting
tags: [infrastructure, monitoring, prometheus, grafana, alerting]
related_files: [profiles/LXC_monitoring-config.nix, system/app/grafana.nix, system/app/prometheus-*.nix]
---

# Monitoring Stack

Centralized monitoring running on LXC_monitoring (192.168.8.85) using NixOS native services.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        LXC_monitoring (192.168.8.85)                        │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                          Prometheus (9090)                           │   │
│  │                                                                      │   │
│  │   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐               │   │
│  │   │   Scrape     │ │   Scrape     │ │   Scrape     │               │   │
│  │   │   Node       │ │   cAdvisor   │ │   Blackbox   │               │   │
│  │   │   Exporters  │ │   (Docker)   │ │   (HTTP/ICMP)│               │   │
│  │   └──────────────┘ └──────────────┘ └──────────────┘               │   │
│  │                                                                      │   │
│  │   ┌──────────────┐ ┌──────────────┐                                 │   │
│  │   │   Scrape     │ │   Scrape     │                                 │   │
│  │   │   SNMP       │ │   PVE        │                                 │   │
│  │   │   (pfSense)  │ │   (Proxmox)  │                                 │   │
│  │   └──────────────┘ └──────────────┘                                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                          Grafana (3002)                              │   │
│  │                                                                      │   │
│  │   Dashboards: Node Exporter, Docker, Blackbox, Proxmox              │   │
│  │   Alerts: → SMTP relay (192.168.8.89:25)                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                          Nginx (443)                                 │   │
│  │              SSL termination for Grafana & Prometheus                │   │
│  │         Cert: /mnt/shared-certs/local.akunito.com.*                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Access URLs

| Service | URL | Auth |
|---------|-----|------|
| Grafana | https://grafana.local.akunito.com | Admin login |
| Prometheus | https://prometheus.local.akunito.com | Basic auth + IP whitelist |

**SSL Certificate**: Uses `*.local.akunito.com` wildcard certificate from LXC_proxy ACME, mounted at `/mnt/shared-certs/` via Proxmox bind mount.

---

## Prometheus Configuration

### Scrape Targets

#### Node Exporter (Port 9100)
System metrics from all LXC containers:

| Target | IP |
|--------|-----|
| lxc_home | 192.168.8.80:9100 |
| lxc_proxy | 192.168.8.102:9100 |
| lxc_plane | 192.168.8.86:9100 |
| lxc_liftcraft | 192.168.8.87:9100 |
| lxc_portfolio | 192.168.8.88:9100 |
| lxc_mailer | 192.168.8.89:9100 |

#### cAdvisor (Port 9092)
Docker container metrics from same targets.

#### Blackbox Exporter - HTTP Probes

**Local Services** (via LAN):
- Jellyfin, Jellyseerr, Nextcloud
- Radarr, Sonarr, Bazarr, Prowlarr
- Syncthing, Calibre, Emulators
- UniFi, Grafana, Prometheus

**Cloudflare-Exposed Services**:
- Plane (plane.akunito.com)
- LeftyWorkout (leftyworkout.akunito.com)
- Portfolio (info.akunito.com)
- WireGuard UI (wgui.akunito.com)

**Local HTTP**:
- Uptime Kuma (192.168.8.89:3001)

#### Blackbox Exporter - ICMP Probes
Network device availability:

| Target | IP |
|--------|-----|
| proxy | 192.168.8.102 |
| truenas | 192.168.20.200 |
| guest_wifi_ap | 192.168.9.2 |
| personal_wifi_ap | 192.168.8.2 |
| switch_usw_24_g2 | 192.168.8.181 |
| switch_usw_aggregation | 192.168.8.180 |
| vps | (from secrets) |
| wireguard_tunnel | 172.26.5.155 |

#### SNMP Exporter
pfSense firewall metrics:
- **Target**: 192.168.8.1
- **Module**: pfsense
- **Community**: From `secrets.snmpCommunity`

#### PVE Exporter
Proxmox hypervisor metrics:
- **Target**: 192.168.8.82
- **API User**: `prometheus@pve` (PVEAuditor role)
- **Token**: `/etc/secrets/pve-token`

---

## Exporters (Local Services)

Running on LXC_monitoring:

| Service | Port | Purpose |
|---------|------|---------|
| Node Exporter | 9091 | Monitoring server's own metrics |
| Blackbox Exporter | 9115 | HTTP/ICMP probes |
| SNMP Exporter | 9116 | SNMP polling (pfSense) |
| PVE Exporter | 9221 | Proxmox API metrics |

---

## Grafana Dashboards

### Installed Dashboards

1. **Node Exporter Full** (ID: 1860)
   - CPU, memory, disk, network per host
   - System load and processes

2. **Docker Container Monitoring**
   - Container CPU, memory, network
   - Container health status

3. **Blackbox Exporter** (HTTP/TLS services)
   - HTTP response times
   - SSL certificate expiry
   - Service availability (Jellyfin, Nextcloud, *arr, etc.)

4. **Infrastructure Status** (ICMP network devices) *Custom*
   - Network device ping status (switches, APs, NAS, VPS)
   - Latency monitoring
   - Quick status overview grid

5. **Proxmox VE**
   - VM/LXC resource usage
   - Cluster health

6. **pfSense Firewall** *Custom*
   - PF status and state table
   - Interface traffic (WAN, LAN, GUEST, WG_VPS, NAS)
   - Interface errors

7. **TrueNAS** *Custom*
   - ZFS pool status and ARC stats
   - CPU, memory, disk I/O
   - Network traffic

8. **Media Stack** *Custom*
   - Sonarr/Radarr queue status
   - Health issues monitoring

---

## Alert Rules

| Alert | Condition | Duration |
|-------|-----------|----------|
| Service Down (HTTP) | probe_success == 0 | 2 minutes |
| Network Device Unreachable (ICMP) | probe_success == 0 | 5 minutes |
| High Memory Usage | memory_used > 90% | 5 minutes |
| High CPU Usage | cpu_usage > 85% | 10 minutes |
| Disk Space Low | disk_free < 15% | 5 minutes |
| Container Down | container_running == 0 | 2 minutes |

### Alert Notification
- **Contact Point**: SMTP (192.168.8.89:25 → LXC_mailer)
- **Recipient**: Configured in Grafana alert rules

---

## NixOS Configuration Files

```
~/.dotfiles/system/app/
├── grafana.nix              # Grafana service config
├── prometheus.nix           # Core Prometheus config
├── prometheus-blackbox.nix  # Blackbox exporter + probes
├── prometheus-snmp.nix      # SNMP exporter for pfSense
└── prometheus-pve.nix       # Proxmox VE exporter
```

---

## Maintenance Commands

```bash
# View service status
systemctl status prometheus grafana

# View Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'

# View alert rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups'

# Test SNMP exporter
curl 'http://localhost:9116/snmp?target=192.168.8.1&module=pfsense'

# Test Blackbox HTTP probe
curl 'http://localhost:9115/probe?target=https://jellyfin.local.akunito.com&module=http_2xx'

# Reload Prometheus config
systemctl reload prometheus
```

---

## Troubleshooting

### Target Shows as Down
1. Check network connectivity: `ping <target_ip>`
2. Verify exporter is running on target
3. Check firewall rules on target

### SNMP Not Working
1. Verify SNMP service on pfSense
2. Check community string matches secrets
3. Test manually: `snmpwalk -v2c -c <community> 192.168.8.1`

### Alerts Not Firing
1. Check alert rules in Grafana
2. Verify SMTP relay is working
3. Check Grafana logs: `journalctl -u grafana`

---

## Related Documentation

- [grafana-dashboards-alerting.md](../../setup/grafana-dashboards-alerting.md) - Detailed setup guide
- [INFRASTRUCTURE_INTERNAL.md](../INFRASTRUCTURE_INTERNAL.md) - All monitoring targets
- [proxy-stack.md](./proxy-stack.md) - SSL termination for monitoring
