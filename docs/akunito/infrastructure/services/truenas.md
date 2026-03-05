---
id: infrastructure.services.truenas
summary: TrueNAS storage server operations, monitoring, and maintenance
tags: [infrastructure, storage, truenas, zfs, monitoring, nas]
related_files: [system/app/prometheus-graphite.nix, .local/bin/truenas-zfs-exporter.sh, .claude/skills/unlock-truenas.md]
---

# TrueNAS Storage Server

**Version**: TrueNAS SCALE 25.04.2.6
**SSH Access**: `ssh truenas_admin@192.168.20.200`
**Web UI**: https://192.168.20.200 (HTTPS only)

---

## System Overview

### Hardware
- **Host**: Custom build
- **CPU**: AMD Ryzen 5 5600G (6 cores / 12 threads, up to 4.46 GHz)
- **RAM**: 62GB (non-ECC)
- **Motherboard**: Gigabyte B550 AORUS ELITE V2
- **Network**: 2x 10GbE LACP bond (bond0: enp8s0f0 + enp8s0f1)
- **Boot Devices**: 2x Samsung 970 EVO Plus 250GB NVMe (mirrored)
- **Power**: S3 suspend schedule (23:00–11:00), RTC alarm wake

### Storage Pools

| Pool | Size | Type | Encryption | Health |
|------|------|------|------------|--------|
| boot-pool | 232GB | 2x NVMe mirror | No | ✅ ONLINE |
| ssdpool | ~5.4TB | RAIDZ1, 4x 2TB SSD | Passphrase | ✅ ONLINE |
| extpool | ~4TB | Single USB NVMe | No | ✅ ONLINE |

> **Pool migration (Mar 2026)**: hddpool (4x HDD, 2x mirror vdevs) removed. All data consolidated to ssdpool (rebuilt as RAIDZ1 with 4x 2TB SSDs). ZFS replication (ssdpool->hddpool) eliminated. New extpool added for game downloads via USB NVMe.

> **Latest Audit**: [2026-02-12](../audits/truenas-audit-2026-02-12.md) - Score 8/10. Key findings: NIC rx_missed_errors, 2 SSDs with pending sectors, NFS exports too open.

### Key Datasets

**ssdpool** (primary storage — RAIDZ1, 4x 2TB SSD):
- `ssdpool/media` - Jellyfin media library (movies, TV shows)
- `ssdpool/workstation_backups` - Workstation restic backups (DESK, LAPTOP_X13)
- `ssdpool/vps-backups` - VPS restic databases (critical)

> **Removed (IAKU-247)**: `ssdpool/library` and `ssdpool/emulators` datasets removed. Data lives on VPS with restic backups.

**extpool** (USB NVMe, ~4TB, no redundancy):
- `extpool/downloads` - Game downloads
- `extpool/vps-backups` - VPS restic services, libraries, nextcloud (re-downloadable)

---

## S3 Sleep Schedule

TrueNAS suspends to RAM (S3) nightly to save power (~280W → 0W during sleep).

| Event | Time | Method |
|-------|------|--------|
| Suspend | 23:00 | `systemctl suspend` via cron |
| Wake | 11:00 | RTC alarm (`rtcwake -m no`) |

- ZFS pools remain unlocked in RAM during S3
- **Docker lifecycle**: Two systemd services (`docker-pre-suspend.service`, `docker-post-resume.service`) bound to `sleep.target` handle graceful stop/start of all Docker containers around suspend
- **Pre-suspend**: Stops all compose projects in reverse order (30s timeout per project)
- **Post-resume**: Waits 10s for networking, then starts projects in order (media force-recreated for fresh mounts)
- **Script**: `/home/truenas_admin/docker-suspend-hook.sh` (deployed by startup script)
- **Log**: `/var/log/docker-suspend-hook.log`
- **IMPORTANT**: TrueNAS root is read-only (`/usr/lib/`), so services go in `/etc/systemd/system/`. TrueNAS updates may reset `/etc/systemd/` — re-run `truenas-docker-startup.sh` to redeploy
- All backup jobs (restic) scheduled within 11:00–23:00 window
- WOL unreliable (r8169 driver limitation) — RTC alarm is the primary wake method

---

