# Gather Database Credentials

Skill for gathering database credentials from all application containers and centralizing them in secrets/domains.nix.

## Purpose

Use this skill to:
- Extract PostgreSQL, MariaDB, and Redis credentials from all LXC containers
- Identify current database users, passwords, and connection strings
- Compare with centralized secrets/domains.nix
- Prepare for database migrations

---

## Credential Sources

### PostgreSQL Databases

| Container | Service | SSH Target | Config Location |
|-----------|---------|------------|-----------------|
| LXC_plane | Plane | 192.168.8.86 | ~/PLANE/.env |
| LXC_liftcraftTEST | LiftCraft | 192.168.8.87 | ~/leftyworkout_TEST/.env.prod |

### MariaDB Databases

| Container | Service | SSH Target | Config Location |
|-----------|---------|------------|-----------------|
| LXC_HOME | Nextcloud | 192.168.8.80 | ~/.homelab/env/homelab/env/nextcloud-db.env |

### Redis/Valkey

| Container | Service | SSH Target | Config Location |
|-----------|---------|------------|-----------------|
| LXC_plane | Plane (Valkey) | 192.168.8.86 | ~/PLANE/docker-compose.yml |
| LXC_HOME | Nextcloud (Redis) | 192.168.8.80 | ~/.homelab/homelab/docker-compose.yml |

---

## Gather Commands

### 1. LiftCraft PostgreSQL (LXC_liftcraftTEST)

```bash
# Get full env file
ssh -A akunito@192.168.8.87 "cat ~/leftyworkout_TEST/.env.prod 2>/dev/null || cat ~/leftyworkout_TEST/.env"

# Extract just database credentials
ssh -A akunito@192.168.8.87 "grep -E '^(POSTGRES_|DB_|DATABASE_)' ~/leftyworkout_TEST/.env.prod 2>/dev/null || grep -E '^(POSTGRES_|DB_|DATABASE_)' ~/leftyworkout_TEST/.env"
```

Expected format:
```
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<password>
POSTGRES_DB=rails_database_prod
```

### 2. Plane PostgreSQL (LXC_plane)

```bash
# Get full env file
ssh -A akunito@192.168.8.86 "cat ~/PLANE/.env"

# Extract just database credentials
ssh -A akunito@192.168.8.86 "grep -E '^(POSTGRES_|REDIS_|RABBITMQ_)' ~/PLANE/.env"
```

Expected format:
```
POSTGRES_USER=plane
POSTGRES_PASSWORD=<password>
POSTGRES_DB=plane
```

### 3. Nextcloud MariaDB (LXC_HOME)

```bash
# Get database env file
ssh -A akunito@192.168.8.80 "cat ~/.homelab/env/homelab/env/nextcloud-db.env"
```

Expected format:
```
MYSQL_ROOT_PASSWORD=<root_password>
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
MYSQL_PASSWORD=<password>
```

### 4. Redis/Valkey Config

```bash
# Plane Valkey (check for password)
ssh -A akunito@192.168.8.86 "grep -i 'redis' ~/PLANE/.env ~/PLANE/docker-compose.yml | head -20"

# Nextcloud Redis (check for password)
ssh -A akunito@192.168.8.80 "grep -A5 'nextcloud-redis' ~/.homelab/homelab/docker-compose.yml"
```

---

## All-in-One Gather Script

Run this to gather all credentials at once:

```bash
echo "=== LiftCraft (LXC_liftcraftTEST - 192.168.8.87) ==="
ssh -A -o ConnectTimeout=10 akunito@192.168.8.87 "grep -E '^(POSTGRES_|DB_|DATABASE_)' ~/leftyworkout_TEST/.env.prod 2>/dev/null || grep -E '^(POSTGRES_|DB_|DATABASE_)' ~/leftyworkout_TEST/.env" 2>/dev/null

echo ""
echo "=== Plane (LXC_plane - 192.168.8.86) ==="
ssh -A -o ConnectTimeout=10 akunito@192.168.8.86 "grep -E '^(POSTGRES_|REDIS_URL)' ~/PLANE/.env" 2>/dev/null

echo ""
echo "=== Nextcloud (LXC_HOME - 192.168.8.80) ==="
ssh -A -o ConnectTimeout=10 akunito@192.168.8.80 "cat ~/.homelab/env/homelab/env/nextcloud-db.env" 2>/dev/null

echo ""
echo "=== Current secrets/domains.nix database section ==="
grep -A 15 "CENTRALIZED DATABASE SERVER" secrets/domains.nix | head -20
```

---

## Secrets File Location

All gathered credentials should be stored in:
- `secrets/domains.nix` (git-crypt encrypted)
- `secrets/domains.nix.template` (public template without real values)

### Current Secret Variables

```nix
# PostgreSQL
dbPlanePassword = "...";
dbLiftcraftPassword = "...";

# MariaDB
dbNextcloudPassword = "...";

# Redis
redisServerPassword = "...";
```

---

## Verification After Update

```bash
# Verify secrets file is encrypted
git-crypt status secrets/domains.nix

# Test syntax
nix-instantiate --parse secrets/domains.nix

# Compare with template
diff <(grep -oE '\w+Password|Password\w+' secrets/domains.nix | sort -u) \
     <(grep -oE '\w+Password|Password\w+' secrets/domains.nix.template | sort -u)
```

---

## Output Format

When reporting gathered credentials, use this format:

```markdown
## Database Credentials Report - [DATE]

### PostgreSQL
| Service | User | Database | Password Source |
|---------|------|----------|-----------------|
| Plane | plane | plane | LXC_plane/.env |
| LiftCraft | liftcraft | rails_database_prod | LXC_liftcraftTEST/.env.prod |

### MariaDB
| Service | User | Database | Password Source |
|---------|------|----------|-----------------|
| Nextcloud | nextcloud | nextcloud | LXC_HOME/nextcloud-db.env |

### Redis
| Service | Has Password | Database Number |
|---------|--------------|-----------------|
| Plane | No | db0 |
| Nextcloud | No | db1 |
| LiftCraft | No | db2 |

### Actions Needed
- [ ] Update secrets/domains.nix with new passwords
- [ ] Verify git-crypt encryption
- [ ] Update template file
```
