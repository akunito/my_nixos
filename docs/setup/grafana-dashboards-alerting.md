# Grafana Dashboards and Alerting Setup

This guide documents how to configure Grafana dashboards and alerting for the homelab monitoring stack.

**Access URLs**:
- Local: `https://grafana.local.akunito.com`
- Public: `https://grafana.akunito.com` (via Cloudflare Tunnel)

## Prerequisites

- Grafana running on LXC_monitoring (192.168.8.85)
- Prometheus configured as data source
- SMTP configured in grafana.nix (relay via 192.168.8.89:25)

---

## Current Configuration State (Declarative)

As of 2026-02-05, the following components are **provisioned declaratively** via `grafana.nix`:

| Component | Status | Notes |
|-----------|--------|-------|
| Prometheus datasource | ✅ Provisioned | UID: `prometheus`, not editable in UI |
| Email contact point | ✅ Provisioned | Name: `email-alerts` |
| Notification policy | ✅ Provisioned | Routes all alerts to `email-alerts` |
| 11 Dashboards | ✅ Provisioned | Editable in UI (`allowUiUpdates = true`) |
| 20+ Alert rules | ✅ Provisioned | Defined in Prometheus rule files |

**You do NOT need to manually configure contact points or notification policies** - they are automatically created on deployment.

---

## 1. Verify Prometheus Data Source (Provisioned)

The Prometheus data source is **automatically provisioned** with:
- **Name**: `Prometheus`
- **UID**: `prometheus` (fixed for dashboard references)
- **URL**: `http://127.0.0.1:9090`
- **Editable**: No (cannot modify in UI)

To verify:
1. Go to **Connections** → **Data sources**
2. Confirm `Prometheus` is listed and shows "provisioned" badge
3. Click to verify connection status

---

## 2. Email Contact Point (Provisioned)

The email contact point is **automatically provisioned** in `grafana.nix`:

```nix
alerting.contactPoints.settings = {
  contactPoints = [{
    name = "email-alerts";
    receivers = [{
      type = "email";
      settings = {
        addresses = secrets.alertEmail;  # From secrets/domains.nix
        singleEmail = true;
      };
    }];
  }];
};
```

To verify or test:
1. Navigate to: **Alerting** → **Contact points**
2. Confirm `email-alerts` is listed with "provisioned" badge
3. Click **Test** to send a test email

**Note**: You cannot edit provisioned contact points in the UI. To change the email address, update `secrets/domains.nix` and redeploy.

---

## 3. Notification Policy (Provisioned)

The notification policy is **automatically provisioned**:

```nix
alerting.policies.settings = {
  policies = [{
    receiver = "email-alerts";
    group_by = ["alertname" "severity"];
    group_wait = "30s";
    group_interval = "5m";
    repeat_interval = "4h";
  }];
};
```

**Behavior**:
- All alerts are routed to `email-alerts`
- Alerts are grouped by `alertname` and `severity`
- First notification after 30s, then every 5m while firing, repeat every 4h

To verify:
1. Go to: **Alerting** → **Notification policies**
2. Confirm the default policy shows `email-alerts` as receiver

---

## 4. Import Community Dashboards

### How to Import

1. Go to: **Dashboards** → **New** → **Import**
2. Enter the dashboard ID in the **"Import via grafana.com"** field
3. Click **"Load"**
4. **IMPORTANT - Fix "Data source is required" error**:
   - In the **Options** section at the bottom, you'll see dropdown(s) for data sources
   - For **DS_PROMETHEUS** or **Prometheus**: Select your Prometheus data source from the dropdown
   - This maps the dashboard's data source variable to your actual Prometheus instance
5. Click **"Import"**

### Recommended Dashboards

| Dashboard | ID | Purpose | Data Source Variable |
|-----------|-----|---------|---------------------|
| Node Exporter Full | `1860` | Detailed host metrics (CPU, memory, disk, network) | `DS_PROMETHEUS` |
| Docker Container Monitoring | `893` | Container metrics from cAdvisor | `DS_PROMETHEUS` |
| Blackbox Exporter | `7587` | HTTP/HTTPS and ICMP probe results | `DS_PROMETHEUS` |
| Proxmox VE | `10347` | Proxmox host and VM metrics | `DS_PROMETHEUS` |

