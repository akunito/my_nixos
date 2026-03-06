---
id: audits.docker-security.2026-03-06
summary: VPS Docker container security audit — network isolation, database access, secrets, hardening
tags: [audit, security, docker, vps, containers, networking, secrets]
related_files: [profiles/VPS*-config.nix, profiles/vps/base.nix, system/app/homelab-docker.nix, system/app/postfix-relay.nix, system/app/postgresql.nix, system/app/redis-server.nix]
date: 2026-03-06
status: published
---

# VPS Docker Container Security Audit

**Date**: 2026-03-06
**Auditor**: Claude Code
**System**: VPS_PROD (Netcup RS 4000 G12, 32GB RAM)
**Scope**: Docker services, networking, isolation, database access, secrets management, container hardening

---

## Executive Summary

The VPS runs 14 rootless Docker stacks alongside native NixOS services (PostgreSQL, MariaDB, Redis, Prometheus, Grafana). A prior security audit (2026-02-19) covered SSH, firewall, kernel hardening, and VPN — those remain in good shape.

This audit found **14 findings** across 5 categories. Key issues:

1. **SASL password world-readable** in `/nix/store/` (Critical — fixed)
2. **pg_hba allows all containers to all databases** (High — fixed)
3. **Postfix mynetworks overly broad** (High — fixed)
4. **Matrix template unhardened** (High — fixed)
5. **Host loopback enabled for all containers** (Critical — accepted risk with compensating controls)

**4 P1 findings fixed** in Nix, **2 P3 findings fixed** in Nix, **6 findings documented** for future work.

---

## Architecture Context

### Docker Mode
- **Rootless Docker** (`dockerRootlessEnable = true`): Containers run as UID 1000 via slirp4netns
- **Host loopback**: `DOCKERD_ROOTLESS_ROOTLESSKIT_DISABLE_HOST_LOOPBACK = "false"` — all containers can reach all host services via `10.0.2.2`
- **DNS**: External (`1.1.1.1`, `9.9.9.9`) — slirp4netns can't reach systemd-resolved

### Docker Stacks (14 total)
portfolio, liftcraft, plane, matrix, miniflux, miniflux-ai, nextcloud, syncthing, uptime-kuma, unifi, romm, calibre, n8n, openclaw

### Native Services on Host
PostgreSQL 17, MariaDB, Redis, PgBouncer, Postfix relay, Prometheus, Grafana, Vaultwarden, Cloudflared, Headscale, nginx-local

---

## Findings

### SEC-DOCKER-NET-001: Host Loopback Enabled for All Containers

| Field | Value |
|-------|-------|
| **Severity** | Critical (Accepted Risk) |
| **Status** | Accepted — compensated by DB ACL + Postfix fixes |
| **Category** | Network Isolation |

**Description**: `DOCKERD_ROOTLESS_ROOTLESSKIT_DISABLE_HOST_LOOPBACK = "false"` allows ALL containers to reach ALL host services via `10.0.2.2`. This is a fundamental architectural choice — rootless Docker's slirp4netns does not support per-container loopback control.

**Risk**: Any compromised container can attempt to connect to any host service (PostgreSQL, MariaDB, Redis, Postfix, Prometheus, etc.).

**Compensating Controls**:
- SEC-DOCKER-DB-001: PostgreSQL per-user-per-database ACLs (fixed)
- SEC-DOCKER-NET-003: Postfix mynetworks narrowed (fixed)
- SEC-DOCKER-DB-003: iptables defense-in-depth on public interface (fixed)
- Redis requires password authentication
- MariaDB user limited to `nextcloud` database only

**Future**: Consider switching to `pasta` backend (net.containers.io) which may offer per-container network policies.

---

### SEC-DOCKER-SEC-001: SASL Password World-Readable in Nix Store

| Field | Value |
|-------|-------|
| **Severity** | Critical |
| **Status** | **Fixed** |
| **Category** | Secrets Management |
| **Files Changed** | `system/app/postfix-relay.nix`, `system/app/database-secrets.nix` |

**Description**: `pkgs.writeText "sasl_passwd"` creates a file in `/nix/store/` with mode `0444` (world-readable). Any local user or container with host filesystem access can read SMTP2GO credentials.

