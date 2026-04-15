# Infrastructure & Project Registry

Compact lookup for all nodes, services, local projects, and management skills. Load this context for infrastructure work, service debugging, or cross-project tasks.

## Nodes

| Node | IP(s) | SSH Command | Profile | Type |
|------|-------|-------------|---------|------|
| DESK | 192.168.8.96 | `ssh -A akunito@192.168.8.96` | DESK | workstation |
| LAPTOP_X13 | 192.168.8.92, 100.64.0.8 | `ssh -A akunito@192.168.8.92` | LAPTOP_X13 | laptop |
| LAPTOP_YOGA | 192.168.8.100 | `ssh -A aga@192.168.8.100` | LAPTOP_YOGA | laptop |
| LAPTOP_A | 192.168.8.78, 100.64.0.4 | `ssh -A akunito@192.168.8.78` | LAPTOP_A | laptop |
| VPS_PROD | 100.64.0.6, 172.26.5.155 | `ssh -A -p 56777 akunito@100.64.0.6` | VPS_PROD | vps |
| TrueNAS | 192.168.20.200 | `ssh akunito@192.168.20.200` | — (FreeBSD) | nas |
| pfSense | 192.168.8.1 | `ssh admin@192.168.8.1` | — (FreeBSD) | firewall |
| KOMI_LXC_database | 192.168.1.10 | `ssh admin@192.168.1.10` | KOMI_LXC_database | lxc |
| KOMI_LXC_mailer | 192.168.1.11 | `ssh admin@192.168.1.11` | KOMI_LXC_mailer | lxc |
| KOMI_LXC_monitoring | 192.168.1.12 | `ssh admin@192.168.1.12` | KOMI_LXC_monitoring | lxc |
| KOMI_LXC_proxy | 192.168.1.13 | `ssh admin@192.168.1.13` | KOMI_LXC_proxy | lxc |
| KOMI_LXC_tailscale | 192.168.1.14 | `ssh admin@192.168.1.14` | KOMI_LXC_tailscale | lxc |
| MACBOOK-KOMI | — | — | MACBOOK-KOMI | macbook |

For deploy commands see `deployment-context.md` or `deploy-servers.conf`.

## Multi-Instance Services

| Service | VPS_PROD | TrueNAS | KOMI_LXC | Type | Doc |
|---------|----------|---------|----------|------|-----|
| Grafana | ✅ NixOS :3002 | — | monitoring :3002 | NixOS native | `services/monitoring-stack.md` |
| Prometheus | ✅ NixOS :9090 | — | monitoring :9090 | NixOS native | `services/monitoring-stack.md` |
| Uptime Kuma | ✅ Docker :3001 | — | mailer :3001 | Docker | `services/kuma.md` |
| NPM | — | ✅ Docker :80/443/81 | proxy :80/443/81 | Docker | `services/proxy-stack.md` |
| Cloudflared | ✅ NixOS | ✅ Docker | proxy (disabled) | Mixed | `services/proxy-stack.md` |
| Tailscale | ✅ NixOS client | ✅ Docker subnet-router | tailscale LXC | Mixed | `services/tailscale-headscale.md` |
| Node-exporter | ✅ NixOS :9091 | ✅ Docker :9100 | all LXCs :9100 | Mixed | `services/monitoring-stack.md` |
| PostgreSQL | ✅ NixOS :5432 | — | database :5432 | NixOS native | `services/database-redis.md` |
| Redis | ✅ NixOS :6379 | — | database :6379 | NixOS native | `services/database-redis.md` |
| UniFi | ✅ Docker :8443 | Docker (manual fallback) | — | Docker | `services/vps-services.md` |
| Postfix | ✅ NixOS :25 | — | mailer :25 | Mixed | `services/vps-services.md` |
| WireGuard | ✅ NixOS :51820 | — | — | NixOS native | `services/pfsense.md` |
| Headscale | ✅ NixOS :8080 | — | — | NixOS native | `services/tailscale-headscale.md` |

All doc paths relative to `docs/akunito/infrastructure/`.

## VPS Docker Containers

