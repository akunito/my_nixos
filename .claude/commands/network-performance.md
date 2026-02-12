# Network Performance Testing

Skill for testing and diagnosing 10GbE network performance across the homelab.

## Purpose

Use this skill to:
- Run iperf3 bandwidth tests (single/multi-stream/reverse/UDP)
- Verify ARP resolution (detect ARP flux issues)
- Check bond status on DESK and Proxmox
- Monitor NIC counters and ring buffers
- Verify switch port speeds via UniFi API
- Compare results against known baselines

---

## Performance Baselines (2026-02-12)

| Path | Protocol | Streams | Result |
|------|----------|---------|--------|
| DESK → Proxmox (vmbr10) | TCP | 1 | 6.84 Gbps |
| DESK → Proxmox (vmbr10) | TCP | 4 | ~9.4 Gbps |
| DESK → LXC_HOME (vmbr10) | TCP | 1 | ~6.8 Gbps |
| DESK → TrueNAS (via pfSense) | TCP | 1 | ~940 Mbps (1G bottleneck) |
| LXC_HOME → Proxmox (local) | TCP | 1 | ~9.4 Gbps |

**Note**: DESK ↔ TrueNAS is bottlenecked by pfSense 1G lagg0 uplink. Direct 10G path requires switch-level routing or storage VLAN changes.

---

## iperf3 Bandwidth Tests

### Prerequisites

Ensure iperf3 server is running on the target:

```bash
# Start iperf3 server on Proxmox
ssh -A root@192.168.8.82 "iperf3 -s -D"

# Start iperf3 server on LXC_HOME
ssh -A akunito@192.168.8.80 "iperf3 -s -D"
```

### Single Stream Test

```bash
# From DESK to Proxmox
iperf3 -c 192.168.8.82 -t 10

# From DESK to LXC_HOME
iperf3 -c 192.168.8.80 -t 10
```

### Multi-Stream Test (saturate bond)

```bash
# 4 parallel streams
iperf3 -c 192.168.8.82 -t 10 -P 4

# 8 parallel streams (full saturation)
iperf3 -c 192.168.8.82 -t 10 -P 8
```

### Reverse Test (server → client)

```bash
iperf3 -c 192.168.8.82 -t 10 -R
```

### UDP Test (jitter/packet loss)

```bash
# 1 Gbps UDP test
iperf3 -c 192.168.8.82 -u -b 1G -t 10

# 5 Gbps UDP test
iperf3 -c 192.168.8.82 -u -b 5G -t 10
```

---

## ARP Verification

### Check Which MAC Is Used

```bash
# View ARP table for Proxmox
ip neigh show 192.168.8.82

# View ARP table for all 10G targets
ip neigh show | grep -E '192.168.8.(80|82)'
```

### Detect ARP Flux

ARP flux occurs when a multi-homed host (e.g., Proxmox with both vmbr0 and vmbr10) responds to ARP requests on the wrong interface. Symptoms: traffic routes over 1G vmbr0 instead of 10G vmbr10.

```bash
# On Proxmox: check ARP sysctl settings
ssh -A root@192.168.8.82 "sysctl net.ipv4.conf.all.arp_filter net.ipv4.conf.all.arp_ignore net.ipv4.conf.all.arp_announce"

# Expected values (ARP flux fixed):
# net.ipv4.conf.all.arp_filter = 1
# net.ipv4.conf.all.arp_ignore = 1
# net.ipv4.conf.all.arp_announce = 2

# Check route metrics (vmbr10 should have lower metric)
ssh -A root@192.168.8.82 "ip route show default"
# Expected: default via 192.168.8.1 dev vmbr10 metric 100
#           default via 192.168.8.1 dev vmbr0 metric 200
```

### Verify Traffic Path

```bash
# Traceroute to confirm direct path (no extra hops)
traceroute -n 192.168.8.82

# Check which interface traffic uses (run during iperf3)
ssh -A root@192.168.8.82 "ip -s link show vmbr10"
```

---

## Bond Status

### DESK (NixOS bond0)

```bash
# Bond status
cat /proc/net/bonding/bond0

# Key fields to check:
# - Bonding Mode: IEEE 802.3ad Dynamic link aggregation
# - MII Status: up (for both slaves)
# - Partner Mac Address: (should match switch MAC)
# - Aggregator ID: (both slaves same ID = aggregated)
```

### Proxmox (bond0)

```bash
ssh -A root@192.168.8.82 "cat /proc/net/bonding/bond0"

# Also check bridge assignment
ssh -A root@192.168.8.82 "bridge link show"
```

---

## NIC Counter Monitoring

