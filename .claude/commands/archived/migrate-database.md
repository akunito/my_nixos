# Migrate Database

Skill for migrating databases from per-container Docker setups to the centralized LXC_database server.

## Purpose

Use this skill to:
- Backup databases from source containers
- Restore to centralized LXC_database
- Update application configurations
- Verify migration success

---

## Migration Order

1. **LiftCraft** (LXC_liftcraftTEST) - Lowest risk, test environment
2. **Plane** (LXC_plane) - Medium risk, internal tool
3. **Nextcloud** (LXC_HOME) - Highest risk, critical data

---

## Phase 1: LiftCraft Migration

### 1.1 Backup PostgreSQL from LXC_liftcraftTEST

```bash
# SSH to source container
ssh -A akunito@192.168.8.87

# Create backup
cd ~/leftyworkout_TEST
docker exec leftyworkout_test-db-1 pg_dump -U postgres -Fc rails_database_prod > /tmp/liftcraft_backup.dump

# Verify backup
ls -lah /tmp/liftcraft_backup.dump

# Copy to LXC_database
scp /tmp/liftcraft_backup.dump akunito@192.168.8.103:/tmp/
```

### 1.2 Restore to LXC_database

```bash
# SSH to LXC_database
ssh -A akunito@192.168.8.103

# Create database and user (should already exist from NixOS config)
sudo -u postgres createdb rails_database_prod 2>/dev/null || echo "Database exists"
sudo -u postgres createuser liftcraft 2>/dev/null || echo "User exists"

# Set password
password=$(cat /etc/secrets/db-liftcraft-password)
sudo -u postgres psql -c "ALTER USER liftcraft WITH PASSWORD '$password';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE rails_database_prod TO liftcraft;"

# Restore dump
sudo -u postgres pg_restore -d rails_database_prod /tmp/liftcraft_backup.dump

# Verify
sudo -u postgres psql -d rails_database_prod -c "\dt" | head -20
```

### 1.3 Update LiftCraft Configuration

```bash
# SSH to LXC_liftcraftTEST
ssh -A akunito@192.168.8.87
cd ~/leftyworkout_TEST

# Create migration branch
git checkout -b database_migration

# Update .env.prod
cat >> .env.prod.new << 'EOF'
# Database Configuration (External - LXC_database)
POSTGRES_USER=liftcraft
POSTGRES_PASSWORD=<from_secrets>
POSTGRES_DB=rails_database_prod
POSTGRES_HOST=192.168.8.103
DATABASE_URL=postgresql://liftcraft:<password>@192.168.8.103:6432/rails_database_prod

# Redis Configuration (External - LXC_database)
REDIS_URL=redis://:${REDIS_PASSWORD}@192.168.8.103:6379/2
EOF

# Update docker-compose.yml to remove db service
# ... manual edit required ...
```

### 1.4 Test LiftCraft Migration

```bash
# Stop old containers
docker compose down

# Start with external database
docker compose up -d

# Check logs
docker compose logs -f backend

# Test endpoint
curl -I http://localhost:3000
```

---

## Phase 2: Plane Migration

### 2.1 Backup PostgreSQL from LXC_plane

```bash
ssh -A akunito@192.168.8.86
cd ~/PLANE

# Backup database
docker exec plane-db pg_dump -U plane -Fc plane > /tmp/plane_backup.dump

# Copy to LXC_database
scp /tmp/plane_backup.dump akunito@192.168.8.103:/tmp/
```

### 2.2 Restore to LXC_database

```bash
ssh -A akunito@192.168.8.103

# Restore (database/user should exist from NixOS config)
password=$(cat /etc/secrets/db-plane-password)
sudo -u postgres psql -c "ALTER USER plane WITH PASSWORD '$password';"
sudo -u postgres pg_restore -d plane /tmp/plane_backup.dump

# Verify
sudo -u postgres psql -d plane -c "\dt" | head -20
```

### 2.3 Update Plane Configuration

```bash
ssh -A akunito@192.168.8.86
cd ~/PLANE

# Update .env
cat >> .env.migration << 'EOF'
# Database (External - LXC_database)
POSTGRES_HOST=192.168.8.103
DATABASE_URL=postgresql://plane:<password>@192.168.8.103:6432/plane

# Redis (External - LXC_database)
REDIS_URL=redis://:${REDIS_PASSWORD}@192.168.8.103:6379/0
EOF

# Update docker-compose.yml to remove plane-db and plane-redis services
```