| Container | Domain | Port | DB | Template |
|-----------|--------|------|----|----------|
| portfolio | info.akunito.com | 3005 | — | `portfolio` |
| leftyworkout (test) | leftyworkout-test.akunito.com | 3001 (FE), 3000 (BE) | pg:rails_database_prod | `~/Projects/leftyworkout` (separate repo) |
| plane | plane.akunito.com | 3000 | pg:plane, redis:db0 | `plane` |
| matrix-synapse | matrix.akunito.com | 8008 | pg:matrix | `matrix/` |
| element-web | element.akunito.com | 8088 | — | `matrix/` |
| matrix-redis | — | 6380 | — | `matrix/` |
| miniflux | freshrss.akunito.com | 8084 | pg:miniflux | `miniflux` |
| miniflux-ai | — | — | — | `miniflux-ai` |
| nextcloud | nextcloud.akunito.com | 8089 | maria:nextcloud, redis:db1 | `nextcloud` |
| syncthing | syncthing.akunito.com | 8384 | — | `syncthing` |
| obsidian-remote | obsidian.akunito.com | 8090 | — | `obsidian-remote` |
| uptime-kuma | status.akunito.com | 3009 | — | `uptime-kuma` |
| unifi-network-app | unifi.akunito.com | 8443 | mongo:unifi | `unifi` |
| cloudflared | — | — | — | NixOS native |
| calibre-web | calibre.local.akunito.com | 8083 | — | `calibre` |
| n8n | — | 5678 | pg:n8n | `n8n` |
| openclaw | — | 18789 | — | `openclaw/` |
| finance-tagger | finance.local.akunito.com | 8190 | sqlite:vaultkeeper.db | `finance-tagger` |

Template paths relative to `templates/`.

## TrueNAS Docker Containers

| Container | Domain | Port | Compose Project | Notes |
|-----------|--------|------|-----------------|-------|
| **Root Docker** | | | | |
| tailscale | — | — | `truenas/tailscale` | Subnet router |
| gluetun | — | — | `truenas/vpn-media` | VPN gateway |
| qbittorrent | qbt.local.akunito.com | 8085 | `truenas/vpn-media` | Via gluetun |
| **Rootless Docker** | | | | |
| cloudflared | — | — | `truenas/cloudflared` | Tunnel to *.local |
| npm | 192.168.20.200 | 80/443/81 | `truenas/npm` | Reverse proxy |
| jellyfin | jellyfin.local.akunito.com | 8096 | `truenas/media` | Media server |
| sonarr | sonarr.local.akunito.com | 8989 | `truenas/media` | TV automation |
| radarr | radarr.local.akunito.com | 7878 | `truenas/media` | Movie automation |
| bazarr | bazarr.local.akunito.com | 6767 | `truenas/media` | Subtitles |
| prowlarr | prowlarr.local.akunito.com | 9696 | `truenas/media` | Indexer mgmt |
| jellyseerr | jellyseerr.local.akunito.com | 5055 | `truenas/media` | Requests |
| solvearr | — | 8191 | `truenas/media` | Captcha solver |
| exportarr (x4) | — | 9707-9710 | `truenas/monitoring` | Arr metrics |
| node-exporter | — | 9100 | `truenas/monitoring` | Host metrics |
| cadvisor | — | 8081 | `truenas/monitoring` | Docker metrics |

## VPS NixOS Native Services

| Service | Port | Nix Module | Notes |
|---------|------|------------|-------|
| PostgreSQL 17 | 5432 | `postgresql.nix` | 6 DBs (plane, rails, matrix, miniflux, vaultwarden, n8n) |
| MariaDB 11 | 3306 | `mariadb.nix` | DB: nextcloud |
| Redis 7 | 6379 | `redis-server.nix` | 5 DB allocations |
| PgBouncer | 6432 | `pgbouncer.nix` | Connection pooler |
| Grafana | 3002 | `grafana.nix` | grafana.akunito.com |
| Prometheus | 9090 | (embedded) | + 10 exporters |
| Headscale | 8080 | `headscale.nix` | VPN coordination |
| Vaultwarden | 8222 | `vaultwarden.nix` | vault.akunito.com |
| Postfix | 25 | `postfix-relay.nix` | SMTP2GO relay |
| Cloudflared | — | `cloudflared.nix` | Outbound tunnel |
| WireGuard | 51820 | `wireguard-server.nix` | Backup tunnel to pfSense |
| OpenClaw | 18789/18790 | `openclaw.nix` | AI assistant gateway + bridge |
| nginx-local | 80/443 | `nginx-local.nix` | Tailscale-only reverse proxy |

All module paths relative to `system/app/`.

## Local Projects on DESK

