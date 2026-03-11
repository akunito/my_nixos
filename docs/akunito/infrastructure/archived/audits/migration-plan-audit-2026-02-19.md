---
id: audits.migration-plan.2026-02-19
summary: Comprehensive audit of Proxmox-to-VPS+TrueNAS migration plan
tags: [audit, migration, vps, truenas, security, backups, performance, networking]
related_files: [profiles/VPS*-config.nix, profiles/LXC*-config.nix, system/**/*.nix]
date: 2026-02-19
status: published
---

# Migration Plan Audit v4 — 2026-02-19

**Plan audited:** `~/.claude/plans/dapper-splashing-pebble.md`
**Auditor:** Claude Code (Opus 4.6) — deep codebase cross-reference
**Scope:** Security, backups, performance, networking, DNS/certs, auth/keys, ordering, missing steps
**Revision:** v4 — full re-audit with codebase verification of every module referenced in plan

---

## Audit Verdict: GOOD plan with actionable gaps

The plan is thorough, well-structured, and covers most critical paths. The phase ordering is sound, rollback procedures exist for each phase, and the DR runbook is thoughtful. However, this audit identifies **7 critical**, **12 high**, and **15 medium** findings that should be addressed before or during execution.

---

## 1. CRITICAL Findings (must fix before execution)

### CRIT-001: Backup alert labels are broken — alerts will NEVER fire

**Where:** `system/app/grafana.nix` alert rules vs `system/security/restic.nix` metrics script

The Grafana alert rules reference `backup_age_seconds{repo="home"}`, but the restic metrics script writes labels `repo="home_nfs"` and `repo="home_legacy"`. The `BackupTooOld`, `BackupCriticallyOld`, and `BackupRepositoryUnhealthy` alerts **will never fire** because no metric with label `repo="home"` exists.

**Impact:** You could lose all backups and never be alerted. This is a pre-existing bug that becomes critical when VPS backups are the only copy of production data.

**Fix:** Update either the alert expressions or the metric labels to match. Also define new alert labels for VPS restic repos (`vps-databases`, `vps-services`, `vps-nextcloud`) and add corresponding alert rules.

---

### CRIT-002: Database ports open to internet if firewall module is reused as-is

**Where:** `system/app/postgresql.nix` (`enableTCPIP = true`, `openFirewall`), `system/app/mariadb.nix`, `system/app/redis-server.nix`, `system/security/firewall.nix`

All three database modules listen on `0.0.0.0` and add ports to `allowedTCPPorts`. The firewall module does **zero source-IP filtering** — it's a flat port list. On a VPS with a public IP, PostgreSQL (5432), MariaDB (3306), Redis (6379), and PgBouncer (6432) would be exposed to the entire internet.

PostgreSQL even has `pg_hba.conf` allowing `scram-sha-256` auth from `192.168.8.0/24` and `172.26.5.0/24`, but a VPS attacker could still brute-force passwords on the open port.

The plan mentions "bind to 127.0.0.1 only" in Phase 6b as post-migration hardening, but this is **too late**. The databases will be internet-exposed from Phase 2 until Phase 6b.

**Fix:** Bind databases to `127.0.0.1` from day one in the VPS profile. Remove database ports from `allowedTCPPorts` in VPS_PROD. Create a `systemSettings.databaseBindAddress` flag (default `0.0.0.0` for backward compat with LXC, override to `127.0.0.1` for VPS). Do this in Phase 1, not 6b.

---

### CRIT-003: Docker port mappings bypass nftables/iptables entirely

**Where:** Plan Section 2b (NPM deployment), Docker networking

The plan correctly notes that NPM admin port 81 should bind to `127.0.0.1:81` (SEC-013). But it doesn't generalize this: **all Docker port mappings bypass the NixOS firewall**. Docker adds its own iptables/nftables DNAT rules that take precedence over `networking.firewall.allowedTCPPorts`.

Even if you don't add port 8008 (Synapse), 3000 (Plane), etc. to `allowedTCPPorts`, Docker `-p 8008:8008` will still expose them publicly.

**Partial mitigation:** For rootless Docker, this is somewhat mitigated — rootless Docker uses `slirp4netns` or `pasta` which doesn't manipulate system iptables the same way. However, with `net.ipv4.ip_unprivileged_port_start = 80`, containers can bind to any port >= 80 on the host.

**Fix:** Ensure ALL docker-compose port mappings use `127.0.0.1:PORT:PORT` syntax. Add this as a mandatory checklist item for every container deployment in Phase 3. Create a validation script that checks all docker-compose files for non-localhost port bindings.

---

