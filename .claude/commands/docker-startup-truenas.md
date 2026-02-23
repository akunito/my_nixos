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

### Prerequisites

- Must be run from a machine with SSH access to TrueNAS (192.168.20.200)
- Encrypted datasets must be unlocked first (run `/unlock-truenas` before this)
- Docker must be running on TrueNAS

### What It Does

Starts Docker compose projects in the correct order:
1. **tailscale** - VPN connectivity
2. **cloudflared** - Cloudflare tunnel for external access
3. **npm** - Nginx Proxy Manager (creates macvlan network if missing)
4. **media** - Jellyfin, Sonarr, Radarr, Bazarr, Prowlarr, Jellyseerr, qBittorrent, Gluetun, Solvearr
5. **homelab** - Calibre-web + EmulatorJS only (migrated services are excluded)
6. **exporters** - Prometheus exportarr for *arr stack metrics
7. **uptime-kuma** - Status monitoring
8. **NPM network connections** - Connects NPM to `homelab_default`, `media_default`, `uptime-kuma_default` so it can reverse-proxy via Docker DNS names (NPM macvlan can't reach host-published ports)

### Services NOT started (migrated or decommissioned)

- **unifi** - Running on VPS (unifi.akunito.com)
- **pihole/network** - Deleted
- **homelab migrated**: nextcloud, syncthing, freshrss, obsidian-remote, redis-local (all on VPS)

### Post-startup verification

After starting, check that all 19 containers are healthy:
```bash
ssh truenas_admin@192.168.20.200 "sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | sort"
```

### Related

- [Unlock TrueNAS](./unlock-truenas.md) - Must run before this skill
- [Manage TrueNAS](./manage-truenas.md) - General TrueNAS management
