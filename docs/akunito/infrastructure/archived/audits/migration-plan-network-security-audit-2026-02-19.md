---
id: audits.migration-plan.network-security.2026-02-19
summary: Network architecture, VPS hardening, and Nextcloud security audit of the Proxmox-to-VPS migration plan
tags: [audit, security, network, vps, nextcloud, tailscale, wireguard, cloudflare, firewall, dns]
date: 2026-02-19
status: published
---

# Migration Plan Audit: Network & Security

| Field | Value |
|-------|-------|
| **Date** | 2026-02-19 |
| **Auditor** | Claude Code (automated) |
| **Plan file** | `~/.claude/plans/dapper-splashing-pebble.md` |
| **Scope** | VPS external hardening, VPS<->TrueNAS connectivity, access patterns (LAN/Global/Tailscale), Nextcloud security |
| **Cross-refs** | `migration-plan-audit-2026-02-19.md` (code-level audit), `pfsense-audit-2026-02-04.md`, `truenas-audit-2026-02-12.md` |

---

## Update Log

| Date | Changes |
|------|---------|
| 2026-02-19 | Initial audit |

---

## Executive Summary

### Scores

| Category | Score | Notes |
|----------|-------|-------|
| VPS External Hardening | 7/10 | Strong baseline (LUKS, fail2ban, key-only SSH, rootless Docker). Gaps in IPv6, rate limiting, IDS, and secret management |
| VPS<->TrueNAS Connectivity | 8/10 | Dual-path design (Tailscale primary + WireGuard backup) is resilient. Circular dependency and sleep-window gaps exist |
| DNS & Access Patterns | 7/10 | Split DNS is correct architecture. Missing: remote *.local.akunito.com resolution, Cloudflare WAF, DNS rebinding protection |
| Nextcloud Security | 5/10 | Most significant gap in the plan. Running as root in container, no 2FA, no brute-force protection, broad trusted_proxies, no file scanning |
| Backup & Recovery | 8/10 | Comprehensive 3-layer backup. Good DR runbook. Missing: backup encryption key rotation, tested restore schedule |

### Top 10 Findings

| # | ID | Severity | Finding |
|---|-----|----------|---------|
| 1 | SEC-NC-001 | **Critical** | Nextcloud has no brute-force protection beyond Cloudflare — no fail2ban jail, no rate limiting |
| 2 | SEC-NC-002 | **Critical** | Nextcloud 2FA/TOTP not mentioned — all user data accessible with just a password |
| 3 | SEC-VPS-001 | **Critical** | No intrusion detection system (IDS/IPS) on VPS — fail2ban only covers SSH/nginx |
| 4 | NET-CIRC-001 | **High** | Headscale on VPS creates circular dependency — VPS crash + TrueNAS reboot = no Tailscale mesh recovery without WireGuard |
| 5 | SEC-VPS-002 | **High** | No secrets management system (agenix/sops-nix) — all secrets are imperative files with no rotation or audit trail |
| 6 | SEC-VPS-003 | **High** | IPv6 handling is "disable or configure" — plan must pick one; if IPv6 leaks, entire firewall is bypassed |
| 7 | NET-DNS-001 | **High** | Remote Tailscale clients cannot resolve *.local.akunito.com without Headscale DNS push — plan mentions CERT-004 but doesn't implement it |
| 8 | SEC-NC-003 | **High** | Nextcloud trusted_proxies set to entire Docker subnet (172.17.0.0/16) — overly broad, allows IP spoofing from any container |
| 9 | SEC-VPS-004 | **High** | Docker socket/API accessible to akunito user — rootless Docker still means container escape = full user account compromise |
| 10 | NET-FW-001 | **Medium** | NixOS firewall doesn't log refused connections — no visibility into attack patterns or port scans |

---

## Part 1: VPS External Hardening

### 1.1 Attack Surface Analysis

The VPS will be directly internet-facing. Every open port and every service behind Cloudflare is an attack vector.

#### Ports exposed to the internet

| Port | Proto | Service | Risk | Plan Coverage |
|------|-------|---------|------|---------------|
| 56777/tcp | SSH | Remote admin | Medium (key-only + fail2ban) | Covered well |
| 2222/tcp | SSH (initrd) | LUKS unlock | **High** — always listening, no fail2ban in initrd | Partially covered |
| 51820/udp | WireGuard | VPN tunnel | Low (cryptographic auth) | Covered |
| 41641/udp | Tailscale | Mesh VPN | Low (cryptographic auth) | Covered |
| 80/tcp | HTTP | ACME/redirect | **See SEC-PORT-001** | **Gap** |
| 443/tcp | HTTPS | Cloudflare/NPM | **See SEC-PORT-001** | **Gap** |
| 3478/udp | STUN/DERP | Tailscale relay | Low | Covered (Phase 6b) |

**Finding SEC-PORT-001 (High): Ports 80/443 in `allowedTCPPorts` but NPM binds to 127.0.0.1**

The plan adds ports 80 and 443 to `networking.firewall.allowedTCPPorts` (line 802), but NPM binds to `127.0.0.1` only (line 1154). This means:
- Ports 80/443 are open in the firewall but nothing listens on them publicly
- If ANY future service accidentally binds `0.0.0.0:80` or `0.0.0.0:443`, it's immediately internet-exposed
- **Recommendation**: Remove 80/443 from `allowedTCPPorts`. cloudflared connects to `localhost:443` — it doesn't need inbound firewall rules. ACME uses DNS-01 challenges — no HTTP-01 needed. The only reason to open these is HTTP-01 ACME fallback, which the plan explicitly doesn't use.

