# Update DBeaver Configuration

Skill for updating DBeaver database connections to match the VPS database server configuration.

## Purpose

Use this skill to:
- Add new database connections to DBeaver when databases are added to VPS
- Sync DBeaver configuration with secrets/domains.nix credentials
- Verify DBeaver can connect to all configured databases

---

## Configuration Files

### DBeaver Configuration Location

```
~/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json
```

### Source of Truth

- **Database server:** VPS (databases run on VPS localhost, accessed via Tailscale)
- **DBeaver connects to:** 100.64.0.6 (VPS Tailscale IP)
- **Credentials:** `secrets/domains.nix` (git-crypt encrypted)
- **Profile configuration:** `profiles/VPS_PROD-config.nix`

---

## Current Database Configuration

### PostgreSQL Databases (Port 5432 / 6432 via PgBouncer)

| Database | User | Password Variable |
|----------|------|-------------------|
| plane | plane | dbPlanePassword |
| rails_database_prod | liftcraft | dbLiftcraftPassword |
| nextcloud | nextcloud | dbNextcloudPassword |
| matrix | matrix | dbMatrixPassword |
| freshrss | freshrss | dbFreshrssPassword |

### Redis (Port 6379)

| DB Index | Purpose | Password Variable |
|----------|---------|-------------------|
| db0 | Plane | redisServerPassword |
| db1 | Nextcloud | redisServerPassword |
| db2 | LiftCraft | redisServerPassword |
| db4 | Matrix | redisServerPassword |

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
"postgres-jdbc-vps-<name>-db": {
    "provider": "postgresql",
    "driver": "postgres-jdbc",
    "name": "VPS - <Name> (PostgreSQL)",
    "save-password": true,
    "folder": "VPS",
    "configuration": {
        "host": "100.64.0.6",
        "port": "5432",
        "database": "<database_name>",
        "user": "<username>",
        "url": "jdbc:postgresql://100.64.0.6:5432/<database_name>",
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

### Step 4: Restart DBeaver

After updating the configuration:
1. Close DBeaver completely
2. Reopen DBeaver
3. Navigate to the "VPS" folder in the Database Navigator
4. Double-click each new connection to test
5. Enter password when prompted (check "Save password")

---

## Adding a New Database to VPS

When adding a new database to the VPS database server:

### 1. Update VPS_PROD Profile

Edit `profiles/VPS_PROD-config.nix`:

```nix
# Add to postgresqlServerDatabases
postgresqlServerDatabases = [ "plane" "rails_database_prod" "nextcloud" "matrix" "freshrss" "new_database" ];

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

### 3. Deploy to VPS

```bash
# IMPORTANT: Commit and push changes first, then deploy via install.sh
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

### 4. Update Workstation Profiles

Add credentials to `profiles/DESK-config.nix` and `profiles/LAPTOP_X13-config.nix`:

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

# LAPTOP_X13
ssh -A akunito@192.168.8.92 "cd ~/.dotfiles && git pull && ./sync-user.sh"
```

### 6. Update DBeaver

Run this skill to add the new connection to DBeaver.

---

## Verification Commands

### Test PostgreSQL Connection

```bash
# Using ~/.pgpass (passwordless after Home Manager rebuild)
psql -h 100.64.0.6 -U plane -d plane -c 'SELECT 1;'
psql -h 100.64.0.6 -U liftcraft -d rails_database_prod -c 'SELECT 1;'
psql -h 100.64.0.6 -U nextcloud -d nextcloud -c 'SELECT 1;'
psql -h 100.64.0.6 -U matrix -d matrix -c 'SELECT 1;'
psql -h 100.64.0.6 -U freshrss -d freshrss -c 'SELECT 1;'

# Via PgBouncer
psql -h 100.64.0.6 -p 6432 -U plane -d plane -c 'SELECT 1;'
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
psql-nextcloud    # Connect to Nextcloud database
psql-matrix       # Connect to Matrix database
psql-freshrss     # Connect to FreshRSS database
redis-db          # Connect to Redis
```

---

## Troubleshooting

### DBeaver Can't Connect

1. Verify VPS database services are running:
   ```bash
   ssh -A -p 56777 akunito@100.64.0.6 "systemctl status postgresql redis"
   ```

2. Test network connectivity to VPS via Tailscale:
   ```bash
   nc -zv 100.64.0.6 5432
   nc -zv 100.64.0.6 6379
   ```

3. Check Tailscale connectivity:
   ```bash
   tailscale ping 100.64.0.6
   tailscale status
   ```

4. Check VPS firewall:
   ```bash
   ssh -A -p 56777 akunito@100.64.0.6 "sudo iptables -L -n | grep -E '5432|6379'"
   ```

### Password Not Working

1. Verify password in secrets:
   ```bash
   cat ~/.dotfiles/secrets/domains.nix | grep dbPlanePassword
   ```

2. Compare with deployed secret on VPS:
   ```bash
   ssh -A -p 56777 akunito@100.64.0.6 "sudo cat /etc/secrets/db-plane-password"
   ```

3. Test directly:
   ```bash
   PGPASSWORD='<password>' psql -h 100.64.0.6 -U plane -d plane -c 'SELECT 1;'
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
- `profiles/VPS_PROD-config.nix` - VPS database server configuration
- `profiles/DESK-config.nix` - DESK workstation profile (includes dbCredentials)
- `profiles/LAPTOP_X13-config.nix` - Laptop profile (includes dbCredentials)
- `user/app/database/db-credentials.nix` - Home Manager module for credential files
- `~/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json` - DBeaver connections
