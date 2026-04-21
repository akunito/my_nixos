# Penetration Test: VPS + NAS Infrastructure

## Context

Adversarial validation of the homelab. Prior audits (`docs/akunito/infrastructure/audits/pfsense-audit-2026-02-04.md`, `docker-security-audit-2026-03-06.md`, `truenas-docker-security-audit-2026-03-06.md`, `nas-nixos-audit-2026-04-15.md`) covered configuration; this exercise tests runtime behavior under active attack.

**Goals**: empirically confirm (a) the small public attack surface holds, (b) Tailscale ACLs are actually enforced (docs say "planned, not confirmed"), (c) Cloudflare Access email OTP adds real protection, (d) fail2ban triggers as expected, (e) VLAN isolation is hard.

**Non-goals**: third-party infra (Cloudflare edge, Netcup hypervisor, Tailscale coordination), availability/DoS testing, anything destructive against production data.

**Authorization**: owner-authorized testing on owned infrastructure. Executor = owner, solo operator with full admin access.

**Vantage priority**: Start with **Phase 1 (5G, Tailscale OFF)** and run it end-to-end before progressing. Phases 2–6 are planned but gated on completing Phase 1 + a review checkpoint.

---

## Attack Surface Summary (reference)

**VPS (`159.195.32.28`, Tailscale `100.64.0.6`)**
- Direct public: `80/443` (nginx → Headscale), `2222/tcp` (initrd SSH, permanently public — cannot be removed), `3478/udp` (DERP), `41641/udp` (TS), `51820/udp` (WG)
- Cloudflare Tunnel (`*.akunito.com`): plane, info (portfolio), leftyworkout-test, grafana, matrix, element, freshrss (miniflux), nextcloud, syncthing, status (kuma), unifi, **vault (vaultwarden)**, headscale. Most gated by **Cloudflare Access email OTP** — robustness unknown, MUST test.
- Tailscale-only (`*.local.akunito.com` on VPS nginx bound to `100.64.0.6`): prometheus (htpasswd), openclaw (18789/18790), finance (basic auth)
- SSH `56777` is VPN-only, key-only. fail2ban: sshd, nginx-botsearch, nginx-http-auth (1d→7d exponential).

**NAS (`192.168.20.200`)** — all public exposure via `cloudflared` Docker (tunnel `truenas-local`). `*.local.akunito.com` FQDNs route here:
- `jellyfin`, `sonarr`, `radarr`, `prowlarr`, `bazarr`, `jellyseerr`, `qbt` (via gluetun), `uptime`, `truenas`
- **Weakest link**: Sonarr/Radarr/Prowlarr/Bazarr have only API-key auth. User states Cloudflare Access is enabled on these — VERIFY per-host.

**pfSense (`192.168.8.1`)** — primary TS subnet router `100.64.0.7` advertising `192.168.8.0/24` + `192.168.20.0/24`; WG peer `172.26.5.1`. VLANs: LAN `8.0/24`, Storage `20.0/24`, Guest `9.0/24` (blocked from LAN/Storage/WG).

---

## Phase 0 — Safety Net (MANDATORY, complete every step)

### 0.1 Backup verification (zero-data-loss precondition)

```bash
# VPS (SSH via Tailscale)
restic snapshots --json | jq '.[-1] | {id, time, hostname}'
restic check --read-data-subset=5%
restic restore latest --target /tmp/restore-test --dry-run

# NAS
restic snapshots --json | jq '.[-1] | {id, time, hostname}'
restic check --read-data-subset=5%
```

**Accept only if** last snapshot < 24h old. If older, trigger a manual run and wait.

### 0.2 Pin NixOS generations

```bash
# VPS
nixos-rebuild list-generations | grep current   # record number, e.g. 142
# NAS
nixos-rebuild list-generations | grep current
```

Rollback command (document, offline): `nixos-rebuild switch --rollback` or `nix-env --switch-generation <N> -p /nix/var/nix/profiles/system`.

### 0.3 pfSense config export

Diagnostics → Backup & Restore → download XML, store offline (not on any test target).