```nix
# BEFORE (plan line 802):
allowedTCPPorts = [ 56777 443 80 2222 ];

# AFTER (recommended):
allowedTCPPorts = [ 56777 2222 ];
# 80/443 not needed: cloudflared uses outbound tunnel, ACME uses DNS-01
# 51820/41641 UDP are already listed in allowedUDPPorts
```

**Finding SEC-INITRD-001 (Medium): Initrd SSH (port 2222) has no brute-force protection**

The initrd SSH listener runs a minimal busybox environment — no fail2ban, no rate limiting. An attacker can brute-force the LUKS passphrase via SSH on port 2222.

- **Mitigating factors**: LUKS passphrase should be a strong diceware phrase (plan says 6-word), SSH key auth is required for initrd SSH (authorized_keys in the plan), the LUKS passphrase is entered interactively after SSH — not as a password to SSH itself.
- **Recommendation**: Confirm that initrd SSH uses `authorizedKeys` only (no password auth). Add `iptables` rate limiting in `boot.initrd.network.postCommands`:
  ```nix
  boot.initrd.network.postCommands = ''
    iptables -A INPUT -p tcp --dport 2222 -m conntrack --ctstate NEW -m recent --set
    iptables -A INPUT -p tcp --dport 2222 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
  '';
  ```

#### Finding SEC-VPS-001 (Critical): No IDS/IPS on VPS

The plan relies solely on fail2ban for active defense. fail2ban only monitors known log patterns (SSH failures, nginx auth failures). It does not detect:
- Port scanning / reconnaissance
- Unusual outbound connections (C2 beaconing from a compromised container)
- Filesystem integrity changes (rootkit detection)
- Anomalous network traffic patterns

**Recommendation (phased)**:
1. **Phase 1 (immediate)**: Enable `networking.firewall.logRefusedConnections = true` — basic visibility
2. **Phase 6b (post-migration)**: Deploy CrowdSec (the plan mentions it as "consider") — make it mandatory:
   ```nix
   services.crowdsec = {
     enable = true;
     # Community threat intelligence + local log parsing
   };
   ```
3. **Phase 6b**: Add AIDE or similar for filesystem integrity monitoring on critical paths (`/etc/`, `/var/lib/headscale/`, `/etc/secrets/`)
4. **Phase 6b**: Add outbound connection monitoring — audit `ss -tnp` in a systemd timer, alert on unexpected ESTABLISHED connections

#### Finding SEC-VPS-003 (High): IPv6 must be explicitly disabled or fully configured

The plan (line 889-896) says "either disable or configure" but doesn't commit to one. This is dangerous:
- If IPv6 is partially enabled, Docker containers may bind IPv6 addresses that bypass the IPv4 firewall rules
- NixOS `networking.firewall` handles both IPv4 and IPv6, but fail2ban jails, Cloudflare Tunnel, and all `127.0.0.1` bindings are IPv4-only
- Rootless Docker with `slirp4netns` may expose IPv6 ports differently than IPv4

**Recommendation**: Disable IPv6 in Phase 1 (simplest, safest). Enable only if a specific service requires it, with full audit of firewall + fail2ban + Docker implications:
```nix
# Mandatory in VPS-base-config.nix:
boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;
boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 1;
```

#### Finding SEC-VPS-002 (High): Imperative secrets with no rotation or audit

All secrets are manually created files (`/etc/secrets/*`). Problems:
- No audit trail of who changed a secret or when
- No automated rotation schedule
- Secrets survive across NixOS rebuilds (not managed declaratively)
- If VPS is compromised, attacker has immediate access to all secrets in `/etc/secrets/`

**Recommendation (post-migration)**:
1. Adopt `sops-nix` for declarative secret management — secrets encrypted in the repo, decrypted at activation time
2. Document rotation schedule: Cloudflare API keys (yearly), DB passwords (yearly), SSH keys (already rotated per commit c7f0d75)
3. Minimum: add a systemd timer that checks file ages of secrets and alerts if >365 days old

### 1.2 SSH Hardening Gaps

The plan covers the basics well (non-standard port, key-only, fail2ban). Missing items:

#### Finding SEC-SSH-001 (Medium): Missing SSH hardening options

Current `sshd.nix` lacks several hardening options that should be added for a public-facing VPS:

```nix
# Add to system/security/sshd.nix or profiles/vps/base.nix:
services.openssh.settings = {
  MaxAuthTries = 3;           # Default 6 — reduce window before fail2ban kicks in
  LoginGraceTime = 30;        # Default 120s — reduce idle connection window
  ClientAliveInterval = 300;  # Disconnect idle sessions after 5min × 3 = 15min
  ClientAliveCountMax = 3;
  X11Forwarding = false;      # Explicit, defense in depth
  AllowAgentForwarding = true; # Needed per CLAUDE.md SSH agent forwarding requirement
  AllowTcpForwarding = true;  # Needed for SSH tunnels to NPM admin (port 81)
};
```

#### Finding SEC-SSH-002 (Low): SSH cipher suite not restricted

NixOS defaults are reasonable but a VPS should use only modern ciphers:
```nix
services.openssh.settings = {
  Ciphers = [ "chacha20-poly1305@openssh.com" "aes256-gcm@openssh.com" ];
  KexAlgorithms = [ "curve25519-sha256" "curve25519-sha256@libssh.org" ];
  Macs = [ "hmac-sha2-512-etm@openssh.com" "hmac-sha2-256-etm@openssh.com" ];
};
```

