---
id: audits.pfsense.2026-02-04
summary: Security, performance, and reliability audit of pfSense firewall
tags: [audit, security, performance, pfsense, firewall]
last_updated: 2026-02-09
---

# pfSense Security, Performance & Reliability Audit

**Initial Date**: 2026-02-04
**Last Updated**: 2026-02-08
**Auditor**: Claude Code
**System**: pfSense 2.7.2-RELEASE (FreeBSD 14.0-CURRENT)
**IP Address**: 192.168.8.1

---

## Update Log

| Date | Changes |
|------|---------|
| 2026-02-09 | REL-001 (AutoConfigBackup) marked as N/A - CE Edition only; local backup is sufficient; pkg database recovered after failed 2.8.1 upgrade attempt |
| 2026-02-08 | SEC-004 (console password) completed via API; NEW-002 (local backup automation) completed with Proxmox NFS; Grafana monitoring added |
| 2026-02-07 | API audit performed; REST API reinstalled; new API key created |
| 2026-02-04 | Initial audit; SEC-001 (SNMPv3), SEC-002 (DNSSEC), REL-002 (unbound-control) completed |

---

## Executive Summary

Overall, the pfSense firewall is **well-configured** with good security practices. The system is operating efficiently with **excellent performance margins**.

### Current Status (as of 2026-02-09)

**Completed Remediations:**
- **SEC-001**: SNMPv3 with authentication and encryption - **DONE**
- **SEC-002**: DNSSEC enabled - **DONE**
- **REL-002**: unbound-control enabled - **DONE**
- **SEC-004**: Console password protection - **DONE** (2026-02-07, via REST API)
- **NEW-002**: Automated backup to Proxmox NFS - **DONE** (2026-02-07)
  - Full backup (config.xml, SSH keys, scripts, RRD data) daily at 2:30 AM
  - Stored at: `proxmox:/mnt/pve/proxmox_backups/pfsense/`
  - 30-day retention, ~2.6MB per backup
  - Monitored via Prometheus/Grafana

**N/A (Not Applicable):**
- **REL-001**: AutoConfigBackup - pfSense Plus only (not available in CE Edition)

**Pending Items:**
- **NEW-001**: System updates check (MEDIUM) - pfSense GUI required
- **SEC-003**: Anti-lockout restriction (LOW) - pfSense GUI required

### Score Summary

| Category | Score | Notes |
|----------|-------|-------|
| **Security** | 9/10 | SNMPv3 + DNSSEC + console protection completed |
| **Performance** | 9/10 | Excellent - massive headroom on all metrics |
| **Reliability** | 9/10 | Local backup automated (AutoConfigBackup N/A for CE) |

---

## Findings Summary

| ID | Severity | Category | Finding | Status |
|----|----------|----------|---------|--------|
| SEC-001 | **High** | Security | SNMPv2c cleartext protocol | **COMPLETED** (2026-02-04) |
| SEC-002 | **Medium** | Security | DNSSEC disabled | **COMPLETED** (2026-02-04) |
| SEC-003 | **Low** | Security | Anti-lockout allows any LAN source | Open |
| SEC-004 | **High** | Security | Console password protection disabled | **COMPLETED** (2026-02-07) |
| SEC-005 | **Info** | Security | sshguard table empty (0 entries) | Verified OK |
| SEC-006 | **Medium** | Security | Kernel PTI/MDS mitigations disabled | Info (see notes) |
| REL-001 | **N/A** | Reliability | AutoConfigBackup (Plus only) | **N/A** (CE Edition) |
| REL-002 | **Medium** | Reliability | unbound-control disabled | **COMPLETED** (2026-02-04) |
| REL-003 | **Low** | Reliability | DNS operates as recursive resolver | Info |
| NEW-001 | **Medium** | Maintenance | Check for system updates | Open |
| NEW-002 | **Medium** | Reliability | Local backup automation | **COMPLETED** (2026-02-07) |
| PERF-001 | **Info** | Performance | lagg0 has 6 TX errors | Minor |
| PERF-002 | **Info** | Performance | ix1 interface unused | Info |

### 2026-02-07 API Audit Findings

Fresh audit performed via REST API on 2026-02-07:

| Metric | Value | Status |
|--------|-------|--------|
| Version | pfSense 2.7.2-RELEASE | Check for updates |
| CPU | Intel i3-12100T (8 cores) | Excellent |
| CPU Usage | 1.5% | Excellent |
| Memory Usage | 7% | Excellent |
| Disk Usage | 1% | Excellent |
| Temperature | 27.9C | Cool |
| Uptime | 3+ days | Stable |
| mbuf Usage | 4% | Good |
| Console Password | Enabled | ✅ Fixed (2026-02-08) |
| Kernel PTI | Disabled | Review (12th gen has HW mitigations) |
| MDS Mitigation | Inactive | Review (12th gen has HW mitigations) |
| SSH Auth | Key-only | Good |

