---
id: infrastructure.migration.phase-2
summary: "VPS foundation: databases, proxy, mailer, monitoring"
tags: [infrastructure, migration, vps, database, monitoring]
date: 2026-02-23
status: published
---

# Phase 2 -- VPS Foundation Services

This document covers the foundational service layer deployed on VPS_PROD before
any application workloads were migrated. Every application in Phase 3 depends on
at least one component established here.

## Overview

| Sub-phase | Service              | Status    | Notes                              |
|-----------|----------------------|-----------|------------------------------------|
| 2a        | PostgreSQL / MariaDB / Redis | Complete | All bound to 127.0.0.1       |
| 2b        | Cloudflare Tunnel + NPM      | Complete | Zero public ports exposed    |
| 2c        | Postfix relay (SMTP2GO)      | Complete | Test emails verified         |
| 2d        | Prometheus + Grafana          | Complete | Remote scrape via Tailscale  |

---

## Phase 2a -- Database Layer

### PostgreSQL 17

PostgreSQL 17 was installed via the NixOS `services.postgresql` module on
VPS_PROD. The data directory lives on the root ZFS dataset at
`/var/lib/postgresql/17`.

**Data migration steps:**

1. On LXC_database (192.168.8.103), a logical dump was taken with
   `pg_dumpall --clean --if-exists` to capture all databases, roles, and
   permissions.
2. The dump was transferred to VPS via `rsync` over Tailscale.
3. On VPS, the dump was restored with `psql -f dumpall.sql`.
4. Application-specific databases verified: `plane`, `matrix_synapse`,
   `nextcloud`, `liftcraft`, `portfolio`, `freshrss`.

**Configuration highlights:**

- `listen_addresses = '127.0.0.1'` -- no external access.
- `max_connections = 200` -- sufficient for all current workloads.
- PgBouncer was evaluated but deferred; 200 connections handles the combined
  load of Plane, Matrix, Nextcloud, LiftCraft, Portfolio, and FreshRSS without
  contention.
- `log_min_duration_statement = 500` for slow-query logging.
- `shared_buffers = 2GB`, `effective_cache_size = 6GB` tuned for the VPS
  8 GB RAM allocation to databases.

### MariaDB 11

MariaDB 11 was deployed for workloads that require MySQL compatibility
(primarily Nextcloud, which performs better on MariaDB than PostgreSQL in
practice).

**Data migration steps:**

1. On LXC_database, `mysqldump --all-databases --single-transaction` captured
   the MariaDB state.
2. A second dump was taken from the TrueNAS Docker MariaDB instance that served
   legacy services.
3. Both dumps were transferred to VPS and restored sequentially.
4. Duplicate databases were reconciled manually -- the LXC_database copy was
   authoritative for Nextcloud; TrueNAS copy was authoritative for legacy
   WordPress data (now archived).

**Configuration highlights:**

- `bind-address = 127.0.0.1` -- no external access.
- `innodb_buffer_pool_size = 1G`.
- `max_connections = 100`.
- Character set forced to `utf8mb4` with `collation-server = utf8mb4_unicode_ci`.

### Redis 7

Redis 7 provides caching and session storage for multiple applications. A
single Redis instance is used with logical database separation.

**Database assignments:**

| DB   | Application | Purpose              |
|------|-------------|----------------------|
| db0  | Plane       | Cache + sessions     |
| db1  | Nextcloud   | File locking + cache |
| db2  | LiftCraft   | Sidekiq jobs + cache |
| db3  | Portfolio   | Cache                |
| db4  | Matrix      | Synapse workers      |

**Configuration highlights:**

- `bind 127.0.0.1` -- no external access.
- `maxmemory 512mb`.
- `maxmemory-policy volatile-lru` -- changed from the default `noeviction` to
  gracefully handle memory pressure by evicting keys with a TTL set. This
  prevents OOM crashes when cache usage spikes during Nextcloud file scans or
  Plane webhook bursts.
- `save ""` -- persistence disabled; Redis is used purely as a cache layer.
  All authoritative state lives in PostgreSQL or MariaDB.

---

## Phase 2b -- Reverse Proxy and Ingress

### Architecture

Public traffic reaches VPS through a **Cloudflare Tunnel** (outbound-only
connection from VPS to Cloudflare edge). There are zero inbound ports open on
the VPS firewall for HTTP/HTTPS traffic.

```
Internet --> Cloudflare Edge --> Cloudflare Tunnel --> cloudflared (VPS)
                                                        |
                                                        v
                                                  NPM (127.0.0.1:80/443)
                                                        |
                                                        v
                                                  Docker services
```

### Cloudflare Tunnel (`cloudflared`)

- Tunnel name: `vps-prod`
- Runs as a systemd service on VPS (NixOS module).
- Ingress rules route `*.akunito.com` to `http://127.0.0.1:80` (NPM).
- Catch-all returns HTTP 404.

### Nginx Proxy Manager (NPM)

NPM runs as a rootless Docker container on VPS.

**Security measures:**

- ALL published ports bound to `127.0.0.1` -- NPM is not reachable from the
  public internet directly; only cloudflared forwards traffic to it.
- Admin panel (`127.0.0.1:81`) accessible only via Tailscale SSH tunnel.
- SSL certificates provisioned via DNS-01 ACME challenge using Cloudflare API
  token. This avoids exposing port 80 for HTTP-01 validation.