### 1.3 Kernel & System Hardening

#### Finding SEC-KERN-001 (Medium): Missing kernel hardening sysctls

The plan includes good network sysctls (SYN cookies, rp_filter, no redirects). Missing:

```nix
boot.kernel.sysctl = {
  # Already in plan:
  "net.ipv4.tcp_syncookies" = 1;
  "net.ipv4.conf.all.rp_filter" = 1;
  # ...

  # Missing — add these:
  "kernel.dmesg_restrict" = 1;           # Restrict dmesg to root (info leak prevention)
  "kernel.kptr_restrict" = 2;            # Hide kernel pointers from all users
  "kernel.yama.ptrace_scope" = 1;        # Restrict ptrace to parent processes
  "net.core.bpf_jit_harden" = 2;        # Harden BPF JIT compiler
  "kernel.unprivileged_bpf_disabled" = 1; # Disable unprivileged BPF
  "kernel.perf_event_paranoid" = 3;      # Restrict perf_event_open
  "fs.protected_hardlinks" = 1;          # Prevent hardlink-based attacks
  "fs.protected_symlinks" = 1;           # Prevent symlink-based attacks
  "fs.suid_dumpable" = 0;               # Don't dump suid core files
};
```

#### Finding SEC-KERN-002 (Low): No security module (AppArmor/SELinux)

The plan doesn't mention any mandatory access control system. NixOS supports AppArmor:
```nix
security.apparmor.enable = true;  # Post-migration optimization
```
This is low priority but adds defense-in-depth for container escapes.

### 1.4 Docker Security on VPS

#### Finding SEC-VPS-004 (High): Rootless Docker blast radius

Rootless Docker is a significant improvement over root Docker. However:
- Container escape from rootless Docker gives the `akunito` user's full permissions
- `akunito` has passwordless sudo (per plan practical approach, line 877)
- Therefore: container escape → `akunito` shell → `sudo su` → root → full VPS compromise

**Attack chain**: Vulnerable web app (e.g., Nextcloud RCE) → container escape (kernel exploit or misconfigured volume mount) → `akunito` user → passwordless `sudo` → root

**Recommendation**:
1. **Strong preference**: Set `wheelNeedsPassword = true` on VPS (the plan discusses this at line 856-883 but chooses `false`). The inconvenience of typing a password for `sudo` is minimal vs. the escalation risk on a public server.
2. If `wheelNeedsPassword = false` is kept: ensure no writable host paths are mounted into containers (all `:ro` except data volumes)
3. Add `no-new-privileges:true` to ALL docker-compose files (plan mentions this in Phase 6b but should be Phase 3)
4. Run `docker scan` or `trivy` on images before deployment

#### Finding SEC-DOCKER-001 (Medium): Docker compose files not version-controlled in dotfiles

The plan stores docker-compose files at `/opt/docker-compose/` on the VPS (not in the NixOS flake). This means:
- No code review for security changes
- No diff history for port binding changes
- The validation script for `127.0.0.1` bindings (plan line 1167) is manual

**Recommendation**: Store docker-compose files in the dotfiles repo under `docker/vps/` and deploy them via NixOS module or `install.sh`. This way, all port bindings are code-reviewed.

### 1.5 Cloudflare as WAF

#### Finding SEC-CF-001 (High): No Cloudflare WAF rules configured

The plan mentions Cloudflare WAF (line 1594) as "consider" in Phase 6b. For a public VPS, WAF should be Phase 2b (when Cloudflare Tunnel is set up).

**Minimum Cloudflare settings (free tier)**:
1. **Bot Fight Mode**: Enable (blocks known bad bots)
2. **Security Level**: Medium or High
3. **Browser Integrity Check**: Enable
4. **Challenge Passage**: 30 minutes
5. **Custom WAF rules** (5 free):
   - Block requests with `User-Agent` containing known scanners (Nikto, sqlmap, etc.)
   - Rate limit: 100 requests/10s per IP to any `*.akunito.com`
   - Block countries you never access from (if applicable)
   - Challenge requests to `/wp-admin`, `/xmlrpc.php`, `/.env` (common scanner paths)
   - Block requests with SQL injection patterns in query strings

6. **Cloudflare Access (Zero Trust)**: For admin panels (NPM at port 81, Grafana, Prometheus):
   - Require email OTP or SSO before reaching the service
   - This is FREE on Cloudflare's free plan for up to 50 users

---

## Part 2: VPS <-> TrueNAS Connectivity

### 2.1 Dual-Path Architecture Assessment

The plan's dual-path design (Tailscale primary + WireGuard backup) is sound:

```
VPS ──── Tailscale mesh (100.x.x.x) ──── TrueNAS (subnet router)
  │                                              │
  └── WireGuard (172.26.5.x) ── pfSense ────────┘ (backup)
```

#### Finding NET-CIRC-001 (High): Headscale circular dependency

Scenario: VPS crashes hard (kernel panic, disk failure). Netcup auto-reboots VPS. You SSH to port 2222, enter LUKS passphrase. NixOS boots. But:
1. Headscale starts on VPS
2. TrueNAS was rebooted during maintenance (e.g., firmware update) while VPS was down
3. TrueNAS Docker Tailscale needs to re-authenticate to Headscale
4. But Headscale just started with an empty ephemeral state? No — the sqlite DB is persistent. **However**: if TrueNAS's Tailscale node key expired (Headscale has key expiry), TrueNAS can't re-auth automatically.

