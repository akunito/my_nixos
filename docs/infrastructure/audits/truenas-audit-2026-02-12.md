---
id: audits.truenas.2026-02-12
summary: Performance, reliability, and configuration audit of TrueNAS storage server
tags: [audit, performance, truenas, zfs, storage, network, iscsi]
last_updated: 2026-02-12
---

# TrueNAS Performance, Reliability & Configuration Audit

**Date**: 2026-02-12
**Auditor**: Claude Code
**System**: TrueNAS SCALE 25.04.2.6 (kernel 6.12.15-production+truenas)
**IP Address**: 192.168.20.200 (Storage VLAN 100)
**Hardware**: AMD Ryzen 5 5600G (6C/12T, up to 4.46 GHz), 62 GB RAM (non-ECC), Gigabyte B550 AORUS ELITE V2

---

## Update Log

| Date | Changes |
|------|---------|
| 2026-02-12 | Initial audit. Same-day remediations: ZFS-001 (recordsize=1M), SMB-001 (multichannel), NFS-001 (16 threads), ISCSI-001 (portal bound), ZFS-002 (pool upgrade), SCRUB-001 (scrub started), NIC-001 (ring buffers 8192 + POSTINIT script), MON-001 (SSH key + basename/sudo bug fix, service verified with all 3 datasets reporting), DESK ring buffer 4096→8192 |

---

## Executive Summary

TrueNAS is **well-configured and healthy** with excellent ZFS ARC performance (95.9% hit rate), clean disk health, and working replication. The system has significant performance headroom.

**Key findings requiring attention:**
1. **CRITICAL**: NIC enp8s0f0 has **4.5 million rx_missed_errors** - packets dropped before kernel processing
2. **HIGH**: Two SSDs (sdb, sdc) each have **1 Current_Pending_Sector** - early sign of potential failure
3. **HIGH**: NFS exports for 5 of 6 shares are open to `*` (any host) - security risk
4. **MEDIUM**: Media datasets use 128K recordsize (default) instead of optimal 1M for large sequential files
5. **MEDIUM**: SMB multichannel is disabled - bond can't be fully utilized by SMB clients
6. **MEDIUM**: Scrubs may have been missed in February due to migration/reboot on Feb 9

### Score Summary

| Category | Score | Notes |
|----------|-------|-------|
| **ZFS Pool Health** | 9/10 | All ONLINE, 0 errors, low fragmentation, excellent ARC |
| **Network** | 7/10 | Bond healthy but rx_missed_errors on one NIC, NFS wide-open |
| **Disk Health** | 8/10 | All PASSED, but 2 SSDs have pending sectors |
| **iSCSI** | 7/10 | Working, but 16K volblocksize suboptimal and portal on 0.0.0.0 |
| **General Setup** | 8/10 | Good practices, some tuning opportunities |
| **Monitoring** | 8/10 | 1432 metrics flowing, but backup age file missing |
| **Overall** | **8/10** | Solid storage server with targeted improvements available |

---

## Findings Summary