## Docker Services

TrueNAS runs **15 Docker containers** across **6 compose projects** for media, local proxy, and monitoring exporters.

See [TrueNAS Docker Services](./truenas-services.md) for full details.

**Key services**: Jellyfin, *arr stack (Sonarr/Radarr/Prowlarr/Bazarr), qBittorrent, NPM (macvlan 192.168.20.201), cloudflared, Tailscale (subnet router), exportarr instances.

**NPM Macvlan**: NPM runs on a macvlan network (`npm_macvlan`) with IP 192.168.20.201 on VLAN 100. pfSense DNS resolves `*.local.akunito.com` → 192.168.20.201.

**Management**:
```bash
# Check all containers
ssh truenas_admin@192.168.20.200 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'

# Restart a compose project
ssh truenas_admin@192.168.20.200 'cd /home/truenas_admin/docker/<project> && docker compose restart'
```

---

## Network Shares

### NFS Exports (Primary)
| Share | Dataset | Clients | Purpose |
|-------|---------|---------|---------|
| /mnt/ssdpool/media | ssdpool/media | TrueNAS Docker (Jellyfin) | Media streaming |
| /mnt/ssdpool/workstation_backups | ssdpool/workstation_backups | 192.168.8.96, 192.168.8.92 | Workstation restic backups (NFS-based unified backup system) |

**Access**: NFSv4, all_squash (mapall_user=akunito) for workstations. Docker containers on TrueNAS access datasets via bind mounts (no NFS needed).

### SMB Shares (Desktop Access)
| Share | Dataset | Purpose |
|-------|---------|---------|
| media | ssdpool/media | Direct desktop access for management |

> **Removed (IAKU-247)**: library and emulators NFS/SMB shares (datasets removed), iSCSI targets (Proxmox shut down), Proxmox backup NFS exports.

---

## Security Configuration

### SSH Hardening (2026-02-09)
- ✅ Password authentication: **DISABLED** (key-only)
- ✅ Root login: **DISABLED**
- ✅ Weak ciphers: **REMOVED** (no AES128-CBC)
- ✅ TCP forwarding: Disabled
- **Authorized User**: `truenas_admin` (sudo access)
- **SSH Keys**: Stored in `~/.ssh/authorized_keys`

### API Access
- **Endpoint**: https://192.168.20.200/api/v2.0
- **Authentication**: Bearer token (X-API-Key header)
- **API Key Name**: automation-key
- **API Key Storage**: `secrets/truenas-api-key.txt` (git-crypt encrypted)
- **Permissions**: Full access (method: *, resource: *)

### Encryption
**Dataset Encryption**:
- **ssdpool datasets**: AES-256-GCM (passphrase-based)
- **extpool**: Not encrypted
- **Passphrase Storage**: `secrets/truenas-encryption-passphrase.txt` (git-crypt encrypted)
- **Unlock Method**: Manual after reboot (API call via `/unlock-truenas` skill)

**Boot Pool Encryption**:
- **Status**: Not encrypted (by design)
- **Rationale**: Enables unattended reboots, remote management, automatic failover
- **Security Mitigation**: Physical server security + all data encrypted at dataset level

---

## Monitoring & Alerting

### Metrics Collection

**1. Built-in Graphite Reporter** (TrueNAS → Prometheus Graphite Exporter)
- **Target**: VPS Graphite Exporter (port 2003, via Tailscale 100.64.0.6)
- **Protocol**: Graphite plaintext
- **Interval**: 10 seconds
- **Metrics Exported**:
  - `servers.truenas.cpu.*` - CPU usage (user, system, iowait, irq, softirq)
  - `servers.truenas.memory.*` - RAM usage (used, free, cached, buffers)
  - `servers.truenas.disktemp.*` - Disk temperatures (SMART)
  - `servers.truenas.interface.*` - Network interface stats (bond0)
  - `servers.truenas.zfs_arc.*` - ZFS ARC statistics
  - `servers.truenas.system.*` - System load, network traffic, disk I/O