### CRIT-004: No Nextcloud data integrity verification after double migration

**Where:** Plan Phase 0.5 (LXC_HOME -> TrueNAS) and Phase 3e (TrueNAS -> VPS)

Nextcloud moves twice. The plan has no data integrity verification step between moves. If a file is silently corrupted during the first `cp -a` from the iSCSI zvol, it propagates to the VPS.

**Fix:** After Phase 0.5 Step 3 (data copy to TrueNAS), run:
```bash
docker exec nextcloud php occ files:scan --all
docker exec nextcloud php occ integrity:check-core
find /mnt/ssdpool/docker/nextcloud-data -type f | wc -l  # Compare with source
```
After Phase 3e (data arrives on VPS), repeat. Also verify file counts match between source and target.

---

### CRIT-005: Redis eviction policy will silently drop Matrix session data

**Where:** `system/app/redis-server.nix` — `maxmemory-policy = allkeys-lru`

The current Redis module uses `allkeys-lru`, which evicts **any** key when memory is full. Matrix Synapse uses Redis for presence data and worker communication. If memory pressure hits 2GB, Matrix sessions will be silently evicted, causing dropped connections and state loss.

The plan assigns Redis 2GB on the VPS (same as LXC_database), but now 5 services share one Redis instance (Plane db0, Nextcloud db1, LiftCraft db2, Portfolio db3, Matrix db4). This was fine with fewer services; adding Matrix and Nextcloud increases pressure.

**Fix:** Either:
- Use `volatile-lru` (only evicts keys with TTL set — cache keys expire, session keys don't)
- Or use separate Redis instances (one for caching with `allkeys-lru`, one for sessions with `noeviction`)
- At minimum, add a Prometheus alert for `redis_evicted_keys_total > 0`

---

### CRIT-006: Missing `secrets/domains.nix` entries for VPS

**Where:** `secrets/domains.nix.template`, plan Phase 1

The plan mentions adding `vpsExternalIp` to `secrets/domains.nix`, but several other new secrets are needed:

| Secret needed | Purpose | Where used |
|---|---|---|
| `vpsExternalIp` | VPS public IP | Mentioned in plan |
| `pfsenseWireguardPubkey` | pfSense WG public key | Plan Phase 1 Step 4 |
| `vpsSshPort` | Non-standard SSH port | VPS fail2ban, deploy.sh |
| `cloudflareApiKey` | ACME DNS-01 challenges | Both NPM instances |
| `dbMatrixPassword` | Matrix DB password (missing from template!) | postgresql.nix |

**Also note:** `secrets/domains.nix.template` does NOT have a `dbMatrixPassword` entry, but `profiles/LXC_database-config.nix` references it. This is a pre-existing gap.

**Fix:** Enumerate all new secrets in Phase 0 preparation, add to `domains.nix.template`, and commit the template update before migration begins.

---

### CRIT-007: Passwordless sudo on VPS is a critical security risk

**Where:** `profiles/LXC-base-config.nix` — `wheelNeedsPassword = false` + `ALL NOPASSWD SETENV`

The LXC base grants fully passwordless sudo to the wheel group. If the VPS base replicates this pattern, any SSH key compromise gives immediate root access without a password. On a LAN-only LXC behind pfSense, this is acceptable. On a public-facing VPS, it's a critical escalation path.

**Fix:** The VPS base profile MUST set `wheelNeedsPassword = true` and restrict `NOPASSWD` to only specific commands (e.g., `nixos-rebuild`, `systemctl`). Never use `ALL NOPASSWD` on the VPS.

---

## 2. HIGH Findings (should fix before or during execution)

### HIGH-001: fail2ban SSH port hardcoded to 22

**Where:** `system/security/fail2ban.nix` — `port = "ssh,22"`

The plan uses SSH port 56777 on VPS but fail2ban is hardcoded to protect port 22. Fail2ban will monitor auth logs for failed SSH attempts but won't block the correct port.

Also: The Gitea jail references `/var/log/gitea/gitea.log` which won't exist on VPS, potentially causing fail2ban startup errors.

**Fix:** Parameterize: `port = "ssh,${toString systemSettings.sshPort}"`. Add `sshPort` to `lib/defaults.nix` (default 22, VPS overrides to 56777). Conditionally enable jails based on which services are present. Plan mentions this fix but doesn't track it as a pre-migration task — add to Phase 0.

---

### HIGH-002: DNS nameservers default to 192.168.8.1 (LAN gateway)

**Where:** `lib/defaults.nix` — `nameServers = ["192.168.8.1" "192.168.8.1"]`

If the VPS profile doesn't explicitly override `nameServers`, the system will try to resolve DNS via a non-existent LAN gateway. DNS resolution will fail for everything including `nixos-rebuild` (can't fetch flake inputs).

