---
id: network-bonding
summary: Network bonding (LACP link aggregation) for increased bandwidth and failover
tags: [networking, bonding, lacp, performance, failover]
related_files:
  - system/hardware/network-bonding.nix
  - lib/defaults.nix
  - profiles/DESK-config.nix
---

# Network Bonding (LACP Link Aggregation)

## Overview

The network bonding module (`system/hardware/network-bonding.nix`) provides declarative configuration for Linux bonding, enabling:
- **Increased bandwidth**: Aggregate multiple network interfaces (e.g., 2x 10GbE = 20Gbps)
- **Automatic failover**: If one link fails, traffic continues on remaining links
- **LACP support**: IEEE 802.3ad dynamic link aggregation with switch coordination

**Supported network managers:**
- NetworkManager (recommended for desktops/laptops)
- systemd-networkd (for headless servers)

## Architecture

### NetworkManager Path (Default)
When `networkManager = true` (default for DESK/LAPTOP profiles):
1. Kernel bonding module loaded via `boot.kernelModules`
2. NetworkManager creates bond via declarative connection profiles in `/etc/NetworkManager/system-connections/`
3. Connection files generated at build time:
   - `bond0.nmconnection` - Master bond interface
   - `bond0-slave-<iface>.nmconnection` - Slave interface profiles
4. NetworkManager manages bond lifecycle (create, configure DHCP, failover)

### systemd-networkd Path
When `useNetworkd = true`:
1. Kernel bonding module loaded
2. Bond created via `networking.bonds.bond0`
3. IP configuration via `networking.interfaces.bond0.useDHCP`

## Prerequisites

### Switch Configuration (CRITICAL)
**Before enabling bonding**, configure LACP/LAG on your switch:

#### UniFi Switch
1. Navigate to: Devices → Switch → Ports
2. Select the ports connected to your server (e.g., ports 5-6)
3. Port Profile → Create New Profile:
   - Name: `LAG-Server-10GbE`
   - Link Aggregation: **LACP** (802.3ad)
4. Apply profile to both ports
5. Verify: Switch should show ports in a single aggregate group

#### Other Switches
- Cisco: `channel-group X mode active` (LACP)
- HPE/Aruba: Configure LACP trunk
- pfSense: System → Advanced → Networking → LACP

**Important**: Both interfaces must be connected to the **same switch** with LAG configured. Cross-switch bonding requires MLAG/vPC.

## Configuration

### Enable Bonding (Profile-Level)

In your profile config (e.g., `DESK-config.nix`):

```nix
systemSettings = {
  # Network Bonding (10GbE LACP aggregation)
  # Prerequisites: Configure LAG on switch before enabling
  # TO DISABLE: Set networkBondingEnable = false; (default)
  networkBondingEnable = true;
  networkBondingMode = "802.3ad";  # LACP
  networkBondingInterfaces = [ "enp11s0f0" "enp11s0f1" ];
  networkBondingDhcp = true;  # Use DHCP (or set to false for static IP)

  # Optional: Static IP configuration (when networkBondingDhcp = false)
  # networkBondingStaticIp = {
  #   address = "192.168.8.96/24";
  #   gateway = "192.168.8.1";
  # };

  # Optional: Advanced tuning (defaults shown)
  networkBondingLacpRate = "fast";  # LACP rate: "fast" (1s) or "slow" (30s)
  networkBondingMiimon = "100";     # Link monitoring interval (ms)
  networkBondingXmitHashPolicy = "layer3+4";  # Traffic distribution policy
};
```

### Disable Bonding

To disable on a profile without bonding hardware (e.g., copying DESK to a laptop):

```nix
systemSettings = {
  networkBondingEnable = false;  # Disables entire bonding module
  # Remove or comment out other networkBonding* settings
};
```

**Default**: Bonding is **disabled** in `lib/defaults.nix`, so it's opt-in per profile.

## Configuration Options

All options are defined in `lib/defaults.nix` and can be overridden per profile:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `networkBondingEnable` | bool | `false` | Enable network bonding module |
| `networkBondingMode` | string | `"802.3ad"` | Bonding mode (see Modes section) |
| `networkBondingInterfaces` | list | `[]` | Interface names to bond (e.g., `["eth0" "eth1"]`) |
| `networkBondingDhcp` | bool | `true` | Use DHCP for bond IP (false for static) |
| `networkBondingStaticIp` | attrset\|null | `null` | Static IP config: `{ address, gateway }` |
| `networkBondingLacpRate` | string | `"fast"` | LACP rate: `"fast"` (1s) or `"slow"` (30s) |
| `networkBondingMiimon` | string | `"100"` | Link monitoring interval (ms) |
| `networkBondingXmitHashPolicy` | string | `"layer3+4"` | Traffic distribution policy |

### Bonding Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `802.3ad` (LACP) | Dynamic link aggregation with switch coordination | **Recommended**: Max bandwidth + failover with LACP-capable switch |
| `balance-rr` | Round-robin across all slaves | High throughput, no switch config needed (but less compatible) |
| `active-backup` | One active, others standby | Simple failover, no switch config, single link speed |
| `balance-xor` | XOR hash distribution | Load balancing without LACP |

