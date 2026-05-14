---
id: infrastructure.services.nas
summary: NixOS NAS (nas-aku) operations, monitoring, and maintenance
tags: [infrastructure, storage, nixos, zfs, monitoring, nas]
related_files: [system/app/nas-services.nix, profiles/NAS_PROD-config.nix, .claude/skills/unlock-nas.md]
---

# NAS Storage Server (NixOS)

**Version**: NixOS 25.11 (Xantusia) — migrated from TrueNAS SCALE in March 2026
**SSH Access**: `ssh -A akunito@192.168.20.200` (or `ssh -A akunito@nas-aku` via Tailscale)
**Profile**: NAS_PROD | **Deploy**: `./deploy.sh --profile NAS_PROD` | **Flags**: `-s -u -d`

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
- `extpool/downloads` - Game storage (long-term, NOT for active torrent downloads)
- `extpool/vps-backups` - VPS restic services, libraries, nextcloud (re-downloadable)

> **USB NVMe limitation**: extpool uses a Lexar NQ790 4TB via RTL9210 USB adapter. It cannot handle sustained random writes (ZFS pool goes SUSPENDED). Torrents download to ssdpool, then move to extpool via `~/scripts/move-games-to-extpool.sh` after completion. Recovery: reseat USB → `sudo zpool clear extpool`. See AINF-334.

---

## S3 Sleep Schedule

The NixOS NAS suspends to RAM (S3) nightly to save power (~280W → 0W during sleep).

| Event | Time | Method |
|-------|------|--------|
| Suspend | 23:00 | `systemctl suspend` via systemd timer |
| Wake | 11:00 | RTC alarm (`rtcwake -m no`) |

- ZFS pools remain unlocked in RAM during S3
- **Docker lifecycle**: Two NixOS-managed systemd services (`docker-pre-suspend.service`, `docker-post-resume.service`) bound to `sleep.target` handle graceful stop/start of all Docker containers around suspend. Defined declaratively in `system/app/nas-services.nix`.
- **Pre-suspend**: Stops all compose projects in reverse order (30s timeout per project)
- **Post-resume**: Waits 10s for networking, then starts projects in order (media force-recreated for fresh mounts)
- All backup jobs (restic on VPS pulling from NAS) scheduled within 11:00–23:00 window
- WOL unreliable (r8169 driver limitation) — RTC alarm is the primary wake method
- Suspend/resume race condition with Docker post-resume tracked in `memory/project_nas_suspend_resume_race.md`

---

## Docker Services

The NixOS NAS runs Docker containers across multiple compose projects for media, local proxy, and monitoring exporters. Most run **rootless** (UID 100999+ namespace); `vpn-media` runs root for `NET_ADMIN`. Project list is managed declaratively in `nas-services.nix` (`nasRootDockerProjects` + `nasRootlessDockerProjects`).

See [nas-services.md](./nas-services.md) for full Docker container inventory and compose-project details.

**Key services**: Jellyfin, *arr stack (Sonarr/Radarr/Prowlarr/Bazarr), qBittorrent, Nginx Proxy Manager (NPM, bridge on 192.168.20.200), cloudflared, Tailscale (subnet router), exportarr instances, node-exporter, cAdvisor.

**NPM**: bridge networking (rootless Docker) with ports 80/443/81 on host 192.168.20.200. pfSense DNS resolves `*.local.akunito.com` → 192.168.20.200.

**Compose root**: `/mnt/ssdpool/docker/compose/<project>/docker-compose.yml`.

**Management**:
```bash
# Check all containers (rootless via DOCKER_HOST env)
ssh -A akunito@192.168.20.200 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'

# Restart a compose project
ssh -A akunito@192.168.20.200 'cd /mnt/ssdpool/docker/compose/<project> && docker compose restart'

# Root-Docker project (vpn-media)
ssh -A akunito@192.168.20.200 'sudo docker ps; sudo systemctl status docker-compose-vpn-media.service'
```

---

## Network Shares

