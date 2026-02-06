# Check Database Health

Skill for checking the health and connectivity of all database services, both local (per-container) and centralized (LXC_database).

## Purpose

Use this skill to:
- Verify database connectivity from application containers
- Check database service status on LXC_database
- Monitor replication, connections, and performance
- Validate backup status

---

## Container Database Locations

### Current (Pre-Migration)

| Container | Database | Type | Port |
|-----------|----------|------|------|
| LXC_plane | plane-db | PostgreSQL 15 | Docker internal |
| LXC_liftcraftTEST | leftyworkout_test-db-1 | PostgreSQL 17 | Docker internal |
| LXC_HOME | nextcloud-db | MariaDB 11.4 | Docker internal |
| LXC_HOME | nextcloud-redis | Redis | Docker internal |
| LXC_plane | plane-redis | Valkey 7.2.5 | Docker internal |

### Centralized (Post-Migration)

| Service | Host | Port |
|---------|------|------|
| PostgreSQL | 192.168.8.103 | 5432 (direct) / 6432 (PgBouncer) |
| MariaDB | 192.168.8.103 | 3306 |
| Redis | 192.168.8.103 | 6379 |

---

## Pre-Migration Health Checks

### 1. Check Docker Database Containers

```bash
# LXC_plane - Plane database
echo "=== Plane Database (LXC_plane) ==="
ssh -A akunito@192.168.8.86 "docker ps --filter 'name=db' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
ssh -A akunito@192.168.8.86 "docker exec plane-db pg_isready -U plane" 2>/dev/null && echo "PostgreSQL: OK" || echo "PostgreSQL: FAILED"

# LXC_liftcraftTEST - LiftCraft database
echo ""
echo "=== LiftCraft Database (LXC_liftcraftTEST) ==="
ssh -A akunito@192.168.8.87 "docker ps --filter 'name=db' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
ssh -A akunito@192.168.8.87 "docker exec leftyworkout_test-db-1 pg_isready -U postgres" 2>/dev/null && echo "PostgreSQL: OK" || echo "PostgreSQL: FAILED"

# LXC_HOME - Nextcloud database
echo ""
echo "=== Nextcloud Database (LXC_HOME) ==="
ssh -A akunito@192.168.8.80 "docker ps --filter 'name=nextcloud-db' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
ssh -A akunito@192.168.8.80 "docker exec nextcloud-db mariadb-admin ping" 2>/dev/null && echo "MariaDB: OK" || echo "MariaDB: FAILED"
```

### 2. Check Redis/Valkey

```bash
# Plane Valkey
echo "=== Plane Redis (LXC_plane) ==="
ssh -A akunito@192.168.8.86 "docker exec plane-redis valkey-cli ping" 2>/dev/null && echo "Valkey: OK" || echo "Valkey: FAILED"

# Nextcloud Redis
echo ""
echo "=== Nextcloud Redis (LXC_HOME) ==="
ssh -A akunito@192.168.8.80 "docker exec nextcloud-redis redis-cli ping" 2>/dev/null && echo "Redis: OK" || echo "Redis: FAILED"
```

---

## Post-Migration Health Checks (LXC_database)

### 1. Check NixOS Services

```bash
ssh -A akunito@192.168.8.103 "systemctl status postgresql mysql redis-homelab pgbouncer --no-pager"
```

### 2. Check PostgreSQL

```bash
# Service status
ssh -A akunito@192.168.8.103 "systemctl is-active postgresql && echo 'PostgreSQL: RUNNING' || echo 'PostgreSQL: STOPPED'"

# Connection test
ssh -A akunito@192.168.8.103 "sudo -u postgres psql -c 'SELECT version();'" 2>/dev/null | head -3

# List databases
ssh -A akunito@192.168.8.103 "sudo -u postgres psql -c '\l'" 2>/dev/null

# Check connections
ssh -A akunito@192.168.8.103 "sudo -u postgres psql -c 'SELECT datname, numbackends FROM pg_stat_database WHERE numbackends > 0;'" 2>/dev/null

# Check replication (if configured)
ssh -A akunito@192.168.8.103 "sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'" 2>/dev/null
```