**Packages Installed:**
- NET-SNMP 0.1.5_11
- pfBlockerNG-devel 3.2.0_20
- WireGuard 0.2.1
- RESTAPI v2.4.3
- Cron 1.0 (for automated backups)

---

## Phase 1: Security Audit

### 1.1 Authentication & Access Control

| Check | Value | Assessment |
|-------|-------|------------|
| SSH port | 22 | Standard |
| SSH authentication | **Public key only** | Good |
| Password auth | **Disabled** | Good |
| PermitRootLogin | yes | Acceptable (admin user) |
| Login method | ED25519 keys | Good (modern algorithm) |

**Last logins reviewed**: All SSH logins are from 192.168.8.97 (your workstation) using ED25519 public keys. No suspicious access patterns observed.

### 1.2 Firewall Rules Analysis

**Rule Count**: 168 total rules (scrub + filter)

#### WAN (igc0) - Inbound Security

| Check | Status | Notes |
|-------|--------|-------|
| Block bogons | **Enabled** | Good |
| Block private networks (RFC1918) | **Enabled** | 10/8, 127/8, 172.16/12, 192.168/16 |
| Block link-local | **Enabled** | 169.254.0.0/16 |
| Block ULA (IPv6) | **Enabled** | fc00::/7 |
| Default deny | **Enabled** | All inbound blocked by default |
| Inbound port forwards | **None** | Good - all via Cloudflare Tunnel |
| pfBlockerNG IP blocks | **Active** | 16,242 IPs blocked on WAN |

**WAN Security Assessment**: **Excellent** - No inbound ports exposed, comprehensive blocking of invalid source addresses.

#### LAN (ix0) - Rule Analysis

| Rule | Assessment |
|------|------------|
| Anti-lockout (SSH/HTTP/HTTPS) | See SEC-003 |
| pfB_DNSBL rules | Proper DNSBL integration |
| SNMP from 192.168.8.85 only | Good - properly restricted |
| Policy routing (WireGuard/OpenVPN) | Properly implemented with kill switch |
| Default allow LAN to any | Common but could be more restrictive |

#### Guest (ix0.200) - Network Isolation

| Check | Status |
|-------|--------|
| Block to LAN | **Enabled** |
| Block to WireGuard | **Enabled** |
| Block to NAS | **Enabled** |
| Allow internet only | **Enabled** |

**Guest Isolation Assessment**: **Excellent** - Properly isolated from internal networks.

#### NAS (lagg0) - Access Control

| Check | Status |
|-------|--------|
| Allow TrueNAS outbound | Enabled |
| Allow from AllowedTrueNAS alias | Enabled |
| Default block to NAS | **Enabled** |

**NAS Access Assessment**: **Good** - Properly restricted to authorized devices.

### 1.3 Security Findings

#### SEC-001: SNMPv2c Cleartext Protocol (High)

**Current State**:
- Protocol: SNMPv2c
- Bind address: 192.168.8.1:161
- Access restricted to: 192.168.8.85 only
- Community string: Complex (acceptable)

**Risk**: SNMP community string transmitted in cleartext. An attacker on the LAN could capture it.

**Mitigating Factors**:
- Firewall restricts access to monitoring server only
- Internal network only

**Recommendation**: Upgrade to SNMPv3 with authentication (SHA) and encryption (AES).

---

#### SEC-002: DNSSEC Disabled (Medium)

**Current State**:
```
harden-dnssec-stripped: no
```

**Risk**: DNS responses are not validated. Potential for DNS spoofing attacks.

**Mitigating Factors**:
- DNS rebinding protection is enabled
- Internal resolver (not forwarding to external)
- DoT (DNS over TLS) available on port 853

**Recommendation**: Enable DNSSEC validation (`harden-dnssec-stripped: yes`).

---

#### SEC-003: Anti-lockout Rule Allows Any LAN Source (Low)

**Current State**:
```
pass in quick on ix0 proto tcp from any to (ix0) port = https keep state label "anti-lockout rule"
pass in quick on ix0 proto tcp from any to (ix0) port = http keep state label "anti-lockout rule"
pass in quick on ix0 proto tcp from any to (ix0) port = ssh keep state label "anti-lockout rule"
```

**Risk**: Any device on LAN can access pfSense management interfaces.

**Current Risk Level**: Low - LAN is trusted, Guest VLAN is isolated.