| ID | Severity | Category | Finding | Status |
|----|----------|----------|---------|--------|
| NIC-001 | **CRITICAL** | Network | enp8s0f0: 4,524,841 rx_missed_errors | **DONE** - ring buffers→8192 + POSTINIT script |
| DISK-001 | **HIGH** | Disk | sdb + sdc: Current_Pending_Sector = 1 each | Monitoring - added SMART watch commands |
| SEC-001 | **HIGH→LOW** | Security | 5/6 NFS exports open to * (any host) | Deprioritized - VLAN 100 isolation sufficient |
| ZFS-001 | **MEDIUM** | ZFS | Media/backup datasets at 128K recordsize (should be 1M) | **DONE** - recordsize=1M set |
| SMB-001 | **MEDIUM** | SMB | Multichannel disabled | **DONE** - enabled via API |
| NIC-002 | **MEDIUM** | Network | Ring buffers at 4096 (max is 8192) | **DONE** - increased to 8192 |
| SCRUB-001 | **MEDIUM** | ZFS | Scrubs possibly missed in Feb (last: Jan 18) | **DONE** - hddpool scrub started |
| ZFS-002 | **MEDIUM** | ZFS | Pool feature upgrade available (hddpool + ssdpool) | **DONE** - longname + large_microzap enabled |
| NFS-001 | **MEDIUM** | NFS | Only 12 server threads (16+ recommended for 10GbE) | **DONE** - increased to 16 |
| ISCSI-001 | **MEDIUM** | iSCSI | Portal listens on 0.0.0.0 (should be 192.168.20.200) | **DONE** - bound to 192.168.20.200 |
| SMB-002 | **LOW** | SMB | xattr=on (dir-based) instead of sa (system attribute) | Open |
| ZFS-003 | **LOW** | ZFS | dnodesize=legacy (could be auto) | Open |
| NET-001 | **LOW** | Network | LACP rate slow (fast preferred for failover) | Open |
| ISCSI-002 | **INFO** | iSCSI | volblocksize=16K (suboptimal but cannot change post-creation) | Info |
| MON-001 | **MEDIUM** | Monitoring | Backup age metrics file missing on LXC_monitoring | **DONE** - SSH key added, basename/sudo bug fixed, service verified |
| MON-002 | **LOW** | Monitoring | No iSCSI session disconnect alert | Open |

---

## Phase 1: System Overview

### Hardware (corrected from docs)

| Property | Value |
|----------|-------|
| CPU | AMD Ryzen 5 5600G (6 cores / 12 threads) |
| RAM | 62 GB DDR4 (non-ECC) |
| Motherboard | Gigabyte B550 AORUS ELITE V2 |
| Network | 2x 10GbE (ixgbe driver, Intel X520-DA2) LACP bond |
| Boot | 2x Samsung 970 EVO Plus 250GB NVMe (mirror) |
| Uptime | 3 days, 2:30 (since migration reboot Feb 9) |
| Load | 0.08 / 0.04 / 0.01 |

### Memory

| Metric | Value |
|--------|-------|
| Total | 62 GB |
| Used (incl ARC) | 51 GB |
| Available | 10.7 GB |
| Swap | 0 B / 0 B |
| ZFS ARC | 48.0 GB (78% of RAM) |

**Assessment**: Excellent. No swap usage. ARC consuming appropriate amount of RAM.

---

## Phase 2: ZFS Pool Performance

### 2.1 Pool Health & Fragmentation

| Pool | Size | Used | Free | Frag | Cap | Health | Last Scrub |
|------|------|------|------|------|-----|--------|------------|
| boot-pool | 232G | 5.58G | 226G | 0% | 2% | ONLINE | N/A |
| hddpool | 21.8T | 6.34T | 15.5T | 3% | 29% | ONLINE | Jan 18 (05:55:22) |
| ssdpool | 3.62T | 1004G | 2.64T | 20% | 27% | ONLINE | Jan 18 (00:59:40) |

- All pools: **0 read/write/checksum errors**
- hddpool: 2x mirror vdevs (4x OOS12000G 12TB HDD)
- ssdpool: 2x mirror vdevs (4x Samsung 870 EVO 2TB SSD)
- boot-pool: mirror (2x Samsung 970 EVO Plus 250GB NVMe)

**Finding ZFS-002**: Both hddpool and ssdpool report "Some supported and requested features are not enabled." Consider `zpool upgrade` to enable all features (one-way operation - pool cannot be downgraded).

**Finding SCRUB-001**: Last scrub was Jan 18 for both pools. Schedule is 1st Sunday (hddpool) and 2nd Sunday (ssdpool). System was rebooted around Feb 9 for migration. Verify Feb scrubs weren't missed; consider running a manual scrub.

### 2.2 Dataset Recordsize Analysis

