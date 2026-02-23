# Deploy Database Secrets

Skill for deploying database credentials from git-crypt encrypted secrets to the VPS.

## Purpose

Use this skill to:
- Deploy updated credentials to `/etc/secrets/` on VPS_PROD
- Verify secret files have correct permissions
- Restart database services after credential changes
- Troubleshoot credential deployment issues

---

## Architecture Overview

```
secrets/domains.nix          ->  database-secrets.nix  ->  /etc/secrets/*
(git-crypt encrypted)           (NixOS module)            (on VPS_PROD)
```

### Files Involved

| File | Location | Purpose |
|------|----------|---------|
| `secrets/domains.nix` | dotfiles repo | Source of truth (encrypted) |
| `system/app/database-secrets.nix` | dotfiles repo | Deployment module |
| `/etc/secrets/db-*-password` | VPS_PROD | Password files for services |

### Deployed Secret Files

| File | Service | Permissions | Owner |
|------|---------|-------------|-------|
| `/etc/secrets/db-plane-password` | PostgreSQL | 0440 | root:postgres |
| `/etc/secrets/db-liftcraft-password` | PostgreSQL | 0440 | root:postgres |
| `/etc/secrets/db-nextcloud-password` | MariaDB | 0440 | root:mysql |
| `/etc/secrets/db-matrix-password` | PostgreSQL | 0440 | root:postgres |
| `/etc/secrets/redis-password` | Redis | 0444 | root:root |

---

## Deployment Steps

### 1. Verify Local Changes

```bash
# In dotfiles directory
cd ~/.dotfiles

# Check secrets file syntax
nix-instantiate --parse secrets/domains.nix

# Verify git-crypt encryption status
git-crypt status secrets/domains.nix
# Expected: encrypted: secrets/domains.nix

# Review changes
git diff secrets/domains.nix
```

### 2. Commit and Push

```bash
# Stage and commit
git add secrets/domains.nix
git commit -m "chore: update database credentials"
git push
```

### 3. Deploy to VPS_PROD

```bash
# SSH to VPS and deploy using install.sh (NO -h flag — hardware-config must be regenerated)
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

### 4. Verify Deployment

```bash
# Check secret files exist with correct permissions
ssh -A -p 56777 akunito@100.64.0.6 "sudo ls -la /etc/secrets/"

# Expected output:
# -rw-r----- root postgres db-plane-password
# -rw-r----- root postgres db-liftcraft-password
# -rw-r----- root mysql    db-nextcloud-password
# -rw-r----- root postgres db-matrix-password
# -rw-r--r-- root root     redis-password
```

---

## One-Liner Deployment

Quick deploy command (run from dotfiles directory):

```bash
git add secrets/domains.nix && \
git commit -m "chore: update database credentials" && \
git push && \
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

---

## Verification Commands

### Check PostgreSQL Users

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -c '\du'"
```

Expected users: postgres, plane, liftcraft, matrix, nextcloud, freshrss, pgbouncer

### Check MariaDB Users

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo mysql -e 'SELECT User, Host FROM mysql.user;'"
```

Expected users: nextcloud, root, exporter

### Check Redis Auth

```bash
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) ping"
```

Expected: PONG

### Test PostgreSQL Password

```bash
# Test plane user
ssh -A -p 56777 akunito@100.64.0.6 "PGPASSWORD=\$(sudo cat /etc/secrets/db-plane-password) psql -h 127.0.0.1 -U plane -d plane -c '\conninfo'"

# Test liftcraft user
ssh -A -p 56777 akunito@100.64.0.6 "PGPASSWORD=\$(sudo cat /etc/secrets/db-liftcraft-password) psql -h 127.0.0.1 -U liftcraft -d rails_database_prod -c '\conninfo'"

# Test matrix user
ssh -A -p 56777 akunito@100.64.0.6 "PGPASSWORD=\$(sudo cat /etc/secrets/db-matrix-password) psql -h 127.0.0.1 -U matrix -d matrix -c '\conninfo'"
```

### Test MariaDB Password

```bash
ssh -A -p 56777 akunito@100.64.0.6 "mysql -h 127.0.0.1 -u nextcloud -p\$(sudo cat /etc/secrets/db-nextcloud-password) -e 'SELECT 1'"
```

---

## Troubleshooting

### Secret Files Missing

If `/etc/secrets/` is empty after deployment:

```bash
# Check if module is loaded
ssh -A -p 56777 akunito@100.64.0.6 "nixos-option services.postgresql.enable"

# Check systemd-tmpfiles ran
ssh -A -p 56777 akunito@100.64.0.6 "sudo systemd-tmpfiles --create"

# Manual check of /etc generation
ssh -A -p 56777 akunito@100.64.0.6 "ls -la /etc/static/secrets/ 2>/dev/null || echo 'No /etc/static/secrets'"
```

### Wrong Permissions

```bash
# Fix PostgreSQL password permissions
ssh -A -p 56777 akunito@100.64.0.6 "sudo chown root:postgres /etc/secrets/db-plane-password /etc/secrets/db-liftcraft-password /etc/secrets/db-matrix-password && sudo chmod 440 /etc/secrets/db-plane-password /etc/secrets/db-liftcraft-password /etc/secrets/db-matrix-password"

# Fix MariaDB password permissions
ssh -A -p 56777 akunito@100.64.0.6 "sudo chown root:mysql /etc/secrets/db-nextcloud-password && sudo chmod 440 /etc/secrets/db-nextcloud-password"
```

### Service Can't Read Password

```bash
# Restart services to pick up new credentials
ssh -A -p 56777 akunito@100.64.0.6 "sudo systemctl restart postgresql mysql redis-homelab"

# Check service status
ssh -A -p 56777 akunito@100.64.0.6 "systemctl status postgresql mysql redis-homelab"
```

### Git-Crypt Unlocked Check

If secrets appear garbled, git-crypt may not be unlocked:

```bash
# On VPS_PROD
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git-crypt status secrets/domains.nix"

# If locked, unlock with:
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git-crypt unlock ~/.git-crypt/dotfiles-key"
```

---

## Adding New Database Credentials

To add credentials for a new database service:

### 1. Add to secrets/domains.nix

```nix
# In secrets/domains.nix
dbNewServicePassword = "generate-strong-password-here";
```

### 2. Add to database-secrets.nix

Edit `system/app/database-secrets.nix`:

```nix
# Add under appropriate mkIf block
"secrets/db-newservice-password" = {
  text = secrets.dbNewServicePassword;
  mode = "0440";
  user = "root";
  group = "postgres";  # or "mysql" for MariaDB
};
```

### 3. Reference in Profile Config

Update `profiles/VPS_PROD-config.nix`:

```nix
postgresqlServerUsers = [
  # ... existing users ...
  {
    name = "newservice";
    passwordFile = "/etc/secrets/db-newservice-password";
    ensureDBOwnership = true;
  }
];
```

### 4. Update Template

Add to `secrets/domains.nix.template` (no real value):

```nix
dbNewServicePassword = "your-newservice-db-password";
```

### 5. Deploy

```bash
git add -A && git commit -m "feat: add newservice database credentials" && git push
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

---

## Password Rotation

To rotate passwords:

1. Generate new password
2. Update `secrets/domains.nix`
3. Deploy to VPS_PROD
4. Update application configs to use new password
5. Test connectivity

```bash
# Generate secure password
openssl rand -base64 32

# After updating secrets/domains.nix
git add secrets/domains.nix && git commit -m "security: rotate database passwords" && git push
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```
