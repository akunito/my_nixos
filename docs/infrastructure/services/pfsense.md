---
id: infrastructure.services.pfsense
summary: pfSense firewall - gateway, DNS resolver, WireGuard, DHCP, NAT, pfBlockerNG, SNMP
tags: [infrastructure, pfsense, firewall, gateway, wireguard, dns, dhcp, snmp, pfblockerng, openvpn]
related_files: [docs/infrastructure/INFRASTRUCTURE.md, docs/infrastructure/services/vps-wireguard.md, profiles/LXC_monitoring-config.nix]
---

# pfSense Firewall & Gateway

## Overview

pfSense serves as the central network gateway for the homelab infrastructure, providing routing, firewall, DNS resolution, DHCP, VPN services, and ad/malware blocking.

| Property | Value |
|----------|-------|
| **Version** | pfSense 2.7.2-RELEASE |
| **OS** | FreeBSD 14.0-CURRENT |
| **Architecture** | amd64 |
| **Hardware** | 12th Gen Intel Core i3-12100T |
| **CPUs** | 8 |
| **Memory** | 16 GB |
| **Storage** | ~95 GB (ZFS) |
| **IP Address** | 192.168.8.1 |
| **Web GUI** | https://192.168.8.1 |
| **SSH** | admin@192.168.8.1 |

---

## Network Interfaces

### Physical & Virtual Interfaces

| Interface | Description | IP Address | Type | Speed | Status |
|-----------|-------------|------------|------|-------|--------|
| **ix0** | LAN | 192.168.8.1/24 | Intel 10G | 10Gbase-Twinax | Active |
| **ix1** | (Free) | - | Intel 10G | - | No carrier |
| **igc0** | WAN | 192.168.1.4/24 | Intel 1G | 1000baseT | Active |
| **ix2** | Switch_24G2 | - | Intel 10G | Bridge member (STP) | Active |
| **ix3** | LAPTOP_10G | - | Intel 10G | Bridge member (STP) | Active |
| **ix0.100** | STORAGE_VLAN | 192.168.20.1/24 | VLAN 100 on ix0 | 10G | Active |
| **ix0.200** | GUEST | 192.168.9.1/24 | VLAN 200 on ix0 | 10G | Active |
| **tun_wg0** | WG_VPS | 172.26.5.1/24 | WireGuard | MTU 1420 | Active |
| **ovpnc1** | OpenVPN Client | 10.100.0.2/21 | OpenVPN | MTU 1500 | Active |

**Removed interfaces**: `lagg0` (was LACP bond to TrueNAS via ix2+ix3) — removed after TrueNAS moved to USW Aggregation switch.

**Bridge**: ix2 (Switch_24G2) and ix3 (LAPTOP_10G) are bridged to LAN (ix0) with STP enabled. This provides L2 connectivity for devices connected directly to pfSense SFP+ ports. Note: ix2/ix3 are 10G SFP+ (Intel 82599) and cannot negotiate with 1G SFP devices directly.

### Interface Architecture

```
                              ISP Router
                                  │
                                  │ 192.168.1.x
                                  ▼
                    ┌─────────────────────────────┐
                    │           igc0              │
                    │         (WAN)               │
                    │       192.168.1.4           │
                    └──────────────┬──────────────┘
                                   │
    ┌──────────────────────────────┼──────────────────────────────┐
    │                              │                              │
    │                       pfSense                               │
    │                     192.168.8.1                             │
    │                              │                              │
    └──────┬──────────┬──────────┬──────┴──────┬──────────┬──────┘
           │          │          │             │          │
           ▼          ▼          ▼             ▼          ▼
    ┌─────────┐┌─────────┐┌─────────┐  ┌─────────┐┌─────────┐
    │  ix0    ││ ix0.100 ││ ix0.200 │  │ tun_wg0 ││ bridge  │
    │ (LAN)  ││(STORAGE)││ (GUEST) │  │(WG_VPS) ││ix2+ix3  │
    │192.168.8││192.168.20│192.168.9│  │172.26.5 ││ (STP)   │
    └─────────┘└─────────┘└─────────┘  └─────────┘└─────────┘
```

---

## VLANs

