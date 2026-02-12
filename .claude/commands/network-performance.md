# Network Performance Testing

Skill for testing and diagnosing 10GbE network performance across the homelab.

## Purpose

Use this skill to:
- Run iperf3 bandwidth tests (single/multi-stream/reverse/UDP)
- Verify ARP resolution (detect ARP flux issues)
- Check bond status on DESK, Proxmox, and TrueNAS
- Monitor NIC counters, ring buffers, and TCP tuning
- Verify switch port speeds via UniFi API
- Test VLAN 100 (storage) connectivity
- Compare results against known baselines

---

## Network Topology (2026-02-12)

```
USW Aggregation (192.168.8.180)
  SFP+ 1: USW-24-G2 (1G uplink to GbE switch)
  SFP+ 2: pfSense ix0 (10G single link) — LAN + VLAN 100 + VLAN 200
  SFP+ 3+4: Proxmox bond0 (LACP 20G) — LAN + VLAN 100
  SFP+ 5+6: TrueNAS bond0 (LACP 20G) — VLAN-NAS 100 access mode
  SFP+ 7+8: DESK bond0 (LACP 20G) — LAN + VLAN 100

pfSense interfaces:
  ix0: LAN (SFP+ 2 on switch) — 192.168.8.1/24
  ix0.100: STORAGE_VLAN — 192.168.20.1/24 (VLAN-NAS gateway)
  ix1: Free (was SFP+ 1)
  ix2: Switch_24G2 bridge member (STP enabled)
  ix3: LAPTOP_10G bridge member (STP enabled)
```

## VLAN 100 Storage Network (192.168.20.0/24)

| Device | VLAN 100 IP | Switch Port | Mode |
|--------|-------------|-------------|------|
| pfSense | 192.168.20.1 | SFP+ 2 (tagged) | Gateway |
| DESK | 192.168.20.96 | SFP+ 7+8 (tagged) | bond0.100 |
| Proxmox | 192.168.20.82 | SFP+ 3+4 (tagged) | vmbr10.100 |
| TrueNAS | 192.168.20.200 | SFP+ 5+6 (access) | Untagged |

**Traffic paths:**
- DESK ↔ TrueNAS: bond0.100 → switch L2 → TrueNAS (direct, no pfSense)
- Proxmox ↔ TrueNAS: vmbr10.100 → switch L2 → TrueNAS (direct)
- DESK ↔ Proxmox: bond0 → switch L2 → Proxmox bond0 (direct, LAN)
- Any device → Internet: via pfSense ix0 (LAN)

---

## Performance Baselines (2026-02-12)

| Path | Protocol | Streams | Result | Notes |
|------|----------|---------|--------|-------|
| DESK → Proxmox | TCP | 1 | 6.84 Gbps | LAN, single 10G link |
| DESK → Proxmox | TCP | 4 | ~9.4 Gbps | Layer3+4 hash |
| DESK → TrueNAS (VLAN 100) | TCP | 1 | 6.81 Gbps | Direct L2 |
| DESK → TrueNAS (VLAN 100) | TCP | 4 | ~6.7 Gbps | Same src/dst IP pair |
| Proxmox → TrueNAS (VLAN 100) | TCP | 1 | 6.82 Gbps | Direct L2 |
| Proxmox → TrueNAS (VLAN 100) | TCP | 4 | ~6.8 Gbps | Direct L2 |
| DESK → LXC_HOME | TCP | 1 | 6.83 Gbps | Via Proxmox vmbr10 |
| DESK → LXC_HOME | TCP | 4 | ~6.7 Gbps | Via Proxmox vmbr10 |
| LXC_HOME → Proxmox (local) | TCP | 1 | ~9.4 Gbps | veth bridge |

**Previous (before VLAN 100 migration):** DESK → TrueNAS was ~940 Mbps (routed through pfSense lagg0).

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
# Proxmox (iperf3 pre-installed)
ssh -A root@192.168.8.82 "iperf3 -s -D"

# LXC_HOME (needs nix-shell, run in foreground for stability)
ssh -A akunito@192.168.8.80 "nix-shell -p iperf3 --run 'iperf3 -s -p 5201'"
# Note: -D (daemon) with nix-shell is unreliable — server may die after first test

# TrueNAS
ssh truenas_admin@192.168.20.200 "iperf3 -s -D"
```

### LAN Tests (192.168.8.0/24)

```bash
# DESK → Proxmox
iperf3 -c 192.168.8.82 -t 10           # Single stream (~6.8G)
iperf3 -c 192.168.8.82 -t 10 -P 4      # Multi-stream (~9.4G)
iperf3 -c 192.168.8.82 -t 10 -P 8      # Saturate (~18-20G theoretical)

# DESK → LXC_HOME
iperf3 -c 192.168.8.80 -t 10           # Single stream (~6.8G)
iperf3 -c 192.168.8.80 -t 10 -P 4      # Multi-stream (~6.7G)
```

### VLAN 100 Storage Tests (192.168.20.0/24)

```bash
# DESK → TrueNAS (bind to VLAN 100 source IP)
iperf3 -c 192.168.20.200 -P 1 -t 10 -B 192.168.20.96
iperf3 -c 192.168.20.200 -P 4 -t 10 -B 192.168.20.96

