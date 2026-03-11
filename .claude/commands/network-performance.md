# Network Performance Testing

Skill for testing and diagnosing 10GbE network performance across the homelab.

> **Note**: Proxmox (SFP+ 3+4) LACP bond is **INACTIVE** -- Proxmox shut down Feb 2026.
> All akunito LXC containers migrated to VPS + TrueNAS. Proxmox-related tests are historical only.

## Purpose

Use this skill to:
- Run iperf3 bandwidth tests (single/multi-stream/reverse/UDP)
- Check bond status on DESK and TrueNAS
- Monitor NIC counters, ring buffers, and TCP tuning
- Verify switch port speeds via UniFi API
- Test VLAN 100 (storage) connectivity between DESK and TrueNAS
- Compare results against known baselines

---

## Network Topology (2026-02-23)

```
USW Aggregation (192.168.8.180)
  SFP+ 1: USW-24-G2 (1G uplink to GbE switch)
  SFP+ 2: pfSense ix0 (10G single link) -- LAN + VLAN 100 + VLAN 200
  SFP+ 3+4: INACTIVE (Proxmox shut down Feb 2026)
  SFP+ 5+6: TrueNAS bond0 (LACP 20G) -- VLAN-NAS 100 access mode
  SFP+ 7+8: DESK bond0 (LACP 20G) -- LAN + VLAN 100

pfSense interfaces:
  ix0: LAN (SFP+ 2 on switch) -- 192.168.8.1/24
  ix0.100: STORAGE_VLAN -- 192.168.20.1/24 (VLAN-NAS gateway)
  ix2: Switch_24G2 bridge member (STP enabled)
  ix3: LAPTOP_10G bridge member (STP enabled)
```

## VLAN 100 Storage Network (192.168.20.0/24)

| Device | VLAN 100 IP | Switch Port | Mode | Status |
|--------|-------------|-------------|------|--------|
| pfSense | 192.168.20.1 | SFP+ 2 (tagged) | Gateway | Active |
| DESK | 192.168.20.96 | SFP+ 7+8 (tagged) | bond0.100 | Active |
| Proxmox | 192.168.20.82 | SFP+ 3+4 (tagged) | vmbr10.100 | **INACTIVE** |
| TrueNAS | 192.168.20.200 | SFP+ 5+6 (access) | Untagged | Active |

**Active traffic paths:**
- DESK <-> TrueNAS: bond0.100 -> switch L2 -> TrueNAS (direct, no pfSense)
- Any device -> Internet: via pfSense ix0 (LAN)

---

## Performance Baselines

| Path | Protocol | Streams | Result | Notes |
|------|----------|---------|--------|-------|
| DESK -> TrueNAS (VLAN 100) | TCP | 1 | 6.81 Gbps | Direct L2 |
| DESK -> TrueNAS (VLAN 100) | TCP | 4 | ~6.7 Gbps | Same src/dst IP pair |
| DESK -> Proxmox | TCP | 1 | 6.84 Gbps | HISTORICAL (Proxmox shut down) |
| DESK -> Proxmox | TCP | 4 | ~9.4 Gbps | HISTORICAL (Proxmox shut down) |
| Proxmox -> TrueNAS (VLAN 100) | TCP | 1 | 6.82 Gbps | HISTORICAL (Proxmox shut down) |
| Proxmox -> TrueNAS (VLAN 100) | TCP | 4 | ~6.8 Gbps | HISTORICAL (Proxmox shut down) |
| DESK -> LXC_HOME | TCP | 1 | 6.83 Gbps | HISTORICAL (Proxmox shut down) |
| DESK -> LXC_HOME | TCP | 4 | ~6.7 Gbps | HISTORICAL (Proxmox shut down) |
| LXC_HOME -> Proxmox (local) | TCP | 1 | ~9.4 Gbps | HISTORICAL (Proxmox shut down) |

**Previous (before VLAN 100 migration):** DESK -> TrueNAS was ~940 Mbps (routed through pfSense lagg0).

**Note on multi-stream:** Layer3+4 hash distributes traffic by IP+port. Same src/dst IP pair = same link (~10G max). Different IPs or many random ports spread across both links (~20G aggregate).

---

## iperf3 Bandwidth Tests

### Prerequisites

**Firewall:** NixOS firewall blocks port 5201 by default. Either:
1. Run iperf3 server on the remote, test from DESK (outbound OK)
2. Or temporarily open the port: `sudo iptables -I nixos-fw 3 -p tcp --dport 5201 -j nixos-fw-accept`

**Install iperf3** (if not in PATH):
```bash
nix-shell -p iperf3 --run 'iperf3 ...'
```

### Start Server

```bash
# TrueNAS
ssh truenas_admin@192.168.20.200 "iperf3 -s -D"
```

### VLAN 100 Storage Tests (192.168.20.0/24)

```bash
# DESK -> TrueNAS (bind to VLAN 100 source IP)
iperf3 -c 192.168.20.200 -P 1 -t 10 -B 192.168.20.96
iperf3 -c 192.168.20.200 -P 4 -t 10 -B 192.168.20.96
```

### Reverse & UDP Tests

```bash
# Reverse test (server -> client)
iperf3 -c 192.168.20.200 -t 10 -R -B 192.168.20.96

# UDP jitter/packet loss
iperf3 -c 192.168.20.200 -u -b 1G -t 10 -B 192.168.20.96
iperf3 -c 192.168.20.200 -u -b 5G -t 10 -B 192.168.20.96
```

---

## Bond Status Verification

### DESK (NixOS bond0 + bond0.100)

