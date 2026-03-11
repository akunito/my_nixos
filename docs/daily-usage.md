---
id: docs.daily-usage
summary: Daily aku commands, common operations, backup overview, maintenance, and script reference.
tags: [aku, commands, maintenance, scripts, backup, garbage-collection]
related_files: [system/bin/aku.nix, sync.sh, upgrade.sh, maintenance.sh, scripts/]
date: 2026-03-11
status: published
---

# Daily Usage

## aku Command Reference

| Command | What it does |
|---------|-------------|
| `aku sync` | Rebuild system + Home Manager (`nixos-rebuild switch` + `home-manager switch`) |
| `aku sync system` | System-only rebuild |
| `aku sync user` | Home Manager-only rebuild (same as `./sync-user.sh`) |
| `aku update` | Update flake inputs (`flake.lock`) |
| `aku upgrade` | Update + sync (full system upgrade) |
| `aku refresh` | Refresh Stylix themes and restart daemons |
| `aku pull` | Fetch and merge upstream changes |
| `aku gc` | Interactive garbage collection |
| `aku gc 30d` | Delete Nix store entries older than 30 days |
| `aku gc full` | Delete everything unused |
| `aku harden` | Make system config files read-only |
| `aku soften` | Relax file permissions for editing |

## Common Operations

### Rebuild after config change

```bash
# Full rebuild (system + user)
aku sync

# User-only (faster, for user/ directory changes)
aku sync user
# or directly:
cd ~/.dotfiles && ./sync-user.sh
```

### Full system upgrade

```bash
aku upgrade    # Updates flake.lock then rebuilds
```

### Theme refresh

```bash
aku refresh    # Re-applies Stylix theme, restarts daemons
```

### Test before applying

```bash
nixos-rebuild build --flake .#DESK    # Dry build (replace DESK with your profile)
```

## Backup Overview

Backups use **Restic** with systemd timers. Full details: [Restic Backups](security/restic-backups.md)

| What | Frequency | Destination |
|------|-----------|-------------|
| VPS PostgreSQL dumps | Hourly | Local, then Restic to TrueNAS |
| VPS service configs | Daily 09:00 | TrueNAS (SFTP via Tailscale) |
| VPS Nextcloud data | Daily 10:00 | TrueNAS (SFTP via Tailscale) |
| DESK home directory | Every 6h | TrueNAS (NFS mount) |
| LAPTOP_X13 home dir | Every 6h | TrueNAS (NFS mount) |
| TrueNAS configs | Daily 18:30 | VPS (rsync) |

## Maintenance

### Garbage collection

```bash
aku gc 30d     # Remove generations older than 30 days
aku gc full    # Remove all unused store paths
```

### Generation cleanup

The `maintenance.sh` script handles scheduled cleanup:

```bash
./maintenance.sh       # Interactive
./maintenance.sh -s    # Silent
```

Defaults: keeps last 6 system generations, 4 Home Manager generations, removes user generations older than 15 days.

### File permissions

```bash
aku soften     # Before editing system files
# make changes...
aku harden     # After editing
```

## Script Reference

Full documentation: [Scripts Reference](scripts/README.md)

| Script | Purpose |
|--------|---------|
| `install.sh` | Full system installation (clone, profile, rebuild) |
| `sync.sh` | Rebuild system + user |
| `sync-system.sh` | System-only rebuild |
| `sync-user.sh` | Home Manager-only rebuild |
| `sync-posthook.sh` | Refresh themes and daemons |
| `update.sh` | Update flake.lock |
| `upgrade.sh` | Update + sync |
| `pull.sh` | Git fetch + merge |
| `maintenance.sh` | Generation cleanup + GC |
| `harden.sh` / `soften.sh` | File permission management |
| `handle_docker.sh` | Stop Docker containers before rebuild |
| `deploy.sh` | TUI-based remote deployment |

## Nix Shell-String Gotcha

When writing bash inside Nix multiline strings (`''`), escape `${}` to prevent Nix interpolation:

```nix
# WRONG: ${PATH} is Nix interpolation
text = '' echo "${PATH}" '';

# CORRECT: ''${PATH} escapes for bash
text = '' echo "''${PATH}" '';
```

This applies to `writeShellApplication`, `home.file` scripts, and any `''` string with bash variables.