| Dataset | Current | Optimal | Workload | Impact |
|---------|---------|---------|----------|--------|
| hddpool/media | 128K | **1M** | Large video files (sequential) | 30-50% HDD seq throughput gain |
| hddpool/proxmox_backups | 128K | **1M** | Large backup archives | 20-30% throughput gain |
| hddpool/workstation_backups | 128K | 128K | Restic 8MB packs | Already optimal |
| ssdpool/library | 128K | 128K | Mixed PDFs/EPUBs | Already optimal |
| ssdpool/emulators | 128K | 128K | Mixed ROM sizes | Already optimal |
| ssdpool/myservices (zvol) | 16K volblock | N/A | iSCSI block device | Cannot change post-creation |

**Finding ZFS-001**: `hddpool/media` (5.3 TB of video) and `hddpool/proxmox_backups` (95 GB) would benefit significantly from `recordsize=1M`. Change only affects newly written data. To benefit existing data, requires `zfs send | zfs recv`.

### 2.3 Compression

All datasets use **lz4** compression. Ratios:

| Dataset | Ratio | Notes |
|---------|-------|-------|
| hddpool/media | 1.00x | Expected - pre-compressed video |
| hddpool/proxmox_backups | 1.00x | Compressed VM images |
| hddpool/ssd_data_backups/library | 1.13x | Some text content |
| hddpool/ssd_data_backups/emulators | 1.10x | Some compressible ROMs |
| ssdpool/library | 1.13x | PDF/EPUB mix |
| ssdpool/myservices | 1.04x | Mixed container data |
| ssdpool/.system/configs | 12.45x | Text configs compress extremely well |

**Assessment**: lz4 is correct choice. No datasets have compression=off. No changes needed.

### 2.4 ZFS ARC Efficiency

| Metric | Value | Assessment |
|--------|-------|------------|
| ARC Size | 48.0 GB | Good (78% of 62GB RAM) |
| ARC Max | 61.2 GB | Default (no artificial limit) |
| Hit Rate | **95.9%** | Excellent (>90% target) |
| Hits | 130,720,190 | - |
| Misses | 5,533,278 | - |
| MFU Hits | 119,131,321 | 91% of hits from frequently used cache |
| MRU Hits | 11,588,872 | 9% from recently used cache |
| L2 Hits | 0 | No L2ARC device |
| Prefetch Misses | 2,508,809 | 45% of misses from prefetch |

**Assessment**: ARC is performing excellently. No L2ARC needed. The high MFU:MRU ratio indicates a stable working set that fits well in memory.

### 2.5 L2ARC & SLOG Assessment

- No L2ARC or SLOG devices present
- **L2ARC**: Not needed. ARC hit rate is 95.9% with plenty of headroom
- **SLOG**: ZIL shows 1,270,217 commits over 3 days uptime. All metadata writes go to normal vdevs (zil_itx_metaslab_slog_count = 0). With async NFS and standard sync, SLOG provides minimal benefit. iSCSI uses standard sync, so SLOG could help iSCSI latency but current load is light

**Recommendation**: No SLOG or L2ARC needed at current workload.

### 2.6 Snapshot Space

| Dataset | Snapshot Space | % of Dataset |
|---------|---------------|--------------|
| hddpool/media | 2.66M | ~0% |
| ssdpool/myservices | 3.21G | 0.13% |
| hddpool/ssd_data_backups/services | 2.17G | 0.41% |
| All others | <4M | ~0% |

- **Total snapshots**: 20 (very clean)
- **Autoreplica snapshots**: 2 per dataset pair (correct per retention policy)
- **Replication**: Running successfully daily at 4:00 AM

**Assessment**: Excellent snapshot hygiene. No bloat.

---

## Phase 3: Network Performance

### 3.1 Bond Status