**Fix:** Override in VPS base profile:
```nix
nameServers = ["1.1.1.1" "9.9.9.9"];  # Cloudflare + Quad9
```

---

### HIGH-003: ACME cert `chmod 644` on private key + Proxmox-specific copy hook

**Where:** `system/security/acme.nix` line 57

The post-renew hook does `chmod 644` on the private key (world-readable) and copies certs to `/mnt/shared-certs/` (a Proxmox bind mount path). On VPS:
1. The private key would be world-readable — any process can read it
2. The copy to `/mnt/shared-certs/` will fail since this path doesn't exist

**Fix:** Change to `chmod 640` with `chgrp docker`. Either conditionally skip the shared-cert copy on VPS (feature flag) or create a VPS-specific ACME hook that doesn't copy. Fix before Phase 2b.

---

### HIGH-004: No monitoring during Phase 0.5 TrueNAS transition

**Where:** Plan Phase 0.5 — Step ordering

When LXC_HOME shuts down and services move to TrueNAS, Prometheus on LXC_monitoring still points to LXC_HOME IPs. Monitoring goes dark for all migrated services. In the plan text, Step 7 (update Prometheus targets) and Step 7b (deploy node_exporter on TrueNAS) appear before Step 8 (verify + shutdown), which is correct. But the Prometheus target update must be verified (`up == 1`) before LXC_HOME shutdown.

**Fix:** Add explicit verification gate between Step 7b and Step 8:
```
- [ ] Verify: Prometheus shows TrueNAS node_exporter target as `up == 1`
- [ ] Verify: Prometheus shows TrueNAS cAdvisor target as `up == 1`
- [ ] Wait 30 minutes for data collection, verify dashboards show TrueNAS metrics
```

---

### HIGH-005: Syncthing topology change not addressed

**Where:** Plan Phase 0.5 Step 8 — brief mention but no concrete action

If LXC_HOME was an always-on Syncthing relay, shutting it down means DESK and phone/laptop can only sync when DESK is powered on. During TrueNAS sleep (00:00-08:00), DESK is also likely off. Sync gaps will occur.

**Fix:** Document whether Syncthing is used as relay or direct-only. If relay: deploy Syncthing on TrueNAS Docker (it runs during waking hours). If DESK-only: document the limitation.

---

### HIGH-006: TrueNAS SCALE Docker Compose compatibility not verified

**Where:** Plan Phase 0.5 Step 4

TrueNAS SCALE 25.04 (Fangtooth) supports Docker Compose natively, but there are TrueNAS-specific quirks:
- Default Docker storage backend may conflict with ZFS
- Docker daemon settings are managed by TrueNAS UI — manual `daemon.json` changes may be overwritten on update
- Host networking with `--net=host` may conflict with TrueNAS's own web UI ports (80/443)

**Fix:** Add a Phase 0.5 sub-step: "Test Docker Compose on TrueNAS with a simple container (e.g., nginx on a non-conflicting port) before migrating production services. Verify Docker data directory is on ssdpool, not boot pool."

---

### HIGH-007: PgBouncer module doesn't exist — needs full creation

**Where:** Plan mentions `system/app/pgbouncer.nix` as new file

No implementation details provided. PgBouncer configuration is non-trivial:
- `userlist.txt` must match PostgreSQL users/passwords (the existing `postgresql.nix` manages passwords via `postStart` ALTER USER scripts — PgBouncer needs to sync)
- `auth_type` must be `scram-sha-256` to match PostgreSQL
- Per-database pool sizes need tuning
- Applications must be reconfigured to connect to port 6432 instead of 5432

**Fix:** Add PgBouncer implementation details to the plan. Consider starting without PgBouncer (200 max_connections is adequate for this workload) and adding it later as optimization.

---

### HIGH-008: No rate limiting or WAF on NPM/Cloudflare

**Where:** Plan Phase 2b, Phase 6b

The plan deploys NPM on a public VPS but doesn't mention rate limiting. A determined attacker can send high request volumes through Cloudflare (free plan has limited DDoS protection).

**Fix:** Add to Phase 6b:
- Enable Cloudflare WAF rules (free tier: 5 custom rules)
- Configure NPM rate limiting per proxy host
- Consider `services.crowdsec` on NixOS as an additional IDS layer

---

### HIGH-009: No IPv6 consideration for VPS

**Where:** Entire plan

