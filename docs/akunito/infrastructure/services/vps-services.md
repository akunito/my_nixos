---
id: infrastructure.services.vps
summary: "VPS services: Docker containers and NixOS native services"
tags: [infrastructure, vps, docker, nixos]
date: 2026-02-23
status: published
---

# VPS Services

## Specs

| Property | Value |
|----------|-------|
| Provider | Netcup RS 4000 G12 |
| CPU | 12 dedicated AMD EPYC 9645 (Zen 5) cores |
| RAM | 32GB DDR5 ECC |
| Disk | 1TB NVMe |
| Network | 2.5 Gbps |
| Location | Nuremberg, Germany (~22ms from Warsaw) |
| Cost | ~32.49 EUR/mo (incl. VAT) |
| OS | NixOS, LUKS full-disk encrypted |

## Access

| Method | Address |
|--------|---------|
| SSH | `ssh -A -p 56777 akunito@100.64.0.6` (Tailscale) |
| SSH (WireGuard) | `ssh -A -p 56777 akunito@172.26.5.155` |
| Initrd SSH | `ssh -p 2222 root@159.195.32.28` (LUKS unlock only) |
| VNC | Netcup SCP panel (emergency) |

SSH is VPN-only (Tailscale + WireGuard). Port 56777 is blocked from public internet via iptables.

## NixOS Profile

Profile: `VPS_PROD` (VPS-base-config.nix → VPS_PROD-config.nix)

Deploy: `ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"`

## Docker Containers (17, rootless)

All containers run as `akunito` user via rootless Docker. ALL ports bound to `127.0.0.1`.

| Container | Domain | Port | Notes |
|-----------|--------|------|-------|
| portfolio | info.akunito.com | — | Static/Node app |
| liftcraft | leftyworkout-test.akunito.com | 3001 | Rails app |
| plane | plane.akunito.com | 3000 | Project management |
| matrix-synapse | matrix.akunito.com | 8008 | Federation server |
| element-web | element.akunito.com | 8088 | Matrix web client |
| matrix-redis | — | 6380 | Redis for Matrix |
| miniflux | freshrss.akunito.com | 8084 | RSS reader (replaces FreshRSS) |
| miniflux_ai | — (internal) | — | AI news summaries (Gemini) |
| nextcloud | nextcloud.akunito.com | 8089 | Cloud storage |
| nextcloud-cron | — | — | Background jobs |
| syncthing | syncthing.akunito.com | 8384 | File sync |
| obsidian-remote | obsidian.akunito.com | — | Remote Obsidian |
| uptime-kuma | status.akunito.com | 3009 | Public monitoring |
| unifi-network-app | unifi.akunito.com | — | Network controller |
| unifi-mongodb | — | 27017 | MongoDB 4.4 for UniFi |
| cloudflared | — | — | Cloudflare tunnel |
| freshrss | — | 8082 | Transitional (remove after migration) |

## NixOS Native Services

| Service | Port | Notes |
|---------|------|-------|
| PostgreSQL 17 | 5432 | plane, liftcraft, matrix, miniflux DBs |
| MariaDB 11 | 3306 | nextcloud DB |
| Redis 7 | 6379 | 5 DB allocations |
| Prometheus | 9090 | Metrics collection |
| Grafana | 3000 | grafana.akunito.com |
| Postfix | 25 | SMTP2GO relay |
| Headscale | 8080 | headscale.akunito.com |
| fail2ban | — | SSH + Nextcloud jails |
| node-exporter | 9091 | Host metrics |
| blackbox-exporter | 9115 | HTTP/ICMP probes |
| snmp-exporter | 9116 | pfSense SNMP |
| graphite-exporter | 9108 | TrueNAS graphite |
| postgres-exporter | 9187 | PostgreSQL metrics |
| mysqld-exporter | 9104 | MariaDB metrics |
| redis-exporter | 9121 | Redis metrics |

## Security

- LUKS full-disk encryption (initrd SSH unlock after reboot)
- Rootless Docker (user namespace isolation)
- SSH VPN-only (iptables: Tailscale + WireGuard only)
- pam_ssh_agent_auth (passwordless sudo only with SSH agent)
- Kernel hardening (SYN flood, IP spoofing, ptrace, BPF restrictions)
- no-new-privileges on ALL Docker containers
- Egress audit timer (daily)
- All database ports bound to 127.0.0.1
- Cloudflare WAF rules (bot fight, scanner blocks, rate limiting)

## RAM Budget

| Component | RAM |
|-----------|-----|
| PostgreSQL | 3.0 GB |
| MariaDB | 1.0 GB |
| Redis | 2.0 GB |
| Prometheus + Grafana | 2.0 GB |
| Docker containers | ~8.0 GB |
| OS + overhead | 2.0 GB |
| **Total used** | **~18 GB** |
| **Free for page cache** | **~14 GB** |