| Property | Value | Assessment |
|----------|-------|------------|
| Mode | IEEE 802.3ad (LACP) | Correct |
| Hash Policy | layer3+4 | Optimal for multi-flow |
| MII Status | up | Good |
| LACP Rate | **slow** | Suboptimal for failover |
| Min Links | 0 | Default |
| Aggregator ID | 2 (both slaves) | Good - both in same LAG |

**Slave Status:**

| Interface | Speed | Duplex | Link Failures | Status |
|-----------|-------|--------|---------------|--------|
| enp8s0f0 | 10000 Mbps | Full | 8 | UP |
| enp8s0f1 | 10000 Mbps | Full | 10 | UP |

**Finding NET-001**: LACP rate is "slow" (30-second intervals). "Fast" (1-second) provides quicker failover detection. Consider changing in TrueNAS network config and matching on the USW Aggregation switch.

### 3.2 NIC Errors

| Counter | enp8s0f0 | enp8s0f1 | Assessment |
|---------|----------|----------|------------|
| rx_errors | 0 | 0 | Good |
| tx_errors | 0 | 0 | Good |
| rx_dropped | 0 | 0 | Good |
| tx_dropped | 1 | 0 | Negligible |
| **rx_missed_errors** | **4,524,841** | **0** | **CRITICAL** |
| rx_no_buffer_count | 0 | 0 | Good |
| rx_crc_errors | 0 | 0 | Good |
| rx_length_errors | 0 | 0 | Good |

**Finding NIC-001 (CRITICAL)**: `enp8s0f0` has **4,524,841 rx_missed_errors**. This means packets arrived at the NIC but were dropped before the kernel could process them. The counter persists across reboots (hardware counter) so this may be cumulative. However, this indicates the NIC's receive ring buffer was full at some point.

**Root cause likely**: Ring buffers were at default (512) before being set to 4096, or a burst of traffic overwhelmed the NIC during high-load operations. The ring buffer max is 8192 - increasing to max would reduce future drops.

**Driver**: ixgbe (Intel X520-DA2), firmware 0x000161ab

### 3.3 Ring Buffers

| Interface | Current RX | Current TX | Max RX | Max TX |
|-----------|-----------|-----------|--------|--------|
| enp8s0f0 | 4096 | 4096 | **8192** | **8192** |
| enp8s0f1 | 4096 | 4096 | **8192** | **8192** |

**Finding NIC-002**: Ring buffers are at 4096 but max is 8192. Increasing to max would provide additional buffer against burst traffic and reduce rx_missed_errors.

### 3.4 MTU

All interfaces at **MTU 1500** (standard). Jumbo frames (9000) could provide 10-15% throughput improvement for large transfers, but requires coordinated change on all L2 endpoints (DESK, Proxmox, pfSense ix0.100, USW Aggregation). Medium effort, low-medium impact.

### 3.5 TCP Buffer Configuration

| Parameter | Value | Optimal | Status |
|-----------|-------|---------|--------|
| net.core.rmem_max | 16777216 (16MB) | 16MB | OK |
| net.core.wmem_max | 16777216 (16MB) | 16MB | OK |
| net.ipv4.tcp_rmem | 4096 1048576 16777216 | Same | OK |
| net.ipv4.tcp_wmem | 4096 1048576 16777216 | Same | OK |
| net.core.netdev_max_backlog | 10000 | >=10000 | OK |
| net.core.somaxconn | 4096 | >=4096 | OK |
| net.ipv4.tcp_congestion_control | **cubic** | bbr preferred | Improvement possible |
| net.ipv4.tcp_mtu_probing | 0 | 0 | OK |

**Assessment**: TCP buffers are well-tuned for 10GbE. Only improvement would be switching congestion control from `cubic` to `bbr` for better performance on high-bandwidth links.

### 3.6 NFS Configuration

| Setting | Value | Assessment |
|---------|-------|------------|
| Protocols | NFSv4 only | Excellent |
| Server Threads | **12** | Low for 10GbE (16+ recommended) |
| Bind IP | 192.168.20.200 | Good (VLAN-only) |
| Allow Non-root | true | Needed for client compatibility |
| Kerberos | false | Expected for home lab |