| VLAN ID | Name | Interface | Subnet | Purpose |
|---------|------|-----------|--------|---------|
| - | Main LAN | ix0 | 192.168.8.0/24 | Primary network (servers, workstations) |
| 100 | Storage (VLAN-NAS) | ix0.100 | 192.168.20.0/24 | TrueNAS storage network (direct L2 via switch) |
| 200 | Guest | ix0.200 | 192.168.9.0/24 | Guest network (isolated, internet only) |

---

## Gateways & Routing

### Configured Gateways

| Gateway | Interface | IP | Purpose |
|---------|-----------|-----|---------|
| **WAN_DHCP** | igc0 | 192.168.1.1 | Default internet gateway |
| **WG_VPS** | tun_wg0 | 172.26.5.1 | WireGuard tunnel to VPS |
| **OpenVPN_4_browsing** | ovpnc1 | 10.100.0.1 | Privacy VPN for browsing |

### Gateway Groups

- **Prefer_WireGuard_V4**: Personal devices route through WireGuard
- **OpenVPN_4_browsing**: Specific devices route through commercial VPN

### Routing Table Summary

| Destination | Gateway | Interface |
|-------------|---------|-----------|
| default | 192.168.1.1 | igc0 (WAN) |
| 192.168.8.0/24 | direct | ix0 (LAN) |
| 192.168.9.0/24 | direct | ix0.200 (Guest) |
| 192.168.20.0/24 | direct | ix0.100 (Storage VLAN) |
| 172.26.5.0/24 | direct | tun_wg0 (WireGuard) |
| 10.100.0.0/21 | direct | ovpnc1 (OpenVPN) |

---

## DNS Resolver (Unbound)

The DNS Resolver uses Unbound with local host overrides and pfBlockerNG integration.

### Configuration

| Setting | Value |
|---------|-------|
| **Mode** | DNS Resolver (Unbound) |
| **Port** | 53 (DNS), 853 (DoT) |
| **Threads** | 8 |
| **Cache Size** | 4MB msg-cache, 8MB rrset-cache |
| **DNSSEC** | Disabled (harden-dnssec-stripped: no) |
| **Prefetch** | Enabled |

### Host Overrides

Most `*.local.akunito.com` domains resolve to **192.168.8.102** (LXC_proxy NPM):

| Domain | IP | Service |
|--------|-----|---------|
| `nextcloud.local.akunito.com` | 192.168.8.102 | Nextcloud |
| `jellyfin.local.akunito.com` | 192.168.8.102 | Jellyfin |
| `syncthing.local.akunito.com` | 192.168.8.102 | Syncthing |
| `freshrss.local.akunito.com` | 192.168.8.102 | FreshRSS |
| `books.local.akunito.com` | 192.168.8.102 | Calibre-Web |
| `emulators.local.akunito.com` | 192.168.8.102 | EmulatorJS |
| `jellyseerr.local.akunito.com` | 192.168.8.102 | Jellyseerr |
| `sonarr.local.akunito.com` | 192.168.8.102 | Sonarr |
| `radarr.local.akunito.com` | 192.168.8.102 | Radarr |
| `prowlarr.local.akunito.com` | 192.168.8.102 | Prowlarr |
| `bazarr.local.akunito.com` | 192.168.8.102 | Bazarr |
| `qbittorrent.local.akunito.com` | 192.168.8.102 | qBittorrent |
| `grafana.local.akunito.com` | 192.168.8.85 | Grafana |
| `prometheus.local.akunito.com` | 192.168.8.85 | Prometheus |

**Pattern**: `*.local.akunito.com` → `192.168.8.102` (LXC_proxy)
**Exceptions**: Monitoring services → `192.168.8.85` (LXC_monitoring)

---

## DHCP Server

### DHCP Ranges

| Interface | Range | Lease Time |
|-----------|-------|------------|
| LAN (ix0) | 192.168.8.50-192.168.8.199 | 24 hours |
| Guest (ix0.200) | 192.168.9.50-192.168.9.199 | 1 hour |

### Static Mappings

Static DHCP reservations are configured for:
- LXC containers (192.168.8.80-89, 102)
- Network equipment (APs, switches)
- Personal devices

---

## Firewall Rules

### Rule Summary by Interface

#### WAN (igc0) - Inbound
- Block bogons
- Block private networks (RFC1918)
- Block link-local addresses
- Default deny all