Netcup VPS typically comes with an IPv6 /64 subnet. The plan only addresses IPv4. If IPv6 is enabled by default:
- Firewall rules must cover IPv6 (NixOS `networking.firewall` handles both, but verify)
- fail2ban must monitor IPv6 SSH attempts
- Docker containers may get IPv6 addresses and be directly internet-accessible
- Services binding to `0.0.0.0` won't catch IPv6 connections

**Fix:** Add to Phase 1: either disable IPv6 explicitly or properly configure IPv6 firewall rules:
```nix
boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;  # If not using IPv6
```

---

### HIGH-010: Grafana SMTP hardcoded to LXC_mailer IP

**Where:** `system/app/grafana.nix` — `host = "192.168.8.89:25"`

Grafana's SMTP settings hardcode the LXC_mailer IP. On VPS, Postfix runs locally (localhost:25), but Grafana won't use it unless the code is updated.

**Fix:** Parameterize Grafana SMTP host via `systemSettings.smtpRelayHost` (default `"192.168.8.89:25"`, VPS overrides to `"127.0.0.1:25"`). Do this before Phase 2d.

---

### HIGH-011: No disk encryption verification procedure

**Where:** Plan Phase 1 — LUKS setup

The plan describes LUKS setup but has no step to verify encryption is actually working after the first reboot. A misconfigured initrd could skip LUKS.

**Fix:** Add to Phase 1 post-install verification:
```bash
cryptsetup status cryptroot        # Verify LUKS is active
lsblk -f                           # Verify / is on dm-0 (LUKS device)
cat /proc/cmdline                  # Verify root= points to /dev/mapper/cryptroot
```

---

### HIGH-012: Matrix signing key backup timing is risky

**Where:** Plan Phase 3d — signing key backup happens during migration

The plan backs up Matrix's signing key as part of Phase 3d. If something goes wrong between stopping the old Matrix container and deploying the new one, the key could be lost. This key is **irrecoverable** — losing it breaks federation permanently for the homeserver.

**Fix:** Back up the Matrix signing key in Phase 0 (preparation), not Phase 3d. Store it in Bitwarden immediately. Add it to the DR-002 Bitwarden items list.

---

## 3. MEDIUM Findings (address during or after migration)

### MED-001: No log aggregation strategy for VPS

The plan mentions journald limits and Docker log limits but no centralized log aggregation. On a multi-service VPS, debugging issues requires searching through many Docker container logs and journald units. Consider deploying Loki + Promtail (integrates with existing Grafana) post-migration.

---

### MED-002: No automated TLS certificate expiry monitoring

Both VPS and TrueNAS NPM use ACME certs. If renewal fails silently, services show cert errors after 90 days. The existing blackbox exporter has `probe_ssl_earliest_cert_expiry`. Ensure all domains are in blackbox HTTP targets and add alert: `probe_ssl_earliest_cert_expiry - time() < 7 * 86400`.

---

### MED-003: Docker image version pinning not specified

The plan mentions pinning Docker image major versions (Phase 6b) but doesn't specify which versions to pin for migration. Using `latest` during migration could pull different versions than what's running.

**Fix:** Before Phase 3, document exact image versions on each LXC:
```bash
docker inspect --format='{{.Config.Image}}' $(docker ps -q) | sort -u
```

---

### MED-004: Nextcloud background jobs (cron.php) not mentioned

Nextcloud relies on `cron.php` running every 5 minutes. The migration plan doesn't mention setting up the cron job on the VPS.

**Fix:** Add to Phase 3e docker-compose or host cron:
```bash
*/5 * * * * docker exec -u www-data nextcloud php cron.php
```
Verify in Nextcloud admin: Settings > Basic settings > Background jobs = "Cron".

---

### MED-005: TrueNAS suspension may corrupt in-flight Docker writes

The plan uses `rtcwake -m mem` for TrueNAS suspension. If a container is mid-write (Jellyfin transcoding, qBittorrent downloading), corruption is possible.

**Fix:** Add a pre-suspend script that gracefully stops containers before `rtcwake`:
```bash
#!/bin/bash
docker compose -f /path/to/media/docker-compose.yml stop
sleep 10
rtcwake -m mem -s 28800
# Containers restart on wake (restart: unless-stopped)
```

---

### MED-006: `dbCredentialsHost` in defaults.nix points to LXC_database

`lib/defaults.nix` has `dbCredentialsHost = "192.168.8.103"`. After migration, user modules generating `.pgpass` files will point to the old LXC_database IP.

**Fix:** Override `dbCredentialsHost` in profiles that need VPS database access (DESK, laptops) to use the VPS Tailscale IP or `localhost`.

---

