# Start Docker Services on TrueNAS

Start all Docker services on TrueNAS after a reboot or after unlocking encrypted datasets.

## Instructions

When this command is invoked, run the startup script from the dotfiles repo:

```bash
bash /home/akunito/.dotfiles/scripts/truenas-docker-startup.sh
```

### Arguments

- If the user asks for status only, pass `--status`
- If the user asks to stop all services, pass `--stop`
- If the user wants to skip compose file sync, pass `--no-sync`

### Prerequisites

- Must be run from a machine with SSH access to TrueNAS (192.168.20.200)
- Encrypted datasets must be unlocked first (run `/unlock-truenas` before this)
- Docker must be running on TrueNAS

### What It Does

1. **Syncs compose files** from `templates/truenas/` in the dotfiles repo to TrueNAS at `/mnt/ssdpool/docker/compose/` (ensures TrueNAS always uses the repo's version)
2. **Starts Docker compose projects** in the correct order:
   1. **tailscale** - VPN connectivity
   2. **cloudflared** - Cloudflare tunnel for external access
   3. **npm** - Nginx Proxy Manager (creates macvlan network if missing)
   4. **media** - Jellyfin, Sonarr, Radarr, Bazarr, Prowlarr, Jellyseerr, qBittorrent, Gluetun, Solvearr
   5. **homelab** - Calibre-web, RomM + MariaDB
   6. **exporters** - Prometheus exportarr for *arr stack metrics
   7. **uptime-kuma** - Status monitoring
   8. **NPM network connections** - Connects NPM to `homelab_default`, `media_default`, `uptime-kuma_default` so it can reverse-proxy via Docker DNS names
   9. **VPN watchdog cron** - Deploys `vpn-watchdog.sh` and installs a cron job (every 5 min) that auto-recovers Gluetun + qBittorrent after suspend/resume

### Compose file management

- **Source of truth**: `templates/truenas/` in the dotfiles repo
- **Deployed to**: `/mnt/ssdpool/docker/compose/` on TrueNAS
- **Secrets**: Stored in `.env` files on TrueNAS (NOT tracked in repo)
- **Sync**: Automatically synced on every startup (use `--no-sync` to skip)
- Compose file changes should be made in the repo, committed, then deployed via this script

### Post-startup verification

After starting, check that all 20 containers are healthy:
```bash
ssh truenas_admin@192.168.20.200 "sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | sort"
```

### Related

- [Unlock TrueNAS](./unlock-truenas.md) - Must run before this skill
- [Manage TrueNAS](./manage-truenas.md) - General TrueNAS management