**Fix**: Moved SASL credentials to `/etc/secrets/smtp2go-credentials` (mode `0600`, root:root) using the existing `database-secrets.nix` pattern. Postfix now reads from `/etc/secrets/` and runs `postmap` in `preStart`.

**Verification**:
```bash
stat -c '%a %U:%G' /etc/secrets/smtp2go-credentials
# Expected: 600 root:root
postmap -q "[mail.smtp2go.com]:2525" hash:/etc/secrets/smtp2go-credentials
# Expected: non-empty output
```

---

### SEC-DOCKER-SEC-002: Credentials in Environment Variables

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Status** | Documented — future improvement |
| **Category** | Secrets Management |

**Description**: Most Docker stacks pass database credentials and API keys via environment variables in `.env` files. These are visible in `/proc/<pid>/environ` and `docker inspect`.

**Recommendation**: Migrate to Docker secrets (`docker secret create`) or bind-mount credential files. Priority services: Plane (DB password), n8n (DB + API keys), Miniflux (DB password).

---

### SEC-DOCKER-SEC-003: Most Compose Files Not Version-Controlled

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Status** | Documented — future improvement |
| **Category** | Secrets Management |

**Description**: Only 3 of 14 compose files are in `templates/` (matrix, openclaw, n8n). The remaining 11 exist only on VPS at `~/.homelab/`. This makes auditing, rollback, and reproducibility difficult.

**Recommendation**: Add compose files to `templates/` directory (stripping secrets to `.env.template`). Priority: plane, liftcraft, nextcloud, miniflux, vaultwarden.

---

### SEC-DOCKER-NET-002: No Docker Network Segmentation

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Status** | Documented — future improvement |
| **Category** | Network Isolation |

**Description**: Most stacks use the default bridge network. Containers in different stacks could potentially communicate if ports overlap. Only matrix has a custom `matrix-net` bridge.

**Recommendation**: Create per-stack networks in compose files. This limits blast radius if one container is compromised.

---

### SEC-DOCKER-NET-003: Postfix mynetworks Overly Broad

| Field | Value |
|-------|-------|
| **Severity** | High |
| **Status** | **Fixed** |
| **Category** | Network Isolation |
| **Files Changed** | `system/app/postfix-relay.nix` |

**Description**: `mynetworks` included `172.16.0.0/12` (all Docker bridges), `10.0.0.0/8` (entire RFC1918), and `100.64.0.0/10` (all Tailscale nodes). Any device on these networks could relay email through the VPS.

**Fix**: Narrowed to `127.0.0.0/8`, `[::1]/128`, `10.0.2.0/24` (slirp4netns NAT subnet). VPS public IP remains via `postfixRelayExtraNetworks`.

**Verification**:
```bash
postconf mynetworks
# Expected: 127.0.0.0/8, [::1]/128, 10.0.2.0/24, <VPS_IP>/32
# Should NOT contain: 172.16.0.0/12, 10.0.0.0/8, 100.64.0.0/10
```

---

### SEC-DOCKER-NET-004: Docker DNS Bypasses Local Resolver

| Field | Value |
|-------|-------|
| **Severity** | Low (Accepted Risk) |
| **Status** | Accepted — slirp4netns limitation |
| **Category** | Network Isolation |

**Description**: Docker daemon is configured with `"dns" = [ "1.1.1.1" "9.9.9.9" ]` because slirp4netns can't reach systemd-resolved's stub at `127.0.0.53`. This bypasses any local DNS policies.

**Future**: Switch to `pasta` backend which supports resolv.conf pass-through.

---

### SEC-DOCKER-DB-001: PostgreSQL Allows All Containers to All Databases

| Field | Value |
|-------|-------|
| **Severity** | High |
| **Status** | **Fixed** |
| **Category** | Database Access |
| **Files Changed** | `profiles/VPS_PROD-config.nix` |

**Description**: `pg_hba.conf` contained `host all all 10.0.0.0/8 scram-sha-256` — any container could connect to any database as any user (if they had the password).

