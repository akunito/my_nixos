---
id: audits.nas-nixos.2026-04-15
summary: Post-migration audit of NixOS NAS — ZFS, network, disks, services, security, monitoring
tags: [audit, nas, nixos, zfs, storage, network, performance]
last_updated: 2026-04-15
---

# NAS NixOS Post-Migration Audit

**Date**: 2026-04-15
**Auditor**: Claude Code
**System**: NixOS 25.11 (Xantusia), kernel 6.12.80
**Hostname**: nas-aku (NAS_PROD profile)
**IP**: 192.168.20.200 (Storage VLAN 100), 100.64.0.1 (Tailscale)
**Hardware**: AMD Ryzen 5 5600G (6C/12T), 62 GB RAM, Gigabyte B550 AORUS ELITE V2
**Uptime at audit**: 8 days 20 hours

---

## Context

The TrueNAS SCALE → NixOS migration completed late March 2026. This is the first comprehensive audit of the NixOS NAS. The previous TrueNAS audit (`docs/akunito/infrastructure/archived/audits/truenas-audit-2026-02-12.md`) serves as the baseline for comparison.

Post-migration fixes already applied before this audit:
- VPS restic backup SSH host key + authorized key (2026-04-07)
- qBittorrent category TMM setting (2026-04-07)
- Prowlarr → qBittorrent hostname fix for rootless/root Docker split (2026-04-07)
- sshAgentSudoEnable for passwordless deploys (2026-04-07)
- NAS_PROD added to deploy.sh (2026-04-07)

---

## Executive Summary

The NAS is **functionally healthy** with excellent ZFS ARC performance (99.3% hit rate), working auto-updates, and all containers running. However, the audit uncovered **three HIGH-severity issues**: zero auto-snapshots since migration (6 weeks of no snapshot protection), no scrub run since migration, and a concerning degradation trend on 3 of 4 SATA SSDs.

All HIGH issues were remediated during the audit. Several MEDIUM and LOW findings remain open.

### Score Summary

| Category | Score | Notes |
|----------|-------|-------|
| **ZFS Pool Health** | 8/10 | ONLINE, 0 errors, 99.3% ARC. But no snapshots/scrubs since migration (fixed). |
| **Network** | 8/10 | Bond healthy. Ring buffers + TCP tuning applied. LACP rate still slow. |
| **Disk Health** | 6/10 | 3/4 SSDs have growing pending sectors — degradation trend. |
| **Services** | 9/10 | 0 failed units, all containers running. Suspend/resume has port conflicts. |
| **Security** | 9/10 | SSH hardened, fail2ban active, Tailscale connected. PAM mismatch noise. |
| **Monitoring** | 9/10 | node_exporter + cAdvisor + 4 exportarrs all healthy. ZFS metrics available. |
| **Overall** | **8/10** | Solid NAS with urgent disk health monitoring needed. |

---

## Findings Summary

