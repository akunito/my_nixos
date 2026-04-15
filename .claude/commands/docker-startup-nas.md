# Start Docker Services on NAS

Start all Docker services on NAS after a reboot or after unlocking encrypted datasets.

## Instructions

When this command is invoked, run the startup script from the dotfiles repo:

```bash
bash /home/akunito/.dotfiles/scripts/nas-docker-startup.sh
```

### Arguments

- If the user asks for status only, pass `--status`
- If the user asks to stop all services, pass `--stop`
- If the user wants to skip compose file sync, pass `--no-sync`

### Prerequisites

- Must be run from a machine with SSH access to NAS (192.168.20.200)
- Encrypted datasets must be unlocked first (run `/unlock-truenas` before this)
- Docker must be running on NAS

### What It Does

1. **Syncs compose files** from `templates/truenas/` in the dotfiles repo to NAS at `/mnt/ssdpool/docker/compose/` (ensures NAS always uses the repo's version)
2. **Starts Docker compose projects** in the correct order:
   1. **tailscale** - VPN connectivity
   2. **cloudflared** - Cloudflare tunnel for external access
   3. **npm** - Nginx Proxy Manager (creates macvlan network if missing)
   4. **media** - Jellyfin, Sonarr, Radarr, Bazarr, Prowlarr, Jellyseerr, qBittorrent, Gluetun, Solvearr
   5. **homelab** - (all migrated to VPS, compose kept for NPM network)
   6. **exporters** - Prometheus exportarr for *arr stack metrics
   7. **NPM network connections** - Connects NPM to `homelab_default`, `media_default` so it can reverse-proxy via Docker DNS names
   8. **VPN watchdog cron** - Deploys `vpn-watchdog.sh` and installs a cron job (every 5 min) that auto-recovers Gluetun + qBittorrent after non-suspend VPN drops
   9. **Suspend/resume hook** - Deploys `docker-suspend-hook.sh` as systemd services for sleep.target so containers are gracefully stopped before S3 suspend and restarted in order after wake

### Compose file management

- **Source of truth**: `templates/truenas/` in the dotfiles repo
- **Deployed to**: `/mnt/ssdpool/docker/compose/` on NAS
- **Secrets**: Stored in `.env` files on NAS (NOT tracked in repo)
- **Sync**: Automatically synced on every startup (use `--no-sync` to skip)
- Compose file changes should be made in the repo, committed, then deployed via this script

### Post-startup verification

After starting, check that all 18 containers are healthy:
```bash
ssh akunito@192.168.20.200 "sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | sort"
```

### Related

- [Unlock NAS](./unlock-truenas.md) - Must run before this skill
- [Manage NAS](./manage-truenas.md) - General NAS management