### 0.4 Git state snapshot

```bash
git -C /home/akunito/.dotfiles log -1 --format="%H %ai %s"
```

Record HEAD commit hash.

### 0.5 fail2ban strategy (intentionally *not* pre-whitelisting 5G IP)

We want to observe fail2ban triggering in Phase 1. But keep emergency unblock ready via Tailscale:

```bash
# From a Tailscale-connected device (unaffected by external bans)
sudo fail2ban-client unban <5G_IP>
sudo fail2ban-client set sshd addignoreip <5G_IP>
sudo fail2ban-client set nginx-http-auth addignoreip <5G_IP>
```

Record 5G public IP at test start: `curl ifconfig.me`.

### 0.6 Out-of-band recovery paths (document offline)

- **VPS**: Netcup SCP KVM console URL + credentials
- **NAS**: physical keyboard/monitor access
- **pfSense**: console cable + admin password

### 0.7 Abort criteria — stop and roll back immediately if

- Unexpected writes/deletes on any data volume during test window
- Scheduled Restic backup fails while testing
- Vaultwarden / Nextcloud / Matrix unreachable > 5 min without explicit test action causing it
- pfSense mgmt interface unresponsive
- Any sign of real third-party exploitation (unexpected process, new user, unknown outbound connection)

### 0.8 Monitoring baseline

Open in a second screen throughout: Grafana (nginx error rate, fail2ban ban count, system load), Uptime Kuma dashboard, pfSense dashboard (state table size, interface errors).

---

## Phase 1 — External red-team (5G laptop, Tailscale OFF)

**Re-read first**: `pfsense-audit-2026-02-04.md`, `docker-security-audit-2026-03-06.md`.

### 1.1 OSINT / subdomain enumeration

```bash
curl "https://crt.sh/?q=%.akunito.com&output=json" | jq -r '.[].name_value' | sort -u
nix-shell -p subfinder --run "subfinder -d akunito.com -silent"
nix-shell -p dnsx --run "dnsx -d akunito.com -w /tmp/seclists/Discovery/DNS/subdomains-top1million-5000.txt -a -cname -silent"
whois 159.195.32.28
```

Flag any subdomain not in the known list and any DNS record **not proxied by Cloudflare** (orange vs grey cloud — grey bypasses Access).

### 1.2 Public port scan

```bash
# PROCEED WITH CAUTION — will trigger fail2ban if we probe 56777 aggressively
nmap -sV -sC -p 80,443,2222,3478,51820,56777 --open 159.195.32.28 -oN /tmp/vps-ext.txt
nmap -sU -p 3478,41641,51820 159.195.32.28
```

Expected open: 80, 443, 2222, 51820/udp. Anything else is a finding.

### 1.3 Port 2222 initrd SSH (PRIORITY)

```bash
ssh -p 2222 root@159.195.32.28 -v 2>&1 | head -40       # banner + offered algorithms
ssh-keyscan -p 2222 -t rsa,ecdsa,ed25519 159.195.32.28
# Confirm password auth is rejected
ssh -p 2222 -o PreferredAuthentications=password root@159.195.32.28
```

Document: host key (distinct from main sshd?), server version + CVEs for that version, key exchange algorithms. This port cannot be hardened; output is a documented risk-acceptance record.

### 1.4 TLS / cert analysis

```bash
nix-shell -p testssl --run "testssl.sh --full https://akunito.com"
nix-shell -p testssl --run "testssl.sh --full https://vault.akunito.com"
nix-shell -p testssl --run "testssl.sh --full https://headscale.akunito.com"
```

Focus: ciphers, HSTS, chain, CT logs, OCSP.

### 1.5 Cloudflare Access (email OTP) — hardest to test

User's note: "*.akunito.com ask for a whitelisted email's code." We do NOT brute-force the OTP (pointless + burns the flow). We test for **misconfigurations that bypass it**.

