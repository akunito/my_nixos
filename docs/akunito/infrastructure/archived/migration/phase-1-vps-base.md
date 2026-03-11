---
id: infrastructure.migration.phase-1
summary: "VPS base setup: NixOS, LUKS, Tailscale, WireGuard"
tags: [infrastructure, migration, vps, nixos, security]
date: 2026-02-23
status: published
---

# Phase 1: VPS Base Setup

## Status: ~90%

Remaining: final egress audit review, documentation of all iptables rules in runbook.

---

## NixOS Installation with LUKS Full-Disk Encryption

### Disk Layout

The VPS has a single 1TB NVMe disk (`/dev/vda`), partitioned as follows:

| Partition | Size | Type | Purpose |
|-----------|------|------|---------|
| vda1 | 512MB | EFI System Partition (FAT32) | GRUB EFI bootloader |
| vda2 | ~999.5GB | LUKS2 encrypted | Root filesystem (ext4) |

### Encryption Setup

```bash
# LUKS2 encryption on the root partition
cryptsetup luksFormat --type luks2 /dev/vda2
cryptsetup luksOpen /dev/vda2 cryptroot
mkfs.ext4 /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt

# EFI partition
mkfs.fat -F 32 /dev/vda1
mkdir -p /mnt/boot
mount /dev/vda1 /mnt/boot
```

### NixOS Boot Configuration

GRUB is used (not systemd-boot) because the VPS uses BIOS/UEFI hybrid booting:

```nix
boot.loader.grub = {
  enable = true;
  device = "nodev";
  efiSupport = true;
  efiInstallAsRemovable = true;
};

boot.initrd.luks.devices."cryptroot" = {
  device = "/dev/disk/by-uuid/<UUID-of-vda2>";
  preLVM = true;
};
```

### Static Networking

The VPS uses static IP assignment (no DHCP from Netcup):

```nix
networking = {
  useDHCP = false;
  interfaces.ens3.ipv4.addresses = [{
    address = "<VPS-PUBLIC-IP>";  # From secrets
    prefixLength = 22;
  }];
  defaultGateway = "<GATEWAY-IP>";  # From secrets
  nameservers = [ "1.1.1.1" "8.8.8.8" ];
};
```

IPv6 is explicitly disabled:

```nix
networking.enableIPv6 = false;
boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;
boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 1;
```

---

## Initrd SSH Unlock (Remote LUKS Passphrase Entry)

After a VPS reboot, the system halts at the LUKS passphrase prompt. Since there is no physical console, an SSH server runs inside the initrd to accept the passphrase remotely.

### Configuration

```nix
boot.initrd.network = {
  enable = true;
  ssh = {
    enable = true;
    port = 2222;
    hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
    authorizedKeys = [ "<your-public-key>" ];
  };
};
```

### Unlock Procedure

```bash
# After VPS reboot, connect to initrd SSH
ssh -p 2222 root@<VPS-TAILSCALE-IP>

# At the initrd prompt, unlock LUKS
cryptsetup-askpass
# Enter passphrase when prompted

# System continues booting to NixOS
# Wait ~30 seconds, then connect normally
ssh -A -p 56777 akunito@<VPS-TAILSCALE-IP>
```

The initrd SSH uses a different host key than the main system, so SSH will warn about host key mismatch. Use a separate known_hosts entry or `-o StrictHostKeyChecking=no` for the initrd connection.

---

## Profile Architecture

### VPS Profile Hierarchy

```
lib/defaults.nix
    |
    v
VPS-base-config.nix        # Common VPS settings
    |
    v
VPS_PROD-config.nix        # Production VPS overrides
```

**VPS-base-config.nix** defines:
- Docker rootless mode
- Base security settings
- Common system packages
- Monitoring agent configuration

**VPS_PROD-config.nix** defines:
- Hostname, network settings (from secrets)
- LUKS device configuration
- Service-specific flags (which Docker stacks to deploy)
- Headscale configuration
- WireGuard configuration
- SSH hardening overrides

---

## Rootless Docker

Docker runs as the unprivileged `akunito` user, not as root:

```nix
virtualisation.docker = {
  enable = true;
  rootless = {
    enable = true;
    setSocketVariable = true;
  };
};

# Enable user linger so Docker persists after logout
users.users.akunito.linger = true;

# Allow unprivileged users to bind ports 80+
boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 80;
```

