---
id: infrastructure.migration.phase-3
summary: "Application migration: Plane, Portfolio, Matrix, Nextcloud"
tags: [infrastructure, migration, vps, docker, applications]
date: 2026-02-23
status: published
---

# Phase 3 -- Application Migration to VPS

This document covers the migration of all application workloads from Proxmox
LXC containers and TrueNAS Docker to VPS_PROD. Each application was migrated
independently with its own verification and rollback window.

## Overview

| Sub-phase | Application       | Source                | Status   |
|-----------|-------------------|-----------------------|----------|
| 3a        | Plane             | LXC_plane             | Complete |
| 3b        | Portfolio          | LXC_portfolioprod     | Complete |
| 3b2       | FreshRSS          | TrueNAS Docker        | Complete |
| 3c        | LiftCraft         | LXC_liftcraftTEST     | Complete |
| 3d        | Matrix Synapse     | LXC_matrix            | Complete |
| 3e        | Nextcloud         | TrueNAS Docker        | Complete |
| 3f        | Backup Pipeline    | New                   | Complete |

---

## Security Baseline for ALL VPS Docker Containers

Every Docker container on VPS_PROD adheres to the following security baseline.
No exceptions are granted without documented justification.

### Container Runtime Restrictions

- **No `--privileged` flag** -- no container runs in privileged mode. Specific
  capabilities are granted individually if needed (e.g., `NET_BIND_SERVICE`).
- **No `docker.sock` mounts** -- the Docker socket is never exposed inside
  containers. Management is performed from the host only.
- **Read-only root filesystem where possible** -- volumes mounted with `:ro`
  unless the application requires write access to that path.
- **CRIT-003: All ports bound to 127.0.0.1** -- every `ports:` directive in
  docker-compose uses the format `127.0.0.1:PORT:PORT`. No container port is
  ever exposed on `0.0.0.0`. Traffic reaches containers exclusively through
  NPM, which itself is only reachable via the Cloudflare tunnel.
- **`no-new-privileges: true`** -- set on every container via
  `security_opt: [no-new-privileges:true]`. Prevents privilege escalation
  inside the container via setuid/setgid binaries.
- **`mem_limit` on every container** -- each container has an explicit memory
  limit to prevent a single runaway process from exhausting VPS RAM. Limits
  are tuned per application (see individual sections below).

### Docker Network Isolation

Containers are segmented into purpose-specific Docker networks. A container
only joins the networks it needs.

| Network     | Purpose                                 | Members                                    |
|-------------|-----------------------------------------|--------------------------------------------|
| `proxy`     | NPM to application frontends            | NPM, Plane web, Portfolio, FreshRSS, etc.  |
| `apps`      | Inter-application communication          | Plane, LiftCraft, Portfolio                |
| `matrix`    | Matrix stack internal                   | Synapse, Element, Claude Bot               |
| `nextcloud` | Nextcloud stack internal                | Nextcloud, Collabora, Imaginary            |

Containers that need database access connect to the host network's loopback
via `extra_hosts: ["host.docker.internal:host-gateway"]` and connect to
PostgreSQL/MariaDB/Redis on `127.0.0.1` from the container's perspective
mapped through the gateway.

---

## Phase 3a -- Plane

### Source

LXC_plane (Proxmox container). Plane is a project management tool with a
multi-container Docker Compose stack.

### Migration Steps

1. Exported Plane PostgreSQL database from LXC_database with
   `pg_dump -Fc plane > plane.dump`.
2. Restored on VPS PostgreSQL: `pg_restore -d plane plane.dump`.
3. Migrated Redis data for db0 (Plane sessions). In practice, session loss
   was acceptable so a clean Redis start was used.
4. Copied Plane Docker Compose stack to VPS, updated environment variables:
   - `DATABASE_URL=postgresql://plane:***@host.docker.internal:5432/plane`
   - `REDIS_URL=redis://host.docker.internal:6379/0`
5. Started Plane stack on VPS. Ran database migrations.
6. Updated NPM proxy host to point to VPS Plane web container.
7. Verified: project boards, issues, attachments all present.

### Container Limits

| Container     | mem_limit | Purpose           |
|---------------|-----------|-------------------|
| plane-web     | 512m      | Frontend          |
| plane-api     | 1g        | API server        |
| plane-worker  | 512m      | Background jobs   |
| plane-beat    | 256m      | Task scheduler    |

---

## Phase 3b -- Portfolio

### Source

LXC_portfolioprod (Proxmox container). Static/dynamic portfolio site served
at `info.akunito.com`.

### Migration Steps

1. Exported portfolio database from LXC_database.
2. Restored on VPS PostgreSQL.
3. Copied application files and Docker Compose to VPS.
4. Updated database connection strings to point to localhost.
5. Updated NPM proxy host for `info.akunito.com`.
6. Verified: all pages render, contact form submits, assets load.

### Container Limits

| Container      | mem_limit | Purpose     |
|----------------|-----------|-------------|
| portfolio-app  | 512m      | Application |

---