### NFS Exports (Primary)
| Share | Dataset | Clients | Purpose |
|-------|---------|---------|---------|
| /mnt/ssdpool/media | ssdpool/media | TrueNAS Docker (Jellyfin) | Media streaming |
| /mnt/ssdpool/workstation_backups | ssdpool/workstation_backups | 192.168.8.96, 192.168.8.92 | Workstation restic backups (NFS-based unified backup system) |
| /mnt/extpool/downloads | extpool/downloads | 192.168.20.0/24, 192.168.8.0/24 | Game downloads (FitGirl, etc.) |

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
- **Authorized User**: `akunito` (sudo access)
- **SSH Keys**: Stored in `~/.ssh/authorized_keys`

### API Access (REMOVED)

The TrueNAS-era REST API on port 9443 (`https://192.168.20.200/api/v2.0/`) was retired with the AINF-336 migration. NixOS NAS administration is via SSH + direct shell tools (`zpool`, `zfs`, `systemctl`, `smartctl`). The `secrets/truenas-api-key.txt` file is kept on VPS_PROD for git-crypt history compatibility but is no longer consumed by any active service.

### Encryption
**Dataset Encryption**:
- **ssdpool datasets**: AES-256-GCM (passphrase-based, ZFS native encryption)
- **extpool**: Not encrypted
- **Passphrase Storage**: `secrets/truenas-encryption-passphrase.txt` (git-crypt encrypted — filename kept for historical compat)
- **Unlock Method**: Use the `/unlock-nas` skill (replaces the old `/unlock-truenas` skill) or run `zfs load-key -r ssdpool` and `zfs mount -a` after reboot

**Boot Pool Encryption**:
- **Status**: Not encrypted (by design)
- **Rationale**: Enables unattended reboots, remote management, automatic failover
- **Security Mitigation**: Physical server security + all data encrypted at dataset level

---

## Monitoring & Alerting

### Metrics Collection (current — post-AINF-336)

All monitoring is Prometheus-native. No TrueNAS Graphite reporter, no
`midclt` API calls — the NAS runs Docker `node-exporter` + custom
NixOS-managed systemd timers that write to the textfile collector.

| Producer | Where | Output | Schedule |
|----------|-------|--------|----------|
| `nas-zfs-pool-metrics.service` (NAS-side, NixOS) | `system/app/nas-services.nix` | `/var/lib/prometheus-node-exporter/textfile/zfs_pools.prom` → `nas_zfs_pool_{size_bytes,allocated_bytes,free_bytes,fragmentation,healthy}` | every 5 min |
| `prometheus-nas-backup.service` (VPS-side) | `system/app/prometheus-nas-backup.nix` | textfile on VPS node-exporter → `nas_backup_{age_seconds,last_success,status}` + `backup_repo_size_bytes` | daily 13:00 |
| `nas-backup-{configs,data}.service` (VPS-side) | `system/app/restic-backup-nas.nix` | textfile → `nas_offsite_backup_{last_success,status,duration_seconds,rsync_warnings}{job}` | daily 15:00 / 16:00 |
| Docker `node-exporter` (NAS) | container in `exporters` compose project | host + ZFS + filesystem + hwmon metrics | scraped 9100 |
| Docker `cadvisor` (NAS) | container in `exporters` compose project | container resource metrics | scraped 8081 |

**Scrape target**: `nas_node` (job) — Prometheus on VPS_PROD pulls `192.168.20.200:9100` (and `8081` for cAdvisor) over Tailscale. Configured via `prometheusRemoteTargets` in `VPS_PROD-config.nix`.

### Grafana Dashboard (current)

**Dashboard**: `system/app/grafana-dashboards/custom/nas.json` (auto-provisioned)
**URL**: `https://grafana.${publicDomain}/d/<nas-uid>/nas`

Panels use `node_*` and `nas_zfs_pool_*` metric names. No `truenas_*` series remain (`servers_truenas_*` TSDB tombstones purged 2026-05-14).

### Prometheus Alert Rules

Defined in `system/app/grafana.nix` under the `nas_alerts` and `backup_alerts` rule groups:

