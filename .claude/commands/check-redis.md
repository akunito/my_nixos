# Check Redis Status

Skill for checking Redis connectivity, database allocation, and key counts across all services using the centralized Redis on LXC_database.

## Purpose

Use this skill to:
- Verify Redis connectivity from all services
- Check database allocation (db0-db3)
- Monitor key counts per database
- Troubleshoot Redis connection issues

---

## Redis Database Allocation

| Database | Service | Container | Expected Keys |
|----------|---------|-----------|---------------|
| db0 | Plane | LXC_plane (192.168.8.86) | Session/job queue |
| db1 | Nextcloud | LXC_HOME (192.168.8.80) | Distributed cache |
| db2 | LiftCraft TEST | LXC_liftcraftTEST (192.168.8.87) | Rails cache |
| db3 | Portfolio | LXC_portfolioprod (192.168.8.88) | `portfolio:*` keys |

---

## Quick Health Check

Run all checks at once:

```bash
# Check all Redis databases from LXC_HOME (has redis-cli via docker)
ssh -A akunito@192.168.8.80 'for db in 0 1 2 3; do
  count=$(docker exec redis-local redis-cli -h 192.168.8.103 -a "PASSWORD" -n $db DBSIZE 2>/dev/null)
  echo "db$db: $count keys"
done'
```

Replace `PASSWORD` with the actual Redis password from `secrets/domains.nix`.

---

## Per-Service Checks

### 1. Portfolio (db3)

```bash
# Check health endpoint
curl -s https://portfolio.akunito.com/api/health | jq

# Check Redis keys
ssh -A akunito@192.168.8.80 "docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n 3 KEYS '*'"

# Expected keys:
# - portfolio:projects-list
# - portfolio:homepage-config
# - portfolio:experience-list-config
# - portfolio:health-check (temporary, 1min TTL)
```

### 2. Nextcloud (db1)

```bash
# Check Nextcloud can connect to Redis
ssh -A akunito@192.168.8.80 "docker exec -u www-data nextcloud-app php occ status"

# Check Redis config inside container
ssh -A akunito@192.168.8.80 "docker exec nextcloud-app cat /var/www/html/config/config.php | grep -A 8 \"'redis'\""

# Verify dbindex is set to 1:
# 'dbindex' => 1,

# Check db1 keys
ssh -A akunito@192.168.8.80 "docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n 1 DBSIZE"
```

### 3. Plane (db0)

```bash
# Check Plane containers are running
ssh -A akunito@192.168.8.86 "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# Check db0 keys
ssh -A akunito@192.168.8.80 "docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n 0 KEYS '*' | head -20"
```

### 4. LiftCraft TEST (db2)

```bash
# Check Rails cache store
ssh -A akunito@192.168.8.87 "cd ~/leftyworkout_TEST && docker exec leftyworkout_test-backend-1 bin/rails runner \"puts Rails.cache.class\""
# Expected: ActiveSupport::Cache::RedisCacheStore

# Test Redis connection
ssh -A akunito@192.168.8.87 "cd ~/leftyworkout_TEST && docker exec leftyworkout_test-backend-1 bin/rails runner \"require 'redis'; r = Redis.new(url: ENV['REDIS_URL']); puts r.ping\""
# Expected: PONG

# Check db2 keys
ssh -A akunito@192.168.8.80 "docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n 2 KEYS '*'"
```

---

## Troubleshooting

### NOAUTH Authentication required

Wrong password. Check `secrets/domains.nix` for the correct `redisServerPassword`.

### Keys in wrong database

Service is not configured with correct database number:
- **Nextcloud**: Add `'dbindex' => 1` to redis array in `config.php`
- **LiftCraft**: Add `/2` to end of REDIS_URL
- **Portfolio**: Add `/3` to end of REDIS_URL
- **Plane**: Uses db0 by default (no change needed)

### Empty database after config change

1. Restart the service container
2. Trigger activity (access web UI, run command)
3. Check again - some services only cache on demand

### Connection refused

Redis service not running on LXC_database:
```bash
ssh -A akunito@192.168.8.103 "systemctl status redis"
```

---

## Key TTLs

Check when keys expire:

```bash
# Check TTL for a specific key
ssh -A akunito@192.168.8.80 "docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n 3 TTL 'portfolio:projects-list'"

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
ssh -A akunito@192.168.8.80 "docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n 3 FLUSHDB"
```

---

## Related Documentation

- [Database & Redis Services](../../docs/infrastructure/services/database-redis.md)
- [Check Database](./check-database.md) - PostgreSQL/MariaDB health checks