- Wildcard certificate `*.akunito.com` covers all subdomains.

### Cloudflare WAF Rules

Web Application Firewall rules configured at the Cloudflare dashboard level:

1. **Bot Fight Mode** -- enabled for all zones. Challenges known bot
   fingerprints.
2. **Scanner/Crawler blocks** -- custom rule blocking user-agents matching
   common vulnerability scanners (Nessus, Nikto, sqlmap, etc.).
3. **Login rate limiting** -- rate limit rule on `/login`, `/api/auth`,
   `/_matrix/client/*/login` paths: 10 requests per minute per IP, then
   challenge.
4. **Country restrictions** -- allow-list for expected origin countries on
   admin paths.

### NET-DNS-002 Rebinding Protection

DNS rebinding attacks are mitigated at two layers:

1. **Cloudflare** -- the tunnel inherently prevents rebinding because DNS
   resolution for `*.akunito.com` points to Cloudflare edge IPs, not the VPS
   directly.
2. **NPM** -- default host returns 444 (connection close) for any request
   with a `Host` header not matching a configured proxy host.

---

## Phase 2c -- Mail Relay

### Postfix via SMTP2GO

Postfix was deployed on VPS as a send-only relay. It does not accept inbound
mail.

**Configuration:**

- `relayhost = [mail.smtp2go.com]:2525`
- SASL authentication with SMTP2GO credentials stored in
  `/etc/postfix/sasl_passwd` (managed by NixOS sops or git-crypt secret).
- `inet_interfaces = 127.0.0.1` -- only local services can submit mail.
- `mynetworks` initially set to `127.0.0.0/8` (expanded in Phase 4e to
  include Tailscale and WireGuard subnets).

**Verification:**

Test emails were sent from VPS to multiple providers (Gmail, ProtonMail,
Outlook) and all arrived in inbox (not spam). SPF, DKIM, and DMARC records
were already configured in Cloudflare DNS from the previous SMTP2GO setup.

**Consumers:**

- Grafana alert notifications
- Nextcloud share notifications and password resets
- Plane email digests
- Prometheus Alertmanager (via Grafana as relay)
- Cron job failure notifications

---

## Phase 2d -- Monitoring Stack

### Prometheus

Prometheus was deployed on VPS via the NixOS `services.prometheus` module.

**Scrape targets:**

| Target                  | Endpoint                          | Transport    |
|-------------------------|-----------------------------------|--------------|
| VPS node_exporter       | 127.0.0.1:9100                    | localhost    |
| VPS cadvisor            | 127.0.0.1:9323                    | localhost    |
| VPS postgres_exporter   | 127.0.0.1:9187                    | localhost    |
| VPS redis_exporter      | 127.0.0.1:9121                    | localhost    |
| DESK node_exporter      | 100.64.0.2:9100                   | Tailscale    |
| TrueNAS node_exporter   | 100.64.0.3:9100                   | Tailscale    |
| pfSense SNMP            | 192.168.8.1:161                   | Tailscale    |
| LXC_HOME node_exporter  | 100.64.0.4:9100                   | Tailscale    |

Remote targets are scraped over the Tailscale mesh VPN. Prometheus has
`scrape_interval: 30s` globally, with a `15s` override for VPS-local targets.

**Retention:**

- `--storage.tsdb.retention.time=90d`
- `--storage.tsdb.retention.size=10GB`

### Grafana

Grafana was deployed on VPS via the NixOS `services.grafana` module, with the
web UI exposed through NPM at `monitor.akunito.com`.

**Data sources:**

- Prometheus (primary)
- Loki (planned, not yet deployed)

**Dashboards migrated from LXC_monitoring:**

- Node Exporter Full (per-host)
- Docker Container Overview
- PostgreSQL Overview
- Redis Overview
- Network connectivity matrix

### Parallel Operation

LXC_monitoring (192.168.8.85) was kept running in parallel with the VPS
monitoring stack for two weeks. During this period:

1. Both Prometheus instances scraped the same targets.
2. Alert rules were duplicated on both.
3. Grafana dashboards were compared side-by-side to verify data parity.
4. After verification, LXC_monitoring was demoted to scrape-only (alerts
   disabled) and eventually shut down in Phase 4g.

### Connectivity Probes

Custom Prometheus blackbox probes were configured to monitor VPN path health:

- `probe_icmp` to Tailscale IPs of all nodes (detect mesh failures).
- `probe_tcp` to WireGuard endpoint (detect tunnel failures).
- `probe_http` to each proxied service (detect application-level failures).

Alert rules fire if any probe fails for more than 3 minutes.

---

## Rollback Plan

Each sub-phase had an independent rollback path:

| Sub-phase | Rollback action                                              |
|-----------|--------------------------------------------------------------|
| 2a        | Re-point applications to LXC_database (192.168.8.103)        |
| 2b        | Revert Cloudflare tunnel to point at LXC_proxy (192.168.8.102) |
| 2c        | Re-enable Postfix on LXC_mailer or send directly via SMTP2GO |
| 2d        | Re-enable alerts on LXC_monitoring Grafana                   |

No rollback was needed -- all sub-phases completed successfully on first
deployment.