### Troubleshooting Dashboard Import

**Error: "DS_PROMETHEUS - A data source is required"**

This happens when the dashboard uses a variable for the data source. Solution:
1. During import, scroll down to the **Options** section
2. Find the dropdown labeled `DS_PROMETHEUS` (or similar)
3. Select `Prometheus` from the dropdown
4. Then click **Import**

**Error: "Panel plugin not found"**

Some dashboards use plugins not installed by default:
1. Note which plugin is missing
2. Go to **Administration** → **Plugins**
3. Search for and install the required plugin
4. Re-import the dashboard

---

## 5. Create Alert Rules

Navigate to: **Alerting** → **Alert rules** → **+ New alert rule**

### Alert 1: Service Down (HTTP)

Triggers when an HTTP service is unreachable for 2+ minutes.

```
Section 1 - Rule name:
  Name: Service Down

Section 2 - Query and alert condition:
  Data source: Prometheus
  Query A: probe_success{job=~"blackbox_http.*"}

  Expression: Reduce
    Function: Last
    Input: A
    Mode: Strict

  Expression: Threshold
    Input: Reduce expression
    IS BELOW: 1

Section 3 - Evaluation behavior:
  Folder: Infrastructure Alerts (create if needed)
  Evaluation group: Create new → "HTTP Checks"
  Pending period: 2m

Section 4 - Labels and annotations:
  Labels:
    severity = critical

  Annotations:
    Summary: Service {{ $labels.instance }} is down
    Description: {{ $labels.url }} has been unreachable for 2+ minutes
```

### Alert 2: Network Device Unreachable (ICMP)

Triggers when a network device doesn't respond to ping for 5 minutes.

```
Section 1 - Rule name:
  Name: Network Device Unreachable

Section 2 - Query and alert condition:
  Data source: Prometheus
  Query A: probe_success{job=~"blackbox_icmp.*"}

  Threshold: IS BELOW 1

Section 3 - Evaluation behavior:
  Folder: Infrastructure Alerts
  Evaluation group: "ICMP Checks"
  Pending period: 5m

Section 4 - Labels and annotations:
  Labels:
    severity = warning

  Annotations:
    Summary: {{ $labels.instance }} is unreachable
    Description: {{ $labels.host }} has not responded to ICMP for 5+ minutes
```

### Alert 3: High Memory Usage

Triggers when memory usage exceeds 90% for 5 minutes.

```
Section 1 - Rule name:
  Name: High Memory Usage

Section 2 - Query and alert condition:
  Data source: Prometheus
  Query A: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

  Threshold: IS ABOVE 90

Section 3 - Evaluation behavior:
  Folder: Infrastructure Alerts
  Evaluation group: "Resource Alerts"
  Pending period: 5m

Section 4 - Labels and annotations:
  Labels:
    severity = warning

  Annotations:
    Summary: {{ $labels.instance }} memory usage above 90%
    Description: Current memory usage is {{ $value | printf "%.1f" }}%
```

### Alert 4: High CPU Usage

Triggers when CPU usage exceeds 85% for 10 minutes.

```
Section 1 - Rule name:
  Name: High CPU Usage

Section 2 - Query and alert condition:
  Data source: Prometheus
  Query A: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

  Threshold: IS ABOVE 85

Section 3 - Evaluation behavior:
  Folder: Infrastructure Alerts
  Evaluation group: "Resource Alerts"
  Pending period: 10m

Section 4 - Labels and annotations:
  Labels:
    severity = warning

  Annotations:
    Summary: {{ $labels.instance }} CPU usage above 85%
    Description: Current CPU usage is {{ $value | printf "%.1f" }}%
```

### Alert 5: Disk Space Low

Triggers when disk space falls below 15% free.