**The WireGuard backup path breaks this circular dependency** — this is correctly identified in the plan (line 1768). However:

**Gap**: The plan doesn't specify how WireGuard failover is triggered. If Tailscale is down and backups need to run, does restic know to use the WireGuard path?

**Recommendation**:
1. Configure restic backup target as a hostname that resolves to TrueNAS Tailscale IP (primary), with a script that falls back to `192.168.20.200` via WireGuard route:
   ```bash
   # In vps-backup-sync.nix ExecStartPre:
   if ! ping -c1 -W3 <TRUENAS_TAILSCALE_IP>; then
     # Tailscale down — route via WireGuard
     ip route add 192.168.20.200/32 via 172.26.5.1 dev wg0 2>/dev/null || true
     BACKUP_TARGET="truenas_admin@192.168.20.200"
   else
     BACKUP_TARGET="truenas_admin@<TRUENAS_TAILSCALE_IP>"
   fi
   ```
2. Set Headscale node key expiry to very long (87600h = 10 years) for infrastructure nodes (TrueNAS, pfSense)
3. Add Prometheus alert: `tailscale_peers_direct == 0 AND wireguard_latest_handshake_seconds > 300` = both paths down

#### Finding NET-SLEEP-001 (Medium): TrueNAS sleep window breaks backup schedule

TrueNAS suspends 00:00-08:00. The plan schedules restic backups during waking hours (08:30-22:30). But:
- If a restic backup runs long (initial nextcloud backup is ~200GB), it could hit midnight
- The `ExecStartPre` connectivity check (ping TrueNAS, 3 retries at 30s) could pass at 23:55, then TrueNAS suspends at 00:00 mid-transfer
- restic handles interruption gracefully (lock + retry), but the backup is incomplete

**Recommendation**:
1. Add `TimeoutStopSec=23h55m` type guard is impractical. Instead: add a pre-suspend notification. TrueNAS sends MQTT/webhook 5 minutes before suspension. VPS `vps-backup-sync.nix` checks a "TrueNAS awake" signal.
2. Simpler: ensure the latest scheduled backup (22:30) is for databases only (small, completes in minutes). Nextcloud backup at 10:00 (maximum 13h before midnight — more than enough for incremental deltas).
3. Add `OnActiveSec=23h` watchdog to kill hung restic processes before midnight.

### 2.2 Service Reachability Matrix

After migration, these services need to communicate:

| Source | Destination | Path | Port | Purpose |
|--------|-------------|------|------|---------|
| VPS Prometheus | TrueNAS node_exporter | Tailscale | 9100 | Monitoring |
| VPS Prometheus | TrueNAS cAdvisor | Tailscale | 8081 | Container monitoring |
| VPS Prometheus | pfSense SNMP | Tailscale→subnet | 161/udp | Firewall monitoring |
| VPS Prometheus | DESK node_exporter | Tailscale→subnet | 9100 | Desktop monitoring |
| VPS restic | TrueNAS SFTP | Tailscale | 22 | Backup |
| VPS Headscale | All Tailscale clients | Internet | 443 | Coordination |
| TrueNAS Kuma | VPS public URLs | Internet | 443 | External monitoring |
| TrueNAS Tailscale | VPS Headscale | Internet | 443 | Mesh registration |
| Mobile/Laptop | VPS services | Cloudflare | 443 | App access |
| Mobile/Laptop | TrueNAS services | Tailscale→subnet→pfSense DNS | 443 | Local services via Tailscale |
| LAN clients | TrueNAS NPM | pfSense DNS | 80/443 | *.local.akunito.com |
| LAN clients | VPS services | Cloudflare | 443 | *.akunito.com |

#### Finding NET-REACH-001 (Medium): No explicit monitoring of inter-site connectivity

The plan monitors services but doesn't explicitly monitor the Tailscale/WireGuard paths themselves.

**Recommendation**: Add Prometheus blackbox exporter probes:
```yaml
# On VPS Prometheus:
- job_name: 'connectivity'
  metrics_path: /probe
  params:
    module: [icmp]
  static_configs:
    - targets:
      - <TRUENAS_TAILSCALE_IP>    # Tailscale path
      - 192.168.8.1               # WireGuard→pfSense path
      - 192.168.20.200            # WireGuard→TrueNAS path (via pfSense route)
```

Alert if all three paths are down simultaneously = complete isolation.

---

## Part 3: DNS & Access Patterns

### 3.1 Split DNS Architecture

The plan's split DNS design (line 1774-1789):

```
*.akunito.com (public)         → Cloudflare → VPS NPM → backend
*.local.akunito.com (local)    → pfSense DNS → TrueNAS NPM (192.168.8.200) → backend
```

This is the correct architecture. Issues found:

#### Finding NET-DNS-001 (High): Remote Tailscale clients can't resolve *.local.akunito.com

The plan identifies this as CERT-004 (line 1741) with a Headscale DNS push solution:
```yaml
dns:
  nameservers: ["192.168.8.1"]
  domains: ["local.akunito.com"]
```

**Problem**: This is mentioned but NOT in any implementation phase checklist. It's in the "Network Architecture" documentation section, not in a Phase task.

