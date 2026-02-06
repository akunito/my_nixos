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
| LXC_HOME | Nextcloud | 192.168.8.80 | Docker container env (inspect) |

### Redis/Valkey

| Container | Service | SSH Target | Config Location |
|-----------|---------|------------|-----------------|
| LXC_plane | Plane (Valkey) | 192.168.8.86 | ~/PLANE/docker-compose.yml |
| LXC_HOME | Nextcloud (Redis) | 192.168.8.80 | ~/.homelab/homelab/docker-compose.yml |

---

## Gather Commands

### 1. LiftCraft PostgreSQL (LXC_liftcraftTEST)

```bash
# Get database credentials
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
# Get database credentials
ssh -A akunito@192.168.8.86 "grep -E '^(POSTGRES_|PGUSER_SUPERUSER_PASSWORD)' ~/PLANE/.env"
```

Expected format:
```
POSTGRES_USER=plane
POSTGRES_PASSWORD=<password>
POSTGRES_DB=plane
```

### 3. Nextcloud MariaDB (LXC_HOME)

```bash
# Get password from running container (most reliable)
ssh -A akunito@192.168.8.80 "docker inspect nextcloud-db 2>/dev/null | grep -E 'MYSQL_ROOT_PASSWORD|MYSQL_PASSWORD' | head -3"
```

Expected format:
```
"MYSQL_ROOT_PASSWORD=<root_password>",
"MYSQL_PASSWORD=<password>",
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
ssh -A -o ConnectTimeout=10 akunito@192.168.8.87 "grep -E 'POSTGRES_PASSWORD' ~/leftyworkout_TEST/.env.prod 2>/dev/null || grep -E 'POSTGRES_PASSWORD' ~/leftyworkout_TEST/.env" 2>/dev/null

echo ""
echo "=== Plane (LXC_plane - 192.168.8.86) ==="
ssh -A -o ConnectTimeout=10 akunito@192.168.8.86 "grep -E 'POSTGRES_PASSWORD' ~/PLANE/.env" 2>/dev/null

echo ""
echo "=== Nextcloud MariaDB (LXC_HOME - 192.168.8.80) ==="
ssh -A -o ConnectTimeout=10 akunito@192.168.8.80 "docker inspect nextcloud-db 2>/dev/null | grep 'MYSQL_PASSWORD' | head -1"

echo ""
echo "=== Current secrets/domains.nix database section ==="
grep -A 15 "CENTRALIZED DATABASE SERVER" secrets/domains.nix | head -20
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

1. **Gather credentials** from source containers (this skill)
2. **Update secrets/domains.nix** with the credentials
3. **Commit and push** to git repository
4. **Deploy to LXC_database** with `nixos-rebuild switch`

The `database-secrets.nix` module reads from `secrets/domains.nix` and creates:
- `/etc/secrets/db-plane-password` (PostgreSQL)
- `/etc/secrets/db-liftcraft-password` (PostgreSQL)
- `/etc/secrets/db-nextcloud-password` (MariaDB)
- `/etc/secrets/redis-password` (Redis)

### Current Secret Variables

```nix
# In secrets/domains.nix (encrypted):

# PostgreSQL
dbPlanePassword = "...";
dbLiftcraftPassword = "...";

# MariaDB
dbNextcloudPassword = "...";

# Redis
redisServerPassword = "...";
```

---

## Update Workflow

After gathering credentials:

```bash
# 1. Edit secrets/domains.nix with new values
vim secrets/domains.nix

# 2. Update template (structure only, no real values)
vim secrets/domains.nix.template

# 3. Verify encryption
git-crypt status secrets/domains.nix
# Expected: encrypted: secrets/domains.nix

# 4. Test syntax
nix-instantiate --parse secrets/domains.nix

# 5. Commit and push
git add secrets/domains.nix secrets/domains.nix.template
git commit -m "chore: update database credentials"
git push

# 6. Deploy to LXC_database
ssh -A akunito@192.168.8.103 "cd ~/.dotfiles && git reset --hard HEAD && git pull && ./install.sh ~/.dotfiles LXC_database -s -u -q 2>&1"
```

---

## Verification After Deployment

```bash
# On LXC_database - verify password files exist
ssh -A akunito@192.168.8.103 "sudo ls -la /etc/secrets/"

# Verify PostgreSQL can authenticate
ssh -A akunito@192.168.8.103 "sudo -u postgres psql -c '\du'"

# Verify MariaDB users
ssh -A akunito@192.168.8.103 "sudo mysql -e 'SELECT User, Host FROM mysql.user;'"

# Verify Redis password
ssh -A akunito@192.168.8.103 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) ping"
```

---

## Output Format

When reporting gathered credentials, use this format:

```markdown
## Database Credentials Report - [DATE]

### PostgreSQL
| Service | User | Database | Password Verified |
|---------|------|----------|-------------------|
| Plane | plane | plane | ✓ |
| LiftCraft | liftcraft | rails_database_prod | ✓ |

### MariaDB
| Service | User | Database | Password Verified |
|---------|------|----------|-------------------|
| Nextcloud | nextcloud | nextcloud | ✓ |

### Redis
| Service | Has Password | Database Number |
|---------|--------------|-----------------|
| Plane | Yes (new) | db0 |
| Nextcloud | Yes (new) | db1 |
| LiftCraft | Yes (new) | db2 |

### Actions Taken
- [x] Updated secrets/domains.nix
- [x] Verified git-crypt encryption
- [x] Updated template file
- [x] Deployed to LXC_database
```
