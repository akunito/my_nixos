# Check Redis Status

Skill for checking Redis connectivity, database allocation, and key counts on the VPS (Netcup RS 4000 G12).

## Purpose

Use this skill to:
- Verify Redis connectivity on VPS
- Check database allocation (db0-db4)
- Monitor key counts per database
- Troubleshoot Redis connection issues

---

## Redis Database Allocation

All Redis databases are on VPS localhost:6379.

| Database | Service | Expected Keys |
|----------|---------|---------------|
| db0 | Plane | Session/job queue |
| db1 | Nextcloud | Distributed cache |
| db2 | LiftCraft | Rails cache |
| db3 | Portfolio | `portfolio:*` keys |
| db4 | Matrix | Synapse cache |

**SSH target:** `ssh -A -p 56777 akunito@100.64.0.6`

---

## Quick Health Check

Run all checks at once:

```bash
ssh -A -p 56777 akunito@100.64.0.6 'for db in 0 1 2 3 4; do
  count=$(redis-cli -a $(sudo cat /etc/secrets/redis-password) -n $db DBSIZE 2>/dev/null)
  case $db in
    0) svc="Plane" ;; 1) svc="Nextcloud" ;; 2) svc="LiftCraft" ;; 3) svc="Portfolio" ;; 4) svc="Matrix" ;;
  esac
  echo "db$db ($svc): $count"
done'
```

---

## Per-Service Checks

### 1. Plane (db0)

```bash
# Check db0 key count
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 0 DBSIZE"

# List sample keys
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 0 KEYS '*' | head -20"

# Check Plane Docker containers are connected
ssh -A -p 56777 akunito@100.64.0.6 "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep plane"
```

### 2. Nextcloud (db1)

```bash
# Check db1 key count
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 1 DBSIZE"

# Check Nextcloud container can reach Redis
ssh -A -p 56777 akunito@100.64.0.6 "docker exec nextcloud-app php occ status" 2>/dev/null

# Verify dbindex is set to 1 in Nextcloud config
ssh -A -p 56777 akunito@100.64.0.6 "docker exec nextcloud-app cat /var/www/html/config/config.php | grep -A 8 \"'redis'\"" 2>/dev/null
```

### 3. LiftCraft (db2)

```bash
# Check db2 key count
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 2 DBSIZE"

# Check Rails cache store type
ssh -A -p 56777 akunito@100.64.0.6 "docker exec liftcraft-backend bin/rails runner \"puts Rails.cache.class\"" 2>/dev/null
# Expected: ActiveSupport::Cache::RedisCacheStore

# Test Redis connection from Rails
ssh -A -p 56777 akunito@100.64.0.6 "docker exec liftcraft-backend bin/rails runner \"require 'redis'; r = Redis.new(url: ENV['REDIS_URL']); puts r.ping\"" 2>/dev/null
# Expected: PONG
```

### 4. Portfolio (db3)

```bash
# Check db3 key count
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 3 DBSIZE"

# List Portfolio keys
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 3 KEYS '*'"

# Expected keys:
# - portfolio:projects-list
# - portfolio:homepage-config
# - portfolio:experience-list-config
# - portfolio:health-check (temporary, 1min TTL)

# Check health endpoint
curl -s https://portfolio.akunito.com/api/health | jq
```

### 5. Matrix (db4)

```bash
# Check db4 key count
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 4 DBSIZE"

# List sample keys
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 4 KEYS '*' | head -20"
```

---

## Redis Service Health

```bash
# Service status
ssh -A -p 56777 akunito@100.64.0.6 "systemctl is-active redis && echo 'Redis: RUNNING' || echo 'Redis: STOPPED'"

# Memory usage
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) info memory | grep -E 'used_memory_human|maxmemory_human'"

# Connected clients
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) info clients | grep connected_clients"

# Full keyspace info
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) info keyspace"
```

---

## Troubleshooting

### NOAUTH Authentication required

Wrong password. Check `secrets/domains.nix` for the correct `redisServerPassword`.

### Keys in wrong database

Service is not configured with correct database number:
- **Plane**: Uses db0 by default (no change needed)
- **Nextcloud**: Add `'dbindex' => 1` to redis array in `config.php`
- **LiftCraft**: Add `/2` to end of REDIS_URL
- **Portfolio**: Add `/3` to end of REDIS_URL
- **Matrix**: Add `/4` to end of REDIS_URL or set in Synapse config

### Empty database after config change

1. Restart the service Docker container on VPS
2. Trigger activity (access web UI, run command)
3. Check again - some services only cache on demand

### Connection refused

Redis service not running on VPS:
```bash
ssh -A -p 56777 akunito@100.64.0.6 "systemctl status redis --no-pager"
```

---

## Key TTLs

Check when keys expire:

```bash
# Check TTL for a specific key
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 3 TTL 'portfolio:projects-list'"

# TTL values:
# -2 = key doesn't exist
# -1 = no expiration
# >0 = seconds until expiration
```

---

## Clear Cache

If needed, flush a specific database:

```bash
# CAUTION: This deletes all keys in the database
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 3 FLUSHDB"
```

---

## Related Documentation

- [Check Database](./check-database.md) - PostgreSQL/MariaDB health checks
- [Check Kuma](./check-kuma.md) - Uptime Kuma monitoring checks