**2. Custom ZFS Pool Metrics Exporter** (API-based)
- **Script**: `~/.local/bin/truenas-zfs-exporter.sh`
- **Automation**: systemd user timer (`truenas-zfs-exporter.timer`)
- **Schedule**: Every 5 minutes (OnBootSec=2min, OnUnitActiveSec=5min)
- **Method**: SSH to TrueNAS → `midclt call pool.query` + `boot.get_state` → parse with jq → send to Graphite
- **Metrics Exported**:
  - `truenas.zfspool.<pool>.size` - Total pool capacity (bytes)
  - `truenas.zfspool.<pool>.allocated` - Used space (bytes)
  - `truenas.zfspool.<pool>.free` - Available space (bytes)
  - `truenas.zfspool.<pool>.fragmentation` - Pool fragmentation percentage
  - `truenas.zfspool.<pool>.healthy` - Pool health (1=ONLINE, 0=DEGRADED/OFFLINE)
- **Pools Covered**: boot-pool, ssdpool, extpool

**Prometheus Mapping** (in `prometheus-graphite.nix`):
```nix
{
  match = "truenas.zfspool.*.*";
  name = "truenas_zfspool_${2}";  # Metric name: truenas_zfspool_allocated
  labels = {
    pool = "${1}";  # Label: pool="boot-pool"
  };
}
```

### Grafana Dashboard

**Dashboard**: TrueNAS (UID: `truenas-storage`)
**URL**: https://grafana.local.akunito.com/d/truenas-storage/truenas

**Key Panels**:
1. **CPU Usage** - Stacked area chart (user, system, iowait, irq, softirq)
2. **Memory Usage** - Gauge (used RAM as %)
3. **ZFS ARC Hit Rate** - Gauge (cache efficiency, target >80%)
4. **ZFS Pool Status** - Stat panel (1=ONLINE, 0=DEGRADED/OFFLINE) ✅
5. **ZFS ARC Size** - Time series (current, target, max)
6. **Memory Usage Over Time** - Time series (used, cached, buffers, free)
7. **Network Traffic** - Time series (bond0 received/sent)
8. **CPU Temperature** - Time series (4 cores, thresholds: 45°C yellow, 55°C red)
9. **System Load** - Time series (1min, 5min, 15min averages)
10. **Disk I/O** - Time series (read/write in KiB/s)
11. **ZFS Pool Capacity** - Bar gauge (% used, thresholds: 70% yellow, 80% orange, 90% red) ✅

**Recent Fixes (2026-02-09)**:
- Panel 4: Fixed to use `truenas_zfspool_healthy{pool="X"}` instead of non-existent `truenas_zfspool_state_*_online`
- Panel 11: Added new capacity bar gauge using `(truenas_zfspool_allocated / truenas_zfspool_size) * 100`

### Prometheus Alerts

**Alert Rules** (in `prometheus-graphite.nix`):

| Alert | Query | Threshold | Severity | Duration |
|-------|-------|-----------|----------|----------|
| TrueNASPoolCapacityWarning | `(allocated / size) * 100` | >80% | warning | 5m |
| TrueNASPoolCapacityCritical | `(allocated / size) * 100` | >90% | critical | 5m |
| TrueNASPoolUnhealthy | `truenas_zfspool_healthy` | ==0 | critical | 2m |
| TrueNASDiskTempWarning | `truenas_disk_temperature_celsius` | >45°C | warning | 10m |
| TrueNASDiskTempCritical | `truenas_disk_temperature_celsius` | >55°C | critical | 5m |
| TrueNASNotReporting | `absent(truenas_cpu_percent)` | No data >5min | warning | 5m |
| TrueNASMemoryHigh | `(used / total) * 100` | >90% | warning | 10m |

**Notification Channel**: Email (via VPS Postfix relay)

### Email Alerts (TrueNAS Native)

**SMTP Configuration**:
- **Server**: VPS Postfix (100.64.0.6:25 via Tailscale)
- **From**: truenas@akunito.com
- **To**: diego88aku@gmail.com
- **Security**: PLAIN (no TLS for internal relay)
- **Test Status**: ✅ Working

**Alert Levels**:
- CRITICAL: Pool degradation, disk failures, scrub errors with errors
- WARNING: Capacity warnings (>80%), SMART warnings, temperature warnings
- NOTICE: Update availability, scrub completion (no errors)

---

## Maintenance Operations

### Scheduled Tasks