# Proxmox → TrueNAS
ssh -A root@192.168.8.82 "iperf3 -c 192.168.20.200 -P 1 -t 10 -B 192.168.20.82"
ssh -A root@192.168.8.82 "iperf3 -c 192.168.20.200 -P 4 -t 10 -B 192.168.20.82"
```

### Reverse & UDP Tests

```bash
# Reverse test (server → client)
iperf3 -c 192.168.8.82 -t 10 -R

# UDP jitter/packet loss
iperf3 -c 192.168.8.82 -u -b 1G -t 10
iperf3 -c 192.168.8.82 -u -b 5G -t 10
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

### Proxmox (bond0 + vmbr10 + vmbr10.100)

```bash
ssh -A root@192.168.8.82 "cat /proc/net/bonding/bond0"
ssh -A root@192.168.8.82 "ip addr show vmbr10.100"
# Should show 192.168.20.82/24

# Bridge info
ssh -A root@192.168.8.82 "bridge link show"
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

# Proxmox
ssh -A root@192.168.8.82 "ethtool -g enp4s0f0"

# TrueNAS
ssh truenas_admin@192.168.20.200 "ethtool -g enp8s0f0"
```

### TCP Buffer Tuning

```bash
# DESK (set declaratively in network-bonding.nix)
sysctl net.core.rmem_max net.core.wmem_max net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.core.netdev_max_backlog
# Expected: rmem_max=16777216, wmem_max=16777216, tcp_rmem/wmem="4096 1048576 16777216", backlog=10000

# Proxmox
ssh -A root@192.168.8.82 "sysctl net.core.rmem_max net.core.wmem_max"
# Note: Proxmox TCP tuning is runtime-only, needs persistence in /etc/sysctl.d/

# TrueNAS
ssh truenas_admin@192.168.20.200 "sysctl net.core.rmem_max net.core.wmem_max"
# Note: TrueNAS tuning is runtime-only, needs persistence
```

### NIC Error Counters

```bash
# DESK
nix-shell -p ethtool --run 'ethtool -S enp11s0f0 | grep -E "rx_errors|tx_errors|rx_dropped|tx_dropped|rx_crc|rx_missed"'
nix-shell -p ethtool --run 'ethtool -S enp11s0f1 | grep -E "rx_errors|tx_errors|rx_dropped|tx_dropped|rx_crc|rx_missed"'

# Proxmox
ssh -A root@192.168.8.82 "ethtool -S enp4s0f0 | grep -E 'rx_errors|tx_errors|rx_dropped|tx_dropped|rx_missed'"
ssh -A root@192.168.8.82 "ethtool -S enp4s0f1 | grep -E 'rx_errors|tx_errors|rx_dropped|tx_dropped|rx_missed'"
```

---

## ARP Verification

### Check Which MAC Is Used

```bash
ip neigh show 192.168.8.82
ip neigh show | grep -E '192.168.8.(80|82)'
```

### Detect ARP Flux

ARP flux occurs when Proxmox (vmbr0 1G + vmbr10 10G same subnet) responds to ARP on the wrong interface. Symptoms: traffic routes over 1G.

```bash
# On Proxmox: check ARP sysctl settings
ssh -A root@192.168.8.82 "sysctl net.ipv4.conf.all.arp_filter net.ipv4.conf.all.arp_ignore net.ipv4.conf.all.arp_announce"
# Expected: arp_filter=1, arp_ignore=1, arp_announce=2

# Check route metrics (vmbr10 should have lower metric)
ssh -A root@192.168.8.82 "ip route show default"
# Expected: default via 192.168.8.1 dev vmbr10 metric 100
```

### ARP Flux Fix (on Proxmox)

```bash
ssh -A root@192.168.8.82 "cat > /etc/sysctl.d/99-arp-fix.conf << 'EOF'
net.ipv4.conf.all.arp_filter = 1
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
EOF
sysctl --system"
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

1. **Check ARP flux** (most common on Proxmox):
   ```bash
   ssh -A root@192.168.8.82 "sysctl net.ipv4.conf.all.arp_filter"
   ```

2. **Check bond is aggregated**:
   ```bash
   cat /proc/net/bonding/bond0 | grep "Aggregator ID"
   # Both slaves same Aggregator ID = OK
   ```

3. **Check ring buffers** (default 512 = bottleneck):
   ```bash
   nix-shell -p ethtool --run 'ethtool -g enp11s0f0'
   # If Current << Max → increase to 4096
   ```

4. **Check rx_missed_errors** (NIC dropping packets):
   ```bash
   nix-shell -p ethtool --run 'ethtool -S enp11s0f0 | grep rx_missed'
   # Non-zero = NIC can't process fast enough, increase ring buffers
   ```

5. **Check TCP retransmits during test**:
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

### LXC container only getting 1G

```bash
# Verify container is on vmbr10 (10G bridge), not vmbr0 (1G)
ssh -A root@192.168.8.82 "for ct in \$(pct list | tail -n+2 | awk '{print \$1}'); do echo \"CT \$ct: \$(pct config \$ct | grep net0 | grep -o 'bridge=[^ ,]*')\"; done"
# All should show bridge=vmbr10
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

- `/etc/NetworkManager/system-connections/bond0.nmconnection` — bond master
- `/etc/NetworkManager/system-connections/bond0-slave-*.nmconnection` — slave NICs
- `/etc/NetworkManager/system-connections/bond0-vlan100.nmconnection` — VLAN 100 overlay
- `systemd.services.bond-ring-buffers` — sets ring buffer size on boot
- `boot.kernel.sysctl` — TCP buffer tuning for 10GbE