**Finding NFS-001**: 12 NFS threads for a 12-core system with 10GbE link. Recommend increasing to 16-32 for better concurrency under load.

### 3.7 NFS Export Security

| Export | Allowed Hosts | Assessment |
|--------|--------------|------------|
| hddpool/ssd_data_backups | `*` | **OPEN** |
| hddpool/media | `*` | **OPEN** |
| ssdpool/library | `*` | **OPEN** |
| ssdpool/emulators | `*` | **OPEN** |
| hddpool/proxmox_backups | `*` | **OPEN** |
| hddpool/workstation_backups | 192.168.8.96, .92, .194 | Restricted |

**Finding SEC-001 (HIGH)**: 5 of 6 NFS exports are accessible from any host on VLAN 100. While VLAN 100 is a restricted storage network, best practice is to limit exports to specific client IPs:
- media, emulators, library, ssd_data_backups → Proxmox (192.168.20.82)
- proxmox_backups → Proxmox (192.168.20.82)

### 3.8 SMB Configuration

| Setting | Value | Assessment |
|---------|-------|------------|
| SMB1 | disabled | Good |
| Multichannel | **false** | Should be enabled |
| NTLMv1 auth | false | Good |
| AAPL Extensions | false | OK (no macOS clients) |
| Encryption | DEFAULT | OK |

**Finding SMB-001**: SMB multichannel is disabled. With an LACP bond, enabling multichannel allows SMB clients to use multiple TCP connections, distributing traffic across both bond links. This can double SMB throughput for single-client transfers.

---

## Phase 4: Disk I/O

### 4.1 SMART Health

**SSDs (ssdpool - Samsung 870 EVO 2TB):**

| Disk | Serial | Temp | Hours | Reallocated | Pending | Wear Level | Status |
|------|--------|------|-------|-------------|---------|------------|--------|
| sda | S5Y4R020A077877 | 27°C | 7234 | 0 | 0 | 100% | PASSED |
| sdb | S5Y4R020A077805 | 40°C | 7392 | **1** | **1** | 100% | PASSED |
| sdc | S5Y4R020A077806 | 40°C | 7403 | **1** | **1** | 100% | PASSED |
| sdd | S5Y4R020A077808 | 40°C | 7410 | 0 | 0 | 100% | PASSED |

**Finding DISK-001 (HIGH)**: sdb and sdc each have **1 Reallocated Sector** and **1 Current_Pending_Sector**. While all drives pass SMART overall health, pending sectors indicate blocks that could not be read and are awaiting reallocation. This is an early warning sign.

**Action**: Monitor weekly. If pending sectors increase, plan drive replacement. The mirror topology protects against single-drive failure.

**HDDs (hddpool - OOS12000G 12TB):**

| Disk | Serial | Temp | Hours | Reallocated | Pending | Status |
|------|--------|------|-------|-------------|---------|--------|
| sde | 0007JMMS | 30°C | 7422 | 0 | 0 | PASSED |
| sdf | 000A20MQ | 30°C | 7422 | 0 | 0 | PASSED |
| sdg | 0000XS00 | 30°C | 7422 | 0 | 0 | PASSED |
| sdh | 000E5D5M | 30°C | 7423 | 0 | 0 | PASSED |

**Assessment**: All 4 HDDs in perfect health. Cool temperatures (30°C), zero errors.

**NVMe (boot-pool - Samsung 970 EVO Plus 250GB):**

| Disk | Serial | Temp | Hours | Available Spare | % Used | Status |
|------|--------|------|-------|-----------------|--------|--------|
| nvme0 | S4EUNS0X309014X | 34°C | 1 | 100% | 0% | PASSED |
| nvme1 | S4EUNS0X309029D | 44°C | 1 | 100% | 0% | PASSED |

**Assessment**: Brand new NVMe drives (installed during Feb 9 migration). Perfect health.