```
Section 1 - Rule name:
  Name: Disk Space Low

Section 2 - Query and alert condition:
  Data source: Prometheus
  Query A: (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes) * 100

  Threshold: IS BELOW 15

Section 3 - Evaluation behavior:
  Folder: Infrastructure Alerts
  Evaluation group: "Resource Alerts"
  Pending period: 5m

Section 4 - Labels and annotations:
  Labels:
    severity = warning

  Annotations:
    Summary: {{ $labels.instance }} disk {{ $labels.mountpoint }} below 15% free
    Description: Only {{ $value | printf "%.1f" }}% disk space remaining
```

### Alert 6: Container Down

Triggers when a monitored container/host is unreachable.

```
Section 1 - Rule name:
  Name: Container Down

Section 2 - Query and alert condition:
  Data source: Prometheus
  Query A: up{job=~".*_node"}

  Threshold: IS BELOW 1

Section 3 - Evaluation behavior:
  Folder: Infrastructure Alerts
  Evaluation group: "Container Alerts"
  Pending period: 2m

Section 4 - Labels and annotations:
  Labels:
    severity = critical

  Annotations:
    Summary: {{ $labels.instance }} is down
    Description: Node exporter on {{ $labels.instance }} is not responding
```

---

## 6. Create Custom Infrastructure Overview Dashboard

1. Go to: **Dashboards** → **New** → **New dashboard**
2. Click **"+ Add visualization"**

### Panel 1: Service Status Grid

Shows all HTTP services as colored boxes (green=up, red=down).

```
Title: Service Availability
Visualization: Stat

Query:
  Data source: Prometheus
  Query: probe_success{job=~"blackbox_http.*"}
  Legend: {{instance}}

Panel options:
  Title: Service Availability

Stat styles:
  Orientation: Horizontal
  Color mode: Background
  Graph mode: None
  Text mode: Name

Standard options:
  Unit: none

Thresholds:
  0 = Red
  1 = Green
```

### Panel 2: Network Devices Status

```
Title: Network Devices
Visualization: Stat

Query:
  Query: probe_success{job=~"blackbox_icmp.*"}
  Legend: {{instance}}

Same options as Panel 1
```

### Panel 3: LXC Container Status

```
Title: LXC Containers
Visualization: Stat

Query:
  Query: up{job=~".*_node"}
  Legend: {{instance}}

Same options as Panel 1
```

### Panel 4: Service Response Time

```
Title: Service Response Time
Visualization: Time series

Query:
  Query: probe_duration_seconds{job=~"blackbox_http.*"}
  Legend: {{instance}}

Standard options:
  Unit: seconds (s)
```

### Panel 5: Memory Usage by Host

```
Title: Memory Usage
Visualization: Gauge

Query:
  Query: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100
  Legend: {{instance}}

Gauge:
  Show threshold markers: Yes

Standard options:
  Unit: percent (0-100)
  Min: 0
  Max: 100

Thresholds:
  0 = Green
  70 = Yellow
  90 = Red
```

### Panel 6: CPU Usage by Host

```
Title: CPU Usage
Visualization: Gauge

Query:
  Query: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
  Legend: {{instance}}

Same options as Memory Usage panel
```

3. Arrange panels as desired
4. Click **Save dashboard** (top right)
5. Name: `Infrastructure Overview`
6. Click **Save**

---

## 7. Verification Commands

Run these on the monitoring server (192.168.8.85) to verify exporters are working:

```bash
# Check Blackbox Exporter
curl -s http://localhost:9115/metrics | head -5

# Check SNMP Exporter
curl -s http://localhost:9116/metrics | head -5

# Check PVE Exporter
curl -s http://localhost:9221/metrics | head -5

# Test HTTP probe
curl -s 'http://localhost:9115/probe?module=http_2xx&target=https://jellyfin.akunito.com' | grep probe_success

# Test ICMP probe
curl -s 'http://localhost:9115/probe?module=icmp&target=192.168.20.200' | grep probe_success

# Count Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'

# List all active targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'
```

---

## 8. Useful PromQL Queries

### Service Availability
```promql
# All HTTP probes status
probe_success{job=~"blackbox_http.*"}

# Failed probes only
probe_success{job=~"blackbox_http.*"} == 0

# Probe duration (response time)
probe_duration_seconds{job=~"blackbox_http.*"}
```

