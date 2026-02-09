---
id: infrastructure.services.truenas
summary: TrueNAS storage server operations, monitoring, and maintenance
tags: [infrastructure, storage, truenas, zfs, monitoring, nas]
related_files: [system/app/prometheus-graphite.nix, .local/bin/truenas-zfs-exporter.sh, .claude/skills/unlock-truenas.md, scripts/truenas-zfs-replicate.sh]
---

# TrueNAS Storage Server

**Version**: TrueNAS SCALE 25.04.2.6
**SSH Access**: `ssh truenas_admin@192.168.20.200`
**Web UI**: https://192.168.20.200 (HTTPS only)

---

## System Overview

### Hardware
- **Host**: Custom build
- **CPU**: Intel (4 cores)
- **RAM**: 62GB
- **Network**: 2x 10GbE LACP bond (bond0: enp8s0f0 + enp8s0f1)
- **Boot Devices**: 2x Samsung 970 EVO Plus 250GB NVMe (mirrored)

### Storage Pools

| Pool | Size | Used | Type | Encryption | Fragmentation | Health |
|------|------|------|------|------------|---------------|--------|
| boot-pool | 232GB | 5.97GB (2.4%) | 2x NVMe mirror | No | 0% | ✅ ONLINE |
| hddpool | 21.8TB | 5.81TB (26.7%) | 4x HDD, 2x mirror vdevs | Passphrase | 3% | ✅ ONLINE |
| ssdpool | 3.6TB | 996GB (27.6%) | 4x SSD, 2x mirror vdevs | Passphrase | 19% | ✅ ONLINE |

### Key Datasets

**hddpool** (bulk storage):
- `hddpool/media` - Jellyfin media library (movies, TV shows)
- `hddpool/proxmox_backups` - Proxmox VM/LXC backup storage
- `hddpool/workstation_backups` - Workstation restic backups (DESK, LAPTOP_L15, VPS)

**ssdpool** (performance storage):
- `ssdpool/library` - Calibre ebook library
- `ssdpool/myservices` - iSCSI zvol (DATA_4TB for Proxmox)
- `ssdpool/emulators` - RetroArch ROM collection
- `ssdpool/ssd_data_backups` - High-priority backup storage

---

## Network Shares

### NFS Exports (Primary)
| Share | Dataset | Clients | Purpose |
|-------|---------|---------|---------|
| /mnt/hddpool/media | hddpool/media | Proxmox, LXC_HOME | Media streaming (Jellyfin) |
| /mnt/ssdpool/emulators | ssdpool/emulators | LXC_HOME | ROM collection (EmulatorJS) |
| /mnt/ssdpool/library | ssdpool/library | LXC_HOME | Ebook library (Calibre-Web) |
| /mnt/hddpool/proxmox_backups | hddpool/proxmox_backups | Proxmox | VM/LXC backup target |
| /mnt/ssdpool/ssd_data_backups | ssdpool/ssd_data_backups | Proxmox | Fast backup storage |
| /mnt/hddpool/workstation_backups | hddpool/workstation_backups | 192.168.8.96, 192.168.8.92 | Workstation restic backups (NFS-based unified backup system) |

**Access**: NFSv4, no_root_squash for Proxmox, all_squash (mapall_user=akunito) for workstations and LXC containers

### SMB Shares (Desktop Access)
| Share | Dataset | Purpose |
|-------|---------|---------|
| media | hddpool/media | Direct desktop access for management |
| library | ssdpool/library | Direct desktop access for book management |

### iSCSI Targets
| Target IQN | Zvol | Size | Connected To | Purpose |
|------------|------|------|--------------|---------|
| iqn.2005-10.org.freenas.ctl:proxmox-pve | ssdpool/myservices | 1TB | Proxmox | DATA_4TB LVM (Docker volumes, service data) |