## Phase 3b2 -- FreshRSS

### Source

TrueNAS Docker. FreshRSS is a self-hosted RSS aggregator served at
`freshrss.akunito.com`.

### Migration Steps

1. Exported FreshRSS data directory from TrueNAS via rsync.
2. Exported FreshRSS PostgreSQL database (or SQLite file, depending on
   configuration).
3. Deployed FreshRSS Docker container on VPS with the migrated data volume.
4. Updated NPM proxy host for `freshrss.akunito.com`.
5. Verified: feeds load, starred items present, OPML export matches source.

### Container Limits

| Container  | mem_limit | Purpose     |
|------------|-----------|-------------|
| freshrss   | 256m      | Application |

---

## Phase 3c -- LiftCraft

### Source

LXC_liftcraftTEST (Proxmox container). LiftCraft is a Ruby on Rails
application for workout tracking.

### Migration Steps

1. Exported LiftCraft PostgreSQL database from LXC_database.
2. Restored on VPS PostgreSQL.
3. Migrated Redis data for db2 (Sidekiq jobs). Clean start was acceptable
   for background jobs.
4. Copied Rails application and Docker Compose to VPS.
5. Updated environment variables:
   - `DATABASE_URL=postgresql://liftcraft:***@host.docker.internal:5432/liftcraft`
   - `REDIS_URL=redis://host.docker.internal:6379/2`
6. Ran `rails db:migrate` inside the container to apply any pending migrations.
7. Updated NPM proxy host.
8. Verified: user login, workout creation, historical data intact.

### Container Limits

| Container       | mem_limit | Purpose          |
|-----------------|-----------|------------------|
| liftcraft-web   | 1g        | Rails + Puma     |
| liftcraft-worker| 512m      | Sidekiq          |

---

## Phase 3d -- Matrix Synapse + Element

### Source

LXC_matrix (192.168.8.104). Matrix is a federated messaging protocol;
Synapse is the homeserver implementation.

### Critical Pre-migration: Signing Key Backup

**The Synapse signing key (`*.signing.key`) is CRITICAL.** If lost, the
homeserver cannot prove its identity to the federation. All federated rooms
would become inaccessible. The key was:

1. Copied from LXC_matrix to a local encrypted backup.
2. Verified with `sha256sum` on both source and backup.
3. Stored in the git-crypt-encrypted secrets directory.
4. Restored on VPS before Synapse first started.

### Migration Steps

1. Exported Matrix Synapse PostgreSQL database from LXC_database:
   `pg_dump -Fc matrix_synapse > matrix_synapse.dump`.
2. Restored on VPS PostgreSQL.
3. Copied `homeserver.yaml` to VPS, updated:
   - `database.args.host: 127.0.0.1`
   - `database.args.port: 5432`
   - `redis.host: 127.0.0.1` (db4)
   - `server_name` unchanged (federation identity).
   - `trusted_key_servers` unchanged.
   - `media_store_path` pointed to VPS volume.
4. Migrated media store via rsync.
5. Deployed Synapse + Element Docker Compose stack on VPS.
6. Updated NPM proxy hosts for `matrix.akunito.com` and
   `element.akunito.com`.

### Federation Verification

1. Tested `/.well-known/matrix/server` returns correct `server_name`.
2. Used `federationtester.matrix.org` to verify federation connectivity.
3. Sent test messages to rooms on `matrix.org` and `mozilla.org` -- messages
   delivered bidirectionally.
4. Verified encryption keys for existing E2EE rooms still functioned.

### Claude Bot Deployment

The Claude Bot (custom Matrix bot powered by Claude API) was deployed as
an additional container in the `matrix` Docker network:

- Connects to Synapse via the internal Docker network.
- API key stored in git-crypt-encrypted environment file.
- Auto-joins configured rooms.
- `mem_limit: 256m`.

### Fail2ban Jail

A fail2ban jail was configured for Matrix login attempts:

- Filter: matches failed login attempts in Synapse logs.
- `maxretry = 5`, `findtime = 300`, `bantime = 3600`.
- Action: bans IP at the iptables level (effective because cloudflared
  passes `CF-Connecting-IP` and Synapse logs it).

### Container Limits

| Container    | mem_limit | Purpose            |
|--------------|-----------|--------------------|
| synapse      | 2g        | Homeserver         |
| element-web  | 256m      | Web client         |
| claude-bot   | 256m      | Matrix bot         |

---

## Phase 3e -- Nextcloud

Nextcloud was the most complex migration due to the volume of user data
(approximately 200 GB) and the number of integrations.

### Source

TrueNAS Docker (Nextcloud + MariaDB + Redis). Data stored on TrueNAS
ZFS datasets.

### Data Migration

1. **Initial rsync** -- bulk data copied from TrueNAS to VPS over the local
   network. This took approximately 8 hours for the initial 200 GB transfer.
   Nextcloud remained operational on TrueNAS during this phase.

2. **Maintenance mode** -- Nextcloud was placed in maintenance mode on TrueNAS:
   `docker exec nextcloud occ maintenance:mode --on`

