---
id: infrastructure.database-redis
summary: Centralized PostgreSQL and Redis services on LXC_database
tags: [infrastructure, database, redis, postgresql, lxc, caching]
related_files: [profiles/LXC_database-config.nix, secrets/domains.nix]
---

# Database & Redis Services (LXC_database)

Centralized database infrastructure providing PostgreSQL and Redis for all homelab services.

## Overview

| Property | Value |
|----------|-------|
| **Container** | LXC_database |
| **IP Address** | 192.168.8.103 |
| **Profile** | `profiles/proxmox-lxc/LXC_database-config.nix` |
| **Services** | PostgreSQL 15, Redis 7 |

## PostgreSQL Databases

| Database | Service | Port | Notes |
|----------|---------|------|-------|
| `plane` | Plane (Project Management) | 5432 | LXC_plane (192.168.8.86) |
| `nextcloud` | Nextcloud | 5432 | LXC_HOME (192.168.8.80) |
| `liftcraft_test` | LiftCraft TEST | 5432 | LXC_liftcraftTEST (192.168.8.87) |
| `matrix` | Matrix Synapse | 5432 | LXC_matrix (192.168.8.104) |

### Connection String Format

```
postgresql://USER:PASSWORD@192.168.8.103:5432/DATABASE
```

Credentials are stored in `secrets/domains.nix` (git-crypt encrypted).

## Redis Database Allocation

Redis uses database numbers (0-15) to separate data for different services.

| Database | Service | Container | Purpose |
|----------|---------|-----------|---------|
| **db0** | Plane | LXC_plane (192.168.8.86) | Session cache, job queue |
| **db1** | Nextcloud | LXC_HOME (192.168.8.80) | Distributed cache, file locking |
| **db2** | LiftCraft TEST | LXC_liftcraftTEST (192.168.8.87) | Rails cache, Action Cable |
| **db3** | Portfolio | LXC_portfolioprod (192.168.8.88) | Next.js page cache |
| **db4** | Matrix Synapse | LXC_matrix (192.168.8.104) | Sessions, presence |

### Redis Connection URL Format

```
redis://:PASSWORD@192.168.8.103:6379/DB_NUMBER
```

Example for Portfolio (db3):
```
redis://:PASSWORD@192.168.8.103:6379/3
```

## Service Configuration

### Nextcloud (db1)

In `config/config.php`:
```php
'redis' => array (
  'host' => '192.168.8.103',
  'password' => 'REDIS_PASSWORD',
  'port' => 6379,
  'dbindex' => 1,
),
'memcache.distributed' => '\\OC\\Memcache\\Redis',
'memcache.locking' => '\\OC\\Memcache\\Redis',
```

**Note**: The container has a `redis-fallback.sh` script that automatically configures Redis at startup. Ensure `EXTERNAL_REDIS_DBINDEX="1"` is set in that script.

### Plane (db0)

In `.env`:
```bash
REDIS_HOST=192.168.8.103
REDIS_PORT=6379
REDIS_PASSWORD=REDIS_PASSWORD
# Note: Plane defaults to db0, no explicit database config needed
```

### LiftCraft (db2)

In `.env.test` or `.env.prod`:
```bash
REDIS_URL=redis://:REDIS_PASSWORD@192.168.8.103:6379/2
```

Rails automatically uses this for:
- `config.cache_store = :redis_cache_store`
- Action Cable connections

### Portfolio (db3)

In `.env.dev` and `.env.prod`:
```bash
REDIS_URL=redis://:REDIS_PASSWORD@192.168.8.103:6379/3
```

The Next.js app uses a custom Redis client (`lib/cache/redis.ts`) with automatic fallback to in-memory cache.

### Matrix Synapse (db4)

In `~/.homelab/matrix/config/homeserver.yaml`:
```yaml
redis:
  enabled: true
  host: 192.168.8.103
  port: 6379
  dbid: 4
  password: "REDIS_PASSWORD"
```

Redis is used for:
- User presence tracking
- Session synchronization
- Push notification queue

## Troubleshooting

### Check Redis Connectivity

From any machine with access to LXC_HOME:
```bash
# Connect to Redis and check all databases
ssh -A akunito@192.168.8.80

# Check specific database key count
docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n 3 DBSIZE

# List keys in a database
docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n 3 KEYS '*'

# Check TTL of a key
docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n 3 TTL 'key_name'
```

### Check All Database Sizes

```bash
for db in 0 1 2 3 4; do
  echo "db$db: $(docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n $db DBSIZE 2>/dev/null)"
done
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `NOAUTH Authentication required` | Wrong password | Check `secrets/domains.nix` for correct password |
| Keys in wrong database | Missing dbindex config | Add `dbindex` to service config and restart |
| Empty database after restart | Service not caching | Trigger service activity (access web UI) |
| Connection refused | Redis not running | Check `systemctl status redis` on LXC_database |

### Verify Service Health

**Portfolio**:
```bash
curl -s https://portfolio.akunito.com/api/health | jq
# Expected: {"cache": "redis", "cacheDetails": {"redisConnected": true}}
```

**Nextcloud**:
```bash
docker exec -u www-data nextcloud-app php occ status
# No Redis errors = working
```

**LiftCraft**:
```bash
docker exec leftyworkout_test-backend-1 bin/rails runner "puts Rails.cache.class"
# Expected: ActiveSupport::Cache::RedisCacheStore
```

## Backup Considerations

- PostgreSQL: Managed via NixOS PostgreSQL backup service
- Redis: Data is cache-only, no backup required (services rebuild cache on restart)

## Related Documentation

- [Monitoring Stack](./monitoring-stack.md) - Prometheus metrics for database/Redis
- [LiftCraft Service](./liftcraft.md) - Rails application setup
- [Homelab Stack](./homelab-stack.md) - Nextcloud and other services
- [Matrix Server](./matrix.md) - Matrix Synapse + Element + Claude Bot