**Recommendation**: Use `802.3ad` (LACP) for production deployments with managed switches.

### Traffic Distribution Policies

`networkBondingXmitHashPolicy` controls how traffic is distributed across slaves:

| Policy | Description | Best For |
|--------|-------------|----------|
| `layer2` | MAC address hash | Single IP, multiple MACs |
| `layer3+4` (default) | IP + port hash | Multiple connections, best balance |
| `layer2+3` | MAC + IP hash | Mixed traffic |
| `encap3+4` | Inner IP+port (for tunnels) | VPN/VXLAN traffic |

## Verification

### After Deployment

```bash
# Check bond status
cat /proc/net/bonding/bond0

# Expected output:
# Bonding Mode: IEEE 802.3ad Dynamic link aggregation
# MII Status: up
# LACP active: on
# Slave Interface: enp11s0f0
# MII Status: up
# Speed: 10000 Mbps
# Slave Interface: enp11s0f1
# MII Status: up
# Speed: 10000 Mbps

# Check IP address
ip addr show bond0
# Should show: inet 192.168.8.x/24 ... bond0

# Check NetworkManager connections
nmcli connection show | grep bond
# Should show: bond0, bond0-slave-enp11s0f0, bond0-slave-enp11s0f1 (all active)

# Test connectivity
ping -c 3 192.168.8.1
# Should work with <1ms latency
```

### Troubleshooting

**Bond doesn't exist after rebuild:**
```bash
# Check if bonding module is loaded
lsmod | grep bonding

# Check NetworkManager connections
nmcli connection show

# Manually activate bond
sudo nmcli connection up bond0
```

**Slave interfaces won't attach:**
- Ensure interfaces are not already in use by another bond/bridge
- Check switch LAG configuration (both ports in same LAG group)
- Verify interface names are correct: `ip link show`

**No IP address (DHCP fails):**
```bash
# Check DHCP configuration
nmcli connection show bond0 | grep ipv4.method
# Should show: ipv4.method: auto

# Check DHCP logs
sudo journalctl -u NetworkManager | grep DHCP

# Manually renew DHCP
sudo nmcli connection down bond0 && sudo nmcli connection up bond0
```

**Link aggregation not working (traffic only on one link):**
- Verify switch shows LACP negotiation successful
- Check LACP rate matches switch config (fast vs slow)
- Ensure both cables connected to same switch (cross-switch requires MLAG)

## Known Issues

### NetworkManager vs systemd-networkd Conflict

**Issue**: Before the 2026-02-10 fix, the module used both `networking.bonds.bond0` (systemd-networkd) and NetworkManager connection profiles simultaneously, causing:
- `bond0-netdev.service` failing with "Device can not be enslaved while up"
- Bond interface not created or slaves not attached

**Resolution**: The module now conditionally uses:
- **NetworkManager path**: When `networkManager = true` (creates bond via NM connection profiles only)
- **systemd-networkd path**: When `useNetworkd = true` (uses `networking.bonds.bond0`)

**Migration**: No action needed. Existing configurations work after rebuild.

## Performance

### Expected Throughput

| Link Speed | Bond Mode | Expected Aggregate | Notes |
|------------|-----------|-------------------|-------|
| 2x 1GbE | LACP | ~1.8 Gbps | Single connection limited to 1 link |
| 2x 10GbE | LACP | ~18 Gbps | Multiple connections distribute across links |
| 4x 10GbE | LACP | ~36 Gbps | Enterprise workstation |

**Important**: A single TCP connection can only use one link (max 10GbE per connection). Aggregate bandwidth requires multiple parallel connections.

### Testing

```bash
# Test with iperf3 (multiple parallel streams)
iperf3 -c <server> -P 4 -t 30
# -P 4: 4 parallel streams (distributes across links)

# Monitor per-interface traffic
watch -n 1 'cat /proc/net/dev | grep enp11s0f'
```

## Example: DESK Profile

The DESK workstation uses 2x Intel 82599ES 10GbE NICs bonded for 20Gbps aggregate:

```nix
# profiles/DESK-config.nix
systemSettings = {
  hostname = "nixosaku";
  ipAddress = "192.168.8.96";  # Reserved in pfSense DHCP

  # Network Bonding (10GbE LACP aggregation)
  networkBondingEnable = true;
  networkBondingMode = "802.3ad";
  networkBondingInterfaces = [ "enp11s0f0" "enp11s0f1" ];
  networkBondingDhcp = true;
};
```

**Switch config**: USW Aggregation (192.168.8.180), SFP+ ports 7-8 in LACP LAG. See `docs/infrastructure/services/network-switching.md`.

**To disable bonding** (e.g., when running on different hardware):
```nix
systemSettings = {
  networkBondingEnable = false;
  # Bond interface will not be created
};
```

## References

- [Linux Bonding Documentation](https://www.kernel.org/doc/Documentation/networking/bonding.txt)
- [IEEE 802.3ad LACP Standard](https://en.wikipedia.org/wiki/Link_aggregation)
- [NetworkManager Bonding Guide](https://networkmanager.dev/docs/api/latest/settings-bond.html)
- NixOS Options: `networking.bonds`, `networking.networkmanager`