3. **Final rsync** -- a delta rsync captured all changes since the initial
   sync. This completed in approximately 15 minutes.

4. **Database migration** -- MariaDB dump from TrueNAS restored on VPS MariaDB:
   ```
   mysqldump --single-transaction nextcloud > nextcloud.sql
   mysql nextcloud < nextcloud.sql
   ```

### config.php Updates

The Nextcloud `config.php` required extensive updates for the new environment:

```php
// Database
'dbtype' => 'mysql',
'dbhost' => '127.0.0.1:3306',     // was TrueNAS Docker network IP
'dbname' => 'nextcloud',
'dbuser' => 'nextcloud',
'dbpassword' => '***',

// Redis
'memcache.local' => '\\OC\\Memcache\\Redis',
'memcache.distributed' => '\\OC\\Memcache\\Redis',
'memcache.locking' => '\\OC\\Memcache\\Redis',
'redis' => [
    'host' => '127.0.0.1',         // was TrueNAS Docker network IP
    'port' => 6379,
    'dbindex' => 1,
],

// Trusted proxies (NPM container)
'trusted_proxies' => ['127.0.0.1', '172.18.0.0/16'],

// Security headers
'overwrite.cli.url' => 'https://cloud.akunito.com',
'overwriteprotocol' => 'https',

// Brute-force protection
'auth.bruteforce.protection.enabled' => true,
```

### Cron Configuration

Nextcloud background jobs configured via system cron on VPS host:

```
*/5 * * * * docker exec -u www-data nextcloud php cron.php
```

This runs every 5 minutes, replacing the previous AJAX-based cron that was
less reliable under load.

### TOTP Two-Factor Authentication

TOTP 2FA was enabled for all admin accounts after migration verification.
Recovery codes were generated and stored in the encrypted secrets vault.

### Container Limits

| Container   | mem_limit | Purpose            |
|-------------|-----------|--------------------|
| nextcloud   | 2g        | Application        |
| collabora   | 1g        | Document editing   |
| imaginary   | 512m      | Image processing   |

---

## Phase 3f -- Initial Backup Pipeline

With all applications running on VPS, a backup pipeline was established to
protect against data loss.

### SSH Key Setup

A dedicated SSH key pair was generated on VPS for restic SFTP access to
TrueNAS:

1. `ssh-keygen -t ed25519 -f /root/.ssh/restic_truenas -N ""`
2. Public key added to TrueNAS `restic` user's `authorized_keys`.
3. SFTP-only access enforced via TrueNAS user shell restriction.

### Restic Repositories

Three separate restic repositories were initialized on TrueNAS, each
dedicated to a different data category:

| Repository   | Path on TrueNAS                    | Content                         |
|--------------|------------------------------------|---------------------------------|
| databases    | /mnt/tank/backups/vps/databases    | PostgreSQL + MariaDB dumps      |
| services     | /mnt/tank/backups/vps/services     | Docker volumes, configs, keys   |
| nextcloud    | /mnt/tank/backups/vps/nextcloud    | Nextcloud data directory         |

Each repository was initialized with:
```bash
restic -r sftp:restic@truenas:/mnt/tank/backups/vps/<name> init
```

### Backup Scripts

Backup scripts were created for each repository:

1. **databases** -- dumps PostgreSQL (`pg_dumpall`) and MariaDB
   (`mysqldump --all-databases`), then runs `restic backup` on the dump
   directory.
2. **services** -- backs up Docker Compose files, environment files,
   Synapse signing key, NPM configuration, and selected Docker volumes.
3. **nextcloud** -- backs up the Nextcloud data directory after placing
   Nextcloud in maintenance mode (to ensure consistency), then disables
   maintenance mode.

### Restore Verification

A full restore test was performed after the first backup:

1. Created a temporary PostgreSQL instance on a test port.
2. Restored the database dump from restic.
3. Verified row counts matched production.
4. Restored a sample of Nextcloud files and verified checksums.
5. Documented the restore procedure in the operations runbook.

### Retention Policy (Initial)

- Keep last 7 daily snapshots.
- Keep last 4 weekly snapshots.
- Keep last 3 monthly snapshots.

Backup schedule was initially set to run at 02:00 UTC daily. This was later
optimized in Phase 4 to avoid overlap with other maintenance windows.

---

## Rollback Plan

| Sub-phase | Rollback action                                                 |
|-----------|-----------------------------------------------------------------|
| 3a        | Re-point NPM to LXC_plane                                      |
| 3b        | Re-point NPM to LXC_portfolioprod                               |
| 3b2       | Re-point NPM to TrueNAS FreshRSS                               |
| 3c        | Re-point NPM to LXC_liftcraftTEST                              |
| 3d        | Re-point NPM to LXC_matrix, restore signing key if needed      |
| 3e        | Disable maintenance mode on TrueNAS Nextcloud, revert DNS       |
| 3f        | N/A (additive -- no rollback needed for backup infrastructure)  |

No rollback was needed. All applications were verified functional on VPS
before the source containers were shut down.