### 3. Check MariaDB

```bash
# Service status
ssh -A akunito@192.168.8.103 "systemctl is-active mysql && echo 'MariaDB: RUNNING' || echo 'MariaDB: STOPPED'"

# Connection test
ssh -A akunito@192.168.8.103 "sudo mysql -e 'SELECT VERSION();'" 2>/dev/null

# List databases
ssh -A akunito@192.168.8.103 "sudo mysql -e 'SHOW DATABASES;'" 2>/dev/null

# Check connections
ssh -A akunito@192.168.8.103 "sudo mysql -e 'SHOW STATUS LIKE \"Threads_connected\";'" 2>/dev/null
```

### 4. Check Redis

```bash
# Service status
ssh -A akunito@192.168.8.103 "systemctl is-active redis-homelab && echo 'Redis: RUNNING' || echo 'Redis: STOPPED'"

# Connection test (with password from secrets)
ssh -A akunito@192.168.8.103 "redis-cli -a \$(cat /etc/secrets/redis-password) ping" 2>/dev/null

# Memory usage
ssh -A akunito@192.168.8.103 "redis-cli -a \$(cat /etc/secrets/redis-password) info memory | grep -E 'used_memory_human|maxmemory_human'" 2>/dev/null

# Database key counts
ssh -A akunito@192.168.8.103 "redis-cli -a \$(cat /etc/secrets/redis-password) info keyspace" 2>/dev/null
```

### 5. Check PgBouncer

```bash
# Service status
ssh -A akunito@192.168.8.103 "systemctl is-active pgbouncer && echo 'PgBouncer: RUNNING' || echo 'PgBouncer: STOPPED'"

# Show pools
ssh -A akunito@192.168.8.103 "psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c 'SHOW POOLS;'" 2>/dev/null

# Show stats
ssh -A akunito@192.168.8.103 "psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c 'SHOW STATS;'" 2>/dev/null
```

---

## Connectivity Tests from App Containers

### Test PostgreSQL from LXC_plane

```bash
ssh -A akunito@192.168.8.86 "docker run --rm postgres:17-alpine psql -h 192.168.8.103 -p 6432 -U plane -d plane -c 'SELECT 1;'" 2>/dev/null
```

### Test PostgreSQL from LXC_liftcraftTEST

```bash
ssh -A akunito@192.168.8.87 "docker run --rm postgres:17-alpine psql -h 192.168.8.103 -p 6432 -U liftcraft -d rails_database_prod -c 'SELECT 1;'" 2>/dev/null
```

### Test MariaDB from LXC_HOME

```bash
ssh -A akunito@192.168.8.80 "docker run --rm mariadb:11.4 mysql -h 192.168.8.103 -u nextcloud -p\$MYSQL_PASSWORD -e 'SELECT 1;'" 2>/dev/null
```

### Test Redis from Any Container

```bash
ssh -A akunito@192.168.8.86 "docker run --rm redis:alpine redis-cli -h 192.168.8.103 -a <password> ping" 2>/dev/null
```

---

## Backup Status Check

```bash
# Check backup timers
ssh -A akunito@192.168.8.103 "systemctl list-timers postgresql-backup mariadb-backup --no-pager"

# Check last backup
ssh -A akunito@192.168.8.103 "ls -lah /var/backup/databases/postgresql/ 2>/dev/null | tail -5"
ssh -A akunito@192.168.8.103 "ls -lah /var/backup/databases/mariadb/ 2>/dev/null | tail -5"

# Check backup metrics (for Prometheus)
ssh -A akunito@192.168.8.103 "cat /var/lib/prometheus-node-exporter/textfile/postgresql_backup.prom 2>/dev/null"
ssh -A akunito@192.168.8.103 "cat /var/lib/prometheus-node-exporter/textfile/mariadb_backup.prom 2>/dev/null"
```