**Recommendation**: Consider restricting to specific admin IPs/alias (e.g., your workstations only).

---

#### SEC-004: Security Tables Status (Info)

| Table | Entries | Status |
|-------|---------|--------|
| **pfB_PRI1_v4** | 16,242 | Active (pfBlockerNG IP blocklist) |
| **sshguard** | 0 | Normal - no brute force attempts |
| **snort2c** | 0 | Normal - IDS not configured |
| **virusprot** | 0 | Normal - virus protection table unused |

**Assessment**: Empty security tables are normal when no attacks have been detected. sshguard is running and monitoring.

### 1.4 Security Sysctls (System Hardening)

| Sysctl | Value | Assessment |
|--------|-------|------------|
| `net.inet.ip.random_id` | 1 | **Good** - Randomized IP IDs |
| `net.inet.tcp.blackhole` | 2 | **Good** - Drop RST to closed ports |
| `net.inet.udp.blackhole` | 1 | **Good** - Drop ICMP for closed UDP ports |
| `net.inet.tcp.drop_synfin` | 1 | **Good** - Drop SYN+FIN packets |

**System Hardening Assessment**: **Excellent** - All recommended security sysctls are properly configured.

### 1.5 VPN Security

#### WireGuard (tun_wg0)

| Check | Value | Assessment |
|-------|-------|------------|
| Preshared key | Enabled | **Good** |
| Persistent keepalive | 25 seconds | Good |
| Last handshake | <30 seconds | Active |
| Transfer | 3.53 GiB rx, 157 MiB tx | Healthy |

**Allowed IPs Analysis**:
```
192.168.8.0/24, 172.26.5.0/24, ::/0, 0.0.0.0/0
```

This is intentional - allows VPS to be a default gateway for certain traffic and reach the home network. The VPS is trusted infrastructure.

#### OpenVPN Client (ovpnc1)

- Active and healthy (10.100.0.2/21)
- Gateway monitoring via dpinger active
- Kill switch implemented via traffic tagging

**VPN Security Assessment**: **Good** - Proper configuration with kill switch.

### 1.6 pfBlockerNG Effectiveness

| Feed Type | Active Feeds | Total Entries |
|-----------|--------------|---------------|
| **DNSBL** | 7 feeds | ~17M domains |
| **IP Blocklist** | 5 feeds | 16,242 IPs |

**Assessment**: **Excellent** - Comprehensive ad/malware blocking active.

---

## Phase 2: Performance Audit

### 2.1 State Table

| Metric | Current | Limit | Usage |
|--------|---------|-------|-------|
| Current entries | **770** | 1,606,000 | **0.05%** |
| Searches/s | 2,473 | - | Normal |
| Inserts/s | 7.9 | - | Normal |
| Removals/s | 7.9 | - | Normal |
| State-mismatch | 9,046 total | - | Minimal |

**State Table Assessment**: **Excellent** - Only using 0.05% of capacity. Massive headroom available.

### 2.2 DNS Performance

| Test | Result |
|------|--------|
| Cold query (google.com) | **33ms** |
| Cached query | **0ms** |
| Unbound memory | 235MB resident |
| Unbound threads | 8 |

**DNS Configuration**:
- Mode: **Recursive resolver** (no forwarders)
- Cache: 4MB msg-cache, 8MB rrset-cache
- Prefetch: **Enabled**
- Prefetch-key: **Enabled**

**DNS Performance Assessment**: **Excellent** - Sub-millisecond cached responses.

### 2.3 System Resources

| Resource | Value | Assessment |
|----------|-------|------------|
| Load average | 0.17, 0.11, 0.09 | **Excellent** (idle) |
| CPU idle | 99.3% | **Excellent** |
| Memory free | 14GB of 16GB | **Excellent** |
| Disk usage | 1% | **Excellent** |
| Swap usage | 0% | Perfect |

**Resource Assessment**: **Excellent** - System is lightly loaded with massive reserves.

### 2.4 Network Interface Performance

| Interface | RX Packets | TX Packets | RX Errors | TX Errors | Assessment |
|-----------|------------|------------|-----------|-----------|------------|
| ix0 (LAN) | 35.1M | 31.4M | 0 | 0 | Excellent |
| igc0 (WAN) | 14.8M | 18.6M | 0 | 0 | Excellent |
| lagg0 (NAS) | 17.0M | 16.9M | 0 | **6** | Minor |
| tun_wg0 | 3.0M | 1.5M | 0 | 12 | Minor |
| ovpnc1 | 109K | 109K | 0 | 0 | Good |

