# Update DBeaver Configuration

Skill for updating DBeaver database connections to match the centralized LXC_database server configuration.

## Purpose

Use this skill to:
- Add new database connections to DBeaver when databases are added to LXC_database
- Sync DBeaver configuration with secrets/domains.nix credentials
- Verify DBeaver can connect to all configured databases

---

## Configuration Files

### DBeaver Configuration Location

```
~/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json
```

### Source of Truth

- **Database server:** LXC_database (192.168.8.103)
- **Credentials:** `secrets/domains.nix` (git-crypt encrypted)
- **Profile configuration:** `profiles/LXC_database-config.nix`

---

## Current Database Configuration

### PostgreSQL Databases (Port 5432 / 6432 via PgBouncer)

| Database | User | Password Variable |
|----------|------|-------------------|
| plane | plane | dbPlanePassword |
| rails_database_prod | liftcraft | dbLiftcraftPassword |

### MariaDB Databases (Port 3306)

| Database | User | Password Variable |
|----------|------|-------------------|
| nextcloud | nextcloud | dbNextcloudPassword |

### Redis (Port 6379)

| DB Index | Purpose | Password Variable |
|----------|---------|-------------------|
| db0 | Plane | redisServerPassword |
| db1 | Nextcloud | redisServerPassword |
| db2 | LiftCraft | redisServerPassword |

---

## Update Procedure

### Step 1: Read Current Secrets

```bash
# View current database passwords (from secrets/domains.nix)
cat ~/.dotfiles/secrets/domains.nix | grep -E "^  db|^  redis"
```

### Step 2: Update DBeaver Configuration

The DBeaver configuration is at:
```
~/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json
```

**Important:** DBeaver encrypts passwords separately. The `data-sources.json` only contains connection metadata. Users must enter passwords on first connection.

### Step 3: Add New Connection to DBeaver

To add a new PostgreSQL database connection, add this to the `connections` object:

```json
"postgres-jdbc-lxc-<name>-db": {
    "provider": "postgresql",
    "driver": "postgres-jdbc",
    "name": "LXC_database - <Name> (PostgreSQL)",
    "save-password": true,
    "folder": "LXC_database",
    "configuration": {
        "host": "192.168.8.103",
        "port": "5432",
        "database": "<database_name>",
        "user": "<username>",
        "url": "jdbc:postgresql://192.168.8.103:5432/<database_name>",
        "configurationType": "MANUAL",
        "type": "dev",
        "closeIdleConnection": true,
        "provider-properties": {
            "@dbeaver-show-non-default-db@": "true"
        },
        "auth-model": "native"
    }
}
```

To add a new MariaDB database connection:

```json
"mariadb-jdbc-lxc-<name>-db": {
    "provider": "mysql",
    "driver": "mariaDB",
    "name": "LXC_database - <Name> (MariaDB)",
    "save-password": true,
    "folder": "LXC_database",
    "configuration": {
        "host": "192.168.8.103",
        "port": "3306",
        "database": "<database_name>",
        "user": "<username>",
        "url": "jdbc:mariadb://192.168.8.103:3306/<database_name>",
        "configurationType": "MANUAL",
        "type": "dev",
        "closeIdleConnection": true,
        "auth-model": "native"
    }
}
```

### Step 4: Restart DBeaver

After updating the configuration:
1. Close DBeaver completely
2. Reopen DBeaver
3. Navigate to the "LXC_database" folder in the Database Navigator
4. Double-click each new connection to test
5. Enter password when prompted (check "Save password")

---

## Adding a New Database to LXC_database

When adding a new database to the centralized server:

### 1. Update LXC_database Profile

Edit `profiles/LXC_database-config.nix`:

```nix
# Add to postgresqlServerDatabases
postgresqlServerDatabases = [ "plane" "rails_database_prod" "new_database" ];

# Add user
postgresqlServerUsers = [
  # ... existing users ...
  {
    name = "new_user";
    passwordFile = "/etc/secrets/db-newdb-password";
    ensureDBOwnership = true;
  }
];
```

