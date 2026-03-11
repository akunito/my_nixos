# Gather Database Credentials

Skill for verifying database credentials on VPS_PROD match the centralized secrets in secrets/domains.nix.

## Purpose

Use this skill to:
- Verify deployed database passwords on VPS match secrets/domains.nix
- Check PostgreSQL, MariaDB, and Redis user accounts and connectivity
- Audit database access and connection strings
- Troubleshoot authentication failures after deployment

---

## Architecture Overview

All databases run as **NixOS native services** on VPS_PROD (not Docker containers).

| Service | Host | Port | Description |
|---------|------|------|-------------|
| PostgreSQL | 127.0.0.1 | 5432 | Primary relational database |
| MariaDB | 127.0.0.1 | 3306 | Nextcloud database |
| Redis | 127.0.0.1 | 6379 | Caching and session store |
| PgBouncer | 127.0.0.1 | 6432 | PostgreSQL connection pooler |

**SSH Target**: `ssh -A -p 56777 akunito@100.64.0.6`

---

## Database Inventory

### PostgreSQL Databases (VPS localhost:5432)

| Database | User | Service | Password File |
|----------|------|---------|---------------|
| plane | plane | Plane project management | /etc/secrets/db-plane-password |
| rails_database_prod | liftcraft | LiftCraft fitness app | /etc/secrets/db-liftcraft-password |
| nextcloud | nextcloud | Nextcloud (via PgBouncer or direct) | /etc/secrets/db-nextcloud-password |
| matrix | matrix | Matrix Synapse homeserver | /etc/secrets/db-matrix-password |
| freshrss | freshrss | FreshRSS feed reader | /etc/secrets/db-freshrss-password |

### MariaDB Databases (VPS localhost:3306)

| Database | User | Service | Password File |
|----------|------|---------|---------------|
| nextcloud | nextcloud | Nextcloud (legacy/alternate) | /etc/secrets/db-nextcloud-password |

### Redis Databases (VPS localhost:6379)

| DB | Service | Notes |
|----|---------|-------|
| db0 | Plane | Plane cache |
| db1 | Nextcloud | Nextcloud session/cache |
| db2 | LiftCraft | Sidekiq job queue |
| db3 | FreshRSS | FreshRSS cache |
| db4 | Matrix Synapse | Synapse replication/cache |

---

## Verification Commands

### 1. Check PostgreSQL Users and Databases

```bash
# List all PostgreSQL users
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -c '\du'"

# List all databases
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -c '\l'"
```

Expected users: postgres, plane, liftcraft, nextcloud, matrix, freshrss, pgbouncer

### 2. Test PostgreSQL Passwords

```bash
# Test plane user
ssh -A -p 56777 akunito@100.64.0.6 "PGPASSWORD=\$(sudo cat /etc/secrets/db-plane-password) psql -h 127.0.0.1 -U plane -d plane -c '\conninfo'"

# Test liftcraft user
ssh -A -p 56777 akunito@100.64.0.6 "PGPASSWORD=\$(sudo cat /etc/secrets/db-liftcraft-password) psql -h 127.0.0.1 -U liftcraft -d rails_database_prod -c '\conninfo'"

# Test matrix user
ssh -A -p 56777 akunito@100.64.0.6 "PGPASSWORD=\$(sudo cat /etc/secrets/db-matrix-password) psql -h 127.0.0.1 -U matrix -d matrix -c '\conninfo'"

# Test nextcloud user
ssh -A -p 56777 akunito@100.64.0.6 "PGPASSWORD=\$(sudo cat /etc/secrets/db-nextcloud-password) psql -h 127.0.0.1 -U nextcloud -d nextcloud -c '\conninfo'"

# Test freshrss user
ssh -A -p 56777 akunito@100.64.0.6 "PGPASSWORD=\$(sudo cat /etc/secrets/db-freshrss-password) psql -h 127.0.0.1 -U freshrss -d freshrss -c '\conninfo'"
```

### 3. Check MariaDB Users

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo mysql -e 'SELECT User, Host FROM mysql.user;'"
```

### 4. Test MariaDB Password

```bash
ssh -A -p 56777 akunito@100.64.0.6 "mysql -h 127.0.0.1 -u nextcloud -p\$(sudo cat /etc/secrets/db-nextcloud-password) -e 'SELECT 1'"
```

### 5. Check Redis Auth

```bash
# Test Redis authentication
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) ping"

