# TrueNAS Pools Performance & Configuration Audit

## Context

TrueNAS SCALE 25.04.2.6 (192.168.20.200) serves as the central storage server with two encrypted pools: **ssdpool** (3.6TB, 4x SSD mirror) and **hddpool** (21.8TB, 4x HDD mirror). Connected via 2x 10GbE LACP bond through USW Aggregation switch. Current network baselines show ~6.8 Gbps single-stream throughput. The goal is to audit pool performance, identify latency/throughput improvements, and review the general TrueNAS setup.

## Approach

Run a comprehensive read-only audit via SSH (`truenas_admin@192.168.20.200`) and API, collecting metrics across 7 areas. Produce a scored audit document following the pfSense audit format at `docs/infrastructure/audits/truenas-audit-2026-02-12.md`.

---

## Phase 1: System Baseline (5 min)

Collect system info, memory breakdown, service status, uptime.

**Commands:**
- `midclt call system.info` - version, cores, uptime
- `free -h` + `/proc/meminfo` - RAM usage, swap (swap should be 0)
- `midclt call service.query` - verify NFS, SMB, iSCSI, SMART all running

---

## Phase 2: ZFS Pool Performance (10 min)

### 2.1 Pool Health & Fragmentation
- `zpool list -o name,size,alloc,free,frag,cap,health`
- `zpool status` - errors, scrub history, device status
- Thresholds: frag <20% good, >50% critical

### 2.2 Dataset Recordsize Tuning
- `zfs list -o name,used,avail,recordsize,compression,compressratio -r hddpool ssdpool`
- Key check: media datasets at 128K default should be 1M (30-50% sequential throughput gain on HDD)

### 2.3 Compression Analysis
- `zfs get compressratio,compression -r hddpool ssdpool`
- Verify lz4 enabled everywhere; check if any datasets have compression=off

### 2.4 ZFS ARC Efficiency
- `/proc/spl/kstat/zfs/arcstats` - hit rate, size vs max
- With 62GB RAM, ARC should be ~50GB. Hit rate >90% = good, <70% = critical

### 2.5 L2ARC/SLOG Assessment
- Check if cache/log vdevs exist
- Evaluate need based on ARC hit rate and sync write volume (ZIL stats)

### 2.6 Snapshot Space
- `zfs list -t snapshot -o name,used -r hddpool ssdpool`
- Check for snapshot bloat (>10% of dataset size)

---

## Phase 3: Network Performance (10 min)

### 3.1 Bond Health
- `/proc/net/bonding/bond0` - LACP status, both slaves up, same aggregator ID

### 3.2 NIC Tuning
- `ethtool -g enp8s0f0` - ring buffers (should be 4096, not default 512)
- `ethtool -S enp8s0f0 | grep error` - zero errors expected
- `ethtool -i enp8s0f0` - driver/firmware version

### 3.3 MTU Analysis
- `ip link show bond0 | grep mtu` - check if 1500 or 9000
- Evaluate jumbo frames feasibility (all L2 endpoints must match)

### 3.4 TCP Buffers
- `sysctl net.core.rmem_max net.core.wmem_max` - should be 16MB for 10GbE
- `sysctl net.ipv4.tcp_congestion_control` - bbr preferred
- `sysctl net.core.netdev_max_backlog` - should be >=10000

### 3.5 NFS Tuning
- `midclt call nfs.config` - version, thread count (>=16 recommended), protocols
- `nfsstat -s` - RPC stats, retransmits

### 3.6 SMB Tuning
- `midclt call smb.config` - multichannel status, SMB1 disabled, protocol version

### 3.7 iperf3 Benchmarks
- Single/multi-stream from DESK (192.168.20.96) and Proxmox (192.168.20.82) to TrueNAS
- Compare against 6.8 Gbps baseline

---

## Phase 4: Disk I/O (10 min)

### 4.1 SMART Health
- `smartctl -a` for all 8 drives (4 HDD + 4 SSD) + 2 NVMe
- Key attributes: Reallocated_Sector_Ct=0, Temperature<45C, Wear_Leveling>50%

### 4.2 I/O Latency
- `iostat -xz 1 5` - avg latency per device
- HDD <10ms good, SSD <1ms good

### 4.3 Throughput Benchmarks (optional, causes load)
- `dd` sequential read/write on each pool
- Expected: hddpool ~300MB/s read, ssdpool ~1000MB/s read

---

## Phase 5: iSCSI Review (5 min)

- `midclt call iscsi.extent.query` - blocksize, zvol path
- `zfs get volblocksize,sync,logbias ssdpool/myservices` - alignment check
- Proxmox-side: `iscsiadm -m session -P 3` - MaxRecvDataSegmentLength, queue depth

---

## Phase 6: General Setup Review (5 min)

- ZFS module params: `zfs_arc_max`, `zfs_prefetch_disable`, vdev queue depths
- `zfs get atime,xattr,dnodesize` - atime=off for media, xattr=sa
- Snapshot tasks: `midclt call pool.snapshottask.query`
- Replication log: `/var/log/zfs-replicate.log`
- Email alerts: `midclt call mail.config`
- Update status: `midclt call update.check_available`

---

## Phase 7: Monitoring Gaps (5 min)

Verify Graphite metrics flowing to Prometheus on LXC_monitoring:
- `curl localhost:9109/metrics | grep truenas_` - all metric families present
- Identify gaps: iSCSI session alerts, ARC hit rate alert, NFS health, fragmentation trend

---

## Phase 8: Compile Results

### Output Document
- **Path**: `docs/infrastructure/audits/truenas-audit-2026-02-12.md`
- **Format**: Same as `docs/infrastructure/audits/pfsense-audit-2026-02-04.md`
- **Sections**: Executive summary, score table (ZFS/Network/Disk/iSCSI/Setup/Monitoring), findings table with IDs, detailed per-phase results, remediation plan, performance baselines

### Expected Recommendation Categories

| ID Prefix | Area | Example |
|-----------|------|---------|
| ZFS-xxx | Pool tuning | Recordsize 1M for media, compression check |
| NET-xxx | Network | Ring buffers, TCP buffers, jumbo frames, SMB multichannel |
| NFS-xxx | NFS | Thread count, NFSv4, export restrictions |
| ISCSI-xxx | iSCSI | Block size alignment, queue depth |
| MON-xxx | Monitoring | New alerts (iSCSI, ARC, fragmentation) |
| BAK-xxx | Backups | Replication coverage |
| SEC-xxx | Security | NFS export ACLs, iSCSI portal binding |

### Post-Audit Updates
- Update `docs/infrastructure/services/truenas.md` with new baselines
- Add new alert rules to `system/app/prometheus-graphite.nix` if needed
- Run `python3 scripts/generate_docs_index.py`

---

## Critical Files

| File | Purpose |
|------|---------|
| `docs/infrastructure/audits/pfsense-audit-2026-02-04.md` | Format template |
| `docs/infrastructure/services/truenas.md` | Primary TrueNAS docs (update post-audit) |
| `system/app/prometheus-graphite.nix` | Alert rules (may add new ones) |
| `.claude/commands/manage-truenas.md` | Diagnostic commands reference |
| `secrets/truenas-api-key.txt` | API auth for any API calls |

## Verification

1. All SSH commands execute successfully against 192.168.20.200
2. Audit document is complete with scores, findings, and remediation plan
3. Performance baselines are recorded for future comparison
4. Any new monitoring alerts proposed are validated against existing prometheus-graphite.nix