### 4.2 I/O Latency (idle)

| Device | r_await (ms) | w_await (ms) | %util | Type |
|--------|-------------|-------------|-------|------|
| sda-sdd (SSD) | 1.2-1.6 | 0.3-0.5 | 0.8-1.0% | SSD pool |
| sde-sdh (HDD) | 6.9-7.0 | 5.9-7.4 | 2.3-2.4% | HDD pool |
| nvme0-1 | 0.13 | 0.29 | 0.02% | Boot pool |
| zd0 (zvol) | 0.36 | 0.41 | 6.1% | iSCSI zvol |

**Assessment**: All latencies within normal ranges. SSDs under 2ms, HDDs under 10ms, NVMe under 1ms. iSCSI zvol shows 6% utilization from Proxmox services.

### 4.3 Throughput Benchmarks (dd)

| Test | Pool | Result | Notes |
|------|------|--------|-------|
| Sequential Write 1GB | hddpool | 2.4 GB/s | ZFS ARC write buffering inflates result |
| Sequential Read 1GB | hddpool | 15.5 GB/s | ARC-cached (RAM speed) |
| Sequential Write 1GB | ssdpool | 3.3 GB/s | Plausible for 4x SSD mirror vdevs |
| Sequential Read 1GB | ssdpool | 15.8 GB/s | ARC-cached (RAM speed) |

**Note**: Read benchmarks reflect ARC cache speed, not disk speed. Write results include ZFS transaction group batching. For real-world NFS/SMB transfers, the 10GbE network (~850 MB/s) is the bottleneck, not storage I/O. The storage layer has significant headroom above network capacity.

---

## Phase 5: iSCSI

### Configuration

| Setting | Value | Assessment |
|---------|-------|------------|
| Target | proxmox-pve | OK |
| Auth | CHAP_MUTUAL | Good (mutual authentication) |
| Extent | zvol/ssdpool/myservices | OK |
| Extent Blocksize | 512 | Standard |
| Portal | **0.0.0.0:3260** | Should be restricted |
| zvol Size | 1.95 TB | OK |
| volblocksize | **16K** | Suboptimal |
| Compression | lz4 (1.04x ratio) | OK |
| Sync | standard | OK |
| Logbias | latency | OK |

**Finding ISCSI-001 (MEDIUM)**: iSCSI portal listens on 0.0.0.0, accepting connections from any network. Should be bound to 192.168.20.200 (storage VLAN only) to prevent unauthorized access.

**Finding ISCSI-002 (INFO)**: volblocksize is 16K. For Proxmox LVM + ext4 workloads, 64K-128K would be more efficient (fewer metadata operations, better sequential I/O). However, **volblocksize cannot be changed after zvol creation**. This would require creating a new zvol with correct blocksize and migrating data. Low priority unless iSCSI performance becomes a concern.

---

## Phase 6: General Setup

### 6.1 ZFS Module Parameters

| Parameter | Value | Default | Assessment |
|-----------|-------|---------|------------|
| zfs_arc_max | 0 (auto) | 0 | Good - uses ~80% RAM |
| zfs_arc_min | 0 (auto) | 0 | OK |
| zfs_prefetch_disable | 0 (enabled) | 0 | Good for sequential workloads |
| zfs_txg_timeout | 5 | 5 | Standard |
| zfs_vdev_async_read_max_active | 3 | 3 | Default |
| zfs_vdev_async_write_max_active | 10 | 10 | Default |
| zfs_vdev_sync_read_max_active | 10 | 10 | Default |
| zfs_vdev_sync_write_max_active | 10 | 10 | Default |

**Assessment**: All defaults. For SSD vdevs, async_read could be increased to 10 and async_write to 30, but current load doesn't warrant tuning.

### 6.2 Dataset Properties