### MED-007: No Cloudflare Tunnel health monitoring

Cloudflare Tunnel is the single ingress path for all public services. No Prometheus alert for tunnel health. If cloudflared crashes, all public services go offline.

**Fix:** Add Uptime Kuma checks (TrueNAS) for all public URLs. Add systemd service monitoring: `systemd_unit_state{name="cloudflared.service"} != 1`.

---

### MED-008: Phase 5 NFS `soft` mount option may cause data loss on writes

`soft` mounts return EIO errors to applications after timeout. If a write is in progress during TrueNAS sleep, data is silently lost (not just delayed).

**Fix:** Use `soft` only for read-mostly mounts (media). For mounts with writes, use `hard,timeo=60,retrans=5` or `x-systemd.automount,x-systemd.idle-timeout=30min` (better NixOS integration).

---

### MED-009: UniFi macvlan host communication limitation

Docker macvlan networks prevent the TrueNAS host from communicating with the macvlan container (UniFi at 192.168.8.206). This is a known Docker limitation.

**Fix:** Create a macvlan shim interface or accept that UniFi management is only possible from other LAN devices (DESK, laptops), not from TrueNAS itself.

---

### MED-010: NPM configuration data not in backup scope

NPM stores its configuration (proxy hosts, SSL certs, access lists) in a SQLite database in its data volume. Neither the VPS nor TrueNAS backup plan mentions backing up NPM data.

**Fix:** Add NPM data directory to restic backup:
- VPS: add NPM Docker volume to `vps-services` restic repo
- TrueNAS: add `/mnt/ssdpool/docker/npm/data/` to restic backup (or TrueNAS -> VPS rsync)

---

### MED-011: `postgresql_17` binary hardcoded in database-backup.nix

`system/app/database-backup.nix` lines 104/111/160 hardcode `pkgs.postgresql_17` for `pg_dump`. If the VPS profile uses a different PostgreSQL version, backup dumps could fail or be incompatible.

**Fix:** Use `config.services.postgresql.package` or parameterize via `systemSettings.postgresqlServerPackage`.

---

### MED-012: LXC_matrix SSH host for 'desk' points to wrong IP

`profiles/LXC_matrix-config.nix` has SSH host `desk` at `192.168.8.50`, but DESK is actually at `192.168.8.96`. Pre-existing bug, not migration-related, but the Claude bot can't SSH to DESK.

---

### MED-013: No pre-migration performance baseline

No step to capture current service performance metrics before migration. Without a baseline, you can't tell if post-migration performance regressed.

**Fix:** Add to Phase 0: capture PostgreSQL query times, Redis hit rates, Nextcloud response times, Matrix federation lag.

---

### MED-014: No Headscale DERP relay STUN port in firewall

Plan Phase 6b adds self-hosted DERP relay with STUN on port 3478/udp but doesn't add it to the Phase 1 firewall rules. STUN won't work until firewall is updated.

**Fix:** Add `3478` to `allowedUDPPorts` when DERP is enabled.

---

### MED-015: Headscale domain certs not addressed

If Headscale runs natively on NixOS (not behind NPM), it needs its own TLS cert. The plan mentions NPM proxying Headscale, but if Headscale serves HTTPS directly, it needs ACME:
```nix
security.acme.certs."headscale.akunito.com" = {
  dnsProvider = "cloudflare";
  credentialsFile = "/etc/secrets/cloudflare-acme";
};
```

---

## 4. Ordering & Sequencing Issues

### SEQ-001: Phase 0.5 has duplicate "Step 3" numbering

The plan has two entries labeled "Step 3" (data copy and path adaptation). Renumber for clarity.

### SEQ-002: Matrix signing key backup too late (Phase 3d -> Phase 0)

As noted in HIGH-012, move to Phase 0 preparation.

### SEQ-003: Database binding to localhost should be Phase 1, not Phase 6b

As noted in CRIT-002, this is security-critical at initial deployment.

### SEQ-004: Backup pipeline should be Phase 3.5, not Phase 6

The plan has Phase 3f (initial backup pipeline) which is correct, but Phase 6 (backup automation) should include the initial backup as a gate for Phase 4 cutover. The Phase 3f section was added to address this, but verify the gate is enforced: "At least one successful restic backup + verified restore before proceeding to Phase 4."

---

## 5. Authentication & Keys Audit

### AUTH-001: SSH key management gaps

**Current state:** Two ed25519 keys hardcoded in `LXC-base-config.nix`. Recent commit `c7f0d75` rotated keys and added Nix-managed SSH hosts.