**Impact**: When you're traveling with your phone/laptop on mobile data, joined to Tailscale, you can reach 192.168.8.x IPs via the subnet router, but `jellyfin.local.akunito.com` won't resolve because:
1. Your phone uses public DNS (e.g., 1.1.1.1)
2. `*.local.akunito.com` is not in public DNS (only pfSense local override)
3. Headscale DNS push would route `.local.akunito.com` queries to pfSense (192.168.8.1) via Tailscale

**Recommendation**: Add to Phase 1 checklist:
- [ ] Configure Headscale `dns.nameservers` to push `192.168.8.1` for `local.akunito.com` domain
- [ ] Verify from mobile on cellular: `dig @192.168.8.1 jellyfin.local.akunito.com` returns `192.168.8.200`
- [ ] Verify: `curl -I https://jellyfin.local.akunito.com` returns valid cert

#### Finding NET-DNS-002 (Medium): No DNS rebinding protection

If an attacker controls a domain that resolves to `127.0.0.1` or `192.168.x.x`, they could use DNS rebinding to access internal VPS services through a victim's browser.

**Recommendation**:
1. NPM on VPS: add a default server block that returns 444 (close connection) for unknown `Host` headers
2. Cloudflare: already protects against DNS rebinding for `*.akunito.com` (traffic goes through their tunnel)
3. TrueNAS NPM: add default server block that rejects unknown `Host` headers

#### Finding NET-DNS-003 (Medium): pfSense DNS override must be updated in Phase 4

The plan mentions updating pfSense DNS in Phase 4 (line 1371):
> Update pfSense DNS overrides for `*.local.akunito.com` to VPS Tailscale IP (100.x.x.x)

**Wait — this is wrong.** The split DNS design says:
- `*.local.akunito.com` → TrueNAS (192.168.8.200) for media/homelab services
- `*.akunito.com` → Cloudflare → VPS for application services

VPS services should NOT be accessed via `*.local.akunito.com` from LAN. LAN clients use the public `*.akunito.com` URLs for VPS services (through Cloudflare). Only TrueNAS services use `*.local.akunito.com`.

**But**: This means LAN access to VPS services (Plane, Matrix, Nextcloud) adds ~22ms latency through Cloudflare even when you're at home. The plan acknowledges this (line 1785-1788) and accepts it.

**Recommendation**: This is fine as designed. Remove the confusing Phase 4 mention of updating `*.local.akunito.com` to VPS Tailscale IP. The pfSense override for `*.local.akunito.com` should point to TrueNAS (192.168.8.200), not VPS.

### 3.2 Access Pattern Verification Matrix

| Scenario | Domain | Resolution Path | Expected | Plan Phase |
|----------|--------|----------------|----------|------------|
| LAN → Jellyfin | jellyfin.local.akunito.com | pfSense → 192.168.8.200 (TrueNAS NPM) | Direct LAN, ~1ms | Phase 0.5 |
| LAN → Plane | plane.akunito.com | Cloudflare → VPS | Via Cloudflare, ~22ms | Phase 4 |
| LAN → Nextcloud | nextcloud.akunito.com | Cloudflare → VPS | Via Cloudflare, ~22ms | Phase 4 |
| Remote (Tailscale) → Jellyfin | jellyfin.local.akunito.com | **Headscale DNS push** → pfSense → TrueNAS NPM | Via Tailscale mesh | **Missing — add to Phase 1** |
| Remote (Tailscale) → Plane | plane.akunito.com | Cloudflare → VPS | Normal public route | Phase 4 |
| Remote (no VPN) → Plane | plane.akunito.com | Cloudflare → VPS | Normal public route | Phase 4 |
| Remote (no VPN) → Jellyfin | jellyfin.local.akunito.com | **Fails** — not in public DNS | Must use Tailscale | By design |
| VPS → TrueNAS (backup) | Tailscale IP | Direct Tailscale mesh | ~22ms VPS↔home | Phase 6 |
| VPS → pfSense (monitoring) | Tailscale → 192.168.8.1 | Subnet routing | ~22ms | Phase 2d |

#### Finding NET-ACCESS-001 (Medium): No fallback for LAN → VPS services if Cloudflare is down

If Cloudflare has an outage (rare but happens), LAN clients cannot reach Plane, Matrix, or Nextcloud because they route through Cloudflare even from home.

**Recommendation**: Add a "Cloudflare bypass" option to pfSense DNS:
```
# Emergency pfSense DNS overrides (disabled by default, enable during Cloudflare outage):
plane.akunito.com → <VPS_TAILSCALE_IP>
matrix.akunito.com → <VPS_TAILSCALE_IP>
nextcloud.akunito.com → <VPS_TAILSCALE_IP>
```
This routes LAN traffic directly to VPS via Tailscale, bypassing Cloudflare. Document as emergency procedure only (certs may not match if VPS NPM expects Cloudflare headers).

---

## Part 4: Nextcloud Security (Critical Focus)

Nextcloud is the highest-risk service in this migration:
- **Public-facing** — anyone on the internet can reach the login page
- **Contains all personal data** — files, photos, contacts, calendars
- **Complex attack surface** — PHP, many plugins, WebDAV, CalDAV, CardDAV
- **Running as root inside container** — per plan's rootless exception (line 1279)

### 4.1 Authentication & Access Control

#### Finding SEC-NC-001 (Critical): No brute-force protection for Nextcloud login