**1.5.a — Direct-to-origin bypass** (the primary real-world bypass):
```bash
# If the VPS nginx serves these domains on its public IP without requiring a CF-Origin Pull cert, Access is bypassable
curl -H "Host: vault.akunito.com" https://159.195.32.28 -k -v
curl -H "Host: plane.akunito.com" https://159.195.32.28 -k -v
curl -H "Host: nextcloud.akunito.com" https://159.195.32.28 -k -v
# Cloudflared tunnels are outbound-only, so nginx may not even listen publicly for these Hosts.
# If curl returns the real app — CRITICAL finding: CF Access is bypassable.
```

Repeat against NAS public IP (if any pfSense port-forward exists) — per exploration there are none, but verify.

**1.5.b — Header injection / trust**:
```bash
curl https://vault.akunito.com -H "Cf-Access-Jwt-Assertion: faketoken" -v
curl https://vault.akunito.com -H "CF-Connecting-IP: 127.0.0.1" -v
curl https://plane.akunito.com -H "Cf-Access-Authenticated-User-Email: someone@example.com" -v
```

If upstream app trusts any `Cf-*` header without verifying CF's JWT signature, it's a HIGH finding.

**1.5.c — Per-FQDN coverage check** (use one legitimate OTP login, then enumerate):
1. Log into one protected service normally, capture `CF_Authorization` cookie.
2. Attempt that cookie on every other `*.akunito.com` and `*.local.akunito.com` — it should be rejected (different Access application audience).
3. For each subdomain from crt.sh, `curl -I` and check for `cf-access-*` headers or redirect to `<team>.cloudflareaccess.com`. Any subdomain without that is **unprotected** — list it.

**1.5.d — NAS-specific** (user flagged): Sonarr/Radarr/Prowlarr/Bazarr — confirm CF Access IS in front of each. Without valid cookie, `curl -I https://sonarr.local.akunito.com` must return `302` to cloudflareaccess. If it returns the app login, CF Access is not wired to that host → HIGH finding (API-key-only auth is thin).

### 1.6 Vaultwarden /admin (PRIORITY)

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://vault.akunito.com/admin
# If Access is NOT in front, send exactly 3 wrong tokens (no more):
for i in 1 2 3; do curl -X POST https://vault.akunito.com/admin -d "token=wrong$i" -w "\n%{http_code}\n"; done
```

Check for rate limiting / progressive backoff. Finding severity = CRITICAL if `/admin` reachable without Access AND no rate limit.

### 1.7 HTTP fuzzing (surface level only in Phase 1; deep app work is Phase 5)

```bash
# Use seclists wordlists via nix-shell, no system install
git clone --depth 1 https://github.com/danielmiessler/SecLists /tmp/seclists
nix-shell -p ffuf --run "ffuf -u https://vault.akunito.com/FUZZ -w /tmp/seclists/Discovery/Web-Content/common.txt -mc 200,301,302,403 -o /tmp/vault-fuzz.json"
nix-shell -p ffuf --run "ffuf -u https://nextcloud.akunito.com/FUZZ -w /tmp/seclists/Discovery/Web-Content/raft-medium-files.txt -mc 200,301,302"
```

Look specifically for `.env`, `.git/config`, `backup*`, `admin*`, `.DS_Store`.

### 1.8 Headscale on 443

```bash
curl https://159.195.32.28/ -k -v              # direct IP
curl https://headscale.<real-domain>/swagger/  # if swagger ships
curl https://headscale.<real-domain>/api/v1/node
# Inspect cert SANs for internal hostnames
openssl s_client -connect 159.195.32.28:443 -servername headscale.<domain> </dev/null | openssl x509 -noout -text | grep -A2 "Subject Alternative Name"
```

### 1.9 fail2ban empirical check (intentional)

```bash
# Triggered on purpose — 5 failed logins on the ONE internet-exposed SSH (port 2222)
for i in 1 2 3 4 5; do ssh -p 2222 -o PreferredAuthentications=password -o StrictHostKeyChecking=no fakeuser@159.195.32.28; done
# Confirm ban via Tailscale SSH:
sudo fail2ban-client status sshd
# Then unban:
sudo fail2ban-client unban <5G_IP>
```

Note: port 2222 may not feed sshd jail since it's dropbear/initrd. Document the actual behavior.

### 1.10 Phase 1 checkpoint

Review all findings, update finding file, **confirm with self/owner before proceeding to Phase 2**.

---

## Phase 2 — External with Tailscale ON (5G)

**Re-read first**: Tailscale ACL file in dotfiles, Headscale server ACL state (`headscale policy get` on VPS).

### 2.1 ACL enforcement test (the "planned vs deployed" question)

```bash
nmap -sV -p 1-1024 --open 100.64.0.6     # VPS TS IP
nmap -sV -p 1-1024 --open 100.64.0.7     # pfSense TS IP
nmap -sV -p 1-1024 --open 100.64.0.9     # NAS TS IP (within 11:00–23:00 window)