| Property | Current | Optimal | Affected |
|----------|---------|---------|----------|
| atime | off | off | All datasets - correct |
| xattr | **on** (dir-based) | **sa** | All datasets |
| dnodesize | **legacy** | **auto** | All datasets |

**Finding SMB-002 (LOW)**: xattr=on stores extended attributes in a hidden directory (ZFS legacy mode). xattr=sa stores them directly in the dnode (faster, especially for SMB ACL operations). Change with `zfs set xattr=sa <dataset>` - affects new files only.

**Finding ZFS-003 (LOW)**: dnodesize=legacy limits dnode to 512 bytes. Setting to "auto" allows larger dnodes (up to 16K) for datasets with many extended attributes or complex metadata.

### 6.3 Snapshot & Replication

**Snapshot Tasks:**

| Dataset | Schedule | Retention | Status |
|---------|----------|-----------|--------|
| hddpool/media | Daily 1:00 AM | 7 days | Running |
| ssdpool/library | Daily 1:00 AM | 7 days | Running |
| ssdpool/emulators | Weekly Sunday 2:00 AM | 4 weeks | Pending |

**Scrub Tasks:**

| Pool | Schedule | Status |
|------|----------|--------|
| hddpool | 1st Sunday 2:00 AM | Last: Jan 18 |
| ssdpool | 2nd Sunday 2:00 AM | Last: Jan 18 |

**Replication (custom script):**
- Runs daily at 4:00 AM as root via cron
- ssdpool → hddpool/ssd_data_backups (library, emulators, myservices)
- Retention: 2 snapshots per dataset
- Last run: 2026-02-12 04:00:01 - **SUCCESS** (all 3 datasets replicated)

### 6.4 Email Alerts

| Setting | Value |
|---------|-------|
| SMTP Server | 192.168.8.89:25 (LXC_mailer) |
| From | truenas@akunito.com |
| Security | PLAIN (internal network) |

**Assessment**: Functional. Internal-only SMTP relay is acceptable for home lab.

---

## Phase 7: Monitoring

### Metric Flow

| Source | Count | Status |
|--------|-------|--------|
| Graphite metrics (total) | 1,432 | Flowing |
| Disk temperatures (10 disks) | 10 | Flowing |
| ZFS pool health (3 pools) | 3 | All healthy=1 |
| ZFS pool capacity | 3 | Flowing |
| ZFS pool fragmentation | 3 | Flowing |

### Monitoring Gaps

**Finding MON-001 (MEDIUM)**: Backup age metrics file (`/var/lib/prometheus-node-exporter/textfile/truenas_backup.prom`) not found on LXC_monitoring. The SSH-based backup checker service may not be running correctly.

**Finding MON-002 (LOW)**: No alert for iSCSI session disconnects, ZFS ARC hit rate degradation, or NFS mount failures.

### Graphite Metric Mapping Issue

The Graphite exporter is receiving raw metrics in `servers_truenas_*` format rather than the mapped `truenas_*` format for some metrics. The ZFS pool metrics (`truenas_zfspool_*`) are correctly mapped via the custom TrueNAS cron job that sends pool metrics directly.

---

## Remediation Plan

### Critical Priority

| ID | Action | Effort | Impact |
|----|--------|--------|--------|
| NIC-001 | Increase ring buffers to 8192: `ethtool -G enp8s0f0 rx 8192 tx 8192` (repeat for enp8s0f1). Persist via TrueNAS init script. Monitor rx_missed_errors for 24h after change | Low | High - prevents packet drops |

### High Priority

| ID | Action | Effort | Impact |
|----|--------|--------|--------|
| DISK-001 | Add sdb (S5Y4R020A077805) and sdc (S5Y4R020A077806) to watch list. Check SMART weekly. If pending sectors grow to 5+, plan replacement under mirror redundancy | Low | Data safety |
| SEC-001 | Restrict NFS exports to specific client IPs. media/emulators/library/ssd_data_backups/proxmox_backups → Proxmox 192.168.20.82 only. workstation_backups already restricted | Medium | Security |

