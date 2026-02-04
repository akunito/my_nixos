---
id: setup.grafana-dashboards
summary: Comprehensive reference for all Grafana dashboards including metrics sources, panel specifications, alert rules, and verification procedures.
tags:
  - grafana
  - prometheus
  - dashboards
  - monitoring
  - alerting
  - metrics
  - truenas
  - wireguard
  - pfsense
  - exportarr
related_files:
  - system/app/grafana.nix
  - system/app/prometheus-*.nix
  - profiles/LXC_monitoring-config.nix
  - docs/setup/grafana-dashboards-alerting.md
---

# Grafana Dashboard Reference

This document provides a comprehensive reference for all Grafana dashboards in the homelab monitoring stack, including available metrics, panel specifications, alert rules, and verification procedures.

## Quick Reference

| # | Dashboard | Grafana ID | Metrics Source | Targets |
|---|-----------|------------|----------------|---------|
| 1 | Node Exporter Full | 1860 | node_exporter | 8 hosts |
| 2 | Docker Container Monitoring | 893 | cAdvisor | 6 LXC hosts |
| 3 | Blackbox Exporter | 7587 | blackbox | 17 HTTP, 2 TLS |
| 4 | Infrastructure Status | *Custom* | blackbox (ICMP) | 8 network devices |
| 5 | Proxmox VE | 10347 | pve_exporter | 1 hypervisor |
| 6 | WireGuard | *Custom* | node_exporter (textfile) | 1 VPS |
| 7 | TrueNAS | *Custom* | graphite_exporter | 1 NAS |
| 8 | pfSense | *Custom* | snmp_exporter | 1 firewall |
| 9 | Media Stack (*arr) | *Custom* | exportarr | 4 apps |

---

## Infrastructure Overview

### Monitoring Server
- **Host**: LXC_monitoring (192.168.8.85)
- **Grafana URL**: https://grafana.local.akunito.com
- **Prometheus URL**: https://prometheus.local.akunito.com (basic auth required)
- **SMTP Relay**: 192.168.8.89:25 (LXC_mailer)

### Prometheus Targets Summary

| Category | Job Pattern | Count | Port |
|----------|-------------|-------|------|
| Node Exporters | `*_node` | 8 | 9100/9091 |
| cAdvisor | `*_docker` | 6 | 9092 |
| Blackbox HTTP | `blackbox_http_*` | 17 | 9115 |
| Blackbox ICMP | `blackbox_icmp_*` | 8 | 9115 |
| Blackbox TLS | `blackbox_tls_*` | 2 | 9115 |
| SNMP (pfSense) | `snmp_pfsense` | 1 | 9116 |
| PVE Exporter | `proxmox` | 1 | 9221 |
| Graphite (TrueNAS) | `truenas_graphite` | 1 | 9109 |
| Exportarr | `*_app` | 4 | 9707-9710 |

---

## 1. Node Exporter Full (ID: 1860)

### Purpose
Comprehensive host-level system metrics monitoring for all Linux hosts.

### Data Source
- **Exporter**: Node Exporter
- **Jobs**: `monitoring_node`, `lxc_home_node`, `lxc_proxy_node`, `lxc_plane_node`, `lxc_liftcraft_node`, `lxc_portfolio_node`, `lxc_mailer_node`, `vps_wireguard_node`

### Monitored Hosts

| Instance | IP Address | Port | Description |
|----------|------------|------|-------------|
| monitoring | 127.0.0.1 | 9091 | Monitoring server itself |
| lxc_home | 192.168.8.80 | 9100 | Main homelab services |
| lxc_proxy | 192.168.8.102 | 9100 | Cloudflare tunnel + NPM |
| lxc_plane | 192.168.8.86 | 9100 | Plane project management |
| lxc_liftcraft | 192.168.8.87 | 9100 | LeftyWorkout test |
| lxc_portfolio | 192.168.8.88 | 9100 | Portfolio website |
| lxc_mailer | 192.168.8.89 | 9100 | Email relay + Uptime Kuma |
| vps_wireguard | 172.26.5.155 | 9100 | VPS (via WireGuard tunnel) |

### Key Panels
- CPU Usage (all modes: user, system, iowait, idle)
- Memory Usage (used, cached, available, buffers)
- Disk I/O (read/write bytes, IOPS)
- Disk Space (per mountpoint)
- Network Throughput (bytes in/out per interface)
- System Load (1m, 5m, 15m)
- Systemd Service Status