| Alert | Source metric | Threshold | Severity | for |
|-------|---------------|-----------|----------|-----|
| `NASPoolCapacityWarning` | `node_filesystem_avail_bytes / node_filesystem_size_bytes` (zfs mounts) | >80% | warning | 5m |
| `NASPoolCapacityCritical` | same | >90% | critical | 5m |
| `NASPoolUnhealthy` | `node_zfs_zpool_state{state="online"} == 0` | online state lost | critical | 2m |
| `NASDiskTempWarning` | `node_hwmon_temp_celsius{chip~"drivetemp.*"}` | >45°C | warning | 10m |
| `NASDiskTempCritical` | same | >55°C | critical | 5m |
| `NASNotReporting` | `up{job="nas_node"} == 0` | no scrape >5min | warning | 5m |
| `NASMemoryHigh` | `node_memory_*` | >90% | warning | 10m |
| `NasVpsBackupStale` | `nas_backup_age_seconds{dataset=~"vps_.*"}` | >36h | warning | 1h |
| `NasWorkstationBackupStale` | `nas_backup_age_seconds{dataset=~"desk_.*\|x13_.*"}` | >30h | warning | 1h |
| `NasBackupMissing` | `nas_backup_status == 0` | repo missing | critical | 15m |
| `NasOffsiteBackupStale` | `(time() - nas_offsite_backup_last_success)` | >36h | warning | 1h |
| `NasOffsiteBackupFailed` | `nas_offsite_backup_status == 0` | last run failed | critical | 15m |
| `NasOffsiteBackupRsyncWarnings` | `nas_offsite_backup_rsync_warnings` | >0 | warning | 15m |

> The legacy `truenas_alerts` rule group (used by the Graphite-based exporter) was removed in commit `f0ab8d4`. The legacy `TrueNAS*`-prefixed alert names are gone — see git history if needed.

**Notification Channel**: Email + Matrix via VPS Postfix relay (Grafana alerts → contact points configured in `grafana.nix`).

---

## Maintenance Operations

### Scheduled Tasks (NixOS-managed)

All scheduled tasks are declared as systemd timers in `system/app/nas-services.nix` or via standard NixOS modules (`services.zfs.autoScrub`, `services.smartd`).

| Task | Schedule | Retention | Mechanism |
|------|----------|-----------|-----------|
| **ZFS scrub** (all pools) | Monthly, 1st Sun 02:00 | N/A | `services.zfs.autoScrub` |
| **ZFS auto-snapshot** (ssdpool/media) | Daily 01:00 | 7 days | `services.zfs.autoSnapshot` |
| **SMART short test** | Weekly, Sat 04:00 | N/A | `services.smartd.tests` |
| **SMART long test** | Monthly, 15th 03:00 | N/A | `services.smartd.tests` |
| **`nas-zfs-pool-metrics`** (Prometheus textfile) | Every 5 min | N/A | systemd timer |
| **`nas-update-metrics`** (Prometheus textfile) | Every 5 min | N/A | systemd timer |
| **NixOS auto-update** | Weekly | N/A | `services.nixos-auto-update` (see autoSystemUpdate module) |

### Manual Operations

**Unlock encrypted datasets** (after reboot — passphrase in `secrets/truenas-encryption-passphrase.txt`):
```bash
# Recommended: use the skill
/unlock-nas

# Or manually via ZFS native commands
ssh -A akunito@192.168.20.200 'sudo zfs load-key -r ssdpool && sudo zfs mount -a'
# (Will prompt for the passphrase; or pipe via -L file:///path/to/keyfile)
```

**Check pool status**:
```bash
ssh -A akunito@192.168.20.200 'zpool status -v'
ssh -A akunito@192.168.20.200 'zpool list -v'
```

**Trigger a manual scrub**:
```bash
ssh -A akunito@192.168.20.200 'sudo zpool scrub ssdpool'
# Monitor with: zpool status ssdpool
# Cancel with:  sudo zpool scrub -s ssdpool
```

**Check SMART status of all drives**:
```bash
ssh -A akunito@192.168.20.200 'sudo smartctl --scan | awk "{print \$1}" | xargs -I{} sudo smartctl -H -A {} 2>&1 | grep -E "Device|Temperature_Celsius|SMART overall|Reallocated"'
# Or use the existing audit doc: docs/akunito/known-issues/reference_nas_disk_smart.md
```