---

## Phase 3: Nextcloud Migration

### 3.1 Backup MariaDB from LXC_HOME

```bash
ssh -A akunito@192.168.8.80
cd ~/.homelab

# Put Nextcloud in maintenance mode
docker exec -u www-data nextcloud-app php occ maintenance:mode --on

# Backup database
docker exec nextcloud-db mysqldump -u root -p'<root_password>' nextcloud > /tmp/nextcloud_backup.sql

# Verify backup
ls -lah /tmp/nextcloud_backup.sql
head -50 /tmp/nextcloud_backup.sql

# Copy to LXC_database
scp /tmp/nextcloud_backup.sql akunito@192.168.8.103:/tmp/
```

### 3.2 Restore to LXC_database

```bash
ssh -A akunito@192.168.8.103

# Create database and user
sudo mysql -e "CREATE DATABASE IF NOT EXISTS nextcloud;"
sudo mysql -e "CREATE USER IF NOT EXISTS 'nextcloud'@'192.168.8.%' IDENTIFIED BY '<password>';"
sudo mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'192.168.8.%';"

# Restore
sudo mysql nextcloud < /tmp/nextcloud_backup.sql

# Verify
sudo mysql -e "USE nextcloud; SHOW TABLES;" | head -20
```

### 3.3 Update Nextcloud Configuration

```bash
ssh -A akunito@192.168.8.80
cd ~/.homelab/homelab

# Update docker-compose.yml
# - Remove nextcloud-db service
# - Update nextcloud-app environment:
#   MYSQL_HOST=192.168.8.103
#   REDIS_HOST=192.168.8.103

# Update Nextcloud config.php if needed
docker exec -u www-data nextcloud-app php occ config:system:set dbhost --value="192.168.8.103"
docker exec -u www-data nextcloud-app php occ config:system:set redis host --value="192.168.8.103"
docker exec -u www-data nextcloud-app php occ config:system:set redis password --value="<redis_password>"
docker exec -u www-data nextcloud-app php occ config:system:set redis dbindex --value="1"

# Disable maintenance mode
docker exec -u www-data nextcloud-app php occ maintenance:mode --off
```

---

## Rollback Procedures

### PostgreSQL Rollback

```bash
# On source container, restart local database
docker compose up -d db

# Revert .env changes
git checkout .env.prod

# Restart application
docker compose restart backend
```

### MariaDB Rollback

```bash
# On LXC_HOME
docker compose up -d nextcloud-db

# Revert Nextcloud config
docker exec -u www-data nextcloud-app php occ config:system:set dbhost --value="nextcloud-db"
docker exec -u www-data nextcloud-app php occ maintenance:mode --off
```

---

## Post-Migration Cleanup

After successful migration and testing period (1-2 weeks):

```bash
# Remove old database containers
ssh -A akunito@192.168.8.87 "cd ~/leftyworkout_TEST && docker compose rm -f db"
ssh -A akunito@192.168.8.86 "cd ~/PLANE && docker compose rm -f plane-db plane-redis"
ssh -A akunito@192.168.8.80 "cd ~/.homelab/homelab && docker compose rm -f nextcloud-db nextcloud-redis"

# Remove old volumes (DANGEROUS - only after confirming migration success)
# docker volume rm leftyworkout_test_db-prod
# docker volume rm plane_plane_pgdata plane_plane_redisdata
# docker volume rm homelab_nextcloud-db homelab_nextcloud-redis
```

---

## Verification Checklist

After each migration:

- [ ] Application starts without errors
- [ ] Data is accessible (check a few records)
- [ ] New data can be created
- [ ] Redis caching works (sessions, cache)
- [ ] Prometheus exporters show metrics
- [ ] No error logs in application
- [ ] Performance is acceptable

---

## Output Format

```markdown
## Migration Report - [SERVICE] - [DATE]

### Pre-Migration State
- Source: [container:database]
- Database size: [X MB]
- Tables: [N]
- Rows (approx): [N]

### Migration Steps Completed
- [x] Backup created
- [x] Backup transferred
- [x] Database restored
- [x] User/permissions configured
- [x] Application config updated
- [x] Application restarted
- [x] Connectivity verified

### Post-Migration Verification
- [x] Application accessible
- [x] Data integrity verified
- [x] New records can be created
- [x] Prometheus metrics available

### Issues Encountered
- None / [List issues and resolutions]

### Rollback Status
- Not required / [Details if rollback was needed]
```