### 2. Update Secrets

Edit `secrets/domains.nix`:

```nix
dbNewdbPassword = "generated-secure-password";
```

### 3. Deploy to LXC_database

```bash
ssh -A akunito@192.168.8.103 "cd ~/.dotfiles && git pull && sudo nixos-rebuild switch --flake .#LXC_database --impure"
```

### 4. Update Workstation Profiles

Add credentials to `profiles/DESK-config.nix` and `profiles/LAPTOP_L15-config.nix`:

```nix
dbCredentialsPostgres = [
  # ... existing ...
  { database = "new_database"; user = "new_user"; password = secrets.dbNewdbPassword; }
];
```

### 5. Deploy to Workstations

```bash
# DESK
cd ~/.dotfiles && ./sync-user.sh

# LAPTOP_L15
ssh -A akunito@192.168.8.92 "cd ~/.dotfiles && git pull && ./sync-user.sh"
```

### 6. Update DBeaver

Run this skill to add the new connection to DBeaver.

---

## Verification Commands

### Test PostgreSQL Connection

```bash
# Using ~/.pgpass (passwordless after Home Manager rebuild)
psql -h 192.168.8.103 -U plane -d plane -c 'SELECT 1;'
psql -h 192.168.8.103 -U liftcraft -d rails_database_prod -c 'SELECT 1;'

# Via PgBouncer
psql -h 192.168.8.103 -p 6432 -U plane -d plane -c 'SELECT 1;'
```

### Test MariaDB Connection

```bash
# Using ~/.my.cnf (passwordless after Home Manager rebuild)
mysql -e 'SELECT 1;'
```

### Test Redis Connection

```bash
# Using credentials from ~/.redis-credentials
source ~/.redis-credentials
redis-cli -h $REDIS_HOST -p $REDIS_PORT -a "$REDIS_PASSWORD" ping
```

### Shell Aliases (After Home Manager Rebuild)

```bash
psql-plane        # Connect to Plane database
psql-liftcraft    # Connect to LiftCraft database
mysql-nextcloud   # Connect to Nextcloud database
redis-db          # Connect to Redis
```

---

## Troubleshooting

### DBeaver Can't Connect

1. Verify LXC_database is running:
   ```bash
   ssh -A akunito@192.168.8.103 "systemctl status postgresql mysql redis-homelab"
   ```

2. Test network connectivity:
   ```bash
   nc -zv 192.168.8.103 5432
   nc -zv 192.168.8.103 3306
   nc -zv 192.168.8.103 6379
   ```

3. Check firewall:
   ```bash
   ssh -A akunito@192.168.8.103 "sudo iptables -L -n | grep -E '5432|3306|6379'"
   ```

### Password Not Working

1. Verify password in secrets:
   ```bash
   cat ~/.dotfiles/secrets/domains.nix | grep dbPlanePassword
   ```

2. Compare with deployed secret:
   ```bash
   ssh -A akunito@192.168.8.103 "sudo cat /etc/secrets/db-plane-password"
   ```

3. Test directly:
   ```bash
   PGPASSWORD='<password>' psql -h 192.168.8.103 -U plane -d plane -c 'SELECT 1;'
   ```

### ~/.pgpass Not Working

1. Check file exists and has correct permissions:
   ```bash
   ls -la ~/.pgpass
   # Should be -rw------- (600)
   ```

2. Rebuild Home Manager:
   ```bash
   cd ~/.dotfiles && ./sync-user.sh
   ```

---

## Related Files

- `secrets/domains.nix` - Database passwords (git-crypt encrypted)
- `profiles/LXC_database-config.nix` - Centralized database server configuration
- `profiles/DESK-config.nix` - DESK workstation profile (includes dbCredentials)
- `profiles/LAPTOP_L15-config.nix` - Laptop profile (includes dbCredentials)
- `user/app/database/db-credentials.nix` - Home Manager module for credential files
- `~/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json` - DBeaver connections