This means:
- Docker socket is at `$XDG_RUNTIME_DIR/docker.sock`
- Containers run as sub-UIDs mapped to the `akunito` user
- Port 80 and 443 can be bound without root
- `docker compose` commands run as `akunito`, not with sudo
- Container data stored under `/home/akunito/.local/share/docker/`

---

## SSH Hardening

### Port and Access Control

SSH listens on a non-standard port and is restricted to VPN subnets only:

```nix
services.openssh = {
  enable = true;
  ports = [ 56777 ];
  settings = {
    PasswordAuthentication = false;
    PermitRootLogin = "no";
    KbdInteractiveAuthentication = false;
  };
};
```

### VPN-Only SSH Access (iptables)

SSH is only accessible from Tailscale and WireGuard subnets:

```nix
networking.firewall.extraCommands = ''
  # Allow SSH only from Tailscale (100.64.0.0/10) and WireGuard (172.26.5.0/24)
  iptables -A INPUT -p tcp --dport 56777 -s 100.64.0.0/10 -j ACCEPT
  iptables -A INPUT -p tcp --dport 56777 -s 172.26.5.0/24 -j ACCEPT
  iptables -A INPUT -p tcp --dport 56777 -j DROP
'';
```

This means SSH is unreachable from the public internet. An attacker must first compromise either the Tailscale network or the WireGuard VPN to even attempt an SSH connection.

### Cipher Restrictions

Only modern, high-security ciphers are permitted:

```nix
services.openssh.settings = {
  Ciphers = [
    "chacha20-poly1305@openssh.com"
    "aes256-gcm@openssh.com"
  ];
  KexAlgorithms = [
    "curve25519-sha256"
    "curve25519-sha256@libssh.org"
  ];
  Macs = [
    "hmac-sha2-512-etm@openssh.com"
    "hmac-sha2-256-etm@openssh.com"
  ];
};
```

---

## Passwordless Sudo via SSH Agent

The VPS uses `pam_ssh_agent_auth` to allow passwordless sudo when an SSH agent is forwarded. This avoids storing or transmitting passwords while maintaining sudo security:

```nix
security.pam.sshAgentAuth.enable = true;
security.pam.sshAgentAuth.authorizedKeysFiles = [
  "/etc/ssh/authorized_keys.d/%u"
];
```

How it works:
1. Connect with `ssh -A` (agent forwarding)
2. Run `sudo <command>`
3. PAM challenges the forwarded SSH agent to sign a nonce
4. If the agent holds an authorized key, sudo succeeds without password
5. If no agent or unauthorized key, falls back to password prompt

