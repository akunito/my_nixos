# LXC Decommissioning & TrueNAS Proxy Setup

## Context

The VPS migration (Phases 1-3B) is complete. All public-facing services, databases, monitoring, and email relay now run on VPS_PROD. Four LXC containers are redundant and should be decommissioned: LXC_proxy, LXC_database, LXC_monitoring, LXC_mailer. Four already-migrated containers (LXC_plane, LXC_liftcraft, LXC_portfolio, LXC_matrix) are also stopped.

The local reverse proxy (NPM) and Cloudflare tunnel for homelab services move to TrueNAS. Kuma local monitoring also moves to TrueNAS.

**Remaining active LXC containers**: LXC_HOME, LXC_tailscale, LXC_database (temporary until Nextcloud migration).

---

## Phase 1: NixOS Config Changes

### 1.1 VPS Postfix — add homelab LAN to mynetworks

**File**: `system/app/postfix-relay.nix` (line 22)

```nix
# Current:
mynetworks = [ "127.0.0.0/8" "[::1]/128" "172.16.0.0/12" "10.0.0.0/8" ];

# Change to:
mynetworks = [ "127.0.0.0/8" "[::1]/128" "172.16.0.0/12" "10.0.0.0/8" "192.168.8.0/24" "192.168.20.0/24" ];
```

Port 25 is NOT in VPS firewall allowedTCPPorts (not internet-exposed). Traffic from homelab arrives via WireGuard (`wg0`) which is a trusted interface — no firewall changes needed.

### 1.2 LXC_HOME — point SMTP to VPS

**File**: `profiles/LXC_HOME-config.nix` (line 116)

```nix
# Current:
notificationSmtpHost = "192.168.8.89";

# Change to:
notificationSmtpHost = "172.26.5.155"; # VPS Postfix via WireGuard
```

### 1.3 VPS monitoring — update Prometheus remote targets

**File**: `profiles/VPS_PROD-config.nix` (lines 181-185)

```nix
# Replace prometheusRemoteTargets with:
prometheusRemoteTargets = [
  # LXC_database kept until Nextcloud migration completes
  { name = "lxc_database";   host = "192.168.8.103"; nodePort = 9100; cadvisorPort = null; }
  # Active infrastructure
  { name = "truenas";        host = "192.168.20.200"; nodePort = 9100; cadvisorPort = null; }
  { name = "lxc_home";       host = "192.168.8.80";  nodePort = 9100; cadvisorPort = 9092; }
  { name = "lxc_tailscale";  host = "192.168.8.105"; nodePort = 9100; cadvisorPort = null; }
];
```

### 1.4 VPS monitoring — add ICMP probes (from LXC_monitoring)

**File**: `profiles/VPS_PROD-config.nix` (lines 212-216)

```nix
# Replace prometheusBlackboxIcmpTargets with:
prometheusBlackboxIcmpTargets = [
  { name = "pfsense"; host = "192.168.8.1"; }
  { name = "pve"; host = "192.168.8.82"; }
  { name = "truenas"; host = "192.168.20.200"; }
  { name = "lxc_home"; host = "192.168.8.80"; }
  { name = "lxc_tailscale"; host = "192.168.8.105"; }
  { name = "switch_usw_aggr"; host = "192.168.8.180"; }
  { name = "switch_usw_24"; host = "192.168.8.181"; }
  { name = "wan"; host = "1.1.1.1"; }
];
```

### 1.5 VPS monitoring — enable exporters migrated from LXC_monitoring

**File**: `profiles/VPS_PROD-config.nix` (add after line ~216)

```nix
# === SNMP Exporter (pfSense — migrated from LXC_monitoring) ===
prometheusSnmpExporterEnable = true;
prometheusSnmpv3User = secrets.snmpv3User;
prometheusSnmpv3AuthPass = secrets.snmpv3AuthPass;
prometheusSnmpv3PrivPass = secrets.snmpv3PrivPass;
prometheusSnmpCommunity = secrets.snmpCommunity;
prometheusSnmpTargets = [
  { name = "pfsense"; host = "192.168.8.1"; module = "pfsense"; }
];

# === Graphite Exporter (TrueNAS pushes metrics — migrated from LXC_monitoring) ===
prometheusGraphiteEnable = true;
prometheusGraphitePort = 9109;
prometheusGraphiteInputPort = 2003;

# === PVE Exporter (Proxmox metrics — migrated from LXC_monitoring) ===
prometheusPveExporterEnable = true;
prometheusPveHost = "192.168.8.82";
prometheusPveUser = "prometheus@pve";
prometheusPveTokenName = "prometheus";
prometheusPveTokenFile = "/etc/secrets/pve-token";

# === Backup Monitoring (migrated from LXC_monitoring) ===
prometheusPveBackupEnable = true;
prometheusTruenasBackupEnable = true;
prometheusPfsenseBackupEnable = true;
prometheusPfsenseBackupProxmoxHost = "192.168.8.82";
prometheusPfsenseBackupPath = "/mnt/pve/proxmox_backups/pfsense";
```

### 1.6 Grafana SMTP fallback — remove dead LXC_mailer reference

**File**: `system/app/grafana.nix` (line 98)

```nix
# Current:
host = systemSettings.smtpRelayHost or "192.168.8.89:25";

# Change to:
host = systemSettings.smtpRelayHost or "localhost:25";
```

### 1.7 lib/defaults.nix — update smtpRelayHost default

**File**: `lib/defaults.nix` (line 627)

```nix
# Current:
smtpRelayHost = "192.168.8.89:25";

# Change to:
smtpRelayHost = "localhost:25"; # Profiles with Postfix use localhost; others override per-profile
```

