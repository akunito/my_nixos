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
│  │                          Nginx (80 + 443)                            │   │
│  │              SSL termination for Grafana & Prometheus                │   │
│  │         Cert: /mnt/shared-certs/local.akunito.com.*                 │   │
│  │                                                                      │   │
│  │    Port 443: grafana.local.akunito.com (HTTPS, local access)        │   │
│  │    Port 80:  grafana.akunito.com (HTTP, Cloudflare Tunnel)          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Access URLs

| Service | Local URL | Public URL | Auth |
|---------|-----------|------------|------|
| Grafana | https://grafana.local.akunito.com | https://grafana.akunito.com | Admin login |
| Prometheus | https://prometheus.local.akunito.com | - | Basic auth + IP whitelist |

**Access Methods**:
- **Local**: Uses `*.local.akunito.com` wildcard certificate from LXC_proxy ACME, mounted at `/mnt/shared-certs/`
- **Public (Grafana only)**: Via Cloudflare Tunnel → LXC_monitoring nginx (HTTP port 80) - TLS terminated by Cloudflare

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

## Grafana Configuration

### Declarative Provisioning (Infrastructure as Code)

All Grafana configuration is managed declaratively via NixOS in `system/app/grafana.nix`. This ensures:
- **Migration-safe**: All dashboards, datasources, and alerting config are automatically restored on new deployments
- **Version-controlled**: All changes are tracked in git
- **Reproducible**: Same configuration on every rebuild

#### What is Provisioned Declaratively

| Component | Status | Location |
|-----------|--------|----------|
| Dashboards (12 JSON files) | ✅ Provisioned | `system/app/grafana-dashboards/` |
| Prometheus datasource | ✅ Provisioned | `grafana.nix` → `datasources.settings` |
| Alert contact points | ✅ Provisioned | `grafana.nix` → `alerting.contactPoints` |
| Notification policies | ✅ Provisioned | `grafana.nix` → `alerting.policies` |
| Alert rules (20+) | ✅ Provisioned | `grafana.nix` → Prometheus `ruleFiles` |
| SMTP settings | ✅ Provisioned | `grafana.nix` → `settings.smtp` |

#### Current Provisioning Settings

```nix
provision = {
  dashboards.settings.providers = [{
    allowUiUpdates = true;    # Can edit dashboards in UI
    disableDeletion = false;  # Can delete dashboards in UI
  }];

  datasources.settings.datasources = [{
    name = "Prometheus";
    editable = false;         # Cannot modify in UI
    uid = "prometheus";       # Fixed UID for dashboard references
  }];

  alerting.contactPoints.settings = {
    contactPoints = [{
      name = "email-alerts";
      receivers = [{ type = "email"; addresses = "<email>"; }];
    }];
  };

  alerting.policies.settings = {
    policies = [{
      receiver = "email-alerts";
      group_by = ["alertname" "severity"];
    }];
  };
};
```

### Dashboard Editing Workflow

Since `allowUiUpdates = true`, you can edit provisioned dashboards in the Grafana UI. However, **changes made in the UI are NOT automatically saved to the repository**.

#### To Persist Dashboard Changes

1. **Edit in Grafana UI** - Make your changes in the dashboard editor
2. **Export the JSON**:
   - Click the dashboard settings icon (⚙️ gear)
   - Select **JSON Model** tab
   - Click **Copy to clipboard** or **Save to file**
3. **Save to repository**:
   ```bash
   # For custom dashboards
   cp dashboard.json ~/.dotfiles/system/app/grafana-dashboards/custom/<name>.json

   # For community dashboards
   cp dashboard.json ~/.dotfiles/system/app/grafana-dashboards/community/<name>.json
   ```
4. **Ensure it's registered** in `grafana.nix`:
   ```nix
   environment.etc = {
     "grafana-dashboards/custom/<name>.json".source = ./grafana-dashboards/custom/<name>.json;
   };
   ```