| Task | Schedule | Retention | Purpose |
|------|----------|-----------|---------|
| **ZFS Scrub (ssdpool)** | 1st Sunday, 2:00 AM | N/A | Data integrity check |
| **ZFS Scrub (extpool)** | 2nd Sunday, 2:00 AM | N/A | Data integrity check |
| **SMART Short Test** | Every Saturday, 4:00 AM | N/A | Quick drive health check |
| **SMART Long Test** | 15th of month, 3:00 AM | N/A | Comprehensive drive test |
| **Config Backup** | Every Sunday, 3:00 AM | 30 days | System configuration export |
| **Snapshots (media)** | Daily, 1:00 AM | 7 days | Point-in-time recovery |
| **Custom ZFS Metrics** | Every 5 minutes | N/A | Prometheus monitoring |

### Manual Operations

**Unlock Encrypted Datasets** (after reboot):
```bash
# Using skill (recommended)
/unlock-truenas

# Or manually via API
curl -X POST https://192.168.20.200/api/v2.0/pool/dataset/unlock \
  -H "Authorization: Bearer $(cat secrets/truenas-api-key.txt)" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "ssdpool",
    "unlock_options": {
      "datasets": [
        {"name": "ssdpool/media", "passphrase": "YOUR_PASSPHRASE"}
      ]
    }
  }'
```

**Check Pool Status**:
```bash
ssh truenas_admin@192.168.20.200 'zpool status'
ssh truenas_admin@192.168.20.200 'zpool list'
```

**Manual Scrub**:
```bash
ssh truenas_admin@192.168.20.200 'midclt call pool.scrub "ssdpool" "START"'
```

**Check SMART Status**:
```bash
ssh truenas_admin@192.168.20.200 'midclt call disk.query | jq ".[] | {name: .devname, temp: .temperature, smart: .smart_enabled}"'
```

**Download Config Backup**:
```bash
curl -X POST https://192.168.20.200/api/v2.0/config/save \
  -H "Authorization: Bearer $(cat secrets/truenas-api-key.txt)" \
  -H "Content-Type: application/json" \
  -d '{"secretseed": true}' \
  -k -o truenas-config-$(date +%Y%m%d).tar
```

**Manual ZFS Metrics Export**:
```bash
~/.local/bin/truenas-zfs-exporter.sh
```

**Restart Services**:
```bash
ssh truenas_admin@192.168.20.200 'midclt call service.restart nfs'
ssh truenas_admin@192.168.20.200 'midclt call service.restart cifs'
```

### ZFS Local Replication (ELIMINATED)

> **Removed (Mar 2026)**: ZFS replication from ssdpool to hddpool was eliminated when hddpool was decommissioned. All data now resides on ssdpool (RAIDZ1). The replication script `scripts/truenas-zfs-replicate.sh` is no longer deployed or scheduled.

---

## Troubleshooting

### Boot Pool Shows Offline/Degraded in Grafana

**Symptoms**: Grafana dashboard shows boot-pool as offline/degraded despite TrueNAS reporting ONLINE

**Root Cause**: TrueNAS SCALE 25.04+ doesn't export ZFS pool capacity metrics via built-in Graphite reporter

**Solution**: Custom ZFS exporter (implemented 2026-02-09)
- Script: `~/.local/bin/truenas-zfs-exporter.sh`
- Automation: `truenas-zfs-exporter.timer` (systemd user timer, every 5 minutes)
- Grafana panel fixed to use `truenas_zfspool_healthy{pool="boot-pool"}`

**Verification**:
```bash
# Check timer status
systemctl --user status truenas-zfs-exporter.timer

# Manually run exporter
~/.local/bin/truenas-zfs-exporter.sh

# Verify metrics in Prometheus (on VPS)
ssh -A -p 56777 akunito@100.64.0.6 'curl -s http://localhost:9109/metrics | grep truenas_zfspool_healthy'
```

### Datasets Locked After Reboot

**Symptoms**: NFS/SMB shares unavailable, services report "Dataset not found"

**Root Cause**: Encrypted datasets require manual passphrase entry after reboot

