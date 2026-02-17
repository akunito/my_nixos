---
id: komi.infrastructure.monitoring-setup
summary: Grafana and Prometheus setup for Komi's monitoring container
tags: [komi, infrastructure, monitoring, grafana, prometheus]
related_files: [profiles/KOMI_LXC_monitoring-config.nix]
date: 2026-02-17
status: published
---

# Komi Monitoring Setup

## Overview

KOMI_LXC_monitoring (192.168.8.12, CTID 112) runs Grafana and Prometheus as native NixOS modules. It scrapes metrics from all other KOMI_LXC containers.

## First-Time Setup

### 1. Deploy the Profile

```bash
./deploy.sh --profile KOMI_LXC_monitoring
```

### 2. Configure PVE Exporter Token

Create a Prometheus API token in Proxmox:
1. SSH to Proxmox: `ssh root@192.168.8.3`
2. Create user: `pveum user add prometheus@pve`
3. Create token: `pveum user token add prometheus@pve prometheus --privsep 0`
4. Note the token value

Deploy the token:
```bash
ssh admin@192.168.8.12
sudo mkdir -p /etc/secrets
echo "your-pve-token-value" | sudo tee /etc/secrets/pve-token
sudo chmod 600 /etc/secrets/pve-token
```

### 3. Verify Services

```bash
ssh admin@192.168.8.12
sudo systemctl status grafana
sudo systemctl status prometheus
```

## Accessing Grafana

- **Direct**: `http://192.168.8.12:3002`
- **Via proxy** (after NPM setup): `https://grafana.local.yourdomain.com`

Default Grafana credentials:
- Username: `admin`
- Password: `admin` (change on first login)

## Prometheus Targets

Pre-configured scrape targets (from profile):

| Target | Host | Port | Metrics |
|--------|------|------|---------|
| komi_database (node) | 192.168.8.10 | 9100 | System metrics |
| komi_database (postgres) | 192.168.8.10 | 9187 | PostgreSQL metrics |
| komi_database (redis) | 192.168.8.10 | 9121 | Redis metrics |
| komi_mailer (node) | 192.168.8.11 | 9100 | System metrics |
| komi_mailer (cadvisor) | 192.168.8.11 | 9092 | Docker metrics |
| komi_proxy (node) | 192.168.8.13 | 9100 | System metrics |
| komi_proxy (cadvisor) | 192.168.8.13 | 9092 | Docker metrics |
| komi_tailscale (node) | 192.168.8.14 | 9100 | System metrics |

Verify targets: `http://192.168.8.12:9090/targets`

## Importing Dashboards

### Recommended Grafana Dashboards

Import these from grafana.com by ID:

1. **Node Exporter Full** (ID: 1860) — System metrics for all containers
2. **PostgreSQL Database** (ID: 9628) — Database performance
3. **Redis Dashboard** (ID: 11835) — Redis metrics
4. **Docker Container** (ID: 893) — cAdvisor Docker metrics
5. **Proxmox VE** (ID: 10347) — Proxmox host metrics

To import: Grafana → Dashboards → Import → Enter ID → Select Prometheus data source

## Adding New Targets

When Komi deploys new services, add them to `profiles/KOMI_LXC_monitoring-config.nix`:

```nix
prometheusRemoteTargets = [
  # ... existing targets ...
  { name = "new_service"; host = "192.168.8.XX"; nodePort = 9100; cadvisorPort = 9092; }
];
```

Then redeploy: `./deploy.sh --profile KOMI_LXC_monitoring`

## Alerting

### Email Alerts
Prometheus alerting rules send notifications via the mailer container (192.168.8.11).

### Blackbox Monitoring
HTTP and ICMP probes are configured for basic connectivity checks. Add more targets as services are deployed:

```nix
prometheusBlackboxHttpTargets = [
  # ... existing ...
  { name = "myservice"; url = "https://myservice.local.yourdomain.com"; }
];
```
