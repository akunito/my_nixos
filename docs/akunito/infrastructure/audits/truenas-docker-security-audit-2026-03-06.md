---
id: audits.truenas-docker-security.2026-03-06
summary: TrueNAS Docker rootless migration and security hardening audit
tags: [audit, security, docker, truenas, rootless, monitoring, networking]
related_files: [templates/truenas/*/docker-compose.yml, scripts/truenas-docker-startup.sh, scripts/truenas-docker-suspend-hook.sh, profiles/VPS_PROD-config.nix]
date: 2026-03-06
status: published
---

# TrueNAS Docker Security Audit — Rootless Migration

**Date**: 2026-03-06
**Scope**: All Docker containers on TrueNAS (192.168.20.200)
**Auditor**: Infrastructure review (IAKU-285)

## Executive Summary

TrueNAS Docker infrastructure migrated from single root Docker daemon (19 containers) to a hybrid model:
- **Root Docker** (3 containers): tailscale, gluetun, qbittorrent — require NET_ADMIN/host netns
- **Rootless Docker** (~18 containers): all remaining services — reduced privilege surface

Additional changes:
- NPM migrated from macvlan (192.168.20.201) to bridge networking (192.168.20.200)
- Security hardening applied to all containers (cap_drop, no-new-privileges, resource limits, healthchecks)
- VPS Prometheus wired to scrape TrueNAS node-exporter (9100) and cadvisor (8081)

## Architecture Context

### Hybrid Docker Model

Full rootless is not possible for 3 containers with hard blockers:

| Container | Daemon | Blocker |
|-----------|--------|---------|
| tailscale | Root | NET_ADMIN on host netns for subnet routing |
| gluetun | Root | NET_ADMIN + /dev/net/tun for VPN tunnel |
| qbittorrent | Root | network_mode: service:gluetun (bound to root namespace) |
| Everything else (~18) | Rootless | No host namespace requirements |

### NPM Migration

| Property | Before | After |
|----------|--------|-------|
| Network | macvlan (npm_macvlan) | Bridge (rootless Docker) |
| IP | 192.168.20.201 (dedicated) | 192.168.20.200 (host ports) |
| Ports | Implicit via macvlan | Explicit: 80, 443, 81 |
| Host comm | macvlan-shim POSTINIT script | Native (same host) |
| TrueNAS Web UI | port 443 | port 9443 (moved to avoid conflict) |

---

## Findings

### SEC-TRUENAS-001: Rootless Docker Daemon

| Field | Value |
|-------|-------|
| **Severity** | Informational (Improvement) |
| **Status** | Implemented |
| **Category** | Privilege Reduction |

**Description**: 18 of 21 containers now run under rootless Docker (uid-mapped namespaces). Container breakout from rootless Docker lands in an unprivileged user namespace, not root.

**Residual Risk**: Root Docker still runs 3 containers. These are compensated by host-level network isolation (VLAN 100) and limited to VPN/networking functions.

### SEC-TRUENAS-002: Root Containers (Accepted Risk)

| Field | Value |
|-------|-------|
| **Severity** | Medium (Accepted Risk) |
| **Status** | Accepted — compensated by network isolation |
| **Category** | Privilege |

**Description**: tailscale, gluetun, and qbittorrent must run on root Docker due to NET_ADMIN capability and host network namespace requirements.

**Compensating Controls**:
- tailscale: upstream official image, host netns is the intended deployment
- gluetun: well-maintained image, only needs NET_ADMIN for tun0 creation
- qbittorrent: no elevated caps itself, bound to gluetun's namespace
- All three have resource limits and healthchecks
- TrueNAS is on isolated VLAN 100

### SEC-TRUENAS-003: Container Hardening

| Field | Value |
|-------|-------|
| **Severity** | Informational (Improvement) |
| **Status** | Implemented |
| **Category** | Defense in Depth |

**Description**: All containers now have security hardening applied:

| Container Type | cap_drop | cap_add | no-new-privileges | read_only | Limits |
|---------------|----------|---------|-------------------|-----------|--------|
| LSIO (bazarr, prowlarr, radarr, sonarr) | ALL | CHOWN, SETUID, SETGID, DAC_OVERRIDE | No (breaks s6) | No | Yes |
| Non-LSIO user:1000 (jellyfin, jellyseerr) | ALL | — | Yes | No | Yes |
| Exportarr (4x) | ALL | — | Yes | Yes | 128M |
| Monitoring (node-exporter, cadvisor) | ALL | — | Yes | Yes | 128-256M |
| NPM | ALL | CHOWN, SETUID, SETGID, DAC_OVERRIDE, NET_BIND_SERVICE | No | No | 512M |
| Cloudflared | ALL | — | Yes | No | 256M |
| Solvearr | ALL | — | Yes | No | 512M |

**Note on LSIO containers**: s6-overlay init system requires SETUID/SETGID/CHOWN/DAC_OVERRIDE for user switching. `no-new-privileges` breaks s6 initialization. This is an accepted trade-off.

### SEC-TRUENAS-004: Resource Limits

| Field | Value |
|-------|-------|
| **Severity** | Informational (Improvement) |
| **Status** | Implemented |
| **Category** | Availability |

**Description**: All containers now have memory limits via `deploy.resources.limits`:

| Container | Memory Limit |
|-----------|-------------|
| jellyfin | 2G |
| qbittorrent | 3G |
| sonarr, radarr | 1G |
| bazarr, prowlarr, jellyseerr, solvearr, npm | 512M |
| gluetun, tailscale, cloudflared, cadvisor | 256M |
| node-exporter, exportarr (4x) | 128M |

### SEC-TRUENAS-005: Logging Configuration

| Field | Value |
|-------|-------|
| **Severity** | Informational (Improvement) |
| **Status** | Implemented |
| **Category** | Observability |

**Description**: All containers have json-file log driver with max-size and max-file rotation. Prevents unbounded log growth filling ssdpool.

### SEC-TRUENAS-006: Healthchecks

| Field | Value |
|-------|-------|
| **Severity** | Informational (Improvement) |
| **Status** | Implemented |
| **Category** | Availability |

**Description**: All containers now have Docker healthchecks. This enables automatic restart detection and monitoring via cadvisor/Prometheus.

### SEC-TRUENAS-007: Monitoring Integration

| Field | Value |
|-------|-------|
| **Severity** | Informational (Improvement) |
| **Status** | Implemented |
| **Category** | Observability |

**Description**: VPS Prometheus now scrapes TrueNAS:
- node-exporter (192.168.20.200:9100): host metrics (CPU, memory, disk, network)
- cadvisor (192.168.20.200:8081): rootless container metrics
- exportarr (192.168.20.200:9707-9710): application metrics (unchanged)

cadvisor monitors rootless containers only. Root containers (tailscale, gluetun, qbittorrent) have their own healthchecks for status monitoring.

---

## Verification Checklist

### Rootless Docker
```bash
systemctl --user status docker                       # rootless daemon running
docker info | grep -i rootless                        # "rootless: true"
loginctl show-user truenas_admin | grep Linger        # Linger=yes
sysctl net.ipv4.ip_unprivileged_port_start            # = 80
```

### Container Distribution
```bash
# Root containers (expect: tailscale, gluetun, qbittorrent)
sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | sort

# Rootless containers (expect: ~18 containers)
docker ps --format 'table {{.Names}}\t{{.Status}}' | sort
```

### Hardening
```bash
for c in exportarr-sonarr exportarr-radarr node-exporter cadvisor; do
  echo "$c caps: $(docker inspect $c --format '{{json .HostConfig.CapDrop}}')"
  echo "$c secopt: $(docker inspect $c --format '{{.HostConfig.SecurityOpt}}')"
done
```

### Monitoring
```bash
curl -s http://192.168.20.200:9100/metrics | head -5   # node-exporter
curl -s http://192.168.20.200:8081/metrics | head -5   # cadvisor
curl -s http://192.168.20.200:9707/metrics | head -5   # exportarr
```

### NPM Bridge
```bash
curl -sI http://192.168.20.200:81                      # NPM admin UI
nslookup jellyfin.local.akunito.com 192.168.8.1        # Should return .200
```

---

## Manual Setup Steps (TrueNAS)

These steps must be performed on TrueNAS via SSH before deploying compose files:

```bash
# 1. Rootless Docker prerequisites
sudo apt-get install -y uidmap
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 truenas_admin

# 2. Enable linger (rootless Docker persists after logout)
sudo loginctl enable-linger truenas_admin

# 3. Install and enable rootless Docker
dockerd-rootless-setuptool.sh install
systemctl --user enable docker
systemctl --user start docker

# 4. Configure rootless daemon
mkdir -p ~/.config/docker
cat > ~/.config/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {"max-size": "10m", "max-file": "3"},
  "dns": ["1.1.1.1", "9.9.9.9"]
}
EOF
systemctl --user restart docker

# 5. Allow unprivileged port binding (80, 443 for NPM)
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80
echo "net.ipv4.ip_unprivileged_port_start=80" | sudo tee /etc/sysctl.d/99-unprivileged-ports.conf

# 6. GPU access for Jellyfin (rootless)
sudo usermod -aG render,video truenas_admin

# 7. Change TrueNAS Web UI port (avoids 443 conflict with NPM)
# Via TrueNAS Web UI: System Settings > General > GUI > HTTPS Port: 9443

# 8. Set DOCKER_HOST in shell profile
echo 'export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock' >> ~/.bashrc
```

---

## Rollback Plan

If rootless Docker fails for specific containers:
```bash
# Move container to root compose
docker compose -f /mnt/ssdpool/docker/compose/<project>/docker-compose.yml down
# Add to vpn-media compose or create new root compose, start with sudo
```

Full rollback:
```bash
systemctl --user stop docker
git checkout HEAD -- templates/truenas/
# Restore macvlan, run original startup script
```