The plan configures fail2ban for SSH and nginx, but there is **no fail2ban jail for Nextcloud**. Nextcloud's login page is publicly accessible via `nextcloud.akunito.com`. An attacker can:
1. Enumerate usernames via timing attacks on the login page
2. Brute-force passwords indefinitely (no rate limiting mentioned)
3. Nextcloud's built-in brute-force protection is IP-based, but behind Cloudflare + NPM, all requests appear to come from the proxy IP unless headers are correctly forwarded

**Recommendation**:
1. **Phase 3e (deployment)**: Configure Nextcloud brute-force protection app (built-in):
   ```php
   // config.php:
   'auth.bruteforce.protection.enabled' => true,
   'ratelimit.protection.enabled' => true,
   ```
2. **Phase 3e**: Add fail2ban jail for Nextcloud on VPS:
   ```nix
   # In fail2ban.nix:
   services.fail2ban.jails.nextcloud = {
     enabled = true;
     filter = "nextcloud";
     logpath = "/var/log/nextcloud.log";  # Or Docker log path
     maxretry = 5;
     bantime = "1h";
     findtime = "600";
   };
   ```
   Requires Nextcloud to log to a file (configure `'logfile' => '/var/log/nextcloud.log'` in config.php), or use Docker log driver.
3. **Phase 2b**: Enable Cloudflare rate limiting on `nextcloud.akunito.com/login` — max 10 requests/minute per IP
4. **Phase 2b**: Enable Cloudflare "Under Attack Mode" option for `nextcloud.akunito.com` if brute-force is detected

#### Finding SEC-NC-002 (Critical): No 2FA/TOTP mentioned

The plan does not mention enabling two-factor authentication for Nextcloud. A stolen or brute-forced password gives complete access to all files.

**Recommendation**:
1. **Phase 3e (deployment)**: Enable TOTP 2FA app in Nextcloud
2. Enforce TOTP for all users (especially admin)
3. Store TOTP recovery codes in Bitwarden
4. Consider: Nextcloud supports WebAuthn/FIDO2 keys — stronger than TOTP

#### Finding SEC-NC-003 (High): Overly broad trusted_proxies

Plan line 1304:
```php
'trusted_proxies' => ['172.17.0.0/16'],  // Docker network range for NPM proxy
```

This trusts the ENTIRE Docker bridge network range. Any container on the VPS Docker bridge can set `X-Forwarded-For` headers and spoof the client IP. This defeats:
- Nextcloud brute-force protection (attacker rotates spoofed IPs)
- IP-based access logging
- Fail2ban IP bans

**Recommendation**: Use the specific NPM container IP, not the entire subnet:
```php
'trusted_proxies' => ['172.17.0.2'],  // Only the NPM container IP
// Or use the Docker container name with Docker DNS:
'trusted_proxies' => ['npm'],
```
Better yet — use Docker network and assign a static IP to NPM:
```yaml
# docker-compose.yml:
services:
  npm:
    networks:
      internal:
        ipv4_address: 172.20.0.2
networks:
  internal:
    ipam:
      config:
        - subnet: 172.20.0.0/24
```
Then: `'trusted_proxies' => ['172.20.0.2']`

### 4.2 Nextcloud Container Security

#### Finding SEC-NC-004 (High): Nextcloud running as root in container

The plan (line 1279) anticipates needing `user: "0:0"` due to PHP-FPM/www-data UID issues. This means:
- Inside the container, processes run as root
- If a Nextcloud vulnerability allows code execution, it executes as root (inside the container)
- With rootless Docker, this is limited to the `akunito` UID namespace, but combined with SEC-VPS-004 (passwordless sudo), it's still dangerous

**Recommendation**:
1. **Phase 3e**: Test WITHOUT `user: "0:0"` first. The official Nextcloud Docker image runs as `www-data` internally. Rootless Docker remaps UIDs, so `www-data` (UID 33) inside maps to `akunito-subuid + 33` on the host. Volume permissions:
   ```bash
   # After starting the container, fix ownership from host:
   podman unshare chown -R 33:33 /var/lib/nextcloud-data
   ```
2. If `user: "0:0"` is truly needed: add `security_opt: [no-new-privileges:true]` and `read_only: true` with explicit tmpfs for writable paths:
   ```yaml
   security_opt:
     - no-new-privileges:true
   read_only: true
   tmpfs:
     - /tmp
     - /var/www/html/data/appdata_*/preview  # Temporary preview generation
   ```

#### Finding SEC-NC-005 (Medium): No antivirus/file scanning

Nextcloud is a file sync service — users upload files. Without scanning:
- Malware can be uploaded and synced to all devices
- EICAR test files won't trigger alerts

**Recommendation (post-migration)**:
1. Enable Nextcloud `files_antivirus` app with ClamAV:
   ```yaml
   # Add to VPS docker-compose:
   clamav:
     image: clamav/clamav:latest
     volumes:
       - /var/lib/clamav:/var/lib/clamav
     mem_limit: 2g  # ClamAV uses significant RAM for virus DB
   ```
2. Configure Nextcloud to use ClamAV daemon mode (clamd socket)
3. This adds ~2GB to VPS RAM budget — check if within the 32GB headroom (plan shows ~13.7GB free, so yes)

### 4.3 Nextcloud Data Protection

#### Finding SEC-NC-006 (Medium): No server-side encryption mentioned

Nextcloud supports server-side encryption (SSE). Without it:
- VPS disk images (LUKS protects at rest, but not if attacker has running access)
- Restic backups on TrueNAS are encrypted by restic, but TrueNAS itself has unencrypted ZFS

