# Deploy LXC Profile

Skill for deploying NixOS configurations to LXC containers via SSH.

## Purpose

Use this skill to:
- Deploy NixOS configuration changes to LXC containers
- Troubleshoot deployment failures
- Fix common deployment issues

---

## LXC Container Reference

| Container | IP Address | Profile Name | Description |
|-----------|------------|--------------|-------------|
| LXC_HOME | 192.168.8.80 | LXC_HOME | Homelab services (Nextcloud, media, etc.) |
| LXC_monitoring | 192.168.8.85 | LXC_monitoring | Grafana, Prometheus |
| LXC_plane | 192.168.8.86 | LXC_plane | Plane project management |
| LXC_liftcraftTEST | 192.168.8.87 | LXC_liftcraftTEST | LiftCraft test environment |
| LXC_portfolioprod | 192.168.8.88 | LXC_portfolioprod | Portfolio production |
| LXC_mailer | 192.168.8.89 | LXC_mailer | Postfix, Uptime Kuma |
| LXC_proxy | 192.168.8.102 | LXC_proxy | NPM, Cloudflared |
| LXC_database | 192.168.8.103 | LXC_database | PostgreSQL, MariaDB, Redis |

---

## Standard Deployment Workflow

### 1. Deploy to a Container

```bash
# Replace <IP> and <PROFILE> with values from the table above
ssh -A akunito@<IP> "cd ~/.dotfiles && git reset --hard HEAD && git pull && ./install.sh ~/.dotfiles <PROFILE> -s -u -q 2>&1"
```

### 2. Examples

```bash
# Deploy to LXC_database
ssh -A akunito@192.168.8.103 "cd ~/.dotfiles && git reset --hard HEAD && git pull && ./install.sh ~/.dotfiles LXC_database -s -u -q 2>&1"

# Deploy to LXC_monitoring
ssh -A akunito@192.168.8.85 "cd ~/.dotfiles && git reset --hard HEAD && git pull && ./install.sh ~/.dotfiles LXC_monitoring -s -u -q 2>&1"

# Deploy to LXC_HOME
ssh -A akunito@192.168.8.80 "cd ~/.dotfiles && git reset --hard HEAD && git pull && ./install.sh ~/.dotfiles LXC_HOME -s -u -q 2>&1"

# Deploy to LXC_proxy
ssh -A akunito@192.168.8.102 "cd ~/.dotfiles && git reset --hard HEAD && git pull && ./install.sh ~/.dotfiles LXC_proxy -s -u -q 2>&1"
```

---

## Install Script Flags

| Flag | Description |
|------|-------------|
| `-s` | System rebuild (nixos-rebuild switch) |
| `-u` | User rebuild (home-manager switch) |
| `-q` | Quick mode (skip Docker handling and hardware-configuration.nix generation) |
| `-d` | Debug mode (verbose output) |

---

## Troubleshooting Common Issues

### Git Conflicts on Remote

If git pull fails due to local changes:

```bash
ssh -A akunito@<IP> "cd ~/.dotfiles && git status"
ssh -A akunito@<IP> "cd ~/.dotfiles && git reset --hard HEAD && git pull"
```

### Service Failures After Deploy

Check which services failed:

```bash
ssh -A akunito@<IP> "sudo systemctl --failed"
```

Check specific service logs:

```bash
ssh -A akunito@<IP> "sudo journalctl -u <service-name> -n 50 --no-pager"
```

Restart failed services:

```bash
ssh -A akunito@<IP> "sudo systemctl reset-failed && sudo systemctl restart <service-name>"
```

### Secrets/Password Files Missing

If services fail due to missing secrets in `/etc/secrets/`:

```bash
# Check what secrets exist
ssh -A akunito@<IP> "sudo ls -la /etc/secrets/"

# Create missing password file with random password
ssh -A akunito@<IP> "sudo bash -c 'head -c 32 /dev/urandom | base64 | tr -d \"\\n\" > /etc/secrets/<filename> && chmod 600 /etc/secrets/<filename>'"

# Fix directory permissions if needed
ssh -A akunito@<IP> "sudo chmod 755 /etc/secrets"
```

### Permission Issues with Secrets

If postStart scripts can't read password files:

```bash
# For PostgreSQL secrets (group: postgres)
ssh -A akunito@<IP> "sudo chown root:postgres /etc/secrets/db-*-password && sudo chmod 640 /etc/secrets/db-*-password"

# For MySQL secrets (group: mysql)
ssh -A akunito@<IP> "sudo chown root:mysql /etc/secrets/db-*-password && sudo chmod 640 /etc/secrets/db-*-password"

# Make secrets directory accessible
ssh -A akunito@<IP> "sudo chmod 755 /etc/secrets"
```

### Rollback After Failed Deploy

```bash
ssh -A akunito@<IP> "sudo nixos-rebuild switch --rollback"
```

### Build Errors

If build fails, check the error and fix locally, then:

```bash
# Commit and push fix locally
git add <files> && git commit -m "fix: description" && git push

# Then redeploy to remote
ssh -A akunito@<IP> "cd ~/.dotfiles && git reset --hard HEAD && git pull && ./install.sh ~/.dotfiles <PROFILE> -s -u -q 2>&1"
```

---

## Post-Deployment Verification

### Check All Services Status

```bash
ssh -A akunito@<IP> "sudo systemctl --failed"
ssh -A akunito@<IP> "sudo systemctl list-units --type=service --state=running | head -30"
```

### Check Specific Service Groups

```bash
# Database services (LXC_database)
ssh -A akunito@192.168.8.103 "sudo systemctl status redis-homelab postgresql mysql pgbouncer prometheus-node-exporter prometheus-postgres-exporter prometheus-redis-exporter prometheus-mysqld-exporter --no-pager 2>&1 | grep -E '(●|×|Active:)'"

# Monitoring services (LXC_monitoring)
ssh -A akunito@192.168.8.85 "sudo systemctl status grafana prometheus prometheus-node-exporter --no-pager 2>&1 | grep -E '(●|×|Active:)'"
```

---

## Deploy Multiple Containers

To deploy to multiple containers in sequence:

```bash
for container in "192.168.8.103:LXC_database" "192.168.8.85:LXC_monitoring" "192.168.8.80:LXC_HOME"; do
  IP="${container%%:*}"
  PROFILE="${container##*:}"
  echo "=== Deploying $PROFILE to $IP ==="
  ssh -A akunito@$IP "cd ~/.dotfiles && git reset --hard HEAD && git pull && ./install.sh ~/.dotfiles $PROFILE -s -u -q 2>&1"
  echo ""
done
```

---

## Quick Reference Commands

```bash
# Check current generation
ssh -A akunito@<IP> "sudo nix-env --list-generations -p /nix/var/nix/profiles/system | tail -5"

# Check disk usage
ssh -A akunito@<IP> "df -h / /nix"

# Garbage collect old generations
ssh -A akunito@<IP> "sudo nix-collect-garbage -d"

# Check NixOS version
ssh -A akunito@<IP> "nixos-version"
```