**Trigger backup metric refresh** (idempotent, used during triage):
```bash
ssh -A akunito@192.168.20.200 'sudo systemctl start nas-zfs-pool-metrics.service'
# Then on VPS: curl localhost:9090/api/v1/query?query=nas_zfs_pool_healthy
```

**Restart NFS / SMB**:
```bash
ssh -A akunito@192.168.20.200 'sudo systemctl restart nfs-server.service'
ssh -A akunito@192.168.20.200 'sudo systemctl restart smbd.service nmbd.service'
```

**Restart all Docker projects** (after suspend/resume race or upgrade):
```bash
ssh -A akunito@192.168.20.200 'systemctl --user restart docker-compose-*.service'
# Root-Docker project (vpn-media):
ssh -A akunito@192.168.20.200 'sudo systemctl restart docker-compose-vpn-media.service'
```

**Deploy a config change**:
```bash
# From a workstation:
git push origin main
ssh -A akunito@192.168.20.200 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles NAS_PROD -s -u -d"
# Flags: -s system rebuild, -u Home Manager, -d skip docker auto-restart (containers are already managed by systemd-compose units)
```

> **Reminder**: never run bare `sudo nixos-rebuild switch` on the NAS — it picks up the wrong `hardware-configuration.nix` and can brick the boot. See `CLAUDE.md` for the deploy invariant.

### ZFS Local Replication (ELIMINATED)

> **Removed (Mar 2026)**: ZFS replication from ssdpool to hddpool was eliminated when hddpool was decommissioned. All data now resides on ssdpool (RAIDZ1). The replication script `scripts/truenas-zfs-replicate.sh` is no longer deployed or scheduled.

---

## Troubleshooting

### Datasets locked after reboot

**Symptoms**: NFS/SMB shares unavailable, Docker containers fail to start with "no such file or directory" on `/mnt/ssdpool/*` paths.

**Root cause**: ssdpool datasets are encrypted (AES-256-GCM, passphrase-based). Keys are not auto-loaded on boot by design — manual unlock prevents unattended dataset access if the host is physically stolen.

**Solution**:
```bash
# Recommended skill:
/unlock-nas

# Or manually:
ssh -A akunito@192.168.20.200 'sudo zfs load-key -r ssdpool && sudo zfs mount -a'

# Check dataset lock state
ssh -A akunito@192.168.20.200 'zfs get -t filesystem encryption,keystatus,mounted ssdpool'
```

### Backup metric reporting wrong values

**Symptoms**: `nas_backup_status{dataset="X"} == 0` or `backup_repo_size_bytes` much smaller than expected.

**Diagnostic path** (informed by AINF triage 2026-05-14):
1. Confirm the source dir actually has data — `sudo du -sh <source>` on the writer.
2. Confirm the user running the backup can read everything — `find <source> | wc -l` as that user.
3. If unreadable: check ZFS `acltype`, then apply POSIX ACL — see `vps-backup-source-acls.service` / `nas-backup-source-acls.service` patterns.
4. Check restic exclude patterns — unanchored `*/foo/*` patterns can accidentally match parent directories. Use absolute paths (`/var/lib/nextcloud-data/foo/*`).
5. Check `nas_offsite_backup_rsync_warnings{job}` — non-zero means rsync is silently dropping files.

Full root-cause history of the nextcloud 0-byte saga is in `docs/akunito/known-issues.md`.

### Email alerts not received

**Symptoms**: No emails from Grafana despite alerts being triggered.

**Common issues**:
1. **VPS Postfix not running** — `ssh -A -p 56777 akunito@100.64.0.6 'systemctl status postfix'`
2. **Network not allowed** — ensure NAS Tailscale IP is in `mynetworks` (managed declaratively in postfix module on VPS_PROD).
3. **Grafana contact point** — check `grafana.nix` contact points + alertmanager rules.

**Test**:
```bash
# Send a test mail from the NAS via the Postfix relay
ssh -A akunito@192.168.20.200 'echo "test body" | mail -s "NAS test" diego88aku@gmail.com'

# Check postfix logs on VPS
ssh -A -p 56777 akunito@100.64.0.6 'journalctl -u postfix --no-pager -n 50'
```

### NFS mounts stale on workstations / containers

