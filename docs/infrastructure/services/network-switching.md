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
                    ┌──────────────────────────────────────────────┐
                    │      USW Aggregation (192.168.8.180)         │
                    │              8x SFP+ 10G                     │
                    │                                              │
                    │  SFP+ 1: ──── USW-24-G2 uplink (1G)           │
                    │  SFP+ 2: ──── pfSense ix0 (10G single link)  │
                    │  SFP+ 3: ──┐                                 │
                    │  SFP+ 4: ──┤ LACP bond → Proxmox            │
                    │  SFP+ 5: ──┐                                 │
                    │  SFP+ 6: ──┤ LACP bond → TrueNAS (VLAN 100) │
                    │  SFP+ 7: ──┐                                 │
                    │  SFP+ 8: ──┤ LACP bond → DESK               │
                    └─────────────────────┬────────────────────────┘
                                          │
                               SFP+ 1 ◄──┘ 1G uplink
                                          │
                    ┌─────────────────────┴────────────────┐
                    │        USW-24-G2 (192.168.8.181)     │
                    │           24x 1G RJ45 + 2x SFP       │
                    │                                      │
                    │  SFP 1:  ──── (empty)                │
                    │  SFP 2:  ──── USW Aggregation (1G)   │
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
| SFP+ 1 | 1G | USW-24-G2 SFP 2 | Inter-switch uplink (OFS-DAC-10G-1M, limited by 24-G2 1G SFP) |
| SFP+ 2 | 10G | pfSense ix0 (LAN) | Single link, VLAN trunk: LAN + VLAN 100 + VLAN 200 (Mellanox MCP2104-X001B) |
| SFP+ 3 | 10G | Proxmox enp4s0f0 | LACP bond, trunk: LAN + VLAN 100 (OFS-DAC-10G-2M) |
| SFP+ 4 | 10G | Proxmox enp4s0f1 | LACP bond, trunk: LAN + VLAN 100 (OFS-DAC-10G-2M) |
| SFP+ 5 | 10G | TrueNAS enp8s0f0 | LACP bond, VLAN-NAS 100 access mode (OFS-DAC-10G-1M) |
| SFP+ 6 | 10G | TrueNAS enp8s0f1 | LACP bond, VLAN-NAS 100 access mode (OFS-DAC-10G-1M) |
| SFP+ 7 | 10G | DESK enp11s0f0 | LACP bond, trunk: LAN + VLAN 100 (OFS-DAC-10G-3M) |
| SFP+ 8 | 10G | DESK enp11s0f1 | LACP bond, trunk: LAN + VLAN 100 (OFS-DAC-10G-3M) |

### USW-24-G2 (192.168.8.181)

| Port | Speed | Connection | Notes |
|------|-------|------------|-------|
| SFP 1 | — | Empty | No SFP module inserted |
| SFP 2 | 1G | USW Aggregation SFP+ 5 | Inter-switch uplink (1G hardware limit) |
| RJ45 1-24 | 1G | Various LAN devices | WiFi APs, IoT, etc. |

---

## LACP Bond Groups

| Bond | Switch Ports | Host | Host Interfaces | Aggregate BW |
|------|-------------|------|-----------------|--------------|
| Proxmox | SFP+ 3 + 4 | Proxmox VE | enp4s0f0 + enp4s0f1 | 20 Gbps |
| TrueNAS | SFP+ 5 + 6 | TrueNAS | enp8s0f0 + enp8s0f1 | 20 Gbps |
| DESK | SFP+ 7 + 8 | nixosaku (DESK) | enp11s0f0 + enp11s0f1 | 20 Gbps |

pfSense uses a single 10G link (SFP+ 2, ix0) — LACP bond was removed when TrueNAS moved to switch.

All bonds use IEEE 802.3ad (LACP) mode. Both ends must be configured - switch LAG group AND host bonding.

### VLAN Configuration

| VLAN ID | Name | Tagged Ports | Access Ports | Subnet |
|---------|------|-------------|--------------|--------|
| 1 (native) | LAN | SFP+ 2, 3+4, 7+8 | SFP+ 1 | 192.168.8.0/24 |
| 100 | VLAN-NAS (Storage) | SFP+ 2, 3+4, 7+8 | SFP+ 5+6 | 192.168.20.0/24 |
| 200 | Guest | SFP+ 2 | — | 192.168.9.0/24 |

