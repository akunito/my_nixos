# Manage TrueNAS

Skill for managing TrueNAS storage server, NFS shares, bonds, and VLAN 100 connectivity.

## Purpose

Use this skill to:
- Check TrueNAS bond and network status
- Manage NFS shares and ACLs
- Verify VLAN 100 storage network connectivity
- Monitor disk health and pool status
- Tune NIC ring buffers and TCP settings
- Unlock encrypted datasets (see also `/unlock-truenas`)

---

## Connection Details

| Access | Address | User |
|--------|---------|------|
| SSH | `ssh truenas_admin@192.168.20.200` | truenas_admin |
| Web GUI | `https://192.168.20.200` | root |
| API | `https://192.168.20.200/api/v2.0/` | API key |

**Network:** TrueNAS is on VLAN 100 (192.168.20.0/24). Access from DESK via bond0.100 (192.168.20.96) or Proxmox via vmbr10.100 (192.168.20.82).

**Switch port:** USW Aggregation SFP+ 5+6 (LACP bond, VLAN-NAS 100 access mode, untagged).

---

## Network & Bond Status

### Check Bond

```bash
ssh truenas_admin@192.168.20.200 "cat /proc/net/bonding/bond0"
# Key fields:
# - Bonding Mode: IEEE 802.3ad
# - MII Status: up (both slaves)
# - Aggregator ID: same on both = aggregated
# - Slave Interfaces: enp8s0f0, enp8s0f1
```

### Check IP & Routes

```bash
ssh truenas_admin@192.168.20.200 "ip addr show bond0"
# Should show 192.168.20.200/24

ssh truenas_admin@192.168.20.200 "ip route show"
# default via 192.168.20.1 dev bond0
```

### Verify Connectivity from All Paths

```bash
# From DESK (VLAN 100 direct)
ping -c 2 192.168.20.200

# From Proxmox (VLAN 100 direct)
ssh -A root@192.168.8.82 "ping -c 2 192.168.20.200"

# From pfSense (VLAN 100 gateway)
ssh admin@192.168.8.1 "ping -c 2 192.168.20.200"

# From LXC container (via Proxmox NFS bind mount path)
ssh -A akunito@192.168.8.80 "ping -c 2 192.168.20.200"
```

---

## NIC Tuning

### Ring Buffers

```bash
# Check current ring buffer sizes
ssh truenas_admin@192.168.20.200 "ethtool -g enp8s0f0"
# If RX/TX < 8192, increase to max:
ssh truenas_admin@192.168.20.200 "sudo ethtool -G enp8s0f0 rx 8192 tx 8192; sudo ethtool -G enp8s0f1 rx 8192 tx 8192"
# Persisted via TrueNAS POSTINIT script: /home/truenas_admin/ring-buffer-init.sh
```

### TCP Buffer Tuning

```bash
# Check current settings
ssh truenas_admin@192.168.20.200 "sysctl net.core.rmem_max net.core.wmem_max net.ipv4.tcp_rmem net.ipv4.tcp_wmem"

# Apply tuning (runtime only)
ssh truenas_admin@192.168.20.200 "sudo sysctl -w net.core.rmem_max=16777216 net.core.wmem_max=16777216 'net.ipv4.tcp_rmem=4096 1048576 16777216' 'net.ipv4.tcp_wmem=4096 1048576 16777216' net.core.netdev_max_backlog=10000"
# Note: TrueNAS SCALE uses /etc/sysctl.d/ or TrueNAS GUI for persistence
```

### NIC Error Counters

```bash
ssh truenas_admin@192.168.20.200 "ethtool -S enp8s0f0 | grep -E 'rx_errors|tx_errors|rx_dropped|tx_dropped|rx_missed'"
ssh truenas_admin@192.168.20.200 "ethtool -S enp8s0f1 | grep -E 'rx_errors|tx_errors|rx_dropped|tx_dropped|rx_missed'"
# rx_missed_errors > 0 → need larger ring buffers
```

---

## NFS Shares

### List NFS Shares

```bash
ssh truenas_admin@192.168.20.200 "cat /etc/exports"
# Or via API:
# curl -sk -H "Authorization: Bearer <token>" https://192.168.20.200/api/v2.0/sharing/nfs
```

### NFS ACL Requirements

After the VLAN 100 migration, NFS shares must allow these client IPs:
- `192.168.20.96` — DESK (VLAN 100)
- `192.168.20.82` — Proxmox (VLAN 100)
- `192.168.20.1` — pfSense (VLAN 100 gateway)
- Or entire `192.168.20.0/24` subnet

### Test NFS Mount Performance