---

## Prometheus Exporter Status

```bash
# Check exporters are running
ssh -A akunito@192.168.8.103 "systemctl is-active prometheus-postgres-exporter prometheus-mysqld-exporter prometheus-redis-exporter"

# Test exporter endpoints
ssh -A akunito@192.168.8.103 "curl -s http://localhost:9187/metrics | head -5"  # PostgreSQL
ssh -A akunito@192.168.8.103 "curl -s http://localhost:9104/metrics | head -5"  # MariaDB
ssh -A akunito@192.168.8.103 "curl -s http://localhost:9121/metrics | head -5"  # Redis

# Check from monitoring server
ssh -A akunito@192.168.8.85 "curl -s http://192.168.8.103:9187/metrics | head -5"
ssh -A akunito@192.168.8.85 "curl -s http://192.168.8.103:9104/metrics | head -5"
ssh -A akunito@192.168.8.85 "curl -s http://192.168.8.103:9121/metrics | head -5"
```

---

## Quick Health Check Script

```bash
#!/bin/bash
echo "=== Database Health Check ==="
echo ""

# LXC_database services
echo "--- LXC_database (192.168.8.103) ---"
for svc in postgresql mysql redis-homelab pgbouncer; do
  status=$(ssh -A -o ConnectTimeout=5 akunito@192.168.8.103 "systemctl is-active $svc" 2>/dev/null)
  printf "%-20s %s\n" "$svc:" "${status:-UNREACHABLE}"
done

echo ""
echo "--- Prometheus Exporters ---"
for port in 9187 9104 9121; do
  status=$(ssh -A -o ConnectTimeout=5 akunito@192.168.8.103 "curl -s -o /dev/null -w '%{http_code}' http://localhost:$port/metrics" 2>/dev/null)
  printf "Port %-5s: %s\n" "$port" "${status:-FAILED}"
done

echo ""
echo "--- Pre-Migration Containers ---"
echo "Plane DB: $(ssh -A -o ConnectTimeout=5 akunito@192.168.8.86 'docker exec plane-db pg_isready -U plane' 2>/dev/null && echo 'OK' || echo 'FAILED')"
echo "LiftCraft DB: $(ssh -A -o ConnectTimeout=5 akunito@192.168.8.87 'docker exec leftyworkout_test-db-1 pg_isready -U postgres' 2>/dev/null && echo 'OK' || echo 'FAILED')"
echo "Nextcloud DB: $(ssh -A -o ConnectTimeout=5 akunito@192.168.8.80 'docker exec nextcloud-db mariadb-admin ping' 2>/dev/null && echo 'OK' || echo 'FAILED')"
```

---

## Output Format

```markdown
## Database Health Report - [DATE]

### Centralized Database (LXC_database - 192.168.8.103)

| Service | Status | Port | Notes |
|---------|--------|------|-------|
| PostgreSQL | RUNNING | 5432 | 2 databases, 15 connections |
| MariaDB | RUNNING | 3306 | 1 database |
| Redis | RUNNING | 6379 | 3 databases configured |
| PgBouncer | RUNNING | 6432 | Transaction pooling |

### Prometheus Exporters

| Exporter | Port | Status |
|----------|------|--------|
| postgres_exporter | 9187 | OK |
| mysqld_exporter | 9104 | OK |
| redis_exporter | 9121 | OK |

### Backup Status

| Database | Last Backup | Size | Status |
|----------|-------------|------|--------|
| plane | 2024-01-15 02:00 | 45MB | OK |
| rails_database_prod | 2024-01-15 02:00 | 12MB | OK |
| nextcloud | 2024-01-15 02:00 | 890MB | OK |

### Issues Found
- None / [List any issues]
```