**Fix**: Replaced with per-user-per-database entries:
- `plane` → `plane` database only
- `liftcraft` → `rails_database_prod` only
- `matrix` → `matrix` only
- `miniflux` → `miniflux` only
- `vaultwarden` → `vaultwarden` only
- `n8n` → `n8n` only

**Verification**:
```bash
sudo -u postgres psql -c "SELECT database, user_name FROM pg_hba_file_rules WHERE address IS NOT NULL AND database != '{all}';"
# Cross-database test (should fail):
PGPASSWORD=... psql -h 127.0.0.1 -U plane -d matrix -c "SELECT 1;"
# Expected: FATAL: no pg_hba.conf entry
```

---

### SEC-DOCKER-DB-002: Redis Single Shared Password

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Status** | Documented — future improvement |
| **Category** | Database Access |

**Description**: Redis uses a single password for all 16 databases. Any container that knows the Redis password can access all databases.

**Recommendation**: Implement Redis ACLs with per-app users. Requires updating `.env` files in each stack that uses Redis (matrix, plane, openclaw, etc.).

---

### SEC-DOCKER-DB-003: Databases Bind 0.0.0.0 Without Secondary Barrier

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Status** | **Fixed** |
| **Category** | Database Access |
| **Files Changed** | `profiles/vps/base.nix` |

**Description**: PostgreSQL, MariaDB, Redis, and PgBouncer bind `0.0.0.0` (needed for rootless Docker access via `10.0.2.2`). While database ports are NOT in `allowedTCPPorts`, a firewall misconfiguration could expose them.

**Fix**: Added explicit iptables DROP rules for ports 5432, 3306, 6379, 6432 on the public interface (`ens3`). This is defense-in-depth — even if firewall rules are accidentally modified, these ports remain blocked externally. Localhost, Tailscale, and WireGuard traffic is unaffected.

**Verification**:
```bash
iptables -L INPUT -n --line-numbers | grep -E "(5432|3306|6379|6432)"
# Expected: 4 DROP rules on ens3
```

---

### SEC-DOCKER-HARD-001: Matrix Template Unhardened

| Field | Value |
|-------|-------|
| **Severity** | High |
| **Status** | **Fixed** |
| **Category** | Container Hardening |
| **Files Changed** | `templates/matrix/docker-compose.yml` |

**Description**: Matrix template used `:latest` tags, no `security_opt`, no `cap_drop`, no resource limits, and ports bound to `0.0.0.0`.

**Fix**:
- Pinned images: `matrixdotorg/synapse:v1.148.0`, `vectorim/element-web:v1.12.11`, `redis:7-alpine`
- Added `security_opt: [no-new-privileges:true]` to all services
- Added `cap_drop: [ALL]` to all services
- Resource limits: Synapse 2G, Element 256M, Redis 512M
- Ports bound to `127.0.0.1`
- `read_only: true` for Redis and Element (static web app)
- Logging limits: 50m x 3 files

**Verification** (after deploying to VPS):
```bash
docker inspect synapse --format '{{.HostConfig.SecurityOpt}}'
# Expected: [no-new-privileges:true]
docker inspect synapse --format '{{json .HostConfig.CapDrop}}'
# Expected: ["ALL"]
```

---

### SEC-DOCKER-HARD-002: homelab-docker.service Unhardened

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Status** | **Fixed** |
| **Category** | Container Hardening |
| **Files Changed** | `system/app/homelab-docker.nix` |

**Description**: The systemd service had no hardening directives. The service runs as the user but has full filesystem access.

**Fix**: Added for rootless mode:
- `ProtectSystem = "strict"` (read-only `/usr`, `/boot`, `/etc`)
- `ReadWritePaths` for homelab dir, Docker runtime, and tmp
- `PrivateTmp = true`
- `NoNewPrivileges = true`
- `ProtectKernelModules`, `ProtectKernelTunables`, `ProtectControlGroups`
- `LockPersonality`, `RestrictRealtime`

**Verification**:
```bash
systemctl show homelab-docker.service | grep -E "(ProtectSystem|NoNewPrivileges)"
# Expected: ProtectSystem=strict, NoNewPrivileges=yes
```

---

### SEC-DOCKER-HARD-003: No Image Pinning Policy

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Status** | Documented — future improvement |
| **Category** | Container Hardening |