**Gaps in plan:**
- No mention of adding VPS SSH host key to `known_hosts` on DESK/laptops
- No mention of adding VPS to Nix-managed SSH hosts module
- initrd SSH host key must be different from main SSH host key (plan handles this)
- DR-002 correctly lists initrd SSH host key in Bitwarden items — good

### AUTH-002: Headscale auth key lifecycle incomplete

The plan generates a reusable auth key with 87600h expiry for TrueNAS Tailscale. But doesn't document:
- Auth key generation for VPS's own Tailscale registration
- Auth key for pfSense Tailscale (Phase 5)
- Key cleanup after registration (plan mentions this for TrueNAS but not others)

**Fix:** Document auth key lifecycle for each node: generate, use, delete from environment.

### AUTH-003: Cloudflare API key scope too broad

Same Cloudflare API key used for VPS NPM, TrueNAS NPM, and potentially Cloudflare Tunnel. If TrueNAS is compromised, attacker can modify DNS for all domains.

**Fix:** Use scoped API tokens: one for `*.akunito.com` DNS editing (VPS), one for `*.local.akunito.com` (TrueNAS). Cloudflare supports per-zone token scoping.

### AUTH-004: Database password authentication vs UNIX socket peer auth

On VPS, all databases are local. Consider using UNIX socket peer authentication instead of password auth for local connections. This eliminates password files for local services entirely. Keep password auth only for PgBouncer connections.

---

## 6. Security Audit — Attack Surface Analysis

### Current (LXC) vs New (VPS) Security Model

**Current:** Each service is isolated in its own LXC container. Compromise of one service doesn't directly affect others. pfSense provides perimeter security. All services are behind NAT.

**New (VPS):** All services on one host. Compromise of any service potentially compromises all services. Only NixOS firewall + Cloudflare protect the VPS. The VPS has a public IP.

**Risk increase:** Significant. The plan mitigates with:
- Rootless Docker (good)
- systemd isolation with `MemoryMax` (good)
- fail2ban (good, if port is fixed)
- LUKS encryption at rest (good)

**Missing mitigations:**
- No AppArmor or seccomp profiles for containers
- No `read_only: true` for container root filesystems
- No file integrity monitoring (AIDE, Tripwire)
- No container runtime security (Falco)
- No `auditd` rules for privilege escalation detection
- No CrowdSec or IP reputation blocking
- Nextcloud `user: "0:0"` override negates rootless isolation for that container

**Recommendation:** Add to Phase 6b:
```yaml
# For every container where feasible:
security_opt:
  - no-new-privileges:true
read_only: true
tmpfs:
  - /tmp
  - /var/tmp
```

### SEC-ADDITIONAL: Docker `.env` secrets exposure

Docker `.env` files contain database passwords, API keys, etc. Docker Compose reads them and exposes values as environment variables visible via `docker inspect` and `/proc/self/environ` inside containers.

**Recommendation:** Use Docker bind-mount secrets pattern and `_FILE` env vars where images support it (PostgreSQL, MariaDB, Redis all do).

---

## 7. Backup Audit — Coverage Matrix

| Data | Covered? | RPO | Gap? |
|---|---|---|---|
| PostgreSQL databases | Yes (hourly dumps + 2h restic) | ~3h | No |
| MariaDB (Nextcloud) | Yes (hourly dumps + 2h restic) | ~3h | No |
| Redis | Yes (BGSAVE + dump.rdb) | ~3h | No |
| Nextcloud user files (~200GB) | Yes (daily restic) | ~24h | No |
| Docker compose + env files | Yes (daily restic) | ~24h | No |
| Headscale state | Yes (vps-services restic) | ~24h | No |
| Matrix signing key | Yes (Bitwarden + restic) | Static | No |
| WireGuard private key | Yes (Bitwarden) | Static | No |
| LUKS passphrase | Yes (Bitwarden + paper) | Static | No |
| git-crypt key | Yes (Bitwarden) | Static | No |
| Cloudflare Tunnel token | Yes (Bitwarden) | Static | No |
| Prometheus TSDB (30d) | **NO** | N/A | Acceptable — rebuilds in 30d |
| Grafana dashboards | Partial — provisioned from Nix | N/A | OK if no manual changes |
| **NPM configuration** | **NO** | N/A | **GAP** — proxy hosts, SSL certs in SQLite |
| TrueNAS *arr databases | Yes (Phase 6b rsync to VPS) | ~24h | No |
| pfSense config.xml | Yes (daily + Bitwarden) | ~24h | No |
| NixOS config | Implicit (dotfiles repo) | Real-time | No |
| **Restic repo passwords** | In Bitwarden | Static | Note: can't rotate without re-encrypting |