This is the preferred method for deploying via `install.sh` on the VPS:
```bash
ssh -A -p 56777 akunito@<VPS-IP> "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

---

## Kernel Hardening

Comprehensive sysctl hardening applied via NixOS configuration:

```nix
boot.kernel.sysctl = {
  # SYN flood protection
  "net.ipv4.tcp_syncookies" = 1;
  "net.ipv4.tcp_max_syn_backlog" = 2048;
  "net.ipv4.tcp_synack_retries" = 2;

  # IP spoofing protection
  "net.ipv4.conf.all.rp_filter" = 1;
  "net.ipv4.conf.default.rp_filter" = 1;

  # Disable source routing
  "net.ipv4.conf.all.accept_source_route" = 0;
  "net.ipv4.conf.default.accept_source_route" = 0;

  # Disable ICMP redirects
  "net.ipv4.conf.all.accept_redirects" = 0;
  "net.ipv4.conf.default.accept_redirects" = 0;
  "net.ipv4.conf.all.send_redirects" = 0;

  # Log martian packets
  "net.ipv4.conf.all.log_martians" = 1;

  # Restrict ptrace
  "kernel.yama.ptrace_scope" = 2;

  # Restrict BPF
  "kernel.unprivileged_bpf_disabled" = 1;
  "net.core.bpf_jit_harden" = 2;

  # Restrict kernel pointers
  "kernel.kptr_restrict" = 2;

  # Restrict dmesg
  "kernel.dmesg_restrict" = 1;
};
```

---

## Headscale Migration

Migrated from the old Hetzner VPS to the new Netcup VPS. Headscale runs as a NixOS native service (not Docker).

### Migration Steps

1. **Export database from old VPS**
   ```bash
   # On old Hetzner VPS
   scp /var/lib/headscale/db.sqlite3 akunito@<DESK-IP>:/tmp/headscale-db-backup.sqlite3
   ```

2. **Import on new VPS**
   ```bash
   # On new Netcup VPS
   sudo systemctl stop headscale
   sudo cp /tmp/headscale-db-backup.sqlite3 /var/lib/headscale/db.sqlite3
   sudo chown headscale:headscale /var/lib/headscale/db.sqlite3
   sudo systemctl start headscale
   ```

3. **DNS cutover**
   - Updated `headscale.akunito.com` DNS A record to new VPS public IP
   - TTL was set to 300s (5 minutes) before migration for fast propagation

4. **Client reconnection**
   - All Tailscale clients reconnected automatically without re-authentication
   - Headscale preserves node keys and machine state in the SQLite database
   - No client-side changes required

### NixOS Headscale Configuration

```nix
services.headscale = {
  enable = true;
  port = 8080;
  settings = {
    server_url = "https://headscale.akunito.com";
    dns = {
      base_domain = "tail.akunito.com";
      nameservers.global = [ "1.1.1.1" "8.8.8.8" ];
    };
  };
};
```

---

## WireGuard Configuration

Reused the same WireGuard private key from the old Hetzner VPS to maintain peer compatibility:

1. **Key migration** -- copied private key from old VPS, stored in secrets (git-crypt encrypted)
2. **pfSense peer update** -- changed the endpoint IP in pfSense WireGuard peer configuration to the new VPS public IP
3. **No client changes** -- all WireGuard peers (pfSense, mobile devices) reconnected after endpoint update

The WireGuard interface provides the 172.26.5.0/24 subnet, used for:
- Site-to-site VPN between homelab and VPS
- SSH access fallback if Tailscale is unavailable
- Monitoring traffic (Prometheus scraping)

---

## Fail2ban

```nix
services.fail2ban = {
  enable = true;
  maxretry = 3;
  bantime = "1h";
  bantime-increment = {
    enable = true;
    maxtime = "168h";  # 1 week max ban
  };
};
```

Monitors SSH (port 56777) for brute-force attempts. Bans escalate from 1 hour to 1 week maximum.

---

## Egress Audit Timer

A systemd timer runs periodically to audit outbound connections and log unexpected egress traffic:

```nix
systemd.timers."egress-audit" = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "hourly";
    Persistent = true;
  };
};
```

The audit script logs all established outbound connections and compares against a known-good baseline. Unexpected destinations trigger a notification.

---

## Break-Glass Recovery Runbook (DR-002)

If the VPS becomes unreachable after a reboot (LUKS not unlocked, network misconfiguration, etc.):

1. **Access Netcup SCP (Server Control Panel)**
   - Login at https://www.servercontrolpanel.de
   - Navigate to the VPS instance
   - Use the VNC console for direct access

2. **VNC Console LUKS Unlock**
   - If stuck at LUKS prompt, enter the passphrase via VNC
   - Passphrase stored in password manager (NOT in dotfiles)

3. **Rescue Mode**
   - Boot into Netcup rescue system (Debian-based)
   - Mount LUKS partition:
     ```bash
     cryptsetup luksOpen /dev/vda2 cryptroot
     mount /dev/mapper/cryptroot /mnt
     mount /dev/vda1 /mnt/boot
     ```
   - Chroot and fix configuration:
     ```bash
     nixos-enter --root /mnt
     # Fix networking, SSH, or other config
     nixos-rebuild switch
     ```

4. **Rollback**
   - NixOS keeps previous generations in GRUB
   - Select previous generation from GRUB menu via VNC console
   - Or from rescue mode: `nix-env --list-generations --profile /mnt/nix/var/nix/profiles/system`

5. **Network Recovery**
   - If Tailscale is down, WireGuard provides backup VPN path
   - If both VPNs are down, Netcup VNC console is the last resort
   - Static IP configuration means no DHCP dependency

---

## Related Documents

- [Phase 0: Preparation](phase-0-preparation.md)
- [Migration Index](README.md)
- [VPS Service Documentation](../services/) -- individual service docs