**LACP Status** (lagg0):
- Protocol: LACP
- Members: ix2, ix3
- Status: Both ACTIVE, COLLECTING, DISTRIBUTING

#### PERF-001: lagg0 TX Errors (Info)

6 TX errors over 17M packets (0.00004% error rate) - negligible and likely from LACP failover testing or transient conditions.

### 2.5 Firewall Performance

| Metric | Value | Assessment |
|--------|-------|------------|
| Total rules | 168 | Reasonable |
| USER_RULE count | ~40 | Well organized |
| Match rate | 8.2/s | Normal |

**Firewall Performance Assessment**: **Good** - Rule count is reasonable, no performance concerns.

### 2.6 Interrupt Distribution

Interrupts are well-distributed across CPU cores with no single core being overloaded. Network card queues (ix0, igc0, ix2, ix3) are properly utilizing multiple RX queues.

---

## Phase 3: Reliability Audit

### 3.1 DNS Reliability

#### REL-002: unbound-control Disabled (Medium)

**Current State**:
```
[1770220192] unbound-control[59356:0] warning: control-enable is 'no' in the config file.
```

**Impact**: Cannot easily query cache statistics, flush cache, or verify DNS health without restarting.

**Recommendation**: Enable unbound-control in DNS Resolver settings:
1. Services → DNS Resolver → Advanced Settings
2. Enable "Enable Remote Control"

#### REL-003: DNS Recursive Resolver Mode (Info)

**Current State**: Unbound operates as a **full recursive resolver** (no upstream forwarders configured).

**Assessment**: This is a valid configuration:
- **Pros**: More privacy (no single upstream DNS provider), full control
- **Cons**: Slightly slower for cold queries, depends on root servers

**Alternative**: Configure DNS over TLS forwarders (e.g., Cloudflare 1.1.1.1, Quad9 9.9.9.9) for faster resolution with privacy.

### 3.2 Gateway Monitoring

| Gateway | IP | Monitor IP | Status |
|---------|-----|------------|--------|
| WANGW | 192.168.1.4 | 192.168.1.1 | dpinger active |
| WAN_DHCP6 | fe80::21b:41ff:fe00:ed8 | fe80::1 | dpinger active |
| WG_VPS_Gate | 172.26.5.1 | 172.26.5.155 | dpinger active |
| WG_VPSGWv6 | fd86:ea04:1111::1 | fd86:ea04:1111::155 | dpinger active |
| NORDVPN | 10.100.0.2 | 10.100.0.1 | dpinger active |
| NASGW | 192.168.20.1 | 192.168.20.1 | dpinger active |

**Gateway Monitoring Assessment**: **Excellent** - All gateways monitored with dpinger.

### 3.3 Backup & Recovery

#### REL-001: No AutoConfigBackup (Medium)

**Current State**: AutoConfigBackup not configured in config.xml.

**Risk**: Configuration loss on hardware failure or misconfiguration.

**Recommendation**:
1. Enable AutoConfigBackup (encrypted backups to Netgate cloud)
2. Or: Implement automated local backup (cron + scp to NAS)
3. Store backup copies in git-crypt encrypted repository

### 3.4 System Stability

| Check | Status |
|-------|--------|
| Crashes (/var/crash) | None (only minfree file) |
| Kernel panics | None observed |
| Service restarts | sshguard restarted at 16:17 (normal) |
| ARP flaps | 192.168.8.82 MAC change (possible VM/container migration) |

**System Stability Assessment**: **Excellent** - No crashes or stability issues.

### 3.5 Software Updates

| Check | Status |
|-------|--------|
| pfSense version | 2.7.2-RELEASE |
| Update status | **"Your system is up to date"** |
| Build date | 2024-03-04 |

**Update Assessment**: **Good** - System is on latest stable release.

---

## Phase 4: Best Practices Review

### 4.1 Configuration Summary

| Practice | Status |
|----------|--------|
| Block bogons on WAN | **Implemented** |
| Block RFC1918 on WAN | **Implemented** |
| Guest network isolation | **Implemented** |
| NAS access restrictions | **Implemented** |
| VPN kill switch | **Implemented** |
| Policy-based routing | **Implemented** |
| DNS-level ad blocking | **Implemented** |
| IP-level threat blocking | **Implemented** |
| Gateway monitoring | **Implemented** |
| Public key SSH auth | **Implemented** |

### 4.2 Areas for Improvement

| Item | Priority | Effort |
|------|----------|--------|
| Upgrade to SNMPv3 | High | Medium |
| Enable DNSSEC | Medium | Low |
| Configure AutoConfigBackup | Medium | Low |
| Enable unbound-control | Medium | Low |
| Restrict anti-lockout rule | Low | Low |