```bash
# Bond status
cat /proc/net/bonding/bond0
# Key: MII Status up, both slaves same Aggregator ID

# VLAN 100 interface
ip addr show bond0.100
# Should show 192.168.20.96/24

# Per-link traffic distribution (run during iperf3)
watch -n 0.5 'cat /sys/class/net/enp11s0f0/statistics/tx_bytes; cat /sys/class/net/enp11s0f1/statistics/tx_bytes'
```

### TrueNAS (bond0)

```bash
ssh truenas_admin@192.168.20.200 "cat /proc/net/bonding/bond0"
# Should show access mode (no VLAN, IP = 192.168.20.200)
```

---

## NIC Tuning Verification

### Ring Buffers

```bash
# DESK (should be 4096 via systemd service)
nix-shell -p ethtool --run 'ethtool -g enp11s0f0'
# Look for: Current hardware settings: RX 4096, TX 4096

# TrueNAS
ssh truenas_admin@192.168.20.200 "ethtool -g enp8s0f0"
```

### TCP Buffer Tuning

```bash
# DESK (set declaratively in network-bonding.nix)
sysctl net.core.rmem_max net.core.wmem_max net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.core.netdev_max_backlog
# Expected: rmem_max=16777216, wmem_max=16777216, tcp_rmem/wmem="4096 1048576 16777216", backlog=10000

# TrueNAS
ssh truenas_admin@192.168.20.200 "sysctl net.core.rmem_max net.core.wmem_max"
# Note: TrueNAS tuning is runtime-only, needs persistence
```

### NIC Error Counters

```bash
# DESK
nix-shell -p ethtool --run 'ethtool -S enp11s0f0 | grep -E "rx_errors|tx_errors|rx_dropped|tx_dropped|rx_crc|rx_missed"'
nix-shell -p ethtool --run 'ethtool -S enp11s0f1 | grep -E "rx_errors|tx_errors|rx_dropped|tx_dropped|rx_crc|rx_missed"'
```

---

## Switch Port Speed Verification

### Via UniFi Controller API

```bash
COOKIE=$(grep unifiSessionCookie secrets/domains.nix | cut -d'"' -f2)

curl -sk -b "unifises=$COOKIE" https://192.168.8.206:8443/api/s/default/stat/device | \
  python3 -c "import sys,json; devs=json.load(sys.stdin)['data']
for d in devs:
  if 'Aggregation' in d.get('name','') or 'aggregation' in d.get('model',''):
    for p in d.get('port_table',[]):
      print(f\"Port {p['port_idx']}: {p.get('speed',0)/1000:.0f}G up={p.get('up',False)} name={p.get('name','')}\")"
```

---

## Troubleshooting

### Low bandwidth despite 10G link

1. **Check bond is aggregated**:
   ```bash
   cat /proc/net/bonding/bond0 | grep "Aggregator ID"
   # Both slaves same Aggregator ID = OK
   ```

2. **Check ring buffers** (default 512 = bottleneck):
   ```bash
   nix-shell -p ethtool --run 'ethtool -g enp11s0f0'
   # If Current << Max -> increase to 4096
   ```

3. **Check rx_missed_errors** (NIC dropping packets):
   ```bash
   nix-shell -p ethtool --run 'ethtool -S enp11s0f0 | grep rx_missed'
   # Non-zero = NIC can't process fast enough, increase ring buffers
   ```

4. **Check TCP retransmits during test**:
   ```bash
   # High retransmits (>10K) indicate receiver bottleneck
   # Look at iperf3 "Retr" column
   ```

### Multi-stream not aggregating across both links

Layer3+4 hash: same src+dst IP pair always goes to same link. To spread:
- Use different source/dest ports (iperf3 -P 8+ with diverse ports)
- NFS: multiple mount points with different source ports
- Real workloads: many concurrent connections naturally spread

### VLAN 100 not reachable

```bash
# Check VLAN interface exists
ip addr show bond0.100

# Check 8021q module loaded
lsmod | grep 8021q

# Check NM connection active
nmcli connection show --active | grep vlan

# Reload if needed
sudo nmcli connection reload
sudo nmcli connection up bond0-vlan100
```

---

## NixOS Bonding Module Reference

### Files

| File | Purpose |
|------|---------|
| `lib/defaults.nix` | Default values for all bonding flags |
| `system/hardware/network-bonding.nix` | Bonding + VLAN + ring buffer module |
| `profiles/DESK-config.nix` | DESK bonding + VLAN 100 config |

### Flags (in systemSettings)

| Flag | Default | DESK Value | Description |
|------|---------|------------|-------------|
| `networkBondingEnable` | false | true | Enable bonding |
| `networkBondingMode` | "802.3ad" | "802.3ad" | LACP mode |
| `networkBondingInterfaces` | [] | ["enp11s0f0" "enp11s0f1"] | NICs to bond |
| `networkBondingDhcp` | true | true | DHCP on bond0 |
| `networkBondingVlans` | [] | [{id=100; name="storage"; address="192.168.20.96/24"}] | VLAN overlays |
| `networkBondingRingBufferSize` | null | 4096 | NIC ring buffer size |
| `networkBondingLacpRate` | "fast" | (default) | LACP negotiation rate |
| `networkBondingXmitHashPolicy` | "layer3+4" | (default) | Hash distribution policy |

### What the module generates

- `/etc/NetworkManager/system-connections/bond0.nmconnection` -- bond master
- `/etc/NetworkManager/system-connections/bond0-slave-*.nmconnection` -- slave NICs
- `/etc/NetworkManager/system-connections/bond0-vlan100.nmconnection` -- VLAN 100 overlay
- `systemd.services.bond-ring-buffers` -- sets ring buffer size on boot
- `boot.kernel.sysctl` -- TCP buffer tuning for 10GbE