### System Resources
```promql
# Memory usage percentage
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# CPU usage percentage
100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Disk usage percentage
100 - (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes * 100)

# Network traffic (bytes/sec)
irate(node_network_receive_bytes_total{device!~"lo|veth.*"}[5m])
irate(node_network_transmit_bytes_total{device!~"lo|veth.*"}[5m])
```

### Container Metrics (cAdvisor)
```promql
# Container CPU usage
rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100

# Container memory usage
container_memory_usage_bytes{name!=""}

# Container network I/O
rate(container_network_receive_bytes_total{name!=""}[5m])
rate(container_network_transmit_bytes_total{name!=""}[5m])
```

---

## 9. Dashboard Persistence Workflow

Dashboards are provisioned from JSON files in the repository. Since `allowUiUpdates = true`, you can edit them in the Grafana UI, but **changes are NOT automatically saved to the repo**.

### Persisting Dashboard Changes

1. **Edit the dashboard** in Grafana UI
2. **Save the dashboard** (Ctrl+S or Save button)
3. **Export the JSON**:
   - Click dashboard settings (⚙️ gear icon)
   - Go to **JSON Model** tab
   - Copy the JSON content
4. **Save to repository**:
   ```bash
   # Create/update the JSON file
   vim ~/.dotfiles/system/app/grafana-dashboards/custom/<dashboard-name>.json
   # Paste the JSON content

   # If this is a NEW dashboard, add it to grafana.nix:
   vim ~/.dotfiles/system/app/grafana.nix
   # Add to environment.etc section:
   # "grafana-dashboards/custom/<dashboard-name>.json".source = ./grafana-dashboards/custom/<dashboard-name>.json;
   ```
5. **Commit and deploy**:
   ```bash
   cd ~/.dotfiles
   git add system/app/grafana-dashboards/custom/<dashboard-name>.json
   git add system/app/grafana.nix  # If modified
   git commit -m "feat: update <dashboard-name> dashboard"
   git push

   # Deploy to monitoring server
   ssh -A 192.168.8.85 "cd ~/.dotfiles && git pull && sudo nixos-rebuild switch --flake .#LXC_monitoring --impure"
   ```

### Dashboard File Locations

| Type | Path | Registration |
|------|------|--------------|
| Custom dashboards | `system/app/grafana-dashboards/custom/` | Must add to `environment.etc` in grafana.nix |
| Community dashboards | `system/app/grafana-dashboards/community/` | Must add to `environment.etc` in grafana.nix |

### Bulk Export Script

To export all dashboards from the running Grafana instance:

```bash
ssh -A 192.168.8.85

# Set credentials
GRAFANA_URL="http://localhost:3002"
AUTH="admin:YOUR_PASSWORD"

# Export each dashboard
curl -s "$GRAFANA_URL/api/search?type=dash-db" -u "$AUTH" | \
  jq -r '.[].uid' | while read uid; do
    filename=$(curl -s "$GRAFANA_URL/api/dashboards/uid/$uid" -u "$AUTH" | \
      jq -r '.meta.slug')
    curl -s "$GRAFANA_URL/api/dashboards/uid/$uid" -u "$AUTH" | \
      jq '.dashboard' > "$filename.json"
    echo "Exported: $filename.json"
  done
```

### Migration Checklist

When migrating to a new machine:
1. ✅ All dashboards are automatically provisioned from JSON files
2. ✅ Contact points and notification policies are automatically created
3. ✅ Prometheus datasource is automatically configured
4. ⚠️ Admin password may need to be reset (or set via environment variable)
5. ⚠️ UI-only dashboards (not in repo) will be lost - export them first!

---

## Related Documentation

- [Ubuntu Node Exporter Setup](./ubuntu-node-exporter.md)
- [Monitoring Stack Overview](../infrastructure/services/monitoring-stack.md)
- [Grafana Dashboard Reference](./grafana-dashboard-reference.md)
- [NixOS Monitoring Configuration](../system-modules/README.md)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Alerting](https://grafana.com/docs/grafana/latest/alerting/)