# Check all Redis database sizes
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) INFO keyspace"
```

### 6. Check PgBouncer

```bash
# Test PgBouncer connectivity
ssh -A -p 56777 akunito@100.64.0.6 "PGPASSWORD=\$(sudo cat /etc/secrets/db-plane-password) psql -h 127.0.0.1 -p 6432 -U plane -d plane -c '\conninfo'"
```

---

## All-in-One Verification Script

Run this to verify all credentials at once:

```bash
VPS_SSH="ssh -A -p 56777 akunito@100.64.0.6"

echo "=== PostgreSQL Users ==="
$VPS_SSH "sudo -u postgres psql -c '\du'" 2>/dev/null

echo ""
echo "=== PostgreSQL Databases ==="
$VPS_SSH "sudo -u postgres psql -c '\l'" 2>/dev/null

echo ""
echo "=== MariaDB Users ==="
$VPS_SSH "sudo mysql -e 'SELECT User, Host FROM mysql.user;'" 2>/dev/null

echo ""
echo "=== Redis Ping ==="
$VPS_SSH "redis-cli -a \$(sudo cat /etc/secrets/redis-password) ping" 2>/dev/null

echo ""
echo "=== Redis Keyspace ==="
$VPS_SSH "redis-cli -a \$(sudo cat /etc/secrets/redis-password) INFO keyspace" 2>/dev/null

echo ""
echo "=== Secret Files ==="
$VPS_SSH "sudo ls -la /etc/secrets/" 2>/dev/null

echo ""
echo "=== Current secrets/domains.nix database section ==="
grep -A 20 "CENTRALIZED DATABASE SERVER" secrets/domains.nix | head -25
```

---

## Secrets Architecture

### File Locations

| File | Purpose | Encryption |
|------|---------|------------|
| `secrets/domains.nix` | Actual credentials | git-crypt encrypted |
| `secrets/domains.nix.template` | Structure reference | Public (no real values) |
| `system/app/database-secrets.nix` | Deployment module | Public |

### How Secrets Get Deployed

1. **Credentials defined** in `secrets/domains.nix` (source of truth)
2. **`database-secrets.nix` module** reads secrets and writes to `/etc/secrets/*` on VPS
3. **NixOS services** (PostgreSQL, MariaDB, Redis) reference password files
4. **Deploy** via `./install.sh ~/.dotfiles VPS_PROD -s -u -d`

The `database-secrets.nix` module creates:
- `/etc/secrets/db-plane-password` (PostgreSQL)
- `/etc/secrets/db-liftcraft-password` (PostgreSQL)
- `/etc/secrets/db-nextcloud-password` (MariaDB/PostgreSQL)
- `/etc/secrets/db-matrix-password` (PostgreSQL)
- `/etc/secrets/db-freshrss-password` (PostgreSQL)
- `/etc/secrets/redis-password` (Redis)

### Current Secret Variables

```nix
# In secrets/domains.nix (encrypted):

# PostgreSQL
dbPlanePassword = "...";
dbLiftcraftPassword = "...";
dbMatrixPassword = "...";
dbNextcloudPassword = "...";
dbFreshrssPassword = "...";

# Redis
redisServerPassword = "...";
```

---

## Deployment Target

After verifying or updating credentials, deploy to VPS_PROD:

```bash
git add secrets/domains.nix && git commit -m "chore: update database credentials" && git push
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

---

## Output Format

When reporting gathered credentials, use this format:

```markdown
## Database Credentials Report - [DATE]

### PostgreSQL (VPS localhost:5432)
| Service | User | Database | Password Verified |
|---------|------|----------|-------------------|
| Plane | plane | plane | yes/no |
| LiftCraft | liftcraft | rails_database_prod | yes/no |
| Matrix | matrix | matrix | yes/no |
| Nextcloud | nextcloud | nextcloud | yes/no |
| FreshRSS | freshrss | freshrss | yes/no |

### MariaDB (VPS localhost:3306)
| Service | User | Database | Password Verified |
|---------|------|----------|-------------------|
| Nextcloud | nextcloud | nextcloud | yes/no |

### Redis (VPS localhost:6379)
| DB | Service | Has Password | Verified |
|----|---------|--------------|----------|
| db0 | Plane | Yes | yes/no |
| db1 | Nextcloud | Yes | yes/no |
| db2 | LiftCraft | Yes | yes/no |
| db3 | FreshRSS | Yes | yes/no |
| db4 | Matrix | Yes | yes/no |

### Actions Taken
- [x] Verified secrets/domains.nix matches deployed passwords
- [x] All PostgreSQL users authenticated successfully
- [x] MariaDB users authenticated successfully
- [x] Redis authentication verified
```