LUKS encryption on VPS and restic encryption for backups provide reasonable protection. SSE adds marginal benefit at significant performance cost. **Acceptable to skip**, but document the threat model.

#### Finding SEC-NC-007 (Medium): Nextcloud config.php needs additional hardening

Beyond what the plan lists (line 1296-1306), add:

```php
// Security headers (if not handled by NPM):
'overwrite.cli.url' => 'https://nextcloud.akunito.com',
'htaccess.RewriteBase' => '/',

// Additional security settings:
'filelocking.enabled' => true,                    // Prevent concurrent edit corruption
'memcache.locking' => '\\OC\\Memcache\\Redis',   // Use Redis for file locking
'memcache.local' => '\\OC\\Memcache\\APCu',      // Local memcache
'memcache.distributed' => '\\OC\\Memcache\\Redis', // Distributed cache

// CRITICAL: Log settings for fail2ban and audit:
'loglevel' => 2,                    // Info level (captures auth failures)
'log_type' => 'file',
'logfile' => '/var/log/nextcloud/nextcloud.log',
'logdateformat' => 'Y-m-d H:i:s',
'logtimezone' => 'UTC',

// Session security:
'session_lifetime' => 3600,        // 1 hour session timeout
'session_keepalive' => true,
'token_auth_enforced' => false,    // Set true after verifying all clients support it

// Disable features that increase attack surface:
'knowledgebaseenabled' => false,
'enable_previews' => true,        // Useful — but limit providers:
'enabledPreviewProviders' => [
  'OC\\Preview\\PNG',
  'OC\\Preview\\JPEG',
  'OC\\Preview\\GIF',
  'OC\\Preview\\BMP',
  'OC\\Preview\\MP3',
  'OC\\Preview\\TXT',
  'OC\\Preview\\MarkDown',
],
// IMPORTANT: Do NOT include Movie, SVG, or PDF preview providers
// SVG/PDF preview generation has had RCE vulnerabilities (ImageMagick/Ghostscript)
```

### 4.4 NPM/Proxy Security for Nextcloud

#### Finding SEC-NC-008 (Medium): Missing security headers for Nextcloud proxy

NPM (Nginx Proxy Manager) should add these headers for Nextcloud:

```nginx
# In NPM proxy host advanced config for nextcloud.akunito.com:
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto https;
proxy_set_header X-Real-IP $remote_addr;

# Security headers:
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "no-referrer" always;
add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;

# WebDAV support (required for sync clients):
proxy_set_header Host $host;
proxy_buffering off;
client_max_body_size 10G;  # Allow large file uploads
proxy_request_buffering off;
```

#### Finding SEC-NC-009 (Low): Consider Cloudflare Access for Nextcloud admin

Nextcloud admin panel (`/settings/admin`) should be protected by an additional layer:
- Cloudflare Access policy: require email OTP to access `/settings/admin/*`
- This prevents an attacker who somehow gets Nextcloud credentials from modifying server settings

---

## Part 5: Firewall & Network Segmentation

### 5.1 VPS Firewall

#### Finding NET-FW-001 (Medium): No connection logging

The plan doesn't set `networking.firewall.logRefusedConnections`. Without this, you have zero visibility into:
- How many bots are scanning your VPS
- Whether specific ports are being targeted
- Whether your firewall rules are actually working

**Recommendation**:
```nix
networking.firewall = {
  enable = true;
  logRefusedConnections = true;   # Add this
  logRefusedPackets = false;      # Too noisy, keep off
  logReversePathDrops = true;     # Log IP spoofing attempts
};
```

#### Finding NET-FW-002 (Medium): No Docker network isolation

All rootless Docker containers share the default bridge network. A compromised Plane container can reach Matrix Synapse's internal port, PostgreSQL (if it binds to the bridge), etc.

**Recommendation**: Use Docker Compose networks to isolate service groups:
```yaml
# Example: create separate networks
networks:
  proxy:          # NPM + cloudflared
  apps:           # Plane, Portfolio, LiftCraft
  matrix:         # Synapse + Element
  nextcloud:      # Nextcloud + internal deps
  databases:      # Only services that need DB access

services:
  npm:
    networks: [proxy, apps, matrix, nextcloud]  # Routes to all
  plane:
    networks: [apps]  # Only reachable from NPM via 'apps' network
  synapse:
    networks: [matrix] # Isolated from Plane/Nextcloud
```

### 5.2 pfSense Rules Update

#### Finding NET-PF-001 (Low): pfSense WireGuard rules need audit after migration

Current pfSense WireGuard rules (from pfsense.md line 210-216) allow broad access from `172.26.5.0/24`. After migration:
- The new VPS has a different public IP (Netcup, not Hetzner)
- pfSense WireGuard peer endpoint must be updated
- Consider restricting WireGuard rules to only the VPS's tunnel IP (`172.26.5.155/32`) instead of the whole `/24`

**Recommendation**: Add to Phase 1 checklist:
- [ ] Update pfSense WireGuard peer endpoint IP from old (Hetzner) to new (Netcup)
- [ ] Tighten WireGuard firewall rules: `172.26.5.155/32` instead of `172.26.5.0/24` (VPS is the only peer)

---

## Part 6: Consolidated Recommendations by Priority

### Critical (must fix before going live)

