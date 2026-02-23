# Check Database Health

Skill for checking the health and connectivity of all database services on the VPS (Netcup RS 4000 G12).

## Purpose

Use this skill to:
- Verify database service status on VPS
- Check connectivity from Docker application containers to localhost databases
- Monitor connections, performance, and replication
- Validate backup status (restic repos and hourly DB dumps)

---

## Database Locations (VPS localhost)

| Service | Type | Port | Databases |
|---------|------|------|-----------|
| PostgreSQL 17 | NixOS native | 5432 (direct) / 6432 (PgBouncer) | plane, rails_database_prod, nextcloud, matrix, freshrss |
| MariaDB 11 | NixOS native | 3306 | nextcloud |
| Redis 7 | NixOS native | 6379 | db0=Plane, db1=Nextcloud, db2=LiftCraft, db3=Portfolio, db4=Matrix |

**SSH target:** `ssh -A -p 56777 akunito@100.64.0.6`

---

## Health Checks

### 1. Check NixOS Services

```bash
ssh -A -p 56777 akunito@100.64.0.6 "systemctl status postgresql mysql redis pgbouncer --no-pager"
```

### 2. Check PostgreSQL

```bash
# Service status
ssh -A -p 56777 akunito@100.64.0.6 "systemctl is-active postgresql && echo 'PostgreSQL: RUNNING' || echo 'PostgreSQL: STOPPED'"

# Connection test
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -c 'SELECT version();'" 2>/dev/null | head -3

# List databases
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -c '\l'" 2>/dev/null

# Check connections per database
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -c 'SELECT datname, numbackends FROM pg_stat_database WHERE numbackends > 0;'" 2>/dev/null

# Check replication (if configured)
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'" 2>/dev/null

# Check database sizes
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -c 'SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size FROM pg_database WHERE datname NOT IN ('\''template0'\'', '\''template1'\'') ORDER BY pg_database_size(datname) DESC;'" 2>/dev/null
```

### 3. Check MariaDB

```bash
# Service status
ssh -A -p 56777 akunito@100.64.0.6 "systemctl is-active mysql && echo 'MariaDB: RUNNING' || echo 'MariaDB: STOPPED'"

# Connection test
ssh -A -p 56777 akunito@100.64.0.6 "sudo mysql -e 'SELECT VERSION();'" 2>/dev/null

# List databases
ssh -A -p 56777 akunito@100.64.0.6 "sudo mysql -e 'SHOW DATABASES;'" 2>/dev/null

# Check connections
ssh -A -p 56777 akunito@100.64.0.6 "sudo mysql -e 'SHOW STATUS LIKE \"Threads_connected\";'" 2>/dev/null

# Check nextcloud database size
ssh -A -p 56777 akunito@100.64.0.6 "sudo mysql -e 'SELECT table_schema AS db, ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb FROM information_schema.tables GROUP BY table_schema;'" 2>/dev/null
```

### 4. Check Redis

```bash
# Service status
ssh -A -p 56777 akunito@100.64.0.6 "systemctl is-active redis && echo 'Redis: RUNNING' || echo 'Redis: STOPPED'"

# Connection test (with password from secrets)
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) ping" 2>/dev/null

# Memory usage
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) info memory | grep -E 'used_memory_human|maxmemory_human'" 2>/dev/null

# Database key counts
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) info keyspace" 2>/dev/null

# Per-database check
ssh -A -p 56777 akunito@100.64.0.6 'for db in 0 1 2 3 4; do
  count=$(redis-cli -a $(sudo cat /etc/secrets/redis-password) -n $db DBSIZE 2>/dev/null)
  echo "db$db: $count"
done'
```

### 5. Check PgBouncer

```bash
# Service status
ssh -A -p 56777 akunito@100.64.0.6 "systemctl is-active pgbouncer && echo 'PgBouncer: RUNNING' || echo 'PgBouncer: STOPPED'"

# Show pools
ssh -A -p 56777 akunito@100.64.0.6 "psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c 'SHOW POOLS;'" 2>/dev/null

# Show stats
ssh -A -p 56777 akunito@100.64.0.6 "psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c 'SHOW STATS;'" 2>/dev/null

# Show clients
ssh -A -p 56777 akunito@100.64.0.6 "psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c 'SHOW CLIENTS;'" 2>/dev/null
```

---

## Connectivity Tests from Docker Containers

All Docker containers on VPS connect to databases via localhost:

```bash
# Test PostgreSQL from a Docker container
ssh -A -p 56777 akunito@100.64.0.6 "docker run --rm --network host postgres:17-alpine psql -h 127.0.0.1 -p 6432 -U plane -d plane -c 'SELECT 1;'" 2>/dev/null

# Test MariaDB from a Docker container
ssh -A -p 56777 akunito@100.64.0.6 "docker run --rm --network host mariadb:11 mysql -h 127.0.0.1 -u nextcloud -e 'SELECT 1;'" 2>/dev/null

# Test Redis from a Docker container
ssh -A -p 56777 akunito@100.64.0.6 "docker run --rm --network host redis:alpine redis-cli -h 127.0.0.1 -a \$(sudo cat /etc/secrets/redis-password) ping" 2>/dev/null
```

