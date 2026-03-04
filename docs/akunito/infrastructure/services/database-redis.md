---
id: infrastructure.services.database
summary: "Database services: PostgreSQL, MariaDB, Redis on VPS"
tags: [infrastructure, database, vps, postgresql, redis]
date: 2026-02-23
status: published
---

# Database & Redis Services

All database services run on the VPS as NixOS native services, bound to **127.0.0.1 only**.

## PostgreSQL 17

| Setting | Value |
|---------|-------|
| Listen | 127.0.0.1:5432 |
| shared_buffers | 2GB |
| effective_cache_size | 8GB |
| maintenance_work_mem | 512MB |
| work_mem | 64MB |
| max_connections | 200 |

### Databases

| Database | Application | Notes |
|----------|-------------|-------|
| plane | Plane | Project management |
| rails_database_prod | LiftCraft | Rails app |
| matrix | Matrix Synapse | Federation server |

### Access

```bash
ssh -A -p 56777 akunito@100.64.0.6
sudo -u postgres psql
# Or specific DB:
sudo -u postgres psql -d plane
```

## MariaDB 11

| Setting | Value |
|---------|-------|
| Listen | 127.0.0.1:3306 |
| innodb_buffer_pool_size | 1G |
| max_connections | 200 |

### Databases

| Database | Application |
|----------|-------------|
| nextcloud | Nextcloud |

### Access

```bash
ssh -A -p 56777 akunito@100.64.0.6
sudo mysql
```

## Redis 7

| Setting | Value |
|---------|-------|
| Listen | 127.0.0.1:6379 |
| maxmemory | 2GB |
| maxmemory-policy | volatile-lru |

### DB Allocations

| DB | Application |
|----|-------------|
| db0 | Plane |
| db1 | Nextcloud |
| db2 | LiftCraft |
| db3 | Portfolio |
| db4 | Matrix Synapse |

### Access

```bash
ssh -A -p 56777 akunito@100.64.0.6
redis-cli -a "$(sudo cat /etc/secrets/redis-password)" -n 0  # Plane
```

## PgBouncer

**Deferred** — not deployed. 200 max_connections is sufficient for ~5 applications. Module exists at `system/app/pgbouncer.nix` for future use if connection exhaustion occurs.

## Backup Schedule

### Layer 1: Local Dumps (database-backup.nix)

| Schedule | Type | Retention | Location |
|----------|------|-----------|----------|
| Hourly | pg_dump -Fc + mysqldump + redis BGSAVE | 72 count (3 days) | /var/backup/databases/ |
| Daily | pg_dump -Fc + SQL format | 7 days | /var/backup/databases/ |

### Layer 2: Restic to TrueNAS

| Schedule | Repo | Retention |
|----------|------|-----------|
| Every 2h (18:00-22:30) | sftp:truenas:/mnt/ssdpool/vps-backups/databases.restic | 7 daily, 4 weekly, 1 monthly |

### Integrity Checks

- Weekly: `restic check` (index + structure)
- Monthly: `restic check --read-data` (full data verification)

## DBeaver Access

Connect via SSH tunnel:
1. SSH Host: 100.64.0.6, Port: 56777, User: akunito
2. DB Host: 127.0.0.1, Port: 5432 (PostgreSQL) or 3306 (MariaDB)

## Previous Setup

All databases previously ran on LXC_database (192.168.8.103, decommissioned Feb 2026). Data was dumped and restored on VPS during Phase 2 of migration.