**Solution**: Use `/unlock-truenas` skill or unlock via API
```bash
# Using skill (recommended)
/unlock-truenas

# Check dataset lock status
ssh truenas_admin@192.168.20.200 'midclt call pool.dataset.query | jq ".[] | select(.encrypted == true) | {name, locked, key_loaded}"'
```

### Email Alerts Not Received

**Symptoms**: No emails from TrueNAS despite alerts being triggered

**Common Issues**:
1. **SMTP relay not accessible** - Check if VPS Postfix is running and reachable via Tailscale
2. **Network not allowed** - Ensure TrueNAS Tailscale IP is in postfix mynetworks on VPS
3. **Email configuration wrong** - Verify SMTP settings in TrueNAS System > Email

**Verification**:
```bash
# Test email from TrueNAS
ssh truenas_admin@192.168.20.200 'midclt call mail.send "{\"subject\": \"Test\", \"text\": \"Test email\"}"'

# Check postfix logs on VPS
ssh -A -p 56777 akunito@100.64.0.6 'journalctl -u postfix --no-pager -n 50'
```

### NFS Mounts Stale on Proxmox/LXC

**Symptoms**: NFS mounts hang, `ls` commands freeze, containers unable to access storage

**Solutions**:
```bash
# On Proxmox/LXC - force unmount
umount -f /mnt/truenas_media

# Remount
mount -a

# Check NFS service on TrueNAS
ssh truenas_admin@192.168.20.200 'midclt call service.query | jq ".[] | select(.service == \"nfs\") | {state, enable}"'

# Restart NFS if needed
ssh truenas_admin@192.168.20.200 'midclt call service.restart nfs'
```

---

## Upgrade History

| Version | Date | Changes | Issues |
|---------|------|---------|--------|
| 24.10.2 | 2025-12-XX | Fresh install on new NVMe boot devices after Patriot SSD failure | Boot pool migration successful |
| 25.04.2.6 | 2026-02-09 | Major version upgrade | Datasets locked after reboot (expected), Graphite pool metrics missing (fixed with custom exporter) |

**Upgrade Notes (25.04.2.6)**:
- Boot pool upgraded from 24.10.2 → 25.04.2.6 without issues
- All datasets locked after reboot (expected behavior for encrypted pools)
- Built-in Graphite reporter no longer exports ZFS pool capacity metrics
- Custom exporter created to fill monitoring gap
- Alert rules updated from filesystem-based to pool-based metrics
- Grafana dashboard updated to use new metric names

**Next Upgrade Considerations**:
- Test dataset auto-unlock on major version upgrades
- Verify Graphite metrics compatibility
- Review API changes (automation-key may need regeneration)

---

## Related Documentation

- [TrueNAS Docker Services](./truenas-services.md) - Full Docker container inventory and compose projects
- [TrueNAS Migration Complete Report](../truenas-migration-complete.md)
- [Boot Pool Analysis (2026-02-09)](~/Nextcloud/myLibrary/MySecurity/TrueNAS/boot-pool-analysis-2026-02-09.md)
- [Unlock TrueNAS Skill](.claude/skills/unlock-truenas.md)
- [Infrastructure Overview](../INFRASTRUCTURE.md)
- [Monitoring Stack](./monitoring-stack.md)

---

## Quick Reference

**Essential Commands**:
```bash
# SSH access
ssh truenas_admin@192.168.20.200

# Pool status
zpool status
zpool list

# Dataset lock status
midclt call pool.dataset.query | jq '.[] | select(.encrypted) | {name, locked}'

# Service status
midclt call service.query | jq '.[] | select(.service | test("nfs|cifs")) | {service, state}'

# System info
midclt call system.info | jq '{version, uptime_seconds, hostname}'

# API health
curl -s https://192.168.20.200/api/v2.0/system/info -H "Authorization: Bearer $TRUENAS_API_KEY" | jq .version
```

**Monitoring URLs**:
- Grafana Dashboard: https://grafana.akunito.com/d/truenas-storage/truenas
- Prometheus Metrics: VPS localhost:9109/metrics (search: `truenas_`)
- Prometheus Alerts: VPS localhost:9090/alerts (search: `TrueNAS`)

**Emergency Contacts**:
- Email Alerts: diego88aku@gmail.com
- Matrix Bot: @claudebot:akunito.com (on VPS)
