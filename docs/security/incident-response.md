---
id: security.incident-response
summary: Security incident response procedures for NixOS homelab infrastructure
tags: [security, incident-response, credentials, rotation, recovery]
related_files: [secrets/*.nix, profiles/*-config.nix]
---

# Incident Response Procedures

Procedures for responding to security incidents and performing credential rotation.

---

## 1. Credential Rotation Procedures

### 1.1 SNMP Community String (pfSense)

**When to rotate:** Suspected exposure, quarterly review, or after network audit.

**Steps:**

1. Generate new community string:
   ```bash
   openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32
   ```

2. Update pfSense:
   - Navigate to Services > SNMP
   - Update "Read Community String"
   - Save and apply

3. Update secrets:
   ```bash
   cd ~/.dotfiles
   git-crypt unlock ~/.git-crypt/dotfiles-key
   # Edit secrets/domains.nix
   vim secrets/domains.nix
   # Update snmpCommunity value
   ```

4. Rebuild monitoring on VPS:
   ```bash
   ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
   ```

5. Verify scraping:
   ```bash
   curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "snmp_pfsense")'
   ```

---

### 1.2 SMTP2GO Credentials

**When to rotate:** Suspected spam abuse, credential exposure, or annual review.

**Steps:**

1. Log into SMTP2GO dashboard (https://app.smtp2go.com)
2. Navigate to Settings > Users
3. Generate new API key or reset password
4. Update dotfiles secrets:
   ```bash
   cd ~/.dotfiles
   git-crypt unlock ~/.git-crypt/dotfiles-key
   vim secrets/domains.nix
   # Update smtp2goPassword value
   git add secrets/domains.nix && git commit -m "chore: rotate SMTP2GO credentials"
   ```

5. Update VPS Postfix (NixOS native service):
   ```bash
   # Update secrets/domains.nix with new SMTP2GO password, commit, then deploy
   ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
   ```

6. Test email delivery:
   ```bash
   # On VPS
   ssh -A -p 56777 akunito@100.64.0.6 'curl --url "smtp://localhost:25" \
     --mail-from "nixos@akunito.com" \
     --mail-rcpt "diego88aku@gmail.com" \
     --upload-file - <<< "Subject: Credential Rotation Test

   SMTP2GO credentials rotated successfully."'
   ```

---

### 1.3 WireGuard Keys

**When to rotate:** Suspected key compromise or annual security review.

**Steps for VPS server key:**

1. Generate new server keys:
   ```bash
   ssh -p 56777 root@172.26.5.155
   cd /etc/wireguard
   wg genkey | tee privatekey | wg pubkey > publickey
   chmod 600 privatekey
   ```

2. Update wg0.conf:
   ```bash
   vim /etc/wireguard/wg0.conf
   # Update PrivateKey with new key
   ```

3. Distribute new public key to all peers (pfSense, clients)

4. Restart WireGuard:
   ```bash
   systemctl restart wg-quick@wg0
   ```

**Steps for peer rotation:**

1. On client, generate new keys
2. Update peer config in WGUI (https://wgui.akunito.com)
3. Download new client config
4. Restart client WireGuard

---

### 1.4 Proxmox API Token (Komi only)

**Note:** Akunito's Proxmox (192.168.8.82) is SHUT DOWN since Feb 2026. PVE exporter removed from VPS monitoring. This section applies only to Komi's Proxmox (192.168.1.3) if monitoring is enabled.

**When to rotate:** Suspected exposure or annual review.

**Steps:**

1. Log into Proxmox web UI (https://192.168.1.3:8006)
2. Navigate to Datacenter > Permissions > API Tokens
3. Remove old token for `prometheus@pve`
4. Create new token with same permissions (PVEAuditor)
5. Update monitoring configuration and deploy

---

### 1.5 Cloudflare API Token (ACME)

**When to rotate:** Suspected exposure or token permissions change.

**Steps:**

1. Log into Cloudflare dashboard
2. Navigate to My Profile > API Tokens
3. Revoke old token, create new one with DNS edit permissions
4. Update in secrets/domains.nix and deploy to VPS:
   ```bash
   # VPS handles public certs via cloudflared tunnel; TrueNAS NPM handles local certs
   ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
   ```

---

## 2. Backup Restoration Procedures

### 2.1 Git Repository Recovery

If git-crypt encrypted repo is corrupted:

1. Clone fresh copy:
   ```bash
   cd ~
   mv .dotfiles .dotfiles.backup
   git clone git@github.com:akunito/dotnix.git .dotfiles
   ```

2. Unlock with key:
   ```bash
   cd .dotfiles
   git-crypt unlock ~/.git-crypt/dotfiles-key
   ```

3. Verify secrets are readable:
   ```bash
   cat secrets/domains.nix
   ```

---

### 2.2 Docker Volume Recovery

For Docker services on VPS:

1. Stop affected stack:
   ```bash
   ssh -A -p 56777 akunito@100.64.0.6
   cd ~/docker/<stack>
   docker compose down
   ```

2. Restore from backup (if using restic):
   ```bash
   restic -r <repo> restore latest --target ~/docker/<stack>
   ```

3. Restart stack:
   ```bash
   docker compose up -d
   ```

For Docker services on TrueNAS:

1. Stop affected stack:
   ```bash
   ssh truenas_admin@192.168.20.200
   cd ~/docker/<stack>
   docker compose down
   ```

2. Restore from ZFS snapshot or restic backup
3. Restart stack:
   ```bash
   docker compose up -d
   ```

---

### 2.3 VPS Recovery

If VPS needs full rebuild:

1. SSH into VPS and clone dotfiles:
   ```bash
   ssh -A -p 56777 akunito@100.64.0.6
   git clone git@github.com:akunito/dotnix.git ~/.dotfiles
   cd ~/.dotfiles && git-crypt unlock ~/.git-crypt/dotfiles-key
   ```
2. Run install script:
   ```bash
   ./install.sh ~/.dotfiles VPS_PROD -s -u -d
   ```
3. Restore Docker volumes from restic backups
4. Start Docker stacks: `cd ~/docker && docker compose up -d`

---

## 3. Security Incident Response

### 3.1 Suspected Compromise

**Immediate Actions:**

1. **Isolate:** Disconnect affected system from network if possible
2. **Preserve:** Do not reboot or destroy evidence
3. **Document:** Record timestamps, symptoms, and actions taken

**Investigation:**

1. Check authentication logs:
   ```bash
   journalctl -u sshd --since "1 hour ago"
   ```

2. Check for unauthorized processes:
   ```bash
   ps aux | grep -v "^\[" | sort -nrk 3 | head -20
   ```

3. Check network connections:
   ```bash
   ss -tunapl
   ```

4. Check for modified files:
   ```bash
   find /etc -mtime -1 -type f
   ```

**Recovery:**

1. Rotate all credentials (see Section 1)
2. Rebuild affected systems from NixOS configuration
3. Review and strengthen firewall rules
4. Update monitoring alerts

---

### 3.2 Service Outage

**Diagnosis:**

1. Check service status:
   ```bash
   systemctl status <service>
   journalctl -u <service> --since "10 minutes ago"
   ```

2. Check resource usage:
   ```bash
   htop
   df -h
   ```

3. Check network connectivity:
   ```bash
   ping 192.168.8.1  # Gateway
   curl -I https://service.local.akunito.com
   ```

**Recovery:**

1. Restart service:
   ```bash
   systemctl restart <service>
   ```

2. If NixOS issue, rebuild:
   ```bash
   cd ~/.dotfiles && ./install.sh ~/.dotfiles <PROFILE> -s
   ```

3. If Docker issue:
   ```bash
   cd ~/.homelab/<stack>
   docker-compose down && docker-compose up -d
   ```

---

## 4. Contact Information

### External Services

| Service | Support URL | Account |
|---------|-------------|---------|
| Cloudflare | dash.cloudflare.com | diego88aku@gmail.com |
| SMTP2GO | smtp2go.com | homelab@akunito.com |
| Let's Encrypt | letsencrypt.org | N/A (email: diego88aku@gmail.com) |

### Key File Locations

| Purpose | Location | Host |
|---------|----------|------|
| Dotfiles git-crypt key | ~/.git-crypt/dotfiles-key | All |
| VPS git-crypt key | /root/.git-crypt-key | VPS |
| Database secrets | /etc/secrets/db-*-password | VPS |
| Redis password | /etc/secrets/redis-password | VPS |
| Cloudflared tunnel token | Environment variable | VPS (Docker) + TrueNAS (Docker) |

---

## 5. Related Documentation

- [hardening.md](./hardening.md) - Security hardening guidelines
- [git-crypt.md](./git-crypt.md) - Secrets management
- [INFRASTRUCTURE_INTERNAL.md](../infrastructure/INFRASTRUCTURE_INTERNAL.md) - Infrastructure details