| ID | Finding | Phase to Fix |
|----|---------|-------------|
| SEC-NC-001 | Add Nextcloud brute-force protection (fail2ban + Cloudflare rate limit + built-in protection) | Phase 3e |
| SEC-NC-002 | Enable TOTP 2FA for all Nextcloud users | Phase 3e |
| SEC-VPS-001 | Deploy CrowdSec or equivalent IDS — at minimum enable firewall connection logging | Phase 2b (logging), Phase 6b (IDS) |

### High (fix within first week of production)

| ID | Finding | Phase to Fix |
|----|---------|-------------|
| SEC-PORT-001 | Remove ports 80/443 from allowedTCPPorts (not needed with DNS-01 ACME + Cloudflare Tunnel) | Phase 1 |
| SEC-VPS-003 | Commit to disabling IPv6 in Phase 1 — don't leave it ambiguous | Phase 1 |
| NET-CIRC-001 | Document WireGuard failover procedure, set long Headscale key expiry for infra nodes | Phase 1 |
| NET-DNS-001 | Implement Headscale DNS push for remote *.local.akunito.com resolution | Phase 1 |
| SEC-NC-003 | Narrow Nextcloud trusted_proxies to specific NPM container IP | Phase 3e |
| SEC-VPS-004 | Strongly consider `wheelNeedsPassword = true` on VPS, or at minimum enforce `no-new-privileges` on all containers | Phase 1 / Phase 3 |
| SEC-CF-001 | Configure Cloudflare WAF rules, Bot Fight Mode, rate limiting | Phase 2b |
| SEC-VPS-002 | Document secret rotation schedule, consider sops-nix adoption | Phase 6b |

### Medium (fix within first month)

| ID | Finding | Phase to Fix |
|----|---------|-------------|
| SEC-INITRD-001 | Add rate limiting to initrd SSH | Phase 1 |
| SEC-SSH-001 | Add MaxAuthTries, LoginGraceTime, ClientAliveInterval to sshd | Phase 1 |
| SEC-KERN-001 | Add kernel hardening sysctls (dmesg_restrict, kptr_restrict, etc.) | Phase 1 |
| NET-FW-001 | Enable firewall connection logging | Phase 1 |
| NET-FW-002 | Isolate Docker containers with separate compose networks | Phase 3 |
| NET-DNS-002 | Add default server block rejecting unknown Host headers on VPS NPM | Phase 2b |
| NET-DNS-003 | Fix Phase 4 pfSense DNS — *.local.akunito.com stays pointing to TrueNAS, not VPS | Phase 4 |
| NET-REACH-001 | Add Prometheus connectivity probes for Tailscale/WireGuard paths | Phase 2d |
| NET-SLEEP-001 | Ensure no backup job can run past midnight (stagger schedules) | Phase 6 |
| SEC-NC-004 | Test Nextcloud without root override, add no-new-privileges + read_only | Phase 3e |
| SEC-NC-005 | Deploy ClamAV for file scanning | Phase 6c |
| SEC-NC-007 | Harden Nextcloud config.php (logging, session timeout, preview providers) | Phase 3e |
| SEC-NC-008 | Add security headers in NPM for Nextcloud | Phase 3e |
| SEC-DOCKER-001 | Version-control docker-compose files in dotfiles repo | Phase 3 |
| NET-ACCESS-001 | Document Cloudflare bypass procedure for emergency LAN→VPS access | Phase 6b |

### Low (post-migration optimization)

| ID | Finding | Phase to Fix |
|----|---------|-------------|
| SEC-SSH-002 | Restrict SSH cipher suite to modern algorithms | Phase 1 |
| SEC-KERN-002 | Enable AppArmor | Phase 6b |
| SEC-NC-006 | Document encryption threat model (LUKS + restic = sufficient, SSE not needed) | Phase 6b |
| SEC-NC-009 | Consider Cloudflare Access for Nextcloud admin panel | Phase 6b |
| NET-PF-001 | Tighten pfSense WireGuard rules to /32 | Phase 1 |

---

## Appendix A: Complete VPS Firewall Configuration (Recommended)

```nix
# profiles/vps/base.nix — recommended firewall section:
networking.firewall = {
  enable = true;
  logRefusedConnections = true;
  logReversePathDrops = true;

  allowedTCPPorts = [
    56777   # SSH (main)
    2222    # SSH (initrd LUKS unlock)
  ];

  allowedUDPPorts = [
    41641   # Tailscale direct connections
    51820   # WireGuard backup tunnel
    3478    # STUN/DERP relay (Phase 6b)
  ];

  # Cloudflare Tunnel handles all HTTPS ingress — no 80/443 needed
  # Docker rootless with 127.0.0.1 bindings — no port exposure
};

# IPv6 disabled:
boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;
boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 1;
```

## Appendix B: Nextcloud Security Checklist

- [ ] TOTP 2FA enabled and enforced for all users
- [ ] Brute-force protection enabled in config.php
- [ ] fail2ban jail configured for Nextcloud login failures
- [ ] Cloudflare rate limiting on login endpoint
- [ ] trusted_proxies set to specific NPM container IP (not /16)
- [ ] Logging to file enabled (for fail2ban and audit)
- [ ] Security headers configured in NPM proxy host
- [ ] SVG/PDF preview providers disabled
- [ ] Session lifetime set to 1 hour
- [ ] ClamAV file scanning (post-migration)
- [ ] Regular Nextcloud security scan: `docker exec nextcloud php occ security:certificates`
- [ ] Nextcloud admin notifications checked weekly
- [ ] No `user: "0:0"` in production (test rootless UID mapping first)
