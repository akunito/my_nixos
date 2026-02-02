# Ubuntu LXC Node Exporter Setup

This guide documents how to install and configure Prometheus Node Exporter on Ubuntu LXC containers (like cloudflared at 192.168.8.102) for monitoring with the homelab Prometheus/Grafana stack.

## Prerequisites

- Ubuntu LXC container running
- Network connectivity to the monitoring server (192.168.8.85)
- Root or sudo access

## Installation

### 1. Install Node Exporter

```bash
sudo apt update
sudo apt install prometheus-node-exporter
```

### 2. Verify Service Status

```bash
sudo systemctl status prometheus-node-exporter
```

The service should be active and running.

### 3. Test Metrics Endpoint

```bash
curl http://localhost:9100/metrics
```

This should return a large amount of Prometheus metrics text.

## Configuration

The default installation listens on port 9100 on all interfaces, which is suitable for remote scraping.

### Custom Configuration (if needed)

Edit `/etc/default/prometheus-node-exporter`:

```bash
# Additional arguments for node_exporter
ARGS="--collector.systemd --collector.processes"
```

Then restart:

```bash
sudo systemctl restart prometheus-node-exporter
```

## Firewall

If ufw is installed and enabled, allow the metrics port:

```bash
sudo ufw allow from 192.168.8.85 to any port 9100 proto tcp
```

Note: The cloudflared LXC (192.168.8.102) does not have ufw installed, so no firewall rules are needed.

## Verification from Monitoring Server

From the monitoring server (192.168.8.85), verify connectivity:

```bash
curl http://192.168.8.102:9100/metrics | head -20
```

## Adding to Prometheus

The target is already configured in `profiles/LXC_monitoring-config.nix`:

```nix
prometheusRemoteTargets = [
  # ... other targets ...
  { name = "lxc_cloudflared"; host = "192.168.8.102"; nodePort = 9100; cadvisorPort = null; }
];
```

Note: `cadvisorPort = null` because Docker/cAdvisor is not running on this Ubuntu container.

## Collected Metrics

Node Exporter collects system metrics including:

- **CPU**: Usage, load averages, context switches
- **Memory**: Usage, swap, buffers/cache
- **Disk**: I/O, space usage, inodes
- **Network**: Interface traffic, errors, drops
- **System**: Uptime, logged users, processes

## Troubleshooting

### Service Won't Start

Check logs:
```bash
sudo journalctl -u prometheus-node-exporter -f
```

### Connection Refused

1. Verify service is running: `systemctl status prometheus-node-exporter`
2. Check binding: `ss -tlnp | grep 9100`
3. Check firewall: `sudo ufw status` (if installed)

### Missing Metrics

Ensure required collectors are enabled in `/etc/default/prometheus-node-exporter`.

## Related Documentation

- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)
- [NixOS Prometheus Exporters](../system-modules.md#prometheus-exporters)