| Project | Path | Tech Stack | Environment | Git Remote | CLAUDE.md | Plane ID |
|---------|------|------------|-------------|------------|-----------|----------|
| portfolio | `~/Projects/portfolio/` | Next.js + Python + Docker | dev (DESK), prod (VPS Docker) | github:akunito/portfolio | Yes | APORT |
| leftyworkout (LiftCraft) | `~/Projects/leftyworkout/` | Rails + React + Docker | dev (DESK), test+prod (VPS `~/Projects/leftyworkout`) | github:akunito/lefty_workout | No | LW |
| portfolio_komi | `~/Projects/portfolio_komi/` | Next.js | dev (DESK) | github:ko-mi/... | No | — (komi) |
| odin_rails_01 | `~/Projects/odin_rails_01/` | Rails + React + Docker | dev only | github:akunito/odin_rails_01 | No | — |
| odin_rails_02_blog | `~/Projects/odin_rails_02_blog/` | Rails + Docker | dev only | github:akunito/... | No | — |
| nixos_dotfiles | `~/Projects/nixos_dotfiles/` → `~/.dotfiles` | Nix | all profiles | github:akunito/nixos_dotfiles | Yes (this file) | AINF |
| my_homelab | `~/Projects/my_homelab/` | Docker compose | reference/archived | github:akunito/my_homelab | No | — |
| homeLab_VMs | `~/Projects/homeLab_VMs/` | Libvirt/KVM | archived | github:akunito/... | No | — |
| mySCRIPTS | `~/Projects/mySCRIPTS/` | Shell/Python | utilities | github:akunito/mySCRIPTS | No | — |
| CombineActuals | `~/Projects/CombineActuals/` | Ruby | utility | github:akunito/... | No | — |
| SpinachKeyboardFramework | `~/Projects/SpinachKeyboardFramework/` | Docs | reference | github:akunito/... | No | — |
| CSVmerger | `~/Projects/CSVmerger/` | — | local only | — | No | — |
| gitTest | `~/Projects/gitTest/` | HTML | local only | — | No | — |

## Management Skills

| Skill | Target Node(s) | Purpose |
|-------|---------------|---------|
| `/audit-infrastructure` | VPS, TrueNAS | Gather current state from all infra nodes |
| `/check-database` | VPS_PROD | PostgreSQL + MariaDB health check |
| `/check-redis` | VPS_PROD | Redis connectivity, DB allocation, key counts |
| `/check-kuma` | VPS_PROD | Uptime Kuma health verification |
| `/manage-truenas` | TrueNAS | Storage, NFS, bonds, VLAN 100 |
| `/manage-pfsense` | pfSense | Firewall, DNS, WireGuard, SNMP |
| `/manage-tailscale` | Tailscale/Headscale | VPN mesh management |
| `/manage-matrix` | VPS_PROD | Matrix Synapse + Element + Claude bot |
| `/manage-proxmox` | Proxmox (Komi only) | LXC management (akunito Proxmox shut down) |
| `/deploy-lxc` | VPS, LXC, Laptops | Deploy NixOS via install.sh |
| `/deploy-db-secrets` | VPS_PROD | Deploy credentials to /etc/secrets/ |
| `/gather-db-credentials` | VPS_PROD | Verify DB credentials match secrets |
| `/docker-startup-truenas` | TrueNAS | Start Docker services after reboot |
| `/unlock-truenas` | TrueNAS | Unlock encrypted ZFS datasets |
| `/wake-on-lan-truenas` | TrueNAS | Wake from sleep with RTC |
| `/network-performance` | Homelab | 10GbE performance testing |
| `/update-dbeaver` | DESK | Update DBeaver DB connections |
| `/sync-vivaldi` | DESK, LAPTOP_X13 | Sync Vivaldi browser config |
| `/clean-gaming` | DESK | Kill stale gamescope/Wine/Proton |
| `/darwin-rebuild` | MACBOOK-KOMI | Apply macOS nix-darwin config |

## Doc Cross-Reference

| Topic | Doc Path |
|-------|----------|
| Architecture overview | `docs/akunito/infrastructure/INFRASTRUCTURE.md` |
| VPS services | `docs/akunito/infrastructure/services/vps-services.md` |
| TrueNAS services | `docs/akunito/infrastructure/services/truenas-services.md` |
| TrueNAS operations | `docs/akunito/infrastructure/services/truenas.md` |
| Databases & Redis | `docs/akunito/infrastructure/services/database-redis.md` |
| Monitoring (Grafana/Prometheus) | `docs/akunito/infrastructure/services/monitoring-stack.md` |
| Grafana dashboards | `docs/setup/grafana-dashboards-alerting.md` |
| Proxy & tunnels | `docs/akunito/infrastructure/services/proxy-stack.md` |
| Tailscale/Headscale | `docs/akunito/infrastructure/services/tailscale-headscale.md` |
| pfSense | `docs/akunito/infrastructure/services/pfsense.md` |
| Matrix | `docs/akunito/infrastructure/services/matrix.md` |
| OpenClaw | `docs/akunito/infrastructure/services/openclaw/README.md` |
| Network switching | `docs/akunito/infrastructure/services/network-switching.md` |