**Description**: Many compose files on VPS use `:latest` tags. This means `docker-compose pull` can introduce breaking or malicious changes.

**Recommendation**: Pin all images to specific versions in compose files. Matrix template (fixed), OpenClaw (already pinned), n8n (already pinned). Remaining: portfolio, liftcraft, plane, nextcloud, syncthing, uptime-kuma, unifi, romm, calibre, miniflux.

---

### SEC-DOCKER-MON-001: No Docker Security Event Alerting

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Status** | Documented — future improvement |
| **Category** | Monitoring |

**Description**: No alerting for Docker security events: OOM kills, restart loops, image CVEs, unexpected container starts/stops.

**Recommendation**:
1. Add Grafana alert rules for container OOM events (`container_oom_events_total` from cAdvisor)
2. Add alert for container restart loops (`container_restarts_total` > threshold)
3. Consider Trivy or Grype for periodic image CVE scanning

---

## Summary of Changes

### Fixed (Nix-side — committed to repo)

| Finding | Files Changed |
|---------|---------------|
| SEC-DOCKER-SEC-001 | `system/app/postfix-relay.nix`, `system/app/database-secrets.nix` |
| SEC-DOCKER-NET-003 | `system/app/postfix-relay.nix` |
| SEC-DOCKER-DB-001 | `profiles/VPS_PROD-config.nix` |
| SEC-DOCKER-DB-003 | `profiles/vps/base.nix` |
| SEC-DOCKER-HARD-001 | `templates/matrix/docker-compose.yml` |
| SEC-DOCKER-HARD-002 | `system/app/homelab-docker.nix` |

### Accepted Risk

| Finding | Rationale |
|---------|-----------|
| SEC-DOCKER-NET-001 | Rootless Docker limitation; compensated by DB ACLs + Postfix fixes |
| SEC-DOCKER-NET-004 | slirp4netns limitation; future fix with `pasta` backend |

### Documented (Future Work)

| Finding | Effort |
|---------|--------|
| SEC-DOCKER-SEC-002 | Medium — per-app secret file migration |
| SEC-DOCKER-SEC-003 | Low — add compose files to templates/ |
| SEC-DOCKER-NET-002 | Low-Medium — per-stack Docker networks |
| SEC-DOCKER-DB-002 | Medium — Redis ACL per-app users |
| SEC-DOCKER-HARD-003 | Low — pin image versions in compose files |
| SEC-DOCKER-MON-001 | Medium — Grafana alert rules |

---

## Post-Deploy Verification

After deploying via `install.sh`, run on VPS:

```bash
# 1. SASL credentials (SEC-DOCKER-SEC-001)
stat -c '%a %U:%G' /etc/secrets/smtp2go-credentials

# 2. Postfix mynetworks (SEC-DOCKER-NET-003)
postconf mynetworks

# 3. pg_hba rules (SEC-DOCKER-DB-001)
sudo -u postgres psql -c "SELECT type,database,user_name,address FROM pg_hba_file_rules WHERE address IS NOT NULL;"

# 4. iptables DB rules (SEC-DOCKER-DB-003)
iptables -L INPUT -n | grep -E "(5432|3306|6379|6432)"

# 5. Systemd hardening (SEC-DOCKER-HARD-002)
systemctl show homelab-docker.service | grep ProtectSystem

# 6. Full service health (all 14 stacks)
docker ps --format "{{.Names}}: {{.Status}}" | sort

# 7. Email delivery test
echo "Audit test $(date)" | mail -s "SEC-DOCKER test" root
journalctl -u postfix --since "5 min ago" | grep status=sent
```

---

## Deployment Instructions

### Matrix template (SEC-DOCKER-HARD-001)

The hardened template is in `templates/matrix/docker-compose.yml`. After deploying Nix changes:

```bash
# On VPS: copy updated template and recreate containers
cp ~/.dotfiles/templates/matrix/docker-compose.yml ~/.homelab/matrix/docker-compose.yml
cd ~/.homelab/matrix
docker-compose pull
docker-compose up -d
```

### All other changes

Deploy via standard workflow:
```bash
# From local machine (after commit + push):
ssh -A -p 56777 akunito@100.64.0.6 \
  "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```