**VLAN 100 traffic paths** (direct L2, no pfSense routing):
- DESK ↔ TrueNAS: bond0.100 → switch → TrueNAS bond0 (~6.8 Gbps/stream)
- Proxmox ↔ TrueNAS: vmbr10.100 → switch → TrueNAS bond0 (~6.8 Gbps/stream)
- pfSense ↔ TrueNAS: ix0.100 → switch → TrueNAS bond0 (10G single link)

---

## DAC Cables

All connections use SFP+ passive DAC (Direct Attach Copper) cables:

| Ports | Cable Model | Length | Connection |
|-------|-------------|--------|------------|
| SFP+ 1 | OFS-DAC-10G-1M | 1m | USW-24-G2 inter-switch uplink |
| SFP+ 2 | Mellanox MCP2104-X001B | 1m | pfSense single link |
| SFP+ 3+4 | OFS-DAC-10G-2M | 2m | Proxmox LACP bond |
| SFP+ 5+6 | OFS-DAC-10G-1M | 1m | TrueNAS LACP bond (moved from pfSense ix2+ix3) |
| SFP+ 7+8 | OFS-DAC-10G-3M | 3m | DESK LACP bond |

---

## Inter-Switch Uplink Bottleneck

The connection between USW Aggregation and USW-24-G2 is limited to **1 Gbps** because:
- USW-24-G2 (model **USL24B**) has only 1G SFP ports (not SFP+)
- API confirms `speed_caps: 1048608` = no 10G capability on SFP ports
- The OFS-DAC-10G-1M cable is 10G-capable but the port caps it at 1G
- This is a **hardware limitation** — cannot be fixed via configuration

**Impact**: Any device connected to USW-24-G2 (WiFi APs, 1G RJ45 devices) can only reach 10G devices at 1 Gbps maximum.

**Workaround**: Devices needing 10G connectivity must connect directly to USW Aggregation via SFP+.

**Upgrade path**: Replace USW-24-G2 with an SFP+ capable switch (e.g., USW-Pro-24, ~$300-400) for 10G uplink.

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
| DESK → Proxmox | TCP | 1 | 6.84 Gbps | LAN, single 10G link |
| DESK → Proxmox | TCP | 4 | ~9.4 Gbps | Layer3+4 hash across bond |
| DESK → TrueNAS (VLAN 100) | TCP | 1 | 6.81 Gbps | Direct L2, no pfSense |
| DESK → TrueNAS (VLAN 100) | TCP | 4 | ~6.7 Gbps | Same src/dst IP pair = 1 link |
| Proxmox → TrueNAS (VLAN 100) | TCP | 1 | 6.82 Gbps | Direct L2 |
| Proxmox → TrueNAS (VLAN 100) | TCP | 4 | ~6.8 Gbps | Direct L2 |
| DESK → LXC_HOME | TCP | 1 | 6.83 Gbps | Via Proxmox vmbr10 bridge |
| DESK → LXC_HOME | TCP | 4 | ~6.7 Gbps | Via Proxmox vmbr10 bridge |
| LXC_HOME → Proxmox | TCP | 1 | ~9.4 Gbps | Local veth bridge |

**Previous (before VLAN 100 migration)**: DESK → TrueNAS was ~940 Mbps (routed through pfSense lagg0, 1G bottleneck).

**Baseline established after**: TrueNAS switch migration, VLAN 100 setup, ring buffer tuning (4096), TCP buffer optimization.

---

## UniFi Controller Access

- **URL**: https://192.168.8.206:8443
- **Authentication**: Username/password + 2FA (TOTP)
- **Hosted on**: LXC_HOME (Docker macvlan network)
- **Credentials**: Stored in `secrets/domains.nix` (unifiEmail, unifiPassword)
- **API authentication**: Session cookie (`unifises`) — required because controller has 2FA
- **Get cookie**: Login to UniFi UI with 2FA, extract `unifises` cookie from browser DevTools
- **Cookie stored in**: `secrets/domains.nix` (`unifiSessionCookie`)
- **Usage**: `curl -sk -b "unifises=COOKIE_VALUE" https://192.168.8.206:8443/api/s/default/stat/device`
- **Expiry**: Cookie expires after session timeout; re-extract from browser when needed

---

## Related Documentation

- [Network Bonding (NixOS)](../../system-modules/network-bonding.md) - NixOS bond configuration
- [DESK Profile](../../../profiles/DESK-config.nix) - Desktop 10GbE bond settings
- [Infrastructure Overview](../INFRASTRUCTURE.md) - Full infrastructure diagram
- [Infrastructure Internal](../INFRASTRUCTURE_INTERNAL.md) - Proxmox network config details