### Check for Errors/Drops

```bash
# DESK NICs
ethtool -S enp11s0f0 | grep -E 'rx_errors|tx_errors|rx_dropped|tx_dropped|rx_crc|rx_missed'
ethtool -S enp11s0f1 | grep -E 'rx_errors|tx_errors|rx_dropped|tx_dropped|rx_crc|rx_missed'

# Proxmox NICs
ssh -A root@192.168.8.82 "ethtool -S enp4s0f0 | grep -E 'rx_errors|tx_errors|rx_dropped|tx_dropped'"
ssh -A root@192.168.8.82 "ethtool -S enp4s0f1 | grep -E 'rx_errors|tx_errors|rx_dropped|tx_dropped'"
```

### Ring Buffer Check

```bash
# DESK
ethtool -g enp11s0f0
# Look for: Pre-set maximums vs Current hardware settings
# If current < max, consider increasing for fewer drops under load

# Proxmox
ssh -A root@192.168.8.82 "ethtool -g enp4s0f0"
```

### Link Speed Verification

```bash
# DESK
ethtool enp11s0f0 | grep Speed
ethtool enp11s0f1 | grep Speed
# Expected: 10000Mb/s

# Proxmox
ssh -A root@192.168.8.82 "ethtool enp4s0f0 | grep Speed"
ssh -A root@192.168.8.82 "ethtool enp4s0f1 | grep Speed"
```

---

## Switch Port Speed Verification

### Via UniFi Controller API

```bash
# Read session cookie from secrets (2FA enabled, cannot use login endpoint directly)
# Cookie stored in secrets/domains.nix (unifiSessionCookie)
# To refresh: Login to https://192.168.8.206:8443 with 2FA, extract 'unifises' cookie from browser DevTools
COOKIE=$(grep unifiSessionCookie secrets/domains.nix | cut -d'"' -f2)

# Get device details for USW Aggregation
curl -sk -b "unifises=$COOKIE" https://192.168.8.206:8443/api/s/default/stat/device | \
  python3 -c "import sys,json; devs=json.load(sys.stdin)['data']
for d in devs:
  if 'Aggregation' in d.get('name','') or 'aggregation' in d.get('model',''):
    for p in d.get('port_table',[]):
      print(f\"Port {p['port_idx']}: {p.get('speed',0)/1000:.0f}G up={p.get('up',False)} name={p.get('name','')}\")"
```

---

## Troubleshooting

### Symptoms: Low bandwidth despite 10G link

1. **Check ARP flux** (most common cause):
   ```bash
   ssh -A root@192.168.8.82 "sysctl net.ipv4.conf.all.arp_filter"
   # If 0 → ARP flux is active, traffic may route over 1G
   ```

2. **Check bond is aggregated** (not just failover):
   ```bash
   cat /proc/net/bonding/bond0 | grep "Aggregator ID"
   # Both slaves should have same Aggregator ID
   ```

3. **Check for NIC errors**:
   ```bash
   ethtool -S enp11s0f0 | grep -c -E '(error|drop|miss|crc).*[1-9]'
   # Should be 0
   ```

4. **Check ring buffers aren't overflowing**:
   ```bash
   ethtool -g enp11s0f0
   # If Current << Max, increase with: ethtool -G enp11s0f0 rx 4096
   ```

### Symptoms: Jellyfin buffering despite good bandwidth

1. Check LXC_HOME is on vmbr10 (not vmbr0):
   ```bash
   ssh -A root@192.168.8.82 "grep net0 /etc/pve/lxc/80.conf"
   # Should show bridge=vmbr10
   ```

2. Check LXC_HOME can reach DESK at 10G:
   ```bash
   ssh -A akunito@192.168.8.80 "iperf3 -c 192.168.8.96 -t 5"
   ```

### ARP Flux Fix (on Proxmox)

If ARP flux is detected, apply this fix on Proxmox:

```bash
ssh -A root@192.168.8.82 "cat > /etc/sysctl.d/99-arp-fix.conf << 'EOF'
# Fix ARP flux for dual-bridge (vmbr0 + vmbr10) setup
# Without this, ARP replies may come from vmbr0 (1G) instead of vmbr10 (10G)
net.ipv4.conf.all.arp_filter = 1
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
EOF
sysctl --system"

# Also set route metric so vmbr10 is preferred
ssh -A root@192.168.8.82 "sed -i 's/gateway 192.168.8.1/gateway 192.168.8.1\n\tmetric 200/' /etc/network/interfaces"
# Note: Only add metric 200 to vmbr0, NOT vmbr10 (vmbr10 defaults to lower metric)
```
