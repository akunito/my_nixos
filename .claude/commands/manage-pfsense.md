# Manage pfSense

Skill for managing the pfSense router/firewall, including interfaces, VLANs, bridges, and firewall rules.

## Purpose

Use this skill to:
- Check pfSense interface and VLAN status
- Manage firewall rules and aliases
- Verify VLAN 100 storage network gateway
- Check bridge members (Switch_24G2, LAPTOP_10G)
- Monitor DNS resolver, VPN tunnels, and pfBlockerNG
- Backup/restore configuration

---

## Connection Details

| Access | Address |
|--------|---------|
| SSH | `ssh admin@192.168.8.1` |
| Web GUI | `https://192.168.8.1` |
| REST API | `https://192.168.8.1/api/v2/` |

**API auth header:** `x-api-key: <key>` (from `secrets/domains.nix` → `pfsenseApiKey`)

---

## Interface Layout (2026-02-12)

| Interface | Assignment | Physical | Speed | Switch Port | Description |
|-----------|-----------|----------|-------|-------------|-------------|
| ix0 | LAN | Intel 82599 | 10G | SFP+ 2 | Main LAN, VLAN trunk |
| ix0.100 | STORAGE_VLAN | VLAN on ix0 | 10G | (tagged) | 192.168.20.1/24 |
| ix0.200 | GUEST | VLAN on ix0 | 10G | (tagged) | Guest network |
| ix1 | (unassigned) | Intel 82599 | 10G | Free | Was SFP+ 1, freed for USW-24-G2 |
| ix2 | Switch_24G2 | Intel 82599 | 10G | N/A | Bridge member (STP), connects to USW-24-G2 |
| ix3 | LAPTOP_10G | Intel 82599 | 10G | N/A | Bridge member (STP), for laptop 10GbE |
| igc0 | WAN | Intel I225 | 1G | N/A | ISP uplink |

**Bridge:** ix2 (Switch_24G2) and ix3 (LAPTOP_10G) are bridged to LAN (ix0) with STP enabled. This provides L2 connectivity for devices connected directly to pfSense SFP+ ports.

**Previous:** ix2+ix3 were lagg0 (LACP bond to TrueNAS). lagg0 was deleted after TrueNAS moved to USW Aggregation.

---

## Common Operations

### Check Interface Status

```bash
# Via SSH
ssh admin@192.168.8.1 "ifconfig ix0; ifconfig ix0.100; ifconfig ix2; ifconfig ix3"

# Via API
curl -sk -H "x-api-key: $(grep pfsenseApiKey secrets/domains.nix | cut -d'\"' -f2)" \
  https://192.168.8.1/api/v2/status/interface
```

### Check VLAN 100 (Storage)

```bash
ssh admin@192.168.8.1 "ifconfig ix0.100"
# Should show: inet 192.168.20.1 netmask 0xffffff00

# Test connectivity to TrueNAS
ssh admin@192.168.8.1 "ping -c 2 192.168.20.200"
```

### Check Bridge Status

```bash
ssh admin@192.168.8.1 "ifconfig bridge0"
# Members: ix0 (LAN), ix2 (Switch_24G2), ix3 (LAPTOP_10G)
# STP should be enabled on ix2 and ix3
```

### Firewall Rules

```bash
# Show all rules
ssh admin@192.168.8.1 "pfctl -sr"

# Show NAT rules
ssh admin@192.168.8.1 "pfctl -sn"

# Show active states
ssh admin@192.168.8.1 "pfctl -ss | wc -l"

# Via API
curl -sk -H "x-api-key: $(grep pfsenseApiKey secrets/domains.nix | cut -d'\"' -f2)" \
  https://192.168.8.1/api/v2/firewall/rule
```

### STORAGE_VLAN Firewall Rules

The STORAGE_VLAN (ix0.100) interface has these rules:
1. TrueNAS outbound: `192.168.20.200` → any → Pass
2. AllowedTrueNAS: `AllowedTrueNAS` alias → NAS subnet → Pass (TCP)
3. Block all: any → NAS subnet → Block

**Note:** DESK and Proxmox access TrueNAS via direct L2 on VLAN 100 (switch-level), bypassing pfSense entirely. These rules only govern traffic entering pfSense from VLAN 100.

---

## DNS Resolver

```bash
ssh admin@192.168.8.1 "unbound-control status"
ssh admin@192.168.8.1 "unbound-control stats_noreset"

# Check DNSSEC
ssh admin@192.168.8.1 "unbound-control list_forwards"
```

---

## WireGuard VPN

```bash
ssh admin@192.168.8.1 "wg show"
# Look for: latest handshake (should be recent)
# Peer: hWv3ipsMkY6HA2fRe/hO7UI4oWeYmfke4qX6af/5SjY=
```

---

## SNMP (Prometheus monitoring)

```bash
# SNMPv3 configured for Prometheus scraping
ssh admin@192.168.8.1 "service snmpd status"
```

---

## Configuration Backup

```bash
# Download full config
ssh admin@192.168.8.1 "cat /conf/config.xml" > /tmp/pfsense-backup-$(date +%Y%m%d).xml

# Via API
curl -sk -H "x-api-key: $(grep pfsenseApiKey secrets/domains.nix | cut -d'\"' -f2)" \
  https://192.168.8.1/api/v2/system/config > /tmp/pfsense-config-$(date +%Y%m%d).json
```

---

## Troubleshooting

### Bridge boot loop

**WARNING:** Creating a bridge without STP can cause switching loops that crash pfSense. Always enable STP on bridge members.

If pfSense enters a boot loop after bridge config:
1. Connect keyboard + monitor to pfSense
2. Boot into single-user mode (option 2 at boot)
3. Mount filesystem: `mount -o rw /`
4. Edit config: remove `<bridges>` section from `/cf/conf/config.xml`
5. Reboot

### VLAN 100 unreachable from pfSense

```bash
# Check ix0.100 is up
ssh admin@192.168.8.1 "ifconfig ix0.100"

# Check routing
ssh admin@192.168.8.1 "netstat -rn | grep 192.168.20"
# Should show: 192.168.20.0/24 link#X U ix0.100
```

### USW-24-G2 devices no internet

```bash
# Check ix2 link
ssh admin@192.168.8.1 "ifconfig ix2"

# Check bridge membership
ssh admin@192.168.8.1 "ifconfig bridge0"

# Note: ix2 is 10G SFP+ but USW-24-G2 has 1G SFP
# They connect via SFP+ 1 on USW Aggregation (not directly to pfSense)
# Actual path: USW-24-G2 SFP 2 → USW Aggregation SFP+ 1 → switch L2 → SFP+ 2 → pfSense ix0
```

### 10G SFP+ vs 1G SFP incompatibility

pfSense ix2/ix3 are Intel 82599 (10G SFP+ only). They cannot negotiate with 1G SFP devices directly. The USW-24-G2 connects to USW Aggregation SFP+ 1 instead, using the switch as an intermediary.
