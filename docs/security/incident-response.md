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

4. Rebuild monitoring:
   ```bash
   ssh akunito@192.168.8.85
   cd ~/.dotfiles && ./install.sh ~/.dotfiles LXC_monitoring -s -u
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

5. Update LXC_mailer .env (git-crypt encrypted):
   ```bash
   ssh akunito@192.168.8.89
   cd ~/homelab-watcher
   git-crypt unlock ~/.keys/homelab-watcher.key
   vim .env
   # Update SMTP2GO_PASSWORD value
   git add .env && git commit -m "chore: rotate SMTP2GO credentials"
   docker compose down && docker compose up -d
   ```

6. Update VPS postfix-relay .env (git-crypt encrypted):
   ```bash
   ssh -p 56777 root@172.26.5.155
   cd /opt/postfix-relay
   git-crypt unlock /root/.keys/postfix-relay.key
   vim .env
   # Update SMTP_PASSWORD value
   git add .env && git commit -m "chore: rotate SMTP2GO credentials"
   docker compose down && docker compose up -d
   ```

7. Test email delivery:
   ```bash
   # On LXC_mailer
   curl --url "smtp://localhost:25" \
     --mail-from "nixos@akunito.com" \
     --mail-rcpt "diego88aku@gmail.com" \
     --upload-file - <<< "Subject: Credential Rotation Test

   SMTP2GO credentials rotated successfully."
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

### 1.4 Proxmox API Token

**When to rotate:** Suspected exposure or annual review.

**Steps:**

1. Log into Proxmox web UI (https://192.168.8.82:8006)
2. Navigate to Datacenter > Permissions > API Tokens
3. Remove old token for `prometheus@pve`
4. Create new token with same permissions (PVEAuditor)
5. Update token file on monitoring server:
   ```bash
   ssh akunito@192.168.8.85
   sudo vim /etc/secrets/pve-token
   # Paste new token value
   ```
6. Rebuild monitoring:
   ```bash
   cd ~/.dotfiles && ./install.sh ~/.dotfiles LXC_monitoring -s -u
   ```

---

### 1.5 Cloudflare API Token (ACME)

**When to rotate:** Suspected exposure or token permissions change.

**Steps:**

1. Log into Cloudflare dashboard
2. Navigate to My Profile > API Tokens
3. Revoke old token, create new one with DNS edit permissions
4. Update on LXC_proxy:
   ```bash
   ssh akunito@192.168.8.102
   sudo vim /etc/secrets/cloudflare-acme
   # Paste new API token
   ```
5. Test certificate renewal:
   ```bash
   sudo acme.sh --renew -d "*.local.akunito.com" --force
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

For Docker services on LXC_HOME:

1. Stop affected stack:
   ```bash
   ssh akunito@192.168.8.80
   cd ~/.homelab/<stack>
   docker-compose down
   ```

2. Restore from backup (if using restic):
   ```bash
   restic -r <repo> restore latest --target /mnt/DATA_4TB/docker/<stack>
   ```

3. Restart stack:
   ```bash
   docker-compose up -d
   ```

---

### 2.3 LXC Container Recovery

If LXC container is corrupted:

1. Create new LXC from Proxmox template
2. Configure network (same IP as original)
3. Mount Proxmox bind mounts
4. Clone dotfiles:
   ```bash
   git clone git@github.com:akunito/dotnix.git ~/.dotfiles
   cd ~/.dotfiles && git-crypt unlock ~/.git-crypt/dotfiles-key
   ```
5. Run install script:
   ```bash
   ./install.sh ~/.dotfiles <PROFILE> -s -u
   ```

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
| Proxmox git-crypt key | /root/.git-crypt-key | Proxmox |
| VPS git-crypt key | /root/.git-crypt-key | VPS |
| Cloudflare ACME token | /etc/secrets/cloudflare-acme | LXC_proxy |
| PVE API token | /etc/secrets/pve-token | LXC_monitoring |
| Cloudflared tunnel token | /etc/secrets/cloudflared-token | LXC_proxy |

---

## 5. Related Documentation

- [hardening.md](./hardening.md) - Security hardening guidelines
- [git-crypt.md](./git-crypt.md) - Secrets management
- [INFRASTRUCTURE_INTERNAL.md](../infrastructure/INFRASTRUCTURE_INTERNAL.md) - Infrastructure details