5. **Commit and deploy**:
   ```bash
   git add system/app/grafana-dashboards/custom/<name>.json system/app/grafana.nix
   git commit -m "feat: update <name> dashboard"
   git push
   ssh -A 192.168.8.85 "cd ~/.dotfiles && git pull && sudo nixos-rebuild switch --flake .#system"
   ```

#### API Export Script (Bulk Export)

To export all dashboards at once:

```bash
# SSH to monitoring server
ssh -A 192.168.8.85

# Export all dashboards via API (requires API key or admin credentials)
GRAFANA_URL="http://localhost:3002"
AUTH="admin:<password>"

curl -s "$GRAFANA_URL/api/search?type=dash-db" -u "$AUTH" | \
  jq -r '.[].uid' | while read uid; do
    title=$(curl -s "$GRAFANA_URL/api/dashboards/uid/$uid" -u "$AUTH" | jq -r '.dashboard.title')
    curl -s "$GRAFANA_URL/api/dashboards/uid/$uid" -u "$AUTH" | \
      jq '.dashboard' > "dashboard-${title// /-}.json"
    echo "Exported: $title"
  done
```

---

## Grafana Dashboards

### Installed Dashboards (Provisioned)

| # | Dashboard | Source | Path |
|---|-----------|--------|------|
| 1 | Node Exporter Full | Community (ID: 1860) | `community/node-exporter-full.json` |
| 2 | Docker Container Monitoring | Community (ID: 893) | `community/docker-cadvisor.json` |
| 3 | Blackbox Exporter | Community (ID: 7587) | `community/blackbox-exporter.json` |
| 4 | Proxmox VE | Community (ID: 10347) | `community/proxmox-ve.json` |
| 5 | Docker System Monitoring | Community | `community/docker-system-monitoring.json` |
| 6 | Infrastructure Overview | **Custom** | `custom/infrastructure-overview.json` |
| 7 | Infrastructure Status | **Custom** | `custom/infrastructure-status.json` |
| 8 | pfSense Firewall | **Custom** | `custom/pfsense.json` |
| 9 | TrueNAS | **Custom** | `custom/truenas.json` |
| 10 | WireGuard | **Custom** | `custom/wireguard.json` |
| 11 | Media Stack (*arr) | **Custom** | `custom/media-stack.json` |

All dashboards are stored in `~/.dotfiles/system/app/grafana-dashboards/`.

---

## Alert Rules

Alert rules are defined in Prometheus format within `grafana.nix` and automatically loaded. They are **NOT** created in the Grafana UI.

| Alert Group | Rules | Severity |
|-------------|-------|----------|
| container_alerts | ContainerMemoryHigh, ContainerMemoryCritical, ContainerCPUThrottling, ContainerRestarting, ContainerDown | warning/critical |
| node_alerts | HostMemoryHigh, HostCPUHigh, HostDiskSpaceLow, HostDiskSpaceCritical, HostDown | warning/critical |
| wireguard_alerts | WireGuardInterfaceDown, WireGuardPfSenseDisconnected, WireGuardNoPeers | warning/critical |
| backup_alerts | BackupTooOld, BackupCriticallyOld, BackupRepositoryUnhealthy | warning/critical |
| arr_alerts | SonarrQueueStuck, RadarrQueueStuck, SonarrHealthIssue, RadarrHealthIssue, ProwlarrHealthIssue, ExportarrTargetDown | warning |
| autoupdate_alerts | NixOSAutoUpdateFailed, NixOSAutoUpdateStale, HomeManagerAutoUpdateFailed | warning |
| pve_backup_alerts | PVEBackupFailed, PVEBackupTooOld, PVEBackupCriticallyOld | warning/critical |

### Alert Notification (Provisioned)

| Setting | Value |
|---------|-------|
| **Contact Point** | `email-alerts` (provisioned) |
| **SMTP Relay** | 192.168.8.89:25 (LXC_mailer) |
| **Recipient** | Configured in `secrets/domains.nix` → `alertEmail` |
| **Group By** | `alertname`, `severity` |
| **Timing** | group_wait: 30s, group_interval: 5m, repeat_interval: 4h |

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