# Subnet routing reachability
ping 192.168.8.1           # pfSense LAN
ping 192.168.20.200        # NAS Storage VLAN
curl -I http://192.168.8.1 # pfSense web UI
nc -zv 192.168.20.200 2049 # NFS
nc -zv 192.168.20.200 445  # SMB
```

**If a random Tailscale client can reach pfSense web UI or NAS SMB/NFS without explicit ACL grant → HIGH finding (ACLs not deployed).**

### 2.2 *.local.akunito.com auth testing

```bash
# prometheus — htpasswd
curl -u admin:admin https://prometheus.local.akunito.com
curl -u admin:password https://prometheus.local.akunito.com
# finance — basic auth; verify HTTPS enforcement
curl -I http://finance.local.akunito.com -v    # must redirect or refuse
# openclaw
curl -v http://openclaw.local.akunito.com:18789
curl -v http://openclaw.local.akunito.com:18790
```

### 2.3 NAS *.local.akunito.com (same FQDN pattern, tunneled through NAS cloudflared)

```bash
# With Tailscale ON, do these resolve via TS DNS (to NAS LAN IP) or via public CF?
dig +short jellyfin.local.akunito.com
# If LAN IP returned, TS DNS is working; test direct
curl -I https://192.168.20.200 -H "Host: sonarr.local.akunito.com" -k
```

---

## Phase 3 — LAN-internal red-team (from DESK, `192.168.8.x`)

**Re-read first**: `pfsense-audit-2026-02-04.md`, exported pfSense config, `nas-nixos-audit-2026-04-15.md`.

```bash
nmap -sV -sC 192.168.8.0/24 --open -oN /tmp/lan.txt
nmap -sV -sC 192.168.20.0/24 --open -oN /tmp/storage.txt
nmap -sV -p- 192.168.20.200 --open -oN /tmp/nas-full.txt
# Cross-reference NAS open ports vs audit; any new port = finding.
```

### 3.1 pfSense REST API

```bash
curl http://192.168.8.1/api/v2/system/version     # auth required?
# Enumerate unauthenticated endpoints
ffuf -u http://192.168.8.1/api/v2/FUZZ -w /tmp/seclists/Discovery/Web-Content/api/api-endpoints.txt -mc 200
```

Test credential strength from `secrets/domains.nix` (`pfsenseApiKey`) — known secure since git-crypt, but confirm rotation cadence.

### 3.2 NFS exposure

```bash
showmount -e 192.168.20.200
# Does a LAN IP (not Tailscale, not Storage) get to mount?
sudo mount -t nfs -o ro 192.168.20.200:/mnt/ssdpool/romm-library /mnt/test
```

### 3.3 Database firewall (`databaseFirewallOpen=false`)

```bash
# From LAN, Postgres and MariaDB should be UNREACHABLE
nc -zv <vps-lan-or-ts-ip> 5432
nc -zv <vps-lan-or-ts-ip> 3306
nc -zv 192.168.20.200 6379
```

### 3.4 WireGuard reachability from LAN

```bash
ping 172.26.5.155      # VPS WG — should fail unless you're on WG
ping 172.26.5.1        # pfSense WG
```

---

## Phase 4 — Guest VLAN isolation (`192.168.9.0/24`)

**PROCEED WITH CAUTION — re-confirm before starting.**

Connect a test device to Guest. From it:

```bash
ping 192.168.8.1       # pfSense LAN — MUST fail
ping 192.168.20.200    # NAS — MUST fail
ping 172.26.5.155      # VPS WG — MUST fail
ping 100.64.0.6        # VPS TS — MUST fail (Guest has no TS)
traceroute 8.8.8.8     # internet must work
arp -a                 # no 192.168.8.x entries
```

Any reachability = CRITICAL finding. Stop and document.

---

## Phase 5 — Application-layer deep dive

**Re-read first**: all four audit files.

Per app, in order: auth bypass → privilege escalation → data exfil → SSRF → known CVEs for the installed version (identify version first via each app's `/status`, `/about`, or `/api/v1/server/info` endpoint).

### 5.1 Vaultwarden (follow-up to Phase 1.6)

```bash
# Registration closed?
curl -X POST https://vault.akunito.com/api/accounts/register \
  -H "Content-Type: application/json" \
  -d '{"email":"x@x.x","masterPasswordHash":"a","key":"a","name":"x"}'
