---
id: infrastructure.services.network-switching
summary: Physical switching layer documentation - USW Aggregation, USW-24-G2, 10GbE LACP bonds, ARP flux
tags: [infrastructure, network, switching, 10gbe, lacp, sfp, aggregation, arp]
related_files: [profiles/DESK-config.nix, docs/system-modules/network-bonding.md, system/hardware/networking.nix]
---

# Network Switching & 10GbE Infrastructure

This document describes the physical switching layer, SFP+ port assignments, LACP bond groups, and known issues.

---

## Physical Topology

```
                    ┌──────────────────────────────────────┐
                    │      USW Aggregation (192.168.8.180) │
                    │              8x SFP+ 10G             │
                    │                                      │
                    │  SFP+ 1: ──── (available)            │
                    │  SFP+ 2: ──── (available)            │
                    │  SFP+ 3: ──┐                         │
                    │  SFP+ 4: ──┤ LACP bond → Proxmox    │
                    │  SFP+ 5: ──── pfSense ix0 (LAN)     │
                    │  SFP+ 6: ──── USW-24-G2 uplink (1G) │
                    │  SFP+ 7: ──┐                         │
                    │  SFP+ 8: ──┤ LACP bond → DESK       │
                    └─────────────────────┬────────────────┘
                                          │
                               SFP+ 6 ◄──┘ 1G uplink
                                          │
                    ┌─────────────────────┴────────────────┐
                    │        USW-24-G2 (192.168.8.181)     │
                    │           24x 1G RJ45 + 2x SFP       │
                    │                                      │
                    │  SFP 1:  ──── USW Aggregation (1G)   │
                    │  SFP 2:  ──── (available)            │
                    │  RJ45 1-24: Various 1G devices       │
                    │     • WiFi AP (192.168.8.2)          │
                    │     • Various LAN devices             │
                    └──────────────────────────────────────┘
```

---

## SFP+ Port Assignments

### USW Aggregation (192.168.8.180)

| Port | Speed | Connection | Notes |
|------|-------|------------|-------|
| SFP+ 1 | 10G | Available | |
| SFP+ 2 | 10G | Available | |
| SFP+ 3 | 10G | Proxmox enp4s0f0 | LACP bond (LAG group) |
| SFP+ 4 | 10G | Proxmox enp4s0f1 | LACP bond (LAG group) |
| SFP+ 5 | 10G | pfSense ix0 (LAN) | Single link, main LAN |
| SFP+ 6 | 1G | USW-24-G2 SFP 1 | Inter-switch uplink (copper SFP) |
| SFP+ 7 | 10G | DESK enp11s0f0 | LACP bond (LAG group) |
| SFP+ 8 | 10G | DESK enp11s0f1 | LACP bond (LAG group) |

### USW-24-G2 (192.168.8.181)

| Port | Speed | Connection | Notes |
|------|-------|------------|-------|
| SFP 1 | 1G | USW Aggregation SFP+ 6 | Inter-switch uplink |
| SFP 2 | 1G | Available | |
| RJ45 1-24 | 1G | Various LAN devices | WiFi APs, IoT, etc. |

---

## LACP Bond Groups

| Bond | Switch Ports | Host | Host Interfaces | Aggregate BW |
|------|-------------|------|-----------------|--------------|
| DESK bond | SFP+ 7 + 8 | nixosaku (DESK) | enp11s0f0 + enp11s0f1 | 20 Gbps |
| Proxmox bond | SFP+ 3 + 4 | Proxmox VE | enp4s0f0 + enp4s0f1 | 20 Gbps |
| pfSense NAS | (on pfSense) | TrueNAS | via pfSense lagg0 | 2 Gbps (LACP) |

All bonds use IEEE 802.3ad (LACP) mode. Both ends must be configured - switch LAG group AND host bonding.

---

## DAC Cables

All 10G connections use OFS DAC (Direct Attach Copper) cables:
- **Model**: OFS-DAC-10G-2M
- **Length**: 2 meters
- **Type**: SFP+ passive DAC
- **Quantity**: 5 in use (2 DESK, 2 Proxmox, 1 pfSense)

