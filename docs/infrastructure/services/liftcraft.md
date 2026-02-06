---
id: infrastructure.services.liftcraft
summary: LiftCraft (LeftyWorkout) - Training plan management Rails application
tags: [infrastructure, liftcraft, leftyworkout, rails, docker, redis]
related_files: [profiles/LXC_liftcraftTEST-config.nix, secrets/domains.nix]
---

# LiftCraft (LeftyWorkout)

Training plan management system built with Rails 8 and React, running on LXC_liftcraftTEST (192.168.8.87).

---

## Overview

LiftCraft is a full-stack web application for athletes and coaches to manage training plans, workouts, and track performance metrics.

| Property | Value |
|----------|-------|
| Host | LXC_liftcraftTEST (192.168.8.87) |
| Repository | `~/leftyworkout_TEST` |
| Branch | `Test` |
| Framework | Rails 8 + React + TypeScript |
| Database | PostgreSQL (LXC_database, 192.168.8.103) |
| Cache/WebSockets | Redis (LXC_database, 192.168.8.103:6379/2) |

---

## Services

### Backend (Rails 8 API)

| Property | Value |
|----------|-------|
| Container | leftyworkout_test-backend-1 |
| Port | 3000 |
| Environment | `test` (RAILS_ENV) |
| Database | `rails_database_test` on 192.168.8.103 |
| Redis DB | 2 (db0=Plane, db1=Nextcloud) |

### Frontend (React SPA)

| Property | Value |
|----------|-------|
| Container | leftyworkout_test-frontend-1 |
| Port | 3001 |
| Environment | `production` (NODE_ENV) |

---

## Infrastructure Dependencies

### PostgreSQL (Centralized)

- **Host**: 192.168.8.103 (LXC_database)
- **Database**: `rails_database_test`
- **User**: `liftcraft`
- **Password**: Stored in `secrets/domains.nix` as `dbLiftcraftPassword`

### Redis (Centralized)

- **Host**: 192.168.8.103:6379 (LXC_database)
- **Database**: db2 (shared server)
- **Password**: Stored in `secrets/domains.nix` as `redisServerPassword`
- **URL Format**: `redis://:PASSWORD%3D@192.168.8.103:6379/2`
  - Note: `=` in password is URL-encoded as `%3D`

**Redis Usage**:
- Action Cable (WebSockets) for real-time updates
- Rails cache store for caching

---

## Environment Files

| File | Purpose |
|------|---------|
| `.env.test` | TEST environment configuration |
| `.env.prod` | PROD environment configuration (future) |
| `.env.dev` | Development configuration (local) |

All environment files are encrypted with git-crypt.

---

## Docker Compose

Scripts wrap docker-compose with correct environment:

```bash
# Test environment
./docker-compose.test.sh up -d
./docker-compose.test.sh logs -f backend
./docker-compose.test.sh exec backend bundle exec rails console

# Build after code changes
./docker-compose.test.sh build backend
./docker-compose.test.sh up -d
```

---

## Access URLs

| Environment | Frontend | Backend API |
|-------------|----------|-------------|
| TEST | https://leftyworkout-test.akunito.com | https://leftyworkout-test.akunito.com/api |
| PROD | https://leftyworkout.akunito.com | https://leftyworkout.akunito.com/api |

---

## Verification Commands

### Test Redis Connectivity

```bash
./docker-compose.test.sh exec backend bundle exec rails runner '
redis = Redis.new(url: ENV["REDIS_URL"])
puts "Redis PING: #{redis.ping}"
'
```

### Test Action Cable

```bash
./docker-compose.test.sh exec backend bundle exec rails runner '
ActionCable.server.pubsub.send(:redis_connection)
puts "Action Cable Redis: OK"
'
```

### Test Cache Store

```bash
./docker-compose.test.sh exec backend bundle exec rails runner '
Rails.cache.write("test_key", "test_value", expires_in: 60)
result = Rails.cache.read("test_key")
puts "Cache test: #{result == \"test_value\" ? \"OK\" : \"FAILED\"}"
Rails.cache.delete("test_key")
'
```

### Check Container Status

```bash
ssh akunito@192.168.8.87 "cd ~/leftyworkout_TEST && docker ps"
```

### View Backend Logs

```bash
./docker-compose.test.sh logs -f backend
```

---

## Deployment

### From Local Machine

```bash
ssh -A akunito@192.168.8.87 "cd ~/leftyworkout_TEST && git pull && ./docker-compose.test.sh build backend && ./docker-compose.test.sh up -d"
```

### Database Migrations

```bash
./docker-compose.test.sh exec backend bundle exec rails db:migrate
```

---

## Troubleshooting

### Backend Container Won't Start

1. Check logs: `./docker-compose.test.sh logs backend`
2. Verify database connectivity: Check PostgreSQL at 192.168.8.103
3. Verify Redis connectivity: Test REDIS_URL

### Redis Connection Issues

1. Verify password matches server: `ssh 192.168.8.103 "sudo cat /run/redis-homelab/nixos.conf | grep requirepass"`
2. Check URL encoding: `=` must be `%3D` in REDIS_URL
3. Test direct connection: `redis-cli -a 'PASSWORD=' -n 2 PING`

### Bundle/Gem Issues

If gems are missing after Gemfile changes:
```bash
./docker-compose.test.sh down -v  # Remove volumes
./docker-compose.test.sh build backend  # Rebuild image
./docker-compose.test.sh up -d
```

---

## Related Documentation

- [Redis Configuration Skill](~/leftyworkout_TEST/.claude/commands/redis-config.md)
- [LiftCraft README](~/leftyworkout_TEST/README.md)
- [LXC_database Profile](profiles/LXC_database-config.nix)