#### LAN (ix0) - Inbound
| Rule | Source | Destination | Action | Note |
|------|--------|-------------|--------|------|
| Anti-lockout | any | pfSense | Pass | SSH, HTTP, HTTPS |
| pfB_DNSBL_Ping | any | 10.10.10.1 | Pass | DNSBL health check |
| pfB_DNSBL_Permit | any | 10.10.10.1:80,443 | Pass | DNSBL redirect |
| SNMP monitoring | 192.168.8.85 | pfSense:161 | Pass | Prometheus SNMP |
| LAN to Guest ping | LAN | Guest | Pass | ICMP only |
| Servers to NAS | AllowedTrueNAS | NAS subnet | Pass | TCP only |
| NAS subnet | NAS subnet | any | Pass | |
| Personal devices | AkunitoPersonalDevices | any | Pass | Route via WireGuard |
| VPN browsing | Route_over_PreferWGv4 | any | Pass | Route via OpenVPN |
| WireGuard network | WG network | any | Pass | |
| Default allow | LAN | any | Pass | |

#### Guest (ix0.200) - Inbound
| Rule | Source | Destination | Action | Note |
|------|--------|-------------|--------|------|
| Block LAN | Guest | LAN | Block | Isolation |
| Block WireGuard | Guest | WG network | Block | Isolation |
| Block NAS | Guest | 192.168.20.1 | Block | Isolation |
| Allow Internet | Guest | any | Pass | Internet access only |

#### WireGuard (tun_wg0) - Inbound
| Rule | Source | Destination | Action | Note |
|------|--------|-------------|--------|------|
| pfBlockerNG | any | pfB_PRI1_v4 | Block | IP blocklist |
| WG clients | 172.26.5.0/24 | any | Pass | VPS clients |
| WG clients v6 | fd86:ea04:1111::/116 | any | Pass | IPv6 |
| LAN | LAN | any | Pass | |
| WG_VPS default | WG network | any | Pass | |

#### NAS (lagg0) - Inbound
| Rule | Source | Destination | Action | Note |
|------|--------|-------------|--------|------|
| TrueNAS outbound | 192.168.20.200 | any | Pass | |
| Allowed to NAS | AllowedTrueNAS | NAS subnet | Pass | TCP only |
| Block all to NAS | any | NAS subnet | Block | Default deny |

### Policy-Based Routing

Devices in specific aliases are routed through VPN gateways:

1. **AkunitoPersonalDevices** → WireGuard (tun_wg0)
   - Personal devices always use WireGuard VPN
   - Tagged with `Private_VPN_Only`
   - Blocked if WireGuard is down (kill switch)

2. **Route_over_PreferWGv4** → OpenVPN (ovpnc1)
   - Specific devices route through commercial VPN
   - Tagged with `Private_VPN_Only`
   - Blocked if OpenVPN is down (kill switch)

---

## NAT Configuration

### Outbound NAT (Automatic)

| Source | Interface | NAT Address |
|--------|-----------|-------------|
| NAS network | lagg0 | 192.168.20.1 |
| WireGuard network | ix0 (LAN) | 192.168.8.1 |
| WireGuard network | igc0 (WAN) | 192.168.1.4 |
| LAN network | tun_wg0 | 172.26.5.1 |
| All traffic | tun_wg0 (IPv6) | fd86:ea04:1111::1 |
| LAN network | ovpnc1 | 10.100.0.2 |
| Outbound subnets | igc0 (WAN) | 192.168.1.4 |

### Port Forwards

No inbound port forwards configured - all external access via Cloudflare Tunnel.

---

## WireGuard VPN

### Tunnel Configuration

| Setting | Value |
|---------|-------|
| **Interface** | tun_wg0 |
| **Description** | WG_VPS |
| **Listen Port** | 51820 |
| **MTU** | 1420 |
| **Local IPv4** | 172.26.5.1/24 |
| **Local IPv6** | fd86:ea04:1111::1/128 |

### Peer (VPS Server)

| Setting | Value |
|---------|-------|
| **Allowed IPs** | 192.168.8.0/24, 172.26.5.0/24, 0.0.0.0/0, ::/0 |
| **Persistent Keepalive** | 25 seconds |
| **Status** | Active (handshake within 30s) |

**Note**: WireGuard keys and VPS endpoint IP are documented in `INFRASTRUCTURE_INTERNAL.md` (encrypted).

### WireGuard Traffic Flow