```bash
# From DESK (using VLAN 100 path)
# Write test
dd if=/dev/zero of=/mnt/truenas-share/testfile bs=1M count=1024 oflag=direct
# Read test
dd if=/mnt/truenas-share/testfile of=/dev/null bs=1M iflag=direct

# Monitor NFS stats
nfsstat -c
```

---

## Pool & Disk Health

### Check Pool Status

```bash
ssh truenas_admin@192.168.20.200 "sudo zpool status"
ssh truenas_admin@192.168.20.200 "sudo zpool list -o name,size,alloc,free,frag,cap,health"
```

### Run Manual Scrub

```bash
# Run scrubs sequentially to avoid I/O contention (hddpool ~6h, ssdpool ~1h)
ssh truenas_admin@192.168.20.200 "sudo zpool scrub hddpool"
# Wait for completion, then:
ssh truenas_admin@192.168.20.200 "sudo zpool scrub ssdpool"
# Check progress:
ssh truenas_admin@192.168.20.200 "sudo zpool status | grep scan"
```

### Check Disk Health

```bash
ssh truenas_admin@192.168.20.200 "sudo smartctl -a /dev/sdX"  # Replace X
```

### SMART Sector Watch (sdb + sdc have pending sectors)

```bash
# Baseline (2026-02-12): sdb=Reallocated:1/Pending:1/Uncorrectable:0, sdc=same
ssh truenas_admin@192.168.20.200 "sudo smartctl -A /dev/sdb | grep -E 'Reallocated|Current_Pending|Offline_Uncorrectable'"
ssh truenas_admin@192.168.20.200 "sudo smartctl -A /dev/sdc | grep -E 'Reallocated|Current_Pending|Offline_Uncorrectable'"
# If pending > 5, plan drive replacement under mirror redundancy
```

### Check iSCSI

```bash
ssh truenas_admin@192.168.20.200 "midclt call iscsi.target.query"
# Verify session from Proxmox:
ssh -A root@192.168.8.82 "iscsiadm -m session -P 1"
```

---

## Encrypted Datasets

### Check Lock Status

```bash
# Via TrueNAS API
curl -sk -H "Authorization: Bearer <token>" \
  https://192.168.20.200/api/v2.0/pool/dataset?extra.properties=encrypted,locked | \
  python3 -c "import sys,json; [print(f'{d[\"name\"]}: locked={d.get(\"locked\",False)}') for d in json.load(sys.stdin) if d.get('encrypted')]"
```

### Unlock Datasets

Use the `/unlock-truenas` skill for guided unlocking.

---

## Topology Reference

```
USW Aggregation
  SFP+ 5: TrueNAS enp8s0f0 (LACP member)
  SFP+ 6: TrueNAS enp8s0f1 (LACP member)
  Profile: VLAN-NAS 100 access mode (untagged)

TrueNAS bond0:
  Mode: 802.3ad (LACP)
  Slaves: enp8s0f0 + enp8s0f1
  IP: 192.168.20.200/24
  Gateway: 192.168.20.1 (pfSense ix0.100)
  DAC cables: from previous pfSense ix2+ix3 connection
```

**Traffic paths:**
- DESK ↔ TrueNAS: bond0.100 → switch L2 → TrueNAS (direct, ~6.8 Gbps per stream)
- Proxmox ↔ TrueNAS: vmbr10.100 → switch L2 → TrueNAS (direct, ~6.8 Gbps)
- LXC containers ↔ TrueNAS: via Proxmox bind mounts (same as Proxmox path)
- pfSense ↔ TrueNAS: ix0.100 → switch VLAN 100 → TrueNAS (~10G single link)

**Previous:** TrueNAS was directly cabled to pfSense (lagg0: ix2+ix3), limiting all traffic to ~940 Mbps through pfSense routing.

---

## Troubleshooting

### TrueNAS unreachable

```bash
# Check from pfSense (gateway)
ssh admin@192.168.8.1 "ping -c 2 192.168.20.200"

# Check VLAN 100 on switch (UniFi GUI)
# Verify SFP+ 5+6 show UP and in VLAN-NAS 100 LAG

# Check bond on TrueNAS (requires console/IPMI access if SSH down)
```

### NFS mount hanging

```bash
# Check NFS server is running
ssh truenas_admin@192.168.20.200 "systemctl status nfs-server"

# Check mountpoint from client
mount | grep nfs
showmount -e 192.168.20.200

# Force unmount stale mount
sudo umount -f /mnt/truenas-share
```

### iSCSI LUN issues (Proxmox DATA_4TB)

```bash
# Check iSCSI session on Proxmox
ssh -A root@192.168.8.82 "iscsiadm -m session -P 3"

# Check filesystem
ssh -A root@192.168.8.82 "e2fsck -n /dev/sdb"

# If dirty disconnect: stop containers using the mount, umount, e2fsck -y, remount
```