**CHAP Authentication**: Enabled (credentials in secrets/domains.nix)

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
- **hddpool datasets**: AES-256-GCM (passphrase-based)
- **ssdpool datasets**: AES-256-GCM (passphrase-based)
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
- **Target**: 192.168.8.85:2003 (LXC_monitoring)
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
- **Pools Covered**: boot-pool, hddpool, ssdpool

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

**Notification Channel**: Email (via LXC_mailer postfix relay)

### Email Alerts (TrueNAS Native)

**SMTP Configuration**:
- **Server**: 192.168.8.89:25 (LXC_mailer postfix relay)
- **From**: truenas@akunito.com
- **To**: diego88aku@gmail.com
- **Security**: PLAIN (no TLS for local relay)
- **Test Status**: ✅ Working (tested 2026-02-09)

**Alert Levels**:
- CRITICAL: Pool degradation, disk failures, scrub errors with errors
- WARNING: Capacity warnings (>80%), SMART warnings, temperature warnings
- NOTICE: Update availability, scrub completion (no errors)

---

## Maintenance Operations

### Scheduled Tasks

| Task | Schedule | Retention | Purpose |
|------|----------|-----------|---------|
| **ZFS Scrub (hddpool)** | 1st Sunday, 2:00 AM | N/A | Data integrity check |
| **ZFS Scrub (ssdpool)** | 2nd Sunday, 2:00 AM | N/A | Data integrity check |
| **SMART Short Test** | Every Saturday, 4:00 AM | N/A | Quick drive health check |
| **SMART Long Test** | 15th of month, 3:00 AM | N/A | Comprehensive drive test |
| **Config Backup** | Every Sunday, 3:00 AM | 30 days | System configuration export |
| **Snapshots (media)** | Daily, 1:00 AM | 7 days | Point-in-time recovery |
| **Snapshots (library)** | Daily, 1:00 AM | 7 days | Point-in-time recovery |
| **Snapshots (emulators)** | Weekly Sunday, 2:00 AM | 4 weeks | Point-in-time recovery |
| **Custom ZFS Metrics** | Every 5 minutes | N/A | Prometheus monitoring |
| **ZFS Local Replication** | Daily, 4:00 AM | 2 snapshots/dataset | ssdpool → hddpool/ssd_data_backups |

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
    "id": "hddpool",
    "unlock_options": {
      "datasets": [
        {"name": "hddpool/media", "passphrase": "YOUR_PASSPHRASE"}
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
ssh truenas_admin@192.168.20.200 'midclt call pool.scrub "hddpool" "START"'
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
ssh truenas_admin@192.168.20.200 'midclt call service.restart iscsitarget'
```

### ZFS Local Replication (ssdpool → hddpool)

**Script**: `scripts/truenas-zfs-replicate.sh` (deployed to `/home/truenas_admin/` on TrueNAS)
**Schedule**: Daily at 4:00 AM via TrueNAS cron job (runs as root)
**Log**: `/var/log/zfs-replicate.log` on TrueNAS

**Replication Map**:

| Source | Destination | Type | Size |
|--------|-------------|------|------|
| `ssdpool/library` | `hddpool/ssd_data_backups/library` | Dataset (ebooks) | ~413 GB |
| `ssdpool/emulators` | `hddpool/ssd_data_backups/emulators` | Dataset (ROMs) | ~55 GB |
| `ssdpool/myservices` | `hddpool/ssd_data_backups/services` | Zvol (iSCSI) | ~2 TB |

**Snapshot Strategy**:
- Prefix: `autoreplica-YYYYMMDD-HHMMSS`
- Retention: 2 per dataset (current + previous for incremental base)
- Encryption: Uses `zfs recv -x encryption` so destination inherits from `hddpool/ssd_data_backups` encryption root

**Manual Operations**:
```bash
# Dry-run (show what would happen)
ssh truenas_admin@192.168.20.200 'sudo /home/truenas_admin/truenas-zfs-replicate.sh --dry-run'

# Incremental replication (daily mode)
ssh truenas_admin@192.168.20.200 'sudo /home/truenas_admin/truenas-zfs-replicate.sh'

# Full re-sync (destroys destination, use if out of sync)
ssh truenas_admin@192.168.20.200 'sudo /home/truenas_admin/truenas-zfs-replicate.sh --init'

# Check replication snapshots
ssh truenas_admin@192.168.20.200 'zfs list -t snapshot -r ssdpool | grep autoreplica'

# Check destination sizes
ssh truenas_admin@192.168.20.200 'zfs list -r hddpool/ssd_data_backups'

# Check log
ssh truenas_admin@192.168.20.200 'tail -50 /var/log/zfs-replicate.log'

# Verify encryption inheritance
ssh truenas_admin@192.168.20.200 'zfs get encryptionroot hddpool/ssd_data_backups/library'
```

**Deploy/Update Script**:
```bash
scp scripts/truenas-zfs-replicate.sh truenas_admin@192.168.20.200:/home/truenas_admin/
ssh truenas_admin@192.168.20.200 'chmod 755 /home/truenas_admin/truenas-zfs-replicate.sh'
```

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

# Verify metrics in Prometheus
curl -s http://192.168.8.85:9109/metrics | grep truenas_zfspool_healthy
```

### Datasets Locked After Reboot

**Symptoms**: NFS/SMB shares unavailable, iSCSI target offline, services report "Dataset not found"

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
1. **SMTP relay not accessible** - Check if LXC_mailer (192.168.8.89) is running
2. **Network not allowed** - Ensure storage network (192.168.20.0/24) is in postfix mynetworks
3. **Email configuration wrong** - Verify SMTP settings in TrueNAS System > Email

**Verification**:
```bash
# Test email from TrueNAS
ssh truenas_admin@192.168.20.200 'midclt call mail.send "{\"subject\": \"Test\", \"text\": \"Test email\"}"'

# Check postfix logs on mailer
ssh akunito@192.168.8.89 'docker logs postfix-relay | tail -50'
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

### iSCSI Target Disconnected

**Symptoms**: Proxmox loses access to DATA_4TB LVM, VMs using that storage fail

**Solutions**:
```bash
# On Proxmox - check iSCSI session
iscsiadm -m session

# Restart iSCSI initiator
systemctl restart iscsid open-iscsi

# Re-login to target
iscsiadm -m node --login

# Check target status on TrueNAS
ssh truenas_admin@192.168.20.200 'midclt call iscsi.target.query'
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

- [TrueNAS Migration Complete Report](docs/infrastructure/truenas-migration-complete.md)
- [Boot Pool Analysis (2026-02-09)](~/Nextcloud/myLibrary/MySecurity/TrueNAS/boot-pool-analysis-2026-02-09.md)
- [Unlock TrueNAS Skill](.claude/skills/unlock-truenas.md)
- [Infrastructure Internal](docs/infrastructure/INFRASTRUCTURE_INTERNAL.md)
- [Monitoring Stack](docs/infrastructure/services/monitoring-stack.md)

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
midclt call service.query | jq '.[] | select(.service | test("nfs|cifs|iscsitarget")) | {service, state}'

# System info
midclt call system.info | jq '{version, uptime_seconds, hostname}'

# API health
curl -s https://192.168.20.200/api/v2.0/system/info -H "Authorization: Bearer $TRUENAS_API_KEY" | jq .version
```

**Monitoring URLs**:
- Grafana Dashboard: https://grafana.local.akunito.com/d/truenas-storage/truenas
- Prometheus Metrics: http://192.168.8.85:9109/metrics (search: `truenas_`)
- Prometheus Alerts: http://192.168.8.85:9090/alerts (search: `TrueNAS`)

**Emergency Contacts**:
- Email Alerts: diego88aku@gmail.com
- Matrix Bot: @claudebot:akunito.com (on LXC_matrix)