### Medium Priority

| ID | Action | Effort | Impact |
|----|--------|--------|--------|
| ZFS-001 | Set `recordsize=1M` on hddpool/media and hddpool/proxmox_backups: `zfs set recordsize=1M hddpool/media` (affects new data only) | Low | 30-50% HDD sequential throughput |
| SMB-001 | Enable SMB multichannel via TrueNAS GUI or API: `midclt call smb.update '{"multichannel": true}'` | Low | Up to 2x SMB throughput |
| NIC-002 | Already at 4096, increase to max 8192 (done with NIC-001) | Low | Buffer headroom |
| SCRUB-001 | Run manual scrub: `zpool scrub hddpool && sleep 3600 && zpool scrub ssdpool` | Low | Data integrity |
| ZFS-002 | Evaluate `zpool upgrade hddpool` and `zpool upgrade ssdpool` to enable new features. One-way operation. | Low | New ZFS features |
| NFS-001 | Increase NFS threads to 16: TrueNAS GUI → Services → NFS → Number of Servers → 16 | Low | Better concurrency |
| ISCSI-001 | Bind iSCSI portal to 192.168.20.200 instead of 0.0.0.0 | Low | Security |
| MON-001 | Investigate prometheus-truenas-backup service on LXC_monitoring. Check SSH key access from root@monitoring to truenas_admin@192.168.20.200 | Low | Monitoring coverage |

### Low Priority

| ID | Action | Effort | Impact |
|----|--------|--------|--------|
| SMB-002 | Set `xattr=sa` on SMB-shared datasets: `zfs set xattr=sa hddpool/media && zfs set xattr=sa ssdpool/library` | Low | Faster SMB ACL operations |
| ZFS-003 | Set `dnodesize=auto` on all datasets (affects new files only) | Low | Better metadata handling |
| NET-001 | Change LACP rate to fast on TrueNAS and USW Aggregation switch | Low | Faster failover detection |
| MON-002 | Add iSCSI session disconnect alert to prometheus-graphite.nix | Low | Early warning |

---

## Performance Baselines (2026-02-12)

### Storage

| Metric | hddpool | ssdpool | boot-pool |
|--------|---------|---------|-----------|
| Capacity Used | 29% | 27% | 2% |
| Fragmentation | 3% | 20% | 0% |
| Read Latency (idle) | 6.9-7.0 ms | 1.2-1.6 ms | 0.13 ms |
| Write Latency (idle) | 5.9-7.4 ms | 0.3-0.5 ms | 0.29 ms |
| Utilization (idle) | 2.3% | 0.8% | 0.02% |

### Network

| Path | Streams | Throughput | Notes |
|------|---------|------------|-------|
| DESK → TrueNAS (VLAN 100) | 1 | ~6.8 Gbps | Previous baseline |
| Proxmox → TrueNAS (VLAN 100) | 1 | ~6.8 Gbps | Previous baseline |
| Network is bottleneck, not storage | - | - | Storage I/O >> network capacity |

### ZFS ARC

| Metric | Value |
|--------|-------|
| Size | 48.0 GB / 61.2 GB max |
| Hit Rate | 95.9% |
| MFU:MRU Ratio | 91:9 |

### Disk Health

| Pool | Drives | Temps | Hours | Issues |
|------|--------|-------|-------|--------|
| ssdpool | 4x Samsung 870 EVO 2TB | 27-40°C | ~7400h | 2 drives w/ 1 pending sector |
| hddpool | 4x OOS12000G 12TB | 30°C | ~7422h | None |
| boot-pool | 2x Samsung 970 EVO Plus 250GB | 34-44°C | 1h (new) | None |

---

## Appendix: Corrected Documentation

The existing `docs/infrastructure/services/truenas.md` lists the CPU as "Intel (4 cores)". The actual hardware is **AMD Ryzen 5 5600G (6 cores, 12 threads)**. This should be corrected.