### No backup testing automation

Plan mentions "monthly: test database restore" but doesn't automate it. Manual procedures get forgotten.

**Recommendation:** Create a monthly systemd timer that:
1. Restores latest PostgreSQL backup to temporary database
2. Runs basic integrity checks (row counts)
3. Drops temporary database
4. Writes Prometheus metrics for restore success/failure

---

## 8. Performance Audit

### RAM: Realistic but monitor under peak load

~18.3GB estimated of 32GB. Comfortable at steady state. Monitor for:
- PostgreSQL `effective_cache_size = 8GB` expects OS page cache that may be reduced by competing services
- Nextcloud PHP-FPM spikes during file operations
- Matrix Synapse memory grows with active federation
- Prometheus TSDB compaction can temporarily spike 2-3GB

**Recommendation:** Set up cgroups memory limits (already planned) and monitor for 2 weeks post-migration.

### Disk I/O: NVMe contention during restic backups

All services share one NVMe. During restic backup (~200GB Nextcloud), disk I/O competes with PostgreSQL WAL writes and Prometheus TSDB. Plan correctly specifies `IOSchedulingClass = "idle"` for restic — good. Also consider:
- PostgreSQL: `IOWeight = 400` (high priority)
- Prometheus: `IOWeight = 200` (medium)

### PgBouncer: Consider deferring

200 max_connections with ~5 applications is adequate for this workload. PgBouncer adds complexity (password sync, connection routing). Consider deploying without PgBouncer initially, adding it only if connection exhaustion becomes a problem.

---

## 9. DNS & Certificates Audit

### CERT-001: Split architecture is sound

VPS NPM handles `*.akunito.com` (public), TrueNAS NPM handles `*.local.akunito.com` (local). Each manages its own ACME certs independently via DNS-01. Clean separation.

### CERT-002: Local access strategy for VPS services is well-defined

Plan Section "Local Access Strategy" clearly specifies Option C (split DNS): LAN clients use `plane.akunito.com` (public URL via Cloudflare) for VPS services, and `jellyfin.local.akunito.com` (pfSense DNS -> TrueNAS) for local services. This adds ~22ms latency for VPS access from LAN (acceptable).

### CERT-003: DNS TTL lowering timing

Plan says lower TTLs 24h before cutover. Some ISP resolvers cache longer than stated TTL. Increase to 48h before Phase 4.

### CERT-004: Split DNS + VPN client resolution

When a Tailscale client is outside the home (phone on mobile data), `*.local.akunito.com` won't resolve unless Headscale pushes DNS settings:
```yaml
dns:
  nameservers: ["192.168.8.1"]  # pfSense, reachable via Tailscale
  domains: ["local.akunito.com"]
```
This ensures remote Tailscale clients can resolve local domains via pfSense even when off-LAN.

---

## 10. Additional Missing Steps

### MISS-001: No firewall audit after initial deployment

Plan configures firewall in Phase 1 but doesn't verify. A misconfigured rule could leave ports open.

**Fix:** Add to Phase 1:
```bash
# From an external machine (NOT the VPS):
nmap -sT -p 1-65535 <VPS_IP>
# Expected open: 56777 (SSH), 80 (HTTP), 443 (HTTPS), 2222 (initrd SSH)
# All others must be filtered/closed
```

### MISS-002: No Netcup VNC/rescue mode documentation

If NixOS doesn't boot after install (LUKS misconfiguration, initrd issue), you need Netcup's VNC/KVM console. Document how to access it and verify it works before relying on the VPS for production.

### MISS-003: No graceful service drain during Phase 4 cutover

Phase 4 says "stop services on Proxmox" then "switch Cloudflare Tunnel". Users currently connected are dropped hard.

**Fix:** Use Cloudflare Tunnel's ability to route to the VPS while old services are still running. Briefly run both, verify new is serving, then shut down old. This achieves near-zero downtime.

### MISS-004: No DNS propagation verification method

Plan says "wait for DNS propagation" without specifying how to verify.

**Fix:** Use:
```bash
dig +short @8.8.8.8 headscale.akunito.com  # Google DNS
dig +short @1.1.1.1 headscale.akunito.com  # Cloudflare DNS
```
Both should return new VPS IP before proceeding.

### MISS-005: Email deliverability (SPF/DKIM/DMARC)

Postfix relay via SMTP2GO needs SPF, DKIM, and DMARC records. If DNS changes, verify these records still include SMTP2GO's sending IPs and DKIM keys.

### MISS-006: Old Cloudflare Tunnel cleanup