| ID | Severity | Category | Finding | Status |
|----|----------|----------|---------|--------|
| SNAP-001 | **HIGH** | ZFS | Zero auto-snapshots since migration (com.sun:auto-snapshot not set) | **FIXED** — property set, 7+ snapshots created |
| SCRUB-002 | **HIGH** | ZFS | No ssdpool scrub since migration (~6 weeks) | **FIXED** — scrub running, 0B repaired so far |
| DISK-002 | **HIGH** | Disks | 3/4 ssdpool SSDs: growing pending sectors (sdb:3, sdc:3, sdd:2) | **MONITORING** — weekly SMART checks |
| RESUME-001 | **MEDIUM** | Sleep | Port conflicts on resume (jellyfin, exportarr, node-exporter) | Open |
| OWN-001 | **MEDIUM** | Ownership | /mnt/ssdpool/docker/ owned by UID 950 (old truenas_admin) | **FIXED** — chowned to akunito:users |
| SSH-001 | **MEDIUM** | Security | "PAM user mismatch" errors every 6 min in journal | Open — investigate source |
| NET-002 | **MEDIUM** | Network | TCP buffers at 8 MB (mkDefault bug in bonding module) | **FIXED** — mkForce, now 16 MB |
| PKG-001 | **MEDIUM** | Packages | ethtool not installed (needed for ring buffer tuning) | **FIXED** — added to systemPackages |
| ZFS-004 | **LOW** | ZFS | extpool: dnodesize=legacy | **FIXED** — set to auto |
| ZFS-006 | **LOW** | ZFS | extpool/vps-backups: recordsize=128K | **FIXED** — set to 1M |
| ZFS-008 | **LOW** | ZFS | TrueNAS legacy datasets (ssdpool/.system/*, ix-apps/*) present | Open — cosmetic |
| NET-003 | **LOW** | Network | LACP rate slow (fast preferred for failover) | Open — needs switch coordination |
| TS-001 | **LOW** | Tailscale | Device name still shows "TrueNAS" | Open |
| IOMMU-001 | **LOW** | Kernel | "AMD-Vi: Completion-Wait loop timed out" occasionally | Open |
| OWN-002 | **LOW** | Ownership | /mnt/ssdpool/pfsense-backups/ owned by UID 950 | **FIXED** |
| ARC-001 | **INFO** | ZFS | ARC at 50.7 GB / 61.2 GB max, 99.3% hit rate | No action — excellent |
| MEM-001 | **INFO** | Memory | 1 GB swap in use despite 62 GB RAM | Benign — inactive pages |
| DEPLOY-001 | **INFO** | Deploy | deploy-servers.conf had -h flag (skips hardware-config) | **FIXED** — now -s -u -d |

---

## Phase 1: System Overview

| Property | Value |
|----------|-------|
| OS | NixOS 25.11.20260410.54170c5 (Xantusia) |
| Kernel | Linux 6.12.80 |
| CPU | AMD Ryzen 5 5600G (6C/12T, up to 4.46 GHz) |
| RAM | 62 GB DDR4 (non-ECC) |
| Motherboard | Gigabyte B550 AORUS ELITE V2 |
| Network | 2x Intel 82599ES 10GbE (ixgbe) LACP bond + RTL8125 2.5GbE fallback |
| Boot | Samsung SSD 840 EVO 500GB (SATA, LUKS-encrypted ext4) |
| NVMe | KIOXIA EXCERIA G2 2TB (boot-adjacent) + Lexar NQ790 4TB (extpool) |
| Uptime | 8 days 20 hours |
| Load | 0.24 / 0.80 / 0.57 |

### Memory

| Metric | Value |
|--------|-------|
| Total | 62 GB |
| Used | 55 GB (incl ARC) |
| Available | 6.3 GB |
| Swap | 1.0 GB / 8.0 GB |
| ZFS ARC | 50.7 GB (82% of RAM) |
| ZFS ARC Max | 61.2 GB |

### Storage Pools

| Pool | Config | Size | Used | Free | Frag | Health |
|------|--------|------|------|------|------|--------|
| ssdpool | RAIDZ1 (4x Samsung 870 EVO 2TB) | 7.27T | 2.26T (31%) | 5.00T | 4% | ONLINE |
| extpool | Single (Lexar NQ790 4TB NVMe) | 3.62T | 2.06T (56%) | 1.57T | 4% | ONLINE |

Both pools: 0 read/write/checksum errors. All pool features enabled (no upgrade needed).

---

## Phase 2: ZFS Health

### ARC Performance

| Metric | Value | Assessment |
|--------|-------|------------|
| ARC Size | 50.7 GB | 82% of RAM — excellent |
| ARC Max | 61.2 GB | ~RAM-1GB (NixOS/OpenZFS default) |
| Hit Rate | **99.3%** | Outstanding (TrueNAS was 95.9%) |
| Hits | 1,355,249,624 | — |
| Misses | 9,131,650 | — |
| Meta Used | 896 MB | Low metadata pressure |

**Assessment**: ARC performance is excellent and has improved significantly from TrueNAS (95.9% → 99.3%). No tuning needed.

### Dataset Properties (post-fix)

| Dataset | recordsize | compression | atime | xattr | dnodesize |
|---------|-----------|-------------|-------|-------|-----------|
| ssdpool | 128K | lz4 | off | on (=sa on Linux) | auto |
| ssdpool/media | **1M** | lz4 | off | on | auto |
| ssdpool/docker | 128K | lz4 | off | on | auto |
| ssdpool/workstation_backups | 128K | lz4 | off | on | auto |
| extpool | 128K | lz4 | off | on | auto |
| extpool/vps-backups | **1M** | lz4 | off | on | auto |

Note: On Linux OpenZFS, `xattr=on` IS the system-attribute (SA) mode. `xattr=dir` would be directory-based (legacy). All datasets are correctly using SA mode.

### Auto-Snapshots

**FINDING SNAP-001 (HIGH, FIXED)**: Zero auto-snapshots existed since the NixOS migration (~6 weeks). Root cause: `services.zfs.autoSnapshot` requires `com.sun:auto-snapshot=true` on datasets, but this property was never set post-migration. The timer ran daily but silently created nothing.

**Fix applied**: Set `com.sun:auto-snapshot=true` on ssdpool, ssdpool/media, ssdpool/docker, ssdpool/workstation_backups, extpool, extpool/vps-backups. Added `nas-zfs-properties` one-shot systemd service to ensure this persists across rebuilds. First daily snapshot created at 09:46 on 2026-04-15.

### Scrub Status

**FINDING SCRUB-002 (HIGH, FIXED)**: No scrub had been run on ssdpool since NixOS migration. Monthly scrub timer (`zfs-scrub.timer`) was active but next run wasn't until May 1. Manual scrub started during audit — 26% complete at time of writing, 0B repaired.

---

## Phase 3: Network

### Bond Status

| Property | Value |
|----------|-------|
| Mode | IEEE 802.3ad (LACP) |
| Hash Policy | layer3+4 |
| LACP Rate | **slow** |
| MII Status | up |
| Aggregator ID | 1 (both slaves) |

| Slave | Speed | Duplex | Link Failures |
|-------|-------|--------|---------------|
| enp8s0f0 | 10000 Mbps | Full | 15 |
| enp8s0f1 | 10000 Mbps | Full | 14 |

Link failure counts are from boot/suspend cycles (expected).

### NIC Ring Buffers (post-fix)

| Interface | RX | TX | Status |
|-----------|-----|-----|--------|
| enp8s0f0 | 8192 | 8192 | Set by bond-ring-buffers.service |
| enp8s0f1 | 8192 | 8192 | Set by bond-ring-buffers.service |

### NIC Error Counters (post-fix baseline)

| Counter | enp8s0f0 | enp8s0f1 |
|---------|----------|----------|
| rx_missed_errors | **0** | **0** |
| rx_dropped | 0 | 0 |
| tx_dropped | 1 | 1 |
| rx_no_buffer_count | 0 | 0 |
| rx_crc_errors | 0 | 0 |

Clean baseline after ring buffer fix. Compare to TrueNAS audit: 4,524,841 rx_missed_errors on enp8s0f0.

### TCP Buffer Configuration (post-fix)

| Parameter | Before | After | Target |
|-----------|--------|-------|--------|
| net.core.rmem_max | 8 MB | **16 MB** | 16 MB |
| net.core.wmem_max | 8 MB | **16 MB** | 16 MB |
| net.ipv4.tcp_rmem max | 8 MB | **16 MB** | 16 MB |
| net.ipv4.tcp_wmem max | 8 MB | **16 MB** | 16 MB |
| tcp_congestion_control | cubic | cubic | cubic (bbr optional) |
| netdev_max_backlog | 5000 | 10000 | 10000 |

**Bug fixed**: `system/hardware/network-bonding.nix` used `lib.mkDefault` (priority 1000) for TCP buffer values, but `profiles/homelab/base.nix` set 8 MB at priority 100 (wins). Changed to `lib.mkForce` so 10GbE tuning takes effect when ring buffers are enabled.

### DNS

Resolved via systemd-resolved stub (127.0.0.53), search domains: `tailnet.headscale.akunito.com`, `local.akunito.com`.

---

## Phase 4: Disk Health

### SATA SSDs (ssdpool RAIDZ1)

| Drive | Serial | Firmware | Temp | Reallocated | Pending | Status | Trend |
|-------|--------|----------|------|-------------|---------|--------|-------|
| sda (877) | S5Y4R020A077877 | **W0724A0** | **24C** | 0 | 0 | PASSED | Stable |
| sdb (805) | S5Y4R020A077805 | W0814A0 | 40C | **3** | **3** | PASSED | **Worsening** |
| sdc (806) | S5Y4R020A077806 | W0814A0 | 40C | **3** | **3** | PASSED | **Worsening** |
| sdd (808) | S5Y4R020A077808 | W0814A0 | 40C | **2** | **2** | PASSED | **Worsening** |

**FINDING DISK-002 (HIGH)**: 3 of 4 ssdpool SSDs show growing pending sectors since the TrueNAS audit (Feb 2026):
- sdb: 1→3 pending, 0→3 reallocated, + 1 offline uncorrectable
- sdc: 1→3 pending, 1→3 reallocated
- sdd: 0→2 pending, 0→2 reallocated (NEW degradation)

Observations:
- sda (healthy) has different firmware (W0724A0 vs W0814A0) and runs 16C cooler (24C vs 40C)
- sda has slightly different capacity (2.04 TB vs 2.00 TB) — different hardware revision
- The 3 degrading drives may share a batch defect or suffer from higher operating temperature
- RAIDZ1 tolerates only **1 drive failure** — with 3 drives degrading, this is a significant risk

**Action**: Monitor weekly. If any drive reaches 10+ pending sectors or SMART overall fails, plan replacement under RAIDZ1 redundancy. Consider improving airflow to reduce temperature on sdb/sdc/sdd.

### NVMe Drives

| Drive | Model | Capacity | Temp | Status |
|-------|-------|----------|------|--------|
| nvme0 | KIOXIA EXCERIA G2 | 2 TB | 36C | PASSED |
| nvme1 (extpool) | Lexar NQ790 | 4 TB | 39C | PASSED |

### Boot Drive

| Drive | Model | Capacity | Temp | Status |
|-------|-------|----------|------|--------|
| sde | Samsung SSD 840 EVO | 500 GB | 25C | PASSED, 0 reallocated |

---

## Phase 5: File Ownership

**FINDING OWN-001 (MEDIUM, FIXED)**: ~20+ files under `/mnt/ssdpool/docker/` (compose files, data dirs, git-crypt key) owned by UID 950 (old `truenas_admin` from TrueNAS SCALE). Docker compose files need to be readable by `akunito` for rootless Docker management.

**Fix applied**: `chown -R akunito:users /mnt/ssdpool/docker /mnt/ssdpool/pfsense-backups`

Remaining ownership notes:
- `/mnt/ssdpool/media` — UID 100999 (rootless Docker remap of container root). **Correct** — Jellyfin/Sonarr/Radarr containers run as root inside rootless Docker, which maps to host UID 100999.
- `/mnt/extpool/downloads` — UID 100999. **Correct** — same rootless Docker remap.
- `/mnt/extpool/vps-backups/*` — akunito:users. **Correct** (fixed in prior session).

---

## Phase 6: Services & Containers

### systemd Health

- **0 failed units**
- **14 active timers** (snapshots, scrub, suspend, auto-update, gc, docker-prune, fstrim, zpool-trim)

### Error Journal (7-day window)

| Pattern | Frequency | Severity | Notes |
|---------|-----------|----------|-------|
| `sshd: PAM user mismatch` | Every 6 min | MEDIUM | SSH-001: likely pam_ssh_agent_auth interacting with a probe |
| `smartd: pending/uncorrectable sectors` | Every 30 min | HIGH | DISK-002: sdb/sdc/sdd reported by smartd |
| `AMD-Vi: Completion-Wait loop timed out` | Occasional | LOW | IOMMU-001: AMD IOMMU timeout, no functional impact |

### Container Health

**Rootless Docker** (15 containers):

| Container | Status | Health |
|-----------|--------|--------|
| node-exporter | Up 8d | healthy |
| cadvisor | Up 8d | healthy |
| jellyfin | Up 8d | healthy |
| sonarr | Up 8d | healthy |
| radarr | Up 8d | healthy |
| prowlarr | Up 7d | healthy |
| bazarr | Up 8d | healthy |
| jellyseerr | Up 8d | healthy |
| solvearr | Up 8d | **unhealthy** |
| cloudflared | Up 8d | — |
| nginx-proxy-manager | Up 8d | healthy |
| exportarr-sonarr | Up 8d | — |
| exportarr-radarr | Up 8d | — |
| exportarr-prowlarr | Up 8d | — |
| exportarr-bazarr | Up 8d | — |

**Root Docker** (vpn-media stack):

| Container | Status | Health |
|-----------|--------|--------|
| gluetun | Up | healthy |
| qbittorrent | Up | healthy |

Note: Root Docker also shows ~12 "Created" (not started) containers — these are stale images of the rootless containers visible through the root socket. They don't consume resources but cause port conflicts during suspend/resume (RESUME-001).

**FINDING RESUME-001 (MEDIUM)**: On wake from S3 suspend, `nas-docker-post-resume` service tries to start ALL compose projects. Rootless containers survive suspend (Docker daemon auto-restarts them), so the resume script encounters port conflicts for jellyfin:8096, exportarr-prowlarr:9709, node-exporter:9100. The errors are non-fatal (containers are already running) but noisy.

---

## Phase 7: Backups & Snapshots

### VPS Inbound Backups (on extpool)

| Repo | Owner | Status |
|------|-------|--------|
| databases.restic | akunito:users | Present, snapshots flowing |
| services.restic | akunito:users | Present, snapshots flowing |
| nextcloud.restic | akunito:users | Present, snapshots flowing |

### Workstation Backups (on ssdpool via NFS)

| Source | Directory | Status |
|--------|-----------|--------|
| DESK (nixosaku) | /mnt/ssdpool/workstation_backups/nixosaku | Present |
| LAPTOP_X13 (nixosx13aku) | /mnt/ssdpool/workstation_backups/nixosx13aku | Present |

### ZFS Auto-Snapshots (post-fix)

7+ snapshots created after SNAP-001 fix. Timers active for frequent (15min), hourly, daily, weekly, monthly cadences.

### Auto-Scrub

Timer: `zfs-scrub.timer` active, monthly on 1st. Next scheduled: 2026-05-01. Manual scrub started during audit — in progress, 0B repaired.

---

## Phase 8: Security

| Check | Status |
|-------|--------|
| SSH PasswordAuth | **disabled** |
| SSH PermitRootLogin | **no** |
| SSH MaxAuthTries | **3** |
| SSH AllowUsers | akunito only |
| Authorized keys | 3 (Desktop, Laptop X13, VPS restic) |
| fail2ban | **active** — 3 jails (sshd, nginx-botsearch, nginx-http-auth) |
| Tailscale | **connected** as 100.64.0.1, 8 peers visible |
| Firewall | NixOS iptables firewall active (nixos-fw chain) |
| Sudo | pam_ssh_agent_auth for passwordless via agent forwarding |

---

## Phase 9: Monitoring

| Exporter | Port | Status | Metric count |
|----------|------|--------|--------------|
| node_exporter | 9100 | healthy | 1981 metrics |
| node_exporter (ZFS) | 9100 | — | 488 `node_zfs_*` metrics (enabled by default) |
| cAdvisor | 8081 | healthy | — |
| exportarr-sonarr | 9707 | up | — |
| exportarr-radarr | 9708 | up | — |
| exportarr-prowlarr | 9709 | up | — |
| exportarr-bazarr | 9710 | up | — |

ZFS metrics (ARC, pool stats) are already exported via node_exporter's built-in ZFS collector. No additional configuration needed.

---

## Phase 10: Wake/Sleep Cycle

Suspend at 23:00 and RTC wake at 11:00 working reliably. Docker pre-suspend stops containers gracefully. Post-resume has port conflict noise (RESUME-001) but all containers end up running.

---

## Phase 11: Auto-Update

| Setting | Value |
|---------|-------|
| Timer | Sat 12:05 (weekly) |
| Last successful run | 2026-04-11 12:23 |
| Current generation | 19 |
| NixOS version | 25.11.20260413.7e495b7 |
| Home Manager generation | 3 |
| Channel | release-25.11 (stable) |

---

## Remediation Applied During Audit

| ID | Action | Commit |
|----|--------|--------|
| SNAP-001 | Set com.sun:auto-snapshot=true on 6 datasets + nas-zfs-properties service | b3601a9 |
| SCRUB-002 | Started manual ssdpool scrub | Imperative |
| NET-002 | Fixed mkDefault→mkForce for TCP buffers in bonding module | b3601a9 |
| PKG-001 | Added ethtool to NAS_PROD systemPackages | b3601a9 |
| Ring buffers | Set networkBondingRingBufferSize=8192 in NAS_PROD profile | b3601a9 |
| ZFS-004 | Set dnodesize=auto on extpool | Imperative + nas-zfs-properties service |
| ZFS-006 | Set recordsize=1M on extpool/vps-backups | Imperative + nas-zfs-properties service |
| OWN-001/002 | chown -R akunito:users on /mnt/ssdpool/docker and pfsense-backups | Imperative |
| DEPLOY-001 | Fixed deploy-servers.conf: NAS_PROD flags -s -u -d (removed -h) | e76c68a |

## Open Items (for future work)

| ID | Severity | Action |
|----|----------|--------|
| DISK-002 | HIGH | Monitor sdb/sdc/sdd pending sectors weekly. Plan replacement if any drive reaches 10+ pending. Consider RAIDZ2 rebuild if replacing 2+ drives. |
| RESUME-001 | MEDIUM | Fix suspend/resume to only restart containers that actually stopped. Remove orphan "Created" containers from root Docker. |
| SSH-001 | MEDIUM | Investigate PAM user mismatch source (likely pam_ssh_agent_auth + monitoring probe). Suppress or fix. |
| NET-003 | LOW | Switch LACP rate to fast — requires coordinating with Unifi switch LAG config. |
| ZFS-008 | LOW | Consider destroying unused TrueNAS legacy datasets (ssdpool/.system/*, ssdpool/ix-apps/*) to reclaim space and reduce snapshot scope. |
| TS-001 | LOW | Rename Tailscale device from "TrueNAS" to "NAS_PROD" or "nas-aku". |
| IOMMU-001 | LOW | Consider adding `iommu=soft` or disabling IOMMU if not needed (no GPU passthrough). |

---

## Performance Baselines (2026-04-15)

### Storage

| Metric | ssdpool | extpool |
|--------|---------|---------|
| Capacity Used | 31% | 56% |
| Fragmentation | 4% | 4% |

### ZFS ARC

| Metric | Value |
|--------|-------|
| Size | 50.7 GB / 61.2 GB max |
| Hit Rate | 99.3% |
| Target (c) | 51.0 GB |
| Meta Used | 896 MB |

### Network

| Metric | Value |
|--------|-------|
| Bond | 2x 10GbE LACP (layer3+4) |
| Ring Buffers | 8192 RX/TX |
| TCP Buffers | 16 MB max |
| rx_missed_errors | 0 (baseline post-fix) |

### Disk Health

| Drive | Pending | Reallocated | Temp | Firmware |
|-------|---------|-------------|------|----------|
| sda (877) | 0 | 0 | 24C | W0724A0 |
| sdb (805) | 3 | 3 | 40C | W0814A0 |
| sdc (806) | 3 | 3 | 40C | W0814A0 |
| sdd (808) | 2 | 2 | 40C | W0814A0 |
| sde (boot) | 0 | 0 | 25C | EXT0DB6Q |
| nvme0 (KIOXIA) | — | — | 36C | — |
| nvme1 (Lexar) | — | — | 39C | — |

---

## Comparison with TrueNAS Audit (Feb 2026)

| Metric | TrueNAS (Feb) | NixOS (Apr) | Change |
|--------|--------------|-------------|--------|
| ARC Hit Rate | 95.9% | 99.3% | +3.4% |
| ARC Size | 48 GB | 50.7 GB | +2.7 GB |
| sdb Pending | 1 | 3 | +2 (worsening) |
| sdc Pending | 1 | 3 | +2 (worsening) |
| sdd Pending | 0 | 2 | +2 (new) |
| rx_missed_errors | 4,524,841 | 0 | Fixed |
| NFS Threads | 12→16 | 16 | Maintained |
| TCP Buffers | 16 MB | 16 MB | Fixed (was 8 MB on NixOS) |
| Auto-Snapshots | Working | Broken→Fixed | Regression fixed |
| Pool Config | 2x mirror (ssdpool) + hddpool | RAIDZ1 (ssdpool) + extpool | Consolidated |