### 1.8 SSH hosts — remove decommissioned entries

**File**: `user/app/ssh-hosts.nix`

Remove these matchBlocks:
- `"planePROD-nixos"` (192.168.8.86)
- `"mailerWatcher"` (192.168.8.89)
- `"leftyworkoutTest"` (192.168.8.87)
- `"portfolioprod"` (192.168.8.88)

Keep: `homelab`, `vps`, `pve`, `aga-laptop`, `truenas`, `github.com`, `ssh-leftyworkout-test.akunito.com`

### 1.9 flake.nix — comment out decommissioned profiles

**File**: `flake.nix` (profiles section)

Comment out:
- `LXC_proxy`, `LXC_plane`, `LXC_mailer`, `LXC_liftcraftTEST`, `LXC_portfolioprod`, `LXC_monitoring`, `LXC_matrix`

Keep active: `LXC_HOME`, `LXC_database` (temporary), `LXC_tailscale`

### 1.10 deploy-servers.conf — remove decommissioned entries

**File**: `deploy-servers.conf`

Remove: LXC_proxy, LXC_plane, LXC_portfolioprod, LXC_mailer, LXC_liftcraftTEST, LXC_monitoring, LXC_matrix

Keep: LXC_HOME, LXC_database (mark temporary), LXC_tailscale

### 1.11 CLAUDE.md — update routing table and hierarchy

**File**: `CLAUDE.md`

- Remove LXC_proxy, LXC_monitoring from routing table
- Remove LXC_mailer, LXC_plane, LXC_matrix, LXC_liftcraftTEST, LXC_portfolioprod if present
- Mark LXC_database as temporary
- Update profile hierarchy tree (remove decommissioned branches)
- Update SSH section (remove LXC_database SSH example)

---

## Phase 2: Deploy NixOS Changes

### 2.1 Pre-deploy: VPS operational setup

SSH to VPS and set up secrets for new exporters:
```bash
# PVE API token (copy from LXC_monitoring)
echo '<token>' | sudo tee /etc/secrets/pve-token && sudo chmod 600 /etc/secrets/pve-token

# SSH keys for backup monitoring (root SSH to Proxmox + TrueNAS)
sudo ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N '' -q 2>/dev/null
sudo cat /root/.ssh/id_ed25519.pub
# Add public key to root@192.168.8.82 and truenas_admin@192.168.20.200
```

### 2.2 Deploy

```bash
# Commit and push from local machine
git add -A && git commit -m "feat: prepare LXC decommissioning" && git push

# Deploy to VPS
ssh -A -p 56777 akunito@<VPS> "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"

# Deploy to LXC_HOME
ssh -A akunito@192.168.8.80 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_HOME -s -u -d -h"
```

### 2.3 Verify

- Test SMTP from LXC_HOME to VPS: trigger test notification
- Check VPS Prometheus targets page — new targets should be UP
- Verify SNMP/PVE/backup exporters in Grafana

---

## Phase 3: TrueNAS Docker Setup (operational)

### 3.1 Cloudflared tunnel

User creates tunnel in Cloudflare dashboard. Set up Docker on TrueNAS:

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    command: tunnel --no-autoupdate run --token <TUNNEL_TOKEN>
    network_mode: host
```

Configure tunnel routes in Cloudflare dashboard for local services.

### 3.2 Kuma uptime monitoring

```yaml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - ./kuma-data:/app/data
```

Export/import monitors from old LXC_mailer Kuma.

### 3.3 NPM (Nginx Proxy Manager) for local reverse proxy

```yaml
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    restart: unless-stopped
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - ./npm-data:/data
      - ./npm-letsencrypt:/etc/letsencrypt
```

NPM has built-in Let's Encrypt with Cloudflare DNS challenge for wildcard certs.

### 3.4 Post-setup

- **pfSense DNS**: Change `*.local.akunito.com` override from `192.168.8.102` → TrueNAS IP
- **TrueNAS Graphite**: Redirect reporting from `192.168.8.85` → `172.26.5.155` (VPS WireGuard)
- **NPM config**: Migrate all proxy host entries from old LXC_proxy NPM
- **Test**: Verify local service access via `*.local.akunito.com`

---

## Phase 4: Decommission Containers

Order matters — stop each, verify, then move on.

1. **LXC_proxy** — after TrueNAS proxy + tunnel verified
2. **LXC_mailer** — after VPS SMTP + TrueNAS Kuma verified
3. **LXC_monitoring** — after VPS monitoring fully verified
4. **LXC_plane, LXC_liftcraft, LXC_portfolio, LXC_matrix** — already migrated
5. **LXC_database** — LAST, after Nextcloud migration (separate session)

Stop: `ssh root@192.168.8.82 "pct stop <CTID>"`
Destroy (after 1-2 weeks): `ssh root@192.168.8.82 "pct destroy <CTID>"`

---

## Files Modified Summary

| File | Change |
|------|--------|
| `system/app/postfix-relay.nix` | Add homelab LAN subnets to mynetworks |
| `profiles/LXC_HOME-config.nix` | SMTP → VPS WireGuard IP |
| `profiles/VPS_PROD-config.nix` | Update targets, add SNMP/PVE/Graphite/backup exporters |
| `system/app/grafana.nix` | Fix SMTP fallback (remove dead IP) |
| `lib/defaults.nix` | Update smtpRelayHost default |
| `user/app/ssh-hosts.nix` | Remove 4 decommissioned host entries |
| `flake.nix` | Comment out 7 decommissioned profiles |
| `deploy-servers.conf` | Remove 7 decommissioned entries |
| `CLAUDE.md` | Update routing table, hierarchy, SSH examples |