### Variables
- `job`: Select specific host (regex: `.*_node`)
- `node`: Host selector dropdown

### Associated Alerts

| Alert | Expression | For | Severity |
|-------|------------|-----|----------|
| HostMemoryHigh | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90` | 5m | warning |
| HostCPUHigh | `100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85` | 10m | warning |
| HostDiskSpaceLow | `(node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15` | 5m | warning |
| HostDiskSpaceCritical | `(node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 5` | 2m | critical |
| HostDown | `up{job=~".*_node"} == 0` | 2m | critical |

### Verification
```bash
# Test node exporter connectivity
curl -s http://192.168.8.80:9100/metrics | head -5

# Check all node targets in Prometheus
curl -s 'http://127.0.0.1:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job | test("_node$")) | {job: .labels.job, health: .health}'
```

---

## 2. Docker Container Monitoring (ID: 893)

### Purpose
Container resource usage monitoring via cAdvisor metrics.

### Data Source
- **Exporter**: cAdvisor
- **Jobs**: `lxc_home_docker`, `lxc_proxy_docker`, `lxc_plane_docker`, `lxc_liftcraft_docker`, `lxc_portfolio_docker`, `lxc_mailer_docker`

### Monitored Hosts

| Instance | IP Address | Port | Containers |
|----------|------------|------|------------|
| lxc_home | 192.168.8.80 | 9092 | Homelab stack (Jellyfin, Nextcloud, *arr, etc.) |
| lxc_proxy | 192.168.8.102 | 9092 | NPM, Cloudflared |
| lxc_plane | 192.168.8.86 | 9092 | Plane stack |
| lxc_liftcraft | 192.168.8.87 | 9092 | LeftyWorkout stack |
| lxc_portfolio | 192.168.8.88 | 9092 | Portfolio stack |
| lxc_mailer | 192.168.8.89 | 9092 | Postfix, Uptime Kuma |

### Key Panels
- Container CPU Usage (per container)
- Container Memory Usage (usage vs limit)
- Container Memory Percentage
- Container Network I/O (bytes in/out)
- Container Restart Count
- Container Last Seen

### Key Metrics

| Metric | Description |
|--------|-------------|
| `container_cpu_usage_seconds_total` | Total CPU time consumed |
| `container_memory_usage_bytes` | Current memory usage |
| `container_spec_memory_limit_bytes` | Memory limit |
| `container_network_receive_bytes_total` | Network bytes received |
| `container_network_transmit_bytes_total` | Network bytes transmitted |
| `container_cpu_cfs_throttled_seconds_total` | CPU throttling time |

### Variables
- `container`: Container name selector
- `instance`: Host selector

### Associated Alerts

| Alert | Expression | For | Severity |
|-------|------------|-----|----------|
| ContainerMemoryHigh | `(container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100 > 85` | 5m | warning |
| ContainerMemoryCritical | `(container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100 > 95` | 2m | critical |
| ContainerCPUThrottling | `rate(container_cpu_cfs_throttled_seconds_total[5m]) > 0.5` | 10m | warning |
| ContainerRestarting | `increase(container_restart_count[1h]) > 3` | 5m | warning |
| ContainerDown | `absent(container_memory_usage_bytes{name=~".+"})` | 2m | critical |

### Verification
```bash
# Test cAdvisor connectivity
curl -s http://192.168.8.80:9092/metrics | grep container_memory_usage_bytes | head -5

# List all containers with metrics
curl -s 'http://127.0.0.1:9090/api/v1/query?query=container_memory_usage_bytes{name!=""}' | jq '.data.result[] | .metric.name'
```

---

## 3. Blackbox Exporter (ID: 7587)

### Purpose
Service availability monitoring via HTTP/HTTPS probes and TLS certificate expiry monitoring. ICMP probes are displayed in the separate Infrastructure Status dashboard.

### Data Source
- **Exporter**: Blackbox Exporter (port 9115)
- **Jobs**: `blackbox_http_*`, `blackbox_tls_*`
- **Variable Filter**: Only shows HTTP/TLS targets (ICMP filtered out)

### HTTP/HTTPS Probes (17 targets)

| Instance | URL | Module |
|----------|-----|--------|
| jellyfin | https://jellyfin.local.akunito.com | http_2xx |
| jellyseerr | https://jellyseerr.local.akunito.com | http_2xx |
| nextcloud | https://nextcloud.local.akunito.com | http_2xx |
| radarr | https://radarr.local.akunito.com | http_2xx |
| sonarr | https://sonarr.local.akunito.com | http_2xx |
| bazarr | https://bazarr.local.akunito.com | http_2xx |
| prowlarr | https://prowlarr.local.akunito.com | http_2xx |
| syncthing | https://syncthing.local.akunito.com | http_2xx |
| calibre | https://books.local.akunito.com | http_2xx |
| emulators | https://emulators.local.akunito.com | http_2xx |
| unifi | https://192.168.8.206:8443/ | http_2xx |
| grafana | https://grafana.local.akunito.com | http_2xx |
| prometheus | https://prometheus.local.akunito.com | http_2xx |
| plane | https://plane.akunito.org.es | http_2xx |
| leftyworkout | https://leftyworkout-test.akunito.org.es | http_2xx |
| portfolio | https://info.akunito.org.es | http_2xx |
| wgui | https://wgui.akunito.org.es | http_2xx |
| kuma | http://192.168.8.89:3001 | http_2xx_nossl |

### ICMP Probes (8 targets)

| Instance | Host | Description |
|----------|------|-------------|
| proxy | 192.168.8.102 | Cloudflare tunnel + NPM |
| truenas | 192.168.20.200 | TrueNAS NAS |
| guest_wifi_ap | 192.168.9.2 | Guest WiFi AP |
| personal_wifi_ap | 192.168.8.2 | Personal WiFi AP |
| switch_usw_24_g2 | 192.168.8.181 | UniFi Switch 24 |
| switch_usw_aggregation | 192.168.8.180 | UniFi Aggregation Switch |
| vps | (external IP) | VPS external |
| wireguard_tunnel | 172.26.5.155 | VPS via WireGuard |

### TLS Certificate Probes (2 targets)

| Instance | Host | Purpose |
|----------|------|---------|
| local_wildcard | nextcloud.local.akunito.com:443 | Local wildcard cert |
| monitoring_cert | grafana.local.akunito.com:443 | Monitoring cert |

### Key Metrics

| Metric | Description |
|--------|-------------|
| `probe_success` | 1 if probe succeeded, 0 otherwise |
| `probe_duration_seconds` | Total probe duration |
| `probe_http_status_code` | HTTP response status code |
| `probe_ssl_earliest_cert_expiry` | Unix timestamp of certificate expiry |

### Key Panels
- Service Status Grid (colored by probe_success)
- Response Time Graph (probe_duration_seconds)
- SSL Certificate Expiry (days remaining)
- Network Device Status (ICMP)
- HTTP Status Codes

### Variables
- `instance`: Target selector
- `job`: Probe type (http/icmp/tls)

### Associated Alerts

| Alert | Expression | For | Severity |
|-------|------------|-----|----------|
| SSLCertExpiringSoon | `(probe_ssl_earliest_cert_expiry - time()) / 86400 < 14` | 1h | warning |
| SSLCertExpiryCritical | `(probe_ssl_earliest_cert_expiry - time()) / 86400 < 7` | 1h | critical |

### Verification
```bash
# Test HTTP probe
curl -s 'http://127.0.0.1:9115/probe?module=http_2xx&target=https://jellyfin.local.akunito.com' | grep probe_success

# Test ICMP probe
curl -s 'http://127.0.0.1:9115/probe?module=icmp&target=192.168.20.200' | grep probe_success

# Check SSL expiry (days remaining)
curl -s 'http://127.0.0.1:9090/api/v1/query?query=(probe_ssl_earliest_cert_expiry-time())/86400' | jq '.data.result[] | {instance: .metric.instance, days: .value[1]}'
```

---

## 4. Infrastructure Status (Custom)

### Purpose
Network infrastructure ICMP ping monitoring for switches, access points, NAS, VPS, and WireGuard tunnel. Provides a quick status overview separate from HTTP service monitoring.

### Data Source
- **Exporter**: Blackbox Exporter (port 9115)
- **Jobs**: `blackbox_icmp_*`

### ICMP Probes (8 targets)

| Instance | Host | Description |
|----------|------|-------------|
| proxy | 192.168.8.102 | Cloudflare tunnel + NPM |
| truenas | 192.168.20.200 | TrueNAS NAS |
| guest_wifi_ap | 192.168.9.2 | Guest WiFi AP |
| personal_wifi_ap | 192.168.8.2 | Personal WiFi AP |
| switch_usw_24_g2 | 192.168.8.181 | UniFi Switch 24 |
| switch_usw_aggregation | 192.168.8.180 | UniFi Aggregation Switch |
| vps | (external IP) | VPS external |
| wireguard_tunnel | 172.26.5.155 | VPS via WireGuard |

### Key Metrics

| Metric | Description |
|--------|-------------|
| `probe_success` | 1 if ping succeeded, 0 otherwise |
| `probe_duration_seconds` | Ping latency |

### Panels

| Panel | Metric/Query | Visualization |
|-------|--------------|---------------|
| Status Overview | `probe_success{job=~"blackbox_icmp_.*"}` | Stat (colored UP/DOWN) |
| Status Over Time | `probe_success{job=~"blackbox_icmp_.*"}` | Time series (step) |
| Ping Response Time | `probe_duration_seconds{job=~"blackbox_icmp_.*"}` | Time series |
| Current Latency | `probe_duration_seconds{job=~"blackbox_icmp_.*"}` | Stat with sparkline |
| Details Table | `probe_success` + `probe_duration_seconds` | Table (merged) |

### Dashboard File
- **Path**: `system/app/grafana-dashboards/custom/infrastructure-status.json`
- **UID**: `infrastructure-status`

### Verification
```bash
# Test ICMP probes
curl -s 'http://127.0.0.1:9115/probe?module=icmp&target=192.168.20.200' | grep probe_success

# Check all ICMP targets
curl -s 'http://127.0.0.1:9090/api/v1/query?query=probe_success{job=~"blackbox_icmp_.*"}' | jq '.data.result[] | {instance: .metric.instance, status: .value[1]}'
```

---

## 5. Proxmox VE (ID: 10347)

### Purpose
Proxmox hypervisor and VM/LXC monitoring.

### Data Source
- **Exporter**: PVE Exporter (port 9221)
- **Job**: `proxmox`

### Target

| Instance | IP Address | API User |
|----------|------------|----------|
| proxmox | 192.168.8.82 | prometheus@pve |

### Key Metrics

| Metric | Description |
|--------|-------------|
| `pve_node_info` | Node information |
| `pve_cpu_usage_ratio` | CPU usage ratio |
| `pve_memory_usage_bytes` | Memory usage |
| `pve_disk_usage_bytes` | Disk usage |
| `pve_guest_info` | VM/LXC information |
| `pve_up` | Target availability |

### Key Panels
- Node CPU/Memory Usage
- VM/LXC Status Grid
- Storage Usage
- Network Traffic per VM
- Cluster Health

### Variables
- `node`: Proxmox node selector
- `vmid`: VM/LXC ID selector

### Verification
```bash
# Test PVE exporter
curl -s http://127.0.0.1:9221/pve?target=192.168.8.82 | head -20

# Check Proxmox target health
curl -s 'http://127.0.0.1:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job == "proxmox")'
```

---

## 6. WireGuard Dashboard (Custom)

### Purpose
VPN tunnel status and peer monitoring for the VPS WireGuard server.

### Data Source
- **Exporter**: Node Exporter with textfile collector on VPS
- **Job**: `vps_wireguard_node`
- **Metrics Path**: `/var/lib/prometheus/node-exporter/wireguard.prom`

### Target

| Instance | IP Address | Access |
|----------|------------|--------|
| vps_wireguard | 172.26.5.155 | Via WireGuard tunnel |

### Custom Metrics (textfile)

| Metric | Description |
|--------|-------------|
| `wireguard_interface_up` | 1 if wg0 interface is up |
| `wireguard_active_peers` | Number of peers with recent handshake |
| `wireguard_pfsense_connected` | 1 if pfSense peer is connected |

### Standard Metrics (node_exporter)

| Metric | Description |
|--------|-------------|
| `node_network_receive_bytes_total{device="wg0"}` | WireGuard bytes received |
| `node_network_transmit_bytes_total{device="wg0"}` | WireGuard bytes transmitted |

### Recommended Panels

| Panel | Metric/Query | Visualization |
|-------|--------------|---------------|
| Interface Status | `wireguard_interface_up` | Stat (green/red) |
| Active Peers | `wireguard_active_peers` | Gauge |
| pfSense Tunnel Status | `wireguard_pfsense_connected` | Stat (green/red) |
| Tunnel Traffic In | `rate(node_network_receive_bytes_total{device="wg0"}[5m])` | Time series |
| Tunnel Traffic Out | `rate(node_network_transmit_bytes_total{device="wg0"}[5m])` | Time series |
| Total Traffic | `increase(node_network_receive_bytes_total{device="wg0"}[24h])` | Stat |

### Associated Alerts

| Alert | Expression | For | Severity |
|-------|------------|-----|----------|
| WireGuardInterfaceDown | `wireguard_interface_up == 0` | 1m | critical |
| WireGuardPfSenseDisconnected | `wireguard_pfsense_connected == 0` | 2m | critical |
| WireGuardNoPeers | `wireguard_active_peers == 0` | 5m | warning |

### Verification
```bash
# Check WireGuard metrics on VPS
ssh -A -p 56777 root@172.26.5.155 'curl -s http://localhost:9100/metrics | grep wireguard'

# Query WireGuard metrics from Prometheus
curl -s 'http://127.0.0.1:9090/api/v1/query?query=wireguard_interface_up' | jq
```

---

## 7. TrueNAS Dashboard (Custom)

### Purpose
NAS storage health, ZFS pool status, disk temperatures, and filesystem usage monitoring.

### Data Source
- **Exporter**: Graphite Exporter (port 9109)
- **Input**: TrueNAS Graphite push to port 2003
- **Job**: `truenas_graphite`

### Target

| Instance | IP Address | Protocol |
|----------|------------|----------|
| truenas | 192.168.20.200 | Graphite (push) |

### Key Metrics (Graphite naming convention)

| Metric | Description |
|--------|-------------|
| `truenas_system_cpu_user` | CPU user time |
| `truenas_system_cpu_system` | CPU system time |
| `truenas_system_ram_used` | RAM used (bytes) |
| `truenas_system_ram_free` | RAM free (bytes) |
| `truenas_zfs_actual_hits_hits` | ZFS ARC hits |
| `truenas_zfs_actual_hits_misses` | ZFS ARC misses |
| `truenas_zfspool_state_{pool}_online` | ZFS pool online status |
| `truenas_zfs_arc_size_size` | ZFS ARC size (bytes) |
| `truenas_system_net_received` | Network bytes received |
| `truenas_system_net_sent` | Network bytes sent |
| `truenas_cputemp_temperatures_{cpu}` | CPU temperature |
| `truenas_system_load_load1/5/15` | System load averages |
| `truenas_system_io_in/out` | Disk I/O |

### Dashboard Panels

| Panel | Metric/Query | Visualization |
|-------|--------------|---------------|
| CPU Usage | `truenas_system_cpu_user + truenas_system_cpu_system` | Gauge (%) |
| Memory Usage | `truenas_system_ram_used / (used + free) * 100` | Gauge (%) |
| ZFS ARC Hit Rate | `truenas_zfs_actual_hits_hits / (hits + misses) * 100` | Gauge (%) |
| ZFS Pool Status | `truenas_zfspool_state_{pool}_online` | Stat (ONLINE/OFFLINE) |
| ZFS ARC Size | `truenas_zfs_arc_size_size` | Stat (bytes) |
| Memory Over Time | `truenas_system_ram_used/free` | Time series (stacked) |
| Network Traffic | `truenas_system_net_received/sent` | Time series |
| CPU Temperature | `truenas_cputemp_temperatures_*` | Stat with thresholds |
| System Load | `truenas_system_load_load1/5/15` | Time series |
| Disk I/O | `truenas_system_io_in/out` | Time series |

### Dashboard File
- **Path**: `system/app/grafana-dashboards/custom/truenas.json`
- **UID**: `truenas-graphite`

### Variables
- `datasource`: Prometheus data source selector

### Associated Alerts

| Alert | Expression | For | Severity |
|-------|------------|-----|----------|
| TrueNASFilesystemCapacityWarning | `(used / (used + free)) * 100 > 80` | 5m | warning |
| TrueNASFilesystemCapacityCritical | `(used / (used + free)) * 100 > 90` | 5m | critical |
| TrueNASDiskTempWarning | `truenas_disk_temperature_celsius > 45` | 10m | warning |
| TrueNASDiskTempCritical | `truenas_disk_temperature_celsius > 55` | 5m | critical |
| TrueNASNotReporting | `absent(truenas_cpu_percent)` | 5m | warning |
| TrueNASMemoryHigh | `(used / (used + free + cached)) * 100 > 90` | 10m | warning |

### TrueNAS Configuration
1. Go to **System > Reporting** (TrueNAS SCALE) or **System > Reporting > Graphite** (CORE)
2. Enable **Remote Graphite Server**
3. Set **Graphite Server**: `192.168.8.85`
4. Set **Graphite Port**: `2003`
5. Save and test

### Verification
```bash
# Check Graphite exporter metrics
curl -s http://127.0.0.1:9109/metrics | grep truenas_ | head -20

# List available TrueNAS metrics
curl -s http://127.0.0.1:9109/metrics | grep truenas_ | cut -d'{' -f1 | sort -u

# Query specific metric
curl -s 'http://127.0.0.1:9090/api/v1/query?query=truenas_disk_temperature_celsius' | jq
```

---

## 8. pfSense Dashboard (Custom)

### Purpose
Firewall status, interface traffic, and connection tracking monitoring.

### Data Source
- **Exporter**: SNMP Exporter (port 9116)
- **Job**: `snmp_pfsense`
- **Module**: `pfsense` (uses BEGEMOT-PF-MIB)

### Target

| Instance | IP Address | SNMP Version |
|----------|------------|--------------|
| pfsense | 192.168.8.1 | v2c |

### Key Metrics (SNMP OIDs)

| Metric | OID | Description |
|--------|-----|-------------|
| `ifDescr` | 1.3.6.1.2.1.2.2.1.2 | Interface description |
| `ifOperStatus` | 1.3.6.1.2.1.2.2.1.8 | Interface status (1=up) |
| `ifHCInOctets` | 1.3.6.1.2.1.31.1.1.1.6 | Bytes received (64-bit) |
| `ifHCOutOctets` | 1.3.6.1.2.1.31.1.1.1.10 | Bytes transmitted (64-bit) |
| `ifInErrors` | 1.3.6.1.2.1.2.2.1.14 | Input errors |
| `ifOutErrors` | 1.3.6.1.2.1.2.2.1.20 | Output errors |
| `pfStatusRunning` | 1.3.6.1.4.1.12325.1.200.1.1.* | PF status |
| `pfCounterMatch` | 1.3.6.1.4.1.12325.1.200.1.2.* | Matched packets |
| `pfStateTableCount` | 1.3.6.1.4.1.12325.1.200.1.3.* | Active connections |

### Interface Mappings

| Logical Name | Interface | Description |
|--------------|-----------|-------------|
| WAN | igc0 | Internet uplink |
| LAN | ix0 | Main LAN (192.168.8.0/24) |
| GUEST | ix0.200 | Guest VLAN 200 (192.168.9.0/24) |
| WG_VPS | tun_wg0 | WireGuard tunnel to VPS |
| NAS | lagg0 | TrueNAS LAGG interface |

### Dashboard Panels

| Panel | Metric/Query | Visualization |
|-------|--------------|---------------|
| PF Status | `pfStatusRunning{job="snmp_pfsense"}` | Stat (RUNNING/DISABLED) |
| Active Connections | `pfStateTableCount{job="snmp_pfsense"}` | Gauge (0-200k) |
| Interface Status | `ifOperStatus{job="snmp_pfsense"}` | Stat grid (UP/DOWN) |
| WAN Traffic | `rate(ifHCInOctets{ifDescr="igc0"}[5m])` | Time series (In/Out) |
| LAN Traffic | `rate(ifHCInOctets{ifDescr="ix0"}[5m])` | Time series (In/Out) |
| GUEST Traffic | `rate(ifHCInOctets{ifDescr="ix0.200"}[5m])` | Time series (In/Out) |
| WG_VPS Traffic | `rate(ifHCInOctets{ifDescr="tun_wg0"}[5m])` | Time series (In/Out) |
| NAS Traffic | `rate(ifHCInOctets{ifDescr="lagg0"}[5m])` | Time series (In/Out) |
| Interface Errors | `rate(ifInErrors[5m]) + rate(ifOutErrors[5m])` | Time series |
| State Table History | `pfStateTableCount{job="snmp_pfsense"}` | Time series |

### Variables
- `interface`: Interface selector (from `ifOperStatus` labels)
- `datasource`: Prometheus data source selector

### Recommended Alerts (future)

| Alert | Expression | For | Severity |
|-------|------------|-----|----------|
| InterfaceDown | `ifOperStatus != 1` | 2m | critical |
| HighStateTable | `pfStateTableCount > 100000` | 5m | warning |
| MemoryDrops | `rate(pfCounterMemDrop[5m]) > 0` | 5m | warning |

### pfSense Configuration
1. Go to **Services > SNMP**
2. Enable SNMP Daemon
3. Set **Community String** (use strong random string)
4. Bind to **LAN interface only**
5. Add firewall rule: **LAN pass UDP 161** from monitoring server to Self

### Verification
```bash
# Test SNMP exporter
curl -s 'http://127.0.0.1:9116/snmp?auth=pfsense_v2&module=pfsense&target=192.168.8.1' | head -30

# Check SNMP target health
curl -s 'http://127.0.0.1:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job == "snmp_pfsense")'
```

---

## 9. Media Stack Dashboard (Custom) - *arr Applications

### Purpose
Monitor Sonarr, Radarr, Prowlarr, and Bazarr for queue status, download progress, and health issues.

### Data Source
- **Exporter**: Exportarr (ports 9707-9710)
- **Jobs**: `sonarr_app`, `radarr_app`, `prowlarr_app`, `bazarr_app`

### Targets

| Instance | IP Address | Port | Application |
|----------|------------|------|-------------|
| sonarr | 192.168.8.80 | 9707 | TV Shows |
| radarr | 192.168.8.80 | 9708 | Movies |
| prowlarr | 192.168.8.80 | 9709 | Indexer Manager |
| bazarr | 192.168.8.80 | 9710 | Subtitles |

### Key Metrics

| Metric | Application | Description |
|--------|-------------|-------------|
| `sonarr_queue_total` | Sonarr | Items in download queue |
| `sonarr_episode_downloaded_total` | Sonarr | Total downloaded episodes |
| `sonarr_series_total` | Sonarr | Total monitored series |
| `sonarr_system_health_issues` | Sonarr | Health issue count |
| `radarr_queue_total` | Radarr | Items in download queue |
| `radarr_movie_downloaded_total` | Radarr | Total downloaded movies |
| `radarr_movie_total` | Radarr | Total monitored movies |
| `radarr_system_health_issues` | Radarr | Health issue count |
| `prowlarr_indexer_*` | Prowlarr | Indexer statistics |
| `prowlarr_system_health_issues` | Prowlarr | Health issue count |
| `bazarr_*` | Bazarr | Subtitle statistics |

### Recommended Panels

| Panel | Metric/Query | Visualization |
|-------|--------------|---------------|
| Sonarr Queue | `sonarr_queue_total` | Stat |
| Radarr Queue | `radarr_queue_total` | Stat |
| Download Progress | `increase(sonarr_episode_downloaded_total[24h])` | Stat |
| Health Issues | `sum(sonarr_system_health_issues + radarr_system_health_issues + prowlarr_system_health_issues)` | Stat (colored) |
| Series Count | `sonarr_series_total` | Stat |
| Movie Count | `radarr_movie_total` | Stat |
| Indexer Health | `prowlarr_indexer_*` | Table |
| Subtitle Stats | `bazarr_*` | Table |

### Variables
- `app`: Application selector (sonarr, radarr, prowlarr, bazarr)

### Associated Alerts

| Alert | Expression | For | Severity |
|-------|------------|-----|----------|
| SonarrQueueStuck | `sonarr_queue_total > 0 and increase(sonarr_episode_downloaded_total[6h]) == 0` | 6h | warning |
| RadarrQueueStuck | `radarr_queue_total > 0 and increase(radarr_movie_downloaded_total[6h]) == 0` | 6h | warning |
| SonarrHealthIssue | `sonarr_system_health_issues > 0` | 30m | warning |
| RadarrHealthIssue | `radarr_system_health_issues > 0` | 30m | warning |
| ProwlarrHealthIssue | `prowlarr_system_health_issues > 0` | 30m | warning |
| ExportarrTargetDown | `up{job=~".*_app"} == 0` | 5m | warning |

### Verification
```bash
# Test Exportarr endpoints
curl -s http://192.168.8.80:9707/metrics | head -20  # Sonarr
curl -s http://192.168.8.80:9708/metrics | head -20  # Radarr
curl -s http://192.168.8.80:9709/metrics | head -20  # Prowlarr
curl -s http://192.168.8.80:9710/metrics | head -20  # Bazarr

# Check all app targets
curl -s 'http://127.0.0.1:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job | test("_app$"))'
```

---

## Alert Rules Summary

All alert rules are defined in Prometheus (`grafana.nix` and exporter modules) and evaluated automatically. Grafana Unified Alerting is enabled and can be used for additional UI-based alerts.

### Alert Groups

| Group | Rules | Source File |
|-------|-------|-------------|
| container_alerts | 5 | grafana.nix |
| node_alerts | 5 | grafana.nix |
| wireguard_alerts | 3 | grafana.nix |
| backup_alerts | 3 | grafana.nix |
| arr_alerts | 6 | grafana.nix |
| ssl_expiry | 2 | prometheus-blackbox.nix |
| truenas_alerts | 6 | prometheus-graphite.nix |

### Alert Severity Levels

| Severity | Notification | Action Required |
|----------|--------------|-----------------|
| critical | Immediate email | Immediate attention |
| warning | Grouped (5m batches) | Review within 24h |

### Contact Points
- **Email**: Configured via `smtp` settings in `grafana.nix`
- **Relay**: 192.168.8.89:25 (LXC_mailer postfix)
- **From**: Configurable in secrets

---

## Dashboard Import Instructions

### Community Dashboards

1. Go to **Dashboards** > **New** > **Import**
2. Enter the Grafana ID (e.g., `1860`)
3. Click **Load**
4. Select **Prometheus** as the data source
5. Click **Import**

### Custom Dashboards

For dashboards without Grafana IDs (WireGuard, TrueNAS, pfSense, Media Stack):

1. Go to **Dashboards** > **New** > **New dashboard**
2. Add panels using the metrics/queries listed above
3. Configure variables as specified
4. Save with descriptive name

---

## Verification Checklist

Run these checks to verify the monitoring stack is healthy:

### Prometheus Targets
```bash
# Count total targets
curl -s 'http://127.0.0.1:9090/api/v1/targets' | jq '.data.activeTargets | length'

# List unhealthy targets
curl -s 'http://127.0.0.1:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.health != "up") | {job: .labels.job, instance: .labels.instance, health: .health}'
```

### Exporter Health
```bash
# Blackbox Exporter
curl -s http://127.0.0.1:9115/metrics | head -5

# SNMP Exporter
curl -s http://127.0.0.1:9116/metrics | head -5

# PVE Exporter
curl -s http://127.0.0.1:9221/metrics | head -5

# Graphite Exporter
curl -s http://127.0.0.1:9109/metrics | head -5
```

### Alert Rules
```bash
# List all alert rules
curl -s 'http://127.0.0.1:9090/api/v1/rules' | jq '.data.groups[] | {group: .name, rules: [.rules[].name]}'

# Check for firing alerts
curl -s 'http://127.0.0.1:9090/api/v1/alerts' | jq '.data.alerts[] | select(.state == "firing")'
```

### Dashboard Panels
- [ ] Node Exporter Full: All 8 hosts selectable and showing data
- [ ] Docker Containers: All containers visible with metrics
- [ ] Blackbox: All HTTP/ICMP probes showing status
- [ ] Proxmox VE: Node and VM metrics displaying
- [ ] WireGuard: Interface status and peer count visible
- [ ] TrueNAS: Disk temps, filesystem usage, ZFS stats
- [ ] pfSense: Interface traffic, PF status
- [ ] Media Stack: Queue counts, health issues

---

## Useful PromQL Queries

### Service Availability
```promql
# All HTTP probes status
probe_success{job=~"blackbox_http.*"}

# Failed services
probe_success{job=~"blackbox_http.*"} == 0

# SSL days remaining
(probe_ssl_earliest_cert_expiry - time()) / 86400
```

### System Resources
```promql
# Memory usage %
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# CPU usage %
100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Disk usage %
100 - (node_filesystem_avail_bytes / node_filesystem_size_bytes * 100)
```

### Container Resources
```promql
# Container CPU usage
rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100

# Container memory %
(container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100
```

### WireGuard
```promql
# Tunnel traffic rate
rate(node_network_receive_bytes_total{device="wg0"}[5m])
rate(node_network_transmit_bytes_total{device="wg0"}[5m])
```

### TrueNAS
```promql
# Filesystem capacity %
(truenas_filesystem_bytes{type="used"}) /
(truenas_filesystem_bytes{type="used"} + truenas_filesystem_bytes{type="free"}) * 100

# Disk temperatures
truenas_disk_temperature_celsius
```

---

## Related Documentation

- [Ubuntu Node Exporter Setup](./ubuntu-node-exporter.md)
- [Grafana Dashboards and Alerting Setup](./grafana-dashboards-alerting.md)
- [Infrastructure Overview](../infrastructure/INFRASTRUCTURE.md)
- [Monitoring Module (grafana.nix)](../../system/app/grafana.nix)