Plan creates a new Cloudflare Tunnel but doesn't mention deleting the old one from the dashboard after decommission. Orphaned tunnels are a security risk.

### MISS-007: No communication plan details

Plan mentions "send Matrix message + email 24h before cutover" but doesn't mention:
- Notifying Nextcloud sync client users (they'll see sync errors)
- Notifying Matrix federation peers (may cache old endpoint)
- Setting up a maintenance status page on Uptime Kuma

### MISS-008: No VPS-specific `deploy-servers.conf` entry format

The plan says "add VPS_PROD entry to deploy-servers.conf" but deploy.sh uses specific flags. VPS needs:
- Non-standard SSH port (`-p 56777`)
- Different user or same `akunito`?
- Which install.sh flags? VPS is neither LXC (`-d -h`) nor laptop (no flags)

---

## Summary Table

| Severity | Count | Key themes |
|---|---|---|
| CRITICAL | 7 | Database exposure, backup alerts broken, Redis eviction, Nextcloud integrity, sudo on VPS, missing secrets, Docker port bypass |
| HIGH | 12 | fail2ban port, DNS defaults, ACME permissions, monitoring gaps, Syncthing, PgBouncer, IPv6, Grafana SMTP, signing key timing, LUKS verify, rate limiting |
| MEDIUM | 15 | Log aggregation, cert monitoring, image pinning, NFS safety, NPM backup, cron.php, macvlan shim, Docker writes on suspend |
| SEQUENCING | 4 | Step numbering, backup pipeline timing, security ordering |
| MISSING STEPS | 8 | Firewall scan, rescue mode, graceful drain, DNS verify, email records, tunnel cleanup, comms plan, deploy.sh format |

---

## Recommended Action Sequence

### Before Phase 0.5
- [ ] Fix CRIT-001: Backup alert label mismatch in grafana.nix
- [ ] Fix CRIT-006: Enumerate and add all new secrets to domains.nix.template
- [ ] Fix HIGH-012: Back up Matrix signing key NOW, store in Bitwarden

### During Phase 0
- [ ] Fix HIGH-001: Parameterize fail2ban SSH port
- [ ] Fix HIGH-003: Fix ACME chmod 644 and Proxmox-specific hook
- [ ] Fix HIGH-010: Parameterize Grafana SMTP host
- [ ] Fix MED-011: Fix postgresql_17 hardcoding in database-backup.nix
- [ ] Fix MED-012: Fix LXC_matrix SSH host IP for 'desk'
- [ ] Capture MED-013: Pre-migration performance baseline

### During Phase 1
- [ ] Fix CRIT-002: Bind databases to 127.0.0.1 in VPS profile
- [ ] Fix CRIT-007: No passwordless sudo on VPS
- [ ] Fix HIGH-002: Override DNS nameservers for VPS
- [ ] Fix HIGH-009: Handle IPv6 (disable or configure firewall)
- [ ] Fix HIGH-011: Verify LUKS encryption after first boot
- [ ] Add MISS-001: External port scan verification
- [ ] Document MISS-002: Netcup VNC/rescue mode access

### During Phase 2
- [ ] Fix CRIT-003: All Docker port bindings must use 127.0.0.1
- [ ] Fix HIGH-007: Implement or defer PgBouncer
- [ ] Fix HIGH-008: Plan rate limiting for NPM

### During Phase 3
- [ ] Fix CRIT-004: Nextcloud integrity verification after each migration
- [ ] Fix CRIT-005: Change Redis eviction policy or add alerts
- [ ] Fix MED-003: Pin Docker image versions to current LXC versions
- [ ] Fix MED-004: Set up Nextcloud cron.php

### Before Phase 4 Cutover
- [ ] Verify Phase 3f backup gate: restic backup + restore test complete
- [ ] Fix MISS-003: Plan graceful service drain (run both briefly)
- [ ] Fix MISS-004: DNS propagation verification method

### Post-Migration (Phase 6+)
- [ ] Fix MED-001: Consider Loki for log aggregation
- [ ] Fix MED-002: TLS certificate expiry alerts
- [ ] Fix MED-005: Pre-suspend script for TrueNAS Docker
- [ ] Fix MED-007: Cloudflare Tunnel health monitoring
- [ ] Fix MED-010: NPM data in backup scope
- [ ] Fix AUTH-003: Scope Cloudflare API tokens per zone
- [ ] Fix MISS-006: Delete old Cloudflare Tunnel from dashboard

---

*Audit v4 completed: 2026-02-19*
*Auditor: Claude Code (Opus 4.6)*
*Method: Full codebase cross-reference of every module, profile, and secret referenced in plan*