---

## Inter-Switch Uplink Bottleneck

The connection between USW Aggregation and USW-24-G2 is limited to **1 Gbps** because:
- USW-24-G2 has only 1G SFP ports (not SFP+)
- The SFP module in use is a 1G copper SFP

**Impact**: Any device connected to USW-24-G2 (WiFi APs, 1G RJ45 devices) can only reach 10G devices at 1 Gbps maximum.

**Workaround**: Devices needing 10G connectivity must connect directly to USW Aggregation via SFP+.

---

## ARP Flux Issue

### Problem

When Proxmox has two bridges (vmbr0 on 1G, vmbr10 on 10G bond) both with the same subnet IP, Linux's default ARP behavior causes **ARP flux**: ARP replies are sent from whichever interface the kernel prefers, not necessarily the correct one. This can cause 10G clients to resolve Proxmox's MAC address as the vmbr0 (1G) interface, routing all traffic over 1G.

### Symptoms

- iperf3 shows ~940 Mbps instead of expected ~6.8 Gbps
- `ip neigh show 192.168.8.82` shows MAC of vmbr0 instead of vmbr10
- Jellyfin buffering/freezing for 4K content despite 10G link

### Fix (applied on Proxmox)

1. **ARP sysctl settings** (`/etc/sysctl.d/99-arp-fix.conf`):
   ```
   net.ipv4.conf.all.arp_filter = 1
   net.ipv4.conf.all.arp_ignore = 1
   net.ipv4.conf.all.arp_announce = 2
   ```

2. **Route metric** on vmbr0 in `/etc/network/interfaces`:
   ```
   # vmbr0 (1G fallback) - higher metric so vmbr10 is preferred
   auto vmbr0
   iface vmbr0 inet static
       address 192.168.8.82/24
       gateway 192.168.8.1
       metric 200
       bridge-ports eno1
       bridge-stp off
       bridge-fd 0
   ```

### Verification

```bash
# Check sysctl (all should be non-zero)
ssh -A root@192.168.8.82 "sysctl net.ipv4.conf.all.arp_filter net.ipv4.conf.all.arp_ignore net.ipv4.conf.all.arp_announce"

# Check route metric (vmbr0 should have metric 200)
ssh -A root@192.168.8.82 "ip route show default"

# Verify from client (MAC should match vmbr10/bond0)
ip neigh show 192.168.8.82
```

---

## Performance Baselines (2026-02-12)

| Path | Protocol | Streams | Bandwidth | Notes |
|------|----------|---------|-----------|-------|
| DESK → Proxmox | TCP | 1 | 6.84 Gbps | Single stream, direct 10G |
| DESK → Proxmox | TCP | 4 | ~9.4 Gbps | Multi-stream saturates bond |
| DESK → LXC_HOME | TCP | 1 | ~6.8 Gbps | LXC_HOME on vmbr10 |
| DESK → TrueNAS | TCP | 1 | ~940 Mbps | 1G bottleneck (pfSense lagg0) |
| LXC_HOME → Proxmox | TCP | 1 | ~9.4 Gbps | Local bridge, minimal overhead |

**Baseline established after**: LXC_HOME migration from vmbr0 → vmbr10, ARP flux fix, Proxmox bond0 creation.

---

## UniFi Controller Access

- **URL**: https://192.168.8.206:8443
- **Authentication**: Username/password + 2FA (TOTP)
- **Hosted on**: LXC_HOME (Docker macvlan network)
- **API access**: Session cookie method (see `/network-performance` command)
- **Credentials**: Stored in `secrets/domains.nix` (unifiUsername, unifiPassword)

---

## Related Documentation

- [Network Bonding (NixOS)](../../system-modules/network-bonding.md) - NixOS bond configuration
- [DESK Profile](../../../profiles/DESK-config.nix) - Desktop 10GbE bond settings
- [Infrastructure Overview](../INFRASTRUCTURE.md) - Full infrastructure diagram
- [Infrastructure Internal](../INFRASTRUCTURE_INTERNAL.md) - Proxmox network config details