**Symptoms**: NFS mounts hang, `ls` freezes, services fail with `Stale file handle`.

**Solutions**:
```bash
# On the client (DESK, LAPTOP, LXC) — force-unmount
sudo umount -f /mnt/NFS_media

# Trigger automount remount
ls /mnt/NFS_media  # or whatever path

# Check the NFS server side
ssh -A akunito@192.168.20.200 'sudo systemctl status nfs-server.service'
ssh -A akunito@192.168.20.200 'sudo exportfs -v'

# Restart NFS server if needed
ssh -A akunito@192.168.20.200 'sudo systemctl restart nfs-server.service'
```

### Post-suspend Docker race

**Symptoms**: After S3 resume (11:00), some Docker containers don't restart; `sshd` may appear refused briefly.

**Known issue**: tracked in `memory/project_nas_suspend_resume_race.md`. Workaround: `sudo systemctl restart docker` on the NAS after the resume completes. The `docker-post-resume.service` should handle it, but a kernel/iptables interaction occasionally needs a manual nudge.

---

## Upgrade History

| Version | Date | Changes | Issues |
|---------|------|---------|--------|
| TrueNAS 24.10.2 | 2025-12-XX | Fresh install on new NVMe boot devices after Patriot SSD failure | Boot pool migration successful |
| TrueNAS 25.04.2.6 | 2026-02-09 | Major version upgrade | Datasets locked after reboot, Graphite pool-capacity metrics missing |
| **NixOS 25.11** | **2026-03 (AINF-336)** | **Migrated off TrueNAS SCALE to NixOS NAS**: declarative system, native ZFS, Docker compose under systemd, all monitoring moved from Graphite to Prometheus textfile collector | See `memory/project_truenas_to_nixos.md` and `docs/akunito/infrastructure/archived/migration/` |
| NixOS auto-update | ongoing | Weekly `services.nixos-auto-update` keeps the system patched declaratively | See `feedback_nas_deploy_flags.md` post-migration audit (2026-04-15) |

**Next upgrade considerations**:
- Test that `services.zfs.autoSnapshot` continues to work across nixpkgs `system.stateVersion` bumps
- Verify Docker compose project units still come up cleanly on major nixpkgs jumps (Docker / runc API changes)
- After ANY change touching `prometheus-nas-backup.nix` or `restic-backup-nas.nix`: trigger the units manually and verify zero `nas_offsite_backup_rsync_warnings`

---

## Related Documentation

- [NAS Docker services](./nas-services.md) — full Docker container inventory + compose projects
- [TrueNAS → NixOS migration archive](../archived/migration/) — historical migration record (AINF-336)
- [Unlock NAS skill](../../../../.claude/skills/unlock-nas.md) — interactive ZFS dataset unlock
- [Known issues](../../known-issues.md) — backup pipeline triage history (nextcloud 0-byte bug, ACL fixes, etc.)
- [Infrastructure overview](../INFRASTRUCTURE.md)

---

## Quick Reference

**Essential commands** (all NixOS / ZFS native — no `midclt`):
```bash
# SSH
ssh -A akunito@192.168.20.200          # LAN
ssh -A akunito@nas-aku                  # Tailscale (if magic DNS is up)

# Pool status
zpool status -v
zpool list -v

# Dataset state (encryption / mount)
zfs get -t filesystem encryption,keystatus,mounted ssdpool

# Service state (NFS / SMB / Docker compose units)
sudo systemctl status nfs-server.service smbd.service nmbd.service
systemctl --user status 'docker-compose-*.service'

# System info
hostnamectl
uptime
zpool history -i ssdpool | tail
```

**Monitoring URLs** (replace `${publicDomain}` with the live one from `secrets/domains.nix`):
- Grafana: `https://grafana.${publicDomain}/d/<nas-uid>/nas`
- Prometheus targets: `https://prometheus.${publicDomain}/targets?search=nas_node`
- Prometheus alerts: `https://prometheus.${publicDomain}/alerts?search=NAS`

**Emergency Contacts**:
- Email Alerts: diego88aku@gmail.com (Grafana → Postfix on VPS_PROD)
- Matrix Bot: `@claudebot:matrix.${publicDomain}`