### 4.3 Unused Features

| Feature | Status | Recommendation |
|---------|--------|----------------|
| ix1 interface | No carrier | Document or remove from config |
| hostapd package | Installed, unused | Consider removing |
| dnsmasq | Installed as backup | Document purpose |
| snort2c table | Empty | OK if IDS not needed |

---

## Remediation Plan

### Completed Items

| ID | Item | Completion Date | Notes |
|----|------|-----------------|-------|
| SEC-001 | Upgrade SNMP to v3 | 2026-02-04 | NET-SNMP + NixOS config |
| SEC-002 | Enable DNSSEC | 2026-02-04 | DNS Resolver custom options |
| REL-002 | Enable unbound-control | 2026-02-04 | DNS Resolver custom options |
| SEC-004 | Enable console password | 2026-02-07 | Via REST API |
| NEW-002 | Local backup automation | 2026-02-07 | scripts/pfsense-backup.sh + systemd timer |

### N/A Items (Not Applicable)

| ID | Item | Reason |
|----|------|--------|
| REL-001 | AutoConfigBackup | Only available in pfSense Plus (not CE Edition). Local backup via NEW-002 is sufficient. |

### Medium Priority (Requires pfSense GUI)

1. **NEW-001: Check for System Updates**
   - System → Update
   - pfSense 2.7.2 is from March 2024 - check for newer releases
   - Note: pfSense does NOT support automatic updates by design
   - Before updating: backup config, review release notes, plan maintenance window

### Low Priority (Backlog)

2. **SEC-003: Restrict anti-lockout rule**
   - Create alias "AdminDevices" with your workstation IPs
   - System → Advanced → Admin Access
   - Consider using custom anti-lockout with specific IPs

3. **SEC-006: Kernel Security Mitigations (Info Only)**
   - Kernel PTI and MDS mitigations are disabled
   - Intel i3-12100T (12th gen) has hardware mitigations for Spectre/Meltdown
   - Low priority - software mitigations have 5-30% performance impact
   - Decision: Leave as-is for home network firewall

4. **Documentation Updates**
   - Document ix1 interface purpose (future expansion?)
   - Document dnsmasq backup purpose
   - Add backup restore procedures

---

## Performance Baseline

For future comparison, current baseline metrics:

| Metric | Value | Date |
|--------|-------|------|
| State table entries | 770 | 2026-02-04 |
| State table limit | 1,606,000 | |
| DNS cold query | 33ms | |
| DNS cached query | 0ms | |
| CPU load avg | 0.17, 0.11, 0.09 | |
| Memory free | 14GB | |
| Disk used | 1% | |
| pfBlockerNG IPs | 16,242 | |
| Firewall rules | 168 | |

---

## Appendix: Raw Data

### A. Unbound Configuration Summary

```
server:
  port: 53
  verbosity: 1
  hide-identity: yes
  hide-version: yes
  harden-glue: yes
  harden-dnssec-stripped: no  # FINDING: Should be yes
  num-threads: 8
  msg-cache-size: 4m
  rrset-cache-size: 8m
  prefetch: yes
  prefetch-key: yes
  tls-port: 853
  private-address: (RFC1918 ranges configured)
```

### B. Key Security Sysctls

```
net.inet.ip.random_id: 1
net.inet.tcp.blackhole: 2
net.inet.udp.blackhole: 1
net.inet.tcp.drop_synfin: 1
```

### C. State Table Limits

```
states        hard limit  1606000
src-nodes     hard limit  1606000
frags         hard limit     5000
table-entries hard limit   400000
```

---

## Audit Conclusion

The pfSense firewall is **well-configured** and **operating efficiently**.

### Completed (as of 2026-02-09)
- SNMPv3 with authentication and encryption
- DNSSEC validation enabled
- unbound-control for DNS monitoring
- Console password protection enabled
- Local backup automation (daily, 30-day retention, monitored)

### N/A (Not Applicable)
- AutoConfigBackup - Only available in pfSense Plus (using local backup instead)

### Remaining Items (pfSense GUI required)
- Check for system updates (MEDIUM) - remain on 2.7.x stable branch
- Restrict anti-lockout rule (LOW)

The system has excellent performance margins and should handle significant traffic increases without concern.

**Note**: Attempted upgrade to pfSense 2.8.1 (FreeBSD 15) on 2026-02-09 failed during package download. Reverted to 2.7.2 stable branch. pkg database was successfully recovered. Recommend waiting for 2.8.x to mature before attempting upgrade again.

---

*Initial audit: 2026-02-04 16:51 CET*
*Last updated: 2026-02-09*