```
        ┌──────────────────────────────────────────────────────┐
        │                      Home Network                     │
        │                                                       │
        │   ┌─────────────┐         ┌─────────────┐            │
        │   │  Personal   │─────────│   pfSense   │            │
        │   │  Devices    │         │  172.26.5.1 │            │
        │   └─────────────┘         └──────┬──────┘            │
        │                                  │                    │
        └──────────────────────────────────┼────────────────────┘
                                           │ WireGuard
                                           │ Port 51820
                                           ▼
        ┌──────────────────────────────────────────────────────┐
        │                      VPS Server                       │
        │                     172.26.5.155                      │
        │                                                       │
        │        Routes: 192.168.8.0/24 → 172.26.5.1           │
        └──────────────────────────────────────────────────────┘
```

---

## OpenVPN Client

A commercial VPN client is configured for privacy-focused browsing.

| Setting | Value |
|---------|-------|
| **Interface** | ovpnc1 |
| **IP Address** | 10.100.0.2/21 |
| **Network** | 10.100.0.0/21 |
| **Purpose** | Privacy VPN for specific devices |

Devices in the `Route_over_PreferWGv4` alias route through this VPN.

---

## pfBlockerNG

### DNSBL (DNS Blocklists)

pfBlockerNG provides DNS-level ad and malware blocking via Unbound integration.

| Feed | Entries | Category |
|------|---------|----------|
| **OISD** | ~10M | Comprehensive ad/tracking blocklist |
| **CERT_PL** | ~5.8M | Polish CERT malware domains |
| **EasyList** | ~954K | Ad blocking |
| **EasyList_Polish** | ~5.7K | Polish ad blocking |
| **EasyList_Spanish** | ~210 | Spanish ad blocking |
| **Abuse_urlhaus** | ~13K | Malware URLs |
| **Compilation_custom** | ~589 | Custom entries |

**DNSBL VIP**: 10.10.10.1 (responds to blocked queries)

### IP Blocklists

| Feed | Entries | Category |
|------|---------|----------|
| **CINS_army** | ~204K | Known malicious IPs |
| **ET_Block** | ~23K | Emerging Threats |
| **ET_Comp** | ~7K | Emerging Threats compromised |
| **ISC_Block** | ~358 | SANS ISC blocklist |
| **Abuse_Feodo_C2** | ~10 | Feodo Trojan C&C |

**Total IPs in pfB_PRI1_v4 table**: ~16,206

### Firewall Integration

pfBlockerNG creates PF tables and rules:
- **pfB_PRI1_v4**: IP blocklist table (inbound block on WAN, outbound block on LAN/WG)
- DNSBL rules allow traffic to 10.10.10.1 for block pages

---

## SNMP Monitoring

SNMP is enabled for Prometheus monitoring from LXC_monitoring.

| Setting | Value |
|---------|-------|
| **Daemon** | NET-SNMP (snmpd) |
| **Bind Address** | 192.168.8.1:161 |
| **Protocol** | SNMPv3 (authPriv) |
| **Auth Protocol** | SHA |
| **Privacy Protocol** | AES |
| **Modules** | mibII, netgraph, pf, hostres, ucd, regex |

**Credentials**: Stored in `secrets/domains.nix` (git-crypt encrypted):
- `snmpv3User` - SNMPv3 username
- `snmpv3AuthPass` - Authentication password
- `snmpv3PrivPass` - Privacy password

**Firewall rule**: Allow SNMP (UDP 161) from 192.168.8.85 (LXC_monitoring) only.

---

## REST API

The pfSense REST API package provides programmatic access for automation and auditing.

### Installation

```bash
# Via SSH (pfSense 2.7.2)
ssh admin@192.168.8.1
pkg-static add https://github.com/pfrest/pfSense-pkg-RESTAPI/releases/download/v2.4.3/pfSense-2.7.2-pkg-RESTAPI.pkg
```