# If 200/201 → SIGNUPS_ALLOWED=true finding
```

### 5.2 Matrix / Element

```bash
curl https://matrix.akunito.com/_matrix/federation/v1/version  # version disclosure
curl -X POST https://matrix.akunito.com/_matrix/client/v3/register -d '{"kind":"guest"}'
```

### 5.3 Nextcloud

```bash
curl https://nextcloud.akunito.com/status.php
curl -X PROPFIND https://nextcloud.akunito.com/remote.php/dav/ -H "Depth: 1"
```

### 5.4 Plane

```bash
curl https://plane.akunito.com/api/v1/ -v
ffuf -u https://plane.akunito.com/api/v1/FUZZ -w common-api-endpoints.txt -mc 200,403
```

### 5.5 Miniflux / FreshRSS — SSRF on feed fetching (high value)

```bash
# Register (if allowed) or use existing account
# Add feed pointing to internal-only URL to test SSRF containment
# e.g. http://100.64.0.6/ or http://192.168.8.1/
```

### 5.6 OpenClaw (18789/18790) + Telegram bot prompt injection

```bash
curl -v http://openclaw.local.akunito.com:18789
# Identify API shape; look for unauthenticated endpoints
# Test prompt injection by sending crafted Telegram message to @alfred_openclaw_aku_bot
# (see memory/openclaw-deployment.md for command structure)
```

### 5.7 NAS app layer (NEW scope per user)

For each of `jellyfin`, `sonarr`, `radarr`, `prowlarr`, `bazarr`, `jellyseerr`, `qbt`, `uptime`, `truenas`:

1. Confirm CF Access is in front (Phase 1.5.c technique).
2. If CF Access NOT in front, check API-key auth path:
   ```bash
   curl -I https://sonarr.local.akunito.com
   curl https://sonarr.local.akunito.com/api/v3/system/status   # needs X-Api-Key
   curl https://sonarr.local.akunito.com/api/v3/system/status -H "X-Api-Key: "   # empty
   ```
3. Prowlarr / qBittorrent are the highest-value targets — compromise = indexer keys + torrent client RCE paths. Version check against latest CVEs.

### 5.8 Finance-tagger

```bash
curl -I http://finance.local.akunito.com       # HTTPS enforced?
curl -u wrong:wrong https://finance.local.akunito.com
```

Basic auth over HTTP = credential exposure.

---

## Phase 6 — Lateral movement / post-compromise (only if a foothold is produced)

If Phase 1–5 yields a real shell, valid credential, or session token, scope expands to:

### 6.1 From VPS (hypothetical)

```bash
ip route show; ss -tlnp
find /etc -name "*.env" -o -name "*.secret" 2>/dev/null
find /home/akunito -name "*.env" -not -path "*/node_modules/*" 2>/dev/null
# Can VPS reach NAS directly? Expected: only via WG tunnel (172.26.5.x)
```

### 6.2 From NAS (hypothetical)

```bash
exportfs -v          # re-export risk
smbclient -L //localhost -N
# Docker socket exposure?
ls -la /var/run/docker.sock
```

### 6.3 Credential reuse — test any captured credential against

- SSH `56777` (should reject password entirely — confirm)
- pfSense API
- prometheus htpasswd
- finance basic auth
- Vaultwarden `/admin`

---

## Tooling

**Already installed**: `nmap`, `gitleaks`, `curl`, `ssh`, `nc`, `dig`, `jq`.

**Temporary via `nix-shell -p`** (no system-wide install):
- `testssl` — TLS analysis (Phase 1.4)
- `ffuf` — HTTP fuzzing (Phases 1.7, 3.1, 5.4)
- `subfinder`, `dnsx` — subdomain/DNS enum (Phase 1.1)
- `nfs-utils` — `showmount` (Phases 3.2, 6.2)
- `nikto` — optional web vuln scanner for Phase 5 spot checks

**Wordlists**: clone SecLists to `/tmp/seclists` (not persisted):
```bash
git clone --depth 1 https://github.com/danielmiessler/SecLists /tmp/seclists
```

**Explicitly NOT using**: metasploit, sqlmap (scope is enumeration + targeted probes; full exploitation frameworks are overkill and noisy), hydra (real brute-force is out of scope — we verify lockout behavior with ≤5 attempts).

---

## Reporting & remediation workflow

**Finding file**: `docs/akunito/infrastructure/audits/pentest-2026-04-21.md`. Per-finding structure:

```
## FIND-NNN: <title>
Severity: CRITICAL | HIGH | MEDIUM | LOW | INFO   (CVSS 3.1 for external, manual CIA for internal)
Phase: <n>
Component: <service>
Description: <what>
Evidence: <exact command + response, redact tokens>
Impact: <attacker gains X>
Remediation: <concrete fix, reference NixOS module or feature flag>
Status: OPEN | MITIGATED | ACCEPTED
```

**Plane tickets**: CRITICAL/HIGH findings → AINF project immediately (ID in finding). MEDIUM/LOW → batch.

**Memory updates**: after each phase, note in `~/.claude/projects/-home-akunito--dotfiles/memory/` — new confirmed open ports, ACL gaps, weak auth paths. Do NOT store secret values, only their existence and location.

**Commit message**: `AINF-<id>: pentest 2026-04-21 findings (<phase>)`.

---

## Verification / kill switches

**Before each phase**:
```bash
fail2ban-client status
restic snapshots --json | jq '.[-1].time'
nixos-rebuild list-generations | tail -3
```

**After each phase**:
```bash
ps auxf --sort=start_time | tail -30           # unexpected new processes
journalctl -u sshd --since "1 hour ago" | grep Accepted
journalctl -p err --since "1 hour ago"
```

**Hard kill switch**: on any abort criterion from 0.7 — `nixos-rebuild switch --rollback` on the affected host, `restic restore` for data, pfSense config re-import from 0.3.

---

## Critical files / paths

Configs to re-read per phase:
- `profiles/VPS_PROD-config.nix`, `profiles/VPS-base-config.nix`
- `profiles/NAS_PROD-config.nix`
- `system/security/sshd.nix`, `system/security/fail2ban.nix`, `system/security/wireguard-server.nix`
- `system/app/nginx-local.nix`, `system/app/headscale.nix`, `system/app/vaultwarden.nix`, `system/app/tailscale.nix`
- `templates/openclaw/docker-compose.yml`
- `docs/akunito/infrastructure/INFRASTRUCTURE.md`
- `docs/akunito/infrastructure/services/pfsense.md`, `services/tailscale-headscale.md`, `services/homelab-stack.md`, `services/proxy-stack.md`
- All four prior audits in `docs/akunito/infrastructure/audits/`
- `secrets/domains.nix` (git-crypt) for credential context only

Plan file: `/home/akunito/.claude/plans/i-want-to-prepare-smooth-marble.md`