---

## Backup Status Check

```bash
# Check restic backup repos
ssh -A -p 56777 akunito@100.64.0.6 "restic -r /var/backup/restic/postgresql snapshots --last 5 2>/dev/null" || echo "Check restic repo path"
ssh -A -p 56777 akunito@100.64.0.6 "restic -r /var/backup/restic/mariadb snapshots --last 5 2>/dev/null" || echo "Check restic repo path"

# Check hourly DB dumps
ssh -A -p 56777 akunito@100.64.0.6 "ls -lah /var/backup/postgresql/ 2>/dev/null | tail -10"
ssh -A -p 56777 akunito@100.64.0.6 "ls -lah /var/backup/mariadb/ 2>/dev/null | tail -10"

# Check backup timers
ssh -A -p 56777 akunito@100.64.0.6 "systemctl list-timers '*backup*' --no-pager"

# Check backup metrics (for Prometheus)
ssh -A -p 56777 akunito@100.64.0.6 "cat /var/lib/prometheus-node-exporter/textfile/postgresql_backup*.prom 2>/dev/null"
ssh -A -p 56777 akunito@100.64.0.6 "cat /var/lib/prometheus-node-exporter/textfile/mariadb_backup*.prom 2>/dev/null"
```

---

## Prometheus Exporter Status

```bash
# Check exporters are running
ssh -A -p 56777 akunito@100.64.0.6 "systemctl is-active prometheus-postgres-exporter prometheus-mysqld-exporter prometheus-redis-exporter"

# Test exporter endpoints
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9187/metrics | head -5"  # PostgreSQL
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9104/metrics | head -5"  # MariaDB
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9121/metrics | head -5"  # Redis

# Verify Prometheus is scraping them
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | test(\"postgres|mysql|redis\")) | {job: .labels.job, health: .health}'"
```

---

## Quick Health Check Script

```bash
#!/bin/bash
echo "=== Database Health Check (VPS) ==="
echo ""

VPS="ssh -A -o ConnectTimeout=5 -p 56777 akunito@100.64.0.6"

echo "--- NixOS Database Services ---"
for svc in postgresql mysql redis pgbouncer; do
  status=$($VPS "systemctl is-active $svc" 2>/dev/null)
  printf "%-20s %s\n" "$svc:" "${status:-UNREACHABLE}"
done

echo ""
echo "--- PostgreSQL Databases ---"
$VPS "sudo -u postgres psql -t -c \"SELECT datname || ': ' || pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datname NOT IN ('template0','template1') ORDER BY datname;\"" 2>/dev/null

echo ""
echo "--- Redis Databases ---"
$VPS 'for db in 0 1 2 3 4; do
  count=$(redis-cli -a $(sudo cat /etc/secrets/redis-password) -n $db DBSIZE 2>/dev/null)
  case $db in
    0) svc="Plane" ;; 1) svc="Nextcloud" ;; 2) svc="LiftCraft" ;; 3) svc="Portfolio" ;; 4) svc="Matrix" ;;
  esac
  echo "db$db ($svc): $count"
done'

echo ""
echo "--- Prometheus Exporters ---"
for port in 9187 9104 9121; do
  status=$($VPS "curl -s -o /dev/null -w '%{http_code}' http://localhost:$port/metrics" 2>/dev/null)
  printf "Port %-5s: %s\n" "$port" "${status:-FAILED}"
done
```

---

## Output Format

```markdown
## Database Health Report - [DATE]

### Database Services (VPS)

| Service | Status | Port | Notes |
|---------|--------|------|-------|
| PostgreSQL 17 | RUNNING | 5432 | 5 databases, N connections |
| MariaDB 11 | RUNNING | 3306 | 1 database (nextcloud) |
| Redis 7 | RUNNING | 6379 | 5 databases (db0-db4) |
| PgBouncer | RUNNING | 6432 | Transaction pooling |

### PostgreSQL Databases

| Database | Size | Connections |
|----------|------|-------------|
| plane | XXmb | N |
| rails_database_prod | XXmb | N |
| nextcloud | XXmb | N |
| matrix | XXmb | N |
| freshrss | XXmb | N |

### Prometheus Exporters

| Exporter | Port | Status |
|----------|------|--------|
| postgres_exporter | 9187 | OK |
| mysqld_exporter | 9104 | OK |
| redis_exporter | 9121 | OK |

### Backup Status

| Database | Last Backup | Size | Status |
|----------|-------------|------|--------|
| plane | YYYY-MM-DD HH:MM | XXmb | OK |
| rails_database_prod | YYYY-MM-DD HH:MM | XXmb | OK |
| nextcloud (pg) | YYYY-MM-DD HH:MM | XXmb | OK |
| nextcloud (maria) | YYYY-MM-DD HH:MM | XXmb | OK |
| matrix | YYYY-MM-DD HH:MM | XXmb | OK |
| freshrss | YYYY-MM-DD HH:MM | XXmb | OK |

### Issues Found
- None / [List any issues]
```