**Note**: Check [GitHub releases](https://github.com/pfrest/pfSense-pkg-RESTAPI/releases) for your pfSense version. The package must be reinstalled after pfSense updates.

### Configuration

| Setting | Value |
|---------|-------|
| **Enable** | Yes |
| **Allowed Interfaces** | LAN, Localhost |
| **Authentication Methods** | Key |
| **Read Only** | No |
| **Login Protection** | Enabled |

### API Key Authentication

**Create API key** (GUI):
1. Navigate to **System → REST API → Keys**
2. Click **Add**
3. Configure:
   - **Name**: Descriptive name (e.g., "claude-connection")
   - **Hash Algorithm**: SHA-512
   - **Length**: 64 bytes
4. Save and **copy the key immediately** (shown only once)

**Credentials**: Stored in `secrets/domains.nix` (git-crypt encrypted):
- `pfsenseApiKey` - API key value
- `pfsenseApiKeyName` - Key name/client-id
- `pfsenseHost` - pfSense IP address

### API Usage

**Header format**: `x-api-key: <key-value>`

**Example request**:
```bash
curl -sk -H "x-api-key: <api-key>" https://192.168.8.1/api/v2/status/system
```

**Common endpoints**:
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v2/status/system` | GET | System status (CPU, memory, uptime) |
| `/api/v2/status/interface` | GET | Interface status and statistics |
| `/api/v2/firewall/rule` | GET | Firewall rules |
| `/api/v2/firewall/alias` | GET | Firewall aliases |
| `/api/v2/services/unbound` | GET | DNS resolver configuration |
| `/api/v2/system/config` | GET | Full system configuration |
| `/api/v2/diagnostics/arp` | GET | ARP table |

**API documentation**: https://192.168.8.1/api/v2/documentation (Swagger UI)

### Security Considerations

- API keys should only be created when needed
- Use descriptive names to track key usage
- Store keys in encrypted secrets (`secrets/domains.nix`)
- Restrict allowed interfaces to LAN and Localhost only
- Enable Login Protection to prevent brute force attacks
- Consider enabling Read Only mode for audit-only access

---

## Installed Packages

### pfSense Packages

| Package | Purpose |
|---------|---------|
| **pfBlockerNG** | IP/DNS blocklists |
| **WireGuard** | VPN tunnel |
| **OpenVPN Client** | Privacy VPN |

### System Packages (selected)

| Package | Version | Purpose |
|---------|---------|---------|
| bind-tools | 9.18.19 | DNS utilities (dig, nslookup) |
| bsnmp-ucd | 0.4.5 | SNMP UCD-MIB support |
| curl | 8.6.0 | HTTP client |
| dnsmasq | 2.89_1 | DNS forwarder (backup) |
| hostapd | 2.10_8 | 802.11 AP (not used) |
| iftop | 1.0.p4 | Bandwidth monitoring |

---

## Aliases

### Network Aliases

| Alias | Type | Contents | Purpose |
|-------|------|----------|---------|
| **LAN__NETWORK** | Network | 192.168.8.0/24 | LAN subnet |
| **OPT2__NETWORK** | Network | 192.168.9.0/24 | Guest subnet |
| **OPT4__NETWORK** | Network | 172.26.5.0/24 | WireGuard subnet |
| **OPT6__NETWORK** | Network | 192.168.20.0/24 | NAS subnet |
| **WAN__NETWORK** | Network | 192.168.1.0/24 | WAN subnet |

### Device Aliases

| Alias | Type | Contents | Purpose |
|-------|------|----------|---------|
| **AkunitoPersonalDevices** | Hosts | 6 IPs | Personal devices for WireGuard routing |
| **AllowedTrueNAS** | Hosts | 10 IPs | Devices allowed to access NAS |
| **Route_over_PreferWGv4** | Hosts | 10 IPs | Devices for OpenVPN routing |

### pfBlockerNG Tables

| Table | Entries | Purpose |
|-------|---------|---------|
| **pfB_PRI1_v4** | 16,206 | IP blocklist |
| **bogons** | 2,885 | Bogon IPv4 addresses |
| **bogonsv6** | 155,212 | Bogon IPv6 addresses |
| **snort2c** | 0 | IDS blocks (unused) |
| **sshguard** | 0 | SSH brute force blocks |
| **virusprot** | 0 | Virus protection blocks |

---

## PF State Table

| Metric | Value |
|--------|-------|
| **Current entries** | ~814 |
| **Searches/s** | ~2,715 |
| **Inserts/s** | ~5.6 |
| **Removals/s** | ~5.6 |

---

## Maintenance Commands

### System Status

```bash
# SSH access
ssh admin@192.168.8.1

# Check uptime
uptime

# Check disk usage
df -h

# Check memory
vmstat
```

### Firewall Status

```bash
# Show firewall rules
pfctl -sr

# Show NAT rules
pfctl -sn

# Show state table info
pfctl -si

# Count active states
pfctl -ss | wc -l

# Show all tables
pfctl -sT

# Show table contents
pfctl -t pfB_PRI1_v4 -T show | head -20
```

### DNS Resolver

```bash
# Check Unbound status
unbound-control status

# Cache statistics
unbound-control stats_noreset

# List local data
unbound-control list_local_data | head -20
```

### WireGuard

```bash
# Show WireGuard status
wg show

# Show WireGuard interface
ifconfig tun_wg0
```

### pfBlockerNG

```bash
# List DNSBL feeds
ls -la /var/db/pfblockerng/dnsbl/

# List IP blocklists
ls -la /var/db/pfblockerng/deny/

# Check pfBlockerNG log
cat /var/db/pfblockerng/pfblockerng.log | tail -30
```

### Service Status

```bash
# Check running services
ps aux | grep -E '(unbound|dhcpd|snmpd|openvpn|wireguard)'

# List all services
ls /usr/local/etc/rc.d/
```

---

## Troubleshooting

### DNS Issues

1. Check Unbound is running:
   ```bash
   ps aux | grep unbound
   unbound-control status
   ```

2. Test DNS resolution:
   ```bash
   dig @192.168.8.1 google.com
   dig @192.168.8.1 nextcloud.local.akunito.com
   ```

3. Check host overrides:
   ```bash
   cat /var/unbound/host_entries.conf
   ```

### WireGuard Tunnel Issues

1. Check handshake timestamp:
   ```bash
   wg show
   ```
   - If handshake is >2 minutes old, tunnel may be down

2. Check interface status:
   ```bash
   ifconfig tun_wg0
   ```

3. Verify routing:
   ```bash
   netstat -rn | grep 172.26.5
   ```

### Firewall Issues

1. Check for blocked traffic:
   ```bash
   pfctl -ss | grep <IP>
   ```

2. Check rule matches:
   ```bash
   pfctl -vvsr | grep "USER_RULE"
   ```

3. Check tables:
   ```bash
   pfctl -sT
   pfctl -t sshguard -T show
   ```

### SNMP Issues

1. Verify SNMP daemon:
   ```bash
   ps aux | grep snmpd
   ```

2. Test SNMPv3 (preferred):
   ```bash
   # From LXC_monitoring or any host with net-snmp-utils
   snmpwalk -v3 -l authPriv \
     -u prometheus \
     -a SHA -A "<auth-password>" \
     -x AES -X "<priv-password>" \
     192.168.8.1 system
   ```

3. Test SNMPv2c (fallback):
   ```bash
   snmpwalk -v2c -c <community> 192.168.8.1 system
   ```

---

## Backup

### Automated Backup to Proxmox NFS

pfSense is configured with automated daily backups to Proxmox NFS storage at `/mnt/pve/proxmox_backups/pfsense/`.

| Setting | Value |
|---------|-------|
| **Script Location** | `/root/backup-to-proxmox.sh` |
| **Schedule** | Daily at 02:00 (via cron) |
| **Destination** | `root@192.168.8.82:/mnt/pve/proxmox_backups/pfsense/` |
| **Retention** | 30 days |
| **Monitoring** | Prometheus metrics via LXC_monitoring |

#### Files Backed Up

| File/Directory | Description |
|----------------|-------------|
| `/conf/config.xml` | Full pfSense configuration |
| `/root/.ssh/` | SSH keys (for automation) |
| `/root/*.sh` | Custom scripts (backup, maintenance) |
| `/var/db/rrd/*.rrd` | RRD data (historical graphs) |

#### Backup Script

The backup script (`/root/backup-to-proxmox.sh`) performs:
1. Creates timestamped tar.gz archive of all important files
2. Transfers to Proxmox via SCP (SSH key authentication)
3. Cleans up backups older than 30 days
4. Writes Prometheus-compatible metrics file

```bash
# View backup script
ssh admin@192.168.8.1 "cat /root/backup-to-proxmox.sh"

# Run manual backup
ssh admin@192.168.8.1 "/root/backup-to-proxmox.sh"

# Check backup files on Proxmox
ssh root@192.168.8.82 "ls -la /mnt/pve/proxmox_backups/pfsense/"
```

#### Cron Configuration

Configured via **pfSense GUI** → Services → Cron (requires pfSense-pkg-Cron):

| Setting | Value |
|---------|-------|
| **Minute** | 0 |
| **Hour** | 2 |
| **Day of Month** | * |
| **Month** | * |
| **Day of Week** | * |
| **User** | root |
| **Command** | `/root/backup-to-proxmox.sh` |

#### SSH Key Setup

pfSense uses SSH key authentication to transfer backups to Proxmox:

```bash
# Generate key on pfSense (if not exists)
ssh admin@192.168.8.1 "ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ''"

# Copy public key to Proxmox authorized_keys
ssh admin@192.168.8.1 "cat /root/.ssh/id_ed25519.pub" >> /root/.ssh/authorized_keys
```

### Prometheus Monitoring

Backup status is monitored via `prometheus-pfsense-backup` service on LXC_monitoring.

**Metrics exposed**:
| Metric | Description |
|--------|-------------|
| `pfsense_backup_last_success` | Unix timestamp of last backup |
| `pfsense_backup_age_seconds` | Age of most recent backup in seconds |
| `pfsense_backup_count` | Total number of backup files |
| `pfsense_backup_size_bytes` | Size of most recent backup |

**Grafana dashboard**: Infrastructure Overview → "Current Backup Age" and "Backup Timeline" panels include pfSense.

### Configuration Backup (Manual)

The complete pfSense configuration is stored in `/conf/config.xml`.

**Manual backup methods**:
1. **GUI**: Diagnostics → Backup & Restore → Download configuration
2. **SSH**: `cat /conf/config.xml > /tmp/pfsense-backup.xml`
3. **REST API**: `curl -sk -H "x-api-key: <key>" https://192.168.8.1/api/v2/system/config`

### Recommended Backup Schedule

- **Automated**: Daily backup to Proxmox NFS (configured above)
- **Before changes**: Manual backup before significant configuration changes
- **Off-site**: Consider periodic backup to cloud storage for disaster recovery

---

## Maintenance

### System Updates

pfSense updates are **manual by design** for stability.

**Pre-update checklist**:
1. Backup config: **Diagnostics → Backup & Restore → Download configuration**
2. Check release notes for breaking changes at https://docs.netgate.com/pfsense/en/latest/releases/
3. Verify AutoConfigBackup has recent backup (if enabled)
4. Plan maintenance window (expect brief network outage during reboot)

**Update steps**:
1. Navigate to **System → Update**
2. Review available updates
3. Click "Confirm" to install
4. System will reboot automatically

**Post-update verification**:
```bash
# SSH to pfSense
ssh admin@192.168.8.1

# Check version
cat /etc/version

# Verify critical services
wg show                    # WireGuard tunnel
pfctl -si                  # Firewall state
ps aux | grep unbound      # DNS resolver
ps aux | grep snmpd        # SNMP (if enabled)
```

### SNMPv3 Configuration

pfSense requires the **NET-SNMP package** for SNMPv3 support.

**Installation**:
```bash
# Via SSH
ssh admin@192.168.8.1
pkg install -y pfSense-pkg-Net-SNMP
```

**Configuration** (via GUI):
1. **Services → SNMP** - Disable built-in bsnmpd (uncheck "Enable")
2. **Services → SNMP (NET-SNMP)** - Configure:
   - **General**: Enable SNMP Service
   - **Host Information**: Set contact and location
   - **Users**: Create SNMPv3 user:
     - Username: `prometheus`
     - Entry Type: User entry (USM)
     - Auth Type: SHA
     - Auth Password: (from secrets/domains.nix)
     - Privacy Protocol: AES
     - Privacy Password: (from secrets/domains.nix)
     - Min Security Level: Private (Encryption Required)

**Credentials**: Stored in `secrets/domains.nix` (git-crypt encrypted):
- `snmpv3User`
- `snmpv3AuthPass`
- `snmpv3PrivPass`

---

## Related Documentation

- [Infrastructure Overview](../INFRASTRUCTURE.md) - Network architecture
- [VPS WireGuard Server](./vps-wireguard.md) - VPS side of WireGuard tunnel
- [Monitoring Stack](./monitoring-stack.md) - Prometheus/Grafana setup
- [INFRASTRUCTURE_INTERNAL.md](../INFRASTRUCTURE_INTERNAL.md) - Sensitive configuration (encrypted)
