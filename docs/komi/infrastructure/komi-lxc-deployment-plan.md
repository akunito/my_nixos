---
id: komi.infrastructure.deployment-plan
summary: Full deployment plan for Komi's LXC infrastructure
tags: [komi, infrastructure, lxc, proxmox, deployment, plan]
related_files: [profiles/KOMI_LXC*]
date: 2026-02-17
status: published
---

# Komi LXC Deployment Plan — Execution Reference

## Phase 5: Proxmox Container Creation

This phase requires SSH access to Komi's Proxmox (192.168.1.3).

### Container Specifications

| CTID | Profile | Cores | RAM (MB) | Disk (GB) | IP |
|------|---------|-------|----------|-----------|-----|
| 110 | KOMI_LXC_database | 2 | 4096 | 30 | 192.168.1.10 |
| 111 | KOMI_LXC_mailer | 1 | 1024 | 10 | 192.168.1.11 |
| 112 | KOMI_LXC_monitoring | 2 | 2048 | 20 | 192.168.1.12 |
| 113 | KOMI_LXC_proxy | 1 | 1024 | 10 | 192.168.1.13 |
| 114 | KOMI_LXC_tailscale | 1 | 1024 | 8 | 192.168.1.14 |

### Clone and Configure

Execute on `ssh -A root@192.168.1.3`:

```bash
# 1. Stop source container
pct stop 102

# 2. Clone LVM snapshots from CT 102
for ctid in 110 111 112 113 114; do
  lvcreate -s -n vm-${ctid}-disk-0 vg_encrypted_lxc/vm-102-disk-0
done

# 3. Copy configs
for ctid in 110 111 112 113 114; do
  cp /etc/pve/lxc/102.conf /etc/pve/lxc/${ctid}.conf
done

# 4. Edit each config
# CTID 110 (database):
cat > /etc/pve/lxc/110.conf << 'EOF'
arch: amd64
cores: 2
features: nesting=1
hostname: komi-database
memory: 4096
net0: name=eth0,bridge=vmbr0,ip=192.168.1.10/24,gw=192.168.1.1,type=veth
ostype: nixos
rootfs: vg_encrypted_lxc:vm-110-disk-0,size=30G
swap: 512
unprivileged: 1
EOF

# CTID 111 (mailer):
cat > /etc/pve/lxc/111.conf << 'EOF'
arch: amd64
cores: 1
features: nesting=1
hostname: komi-mailer
memory: 1024
net0: name=eth0,bridge=vmbr0,ip=192.168.1.11/24,gw=192.168.1.1,type=veth
ostype: nixos
rootfs: vg_encrypted_lxc:vm-111-disk-0,size=10G
swap: 512
unprivileged: 1
EOF

# CTID 112 (monitoring):
cat > /etc/pve/lxc/112.conf << 'EOF'
arch: amd64
cores: 2
features: nesting=1
hostname: komi-monitoring
memory: 2048
net0: name=eth0,bridge=vmbr0,ip=192.168.1.12/24,gw=192.168.1.1,type=veth
ostype: nixos
rootfs: vg_encrypted_lxc:vm-112-disk-0,size=20G
swap: 512
unprivileged: 1
EOF

# CTID 113 (proxy):
cat > /etc/pve/lxc/113.conf << 'EOF'
arch: amd64
cores: 1
features: nesting=1
hostname: komi-proxy
memory: 1024
net0: name=eth0,bridge=vmbr0,ip=192.168.1.13/24,gw=192.168.1.1,type=veth
ostype: nixos
rootfs: vg_encrypted_lxc:vm-113-disk-0,size=10G
swap: 512
unprivileged: 1
EOF

# CTID 114 (tailscale):
cat > /etc/pve/lxc/114.conf << 'EOF'
arch: amd64
cores: 1
features: nesting=1
hostname: komi-tailscale
memory: 1024
net0: name=eth0,bridge=vmbr0,ip=192.168.1.14/24,gw=192.168.1.1,type=veth
ostype: nixos
rootfs: vg_encrypted_lxc:vm-114-disk-0,size=8G
swap: 512
unprivileged: 1
EOF

# 5. Resize database disk (CT 102 is 24G, database needs 30G)
lvextend -L 30G vg_encrypted_lxc/vm-110-disk-0
resize2fs /dev/vg_encrypted_lxc/vm-110-disk-0

# 6. Update unlock script
# Edit /root/scripts/unlock_luks.sh and set:
# ENCRYPTED_LXC_CONTAINERS="110 111 112 113 114"
# Do NOT include CT 102 (template)

# 7. Ensure CT 102 does NOT autostart
# Remove any 'onboot: 1' line from /etc/pve/lxc/102.conf

# 8. Start new containers
for ctid in 110 111 112 113 114; do pct start $ctid; done
```

### Post-Clone Setup Per Container

```bash
# For each container (110-114):
pct enter <CTID>

# Create admin user
useradd -m -s /bin/bash admin
passwd admin  # set temporary password
usermod -aG wheel admin
mkdir -p /home/admin/.ssh
cat > /home/admin/.ssh/authorized_keys << 'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICNuaNKI7wjrI10olCOkRO/Y2RT+G6c+IkzvvRO1wSsX komi@Ms-Macbook.local
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com
EOF
chown -R admin:admin /home/admin/.ssh
chmod 700 /home/admin/.ssh
chmod 600 /home/admin/.ssh/authorized_keys

# Exit container, then SSH as admin
exit
ssh admin@192.168.1.<XX>

# Clone dotfiles
git clone git@github.com:<repo>.git ~/.dotfiles
cd ~/.dotfiles
git-crypt unlock --key-name komi ~/komi-key

# First-time install
./install.sh ~/.dotfiles KOMI_LXC_<name> -s -u -d -h -f
```

## Verification Checklist

- [ ] All 5 KOMI_LXC profiles evaluate: `nix eval .#nixosConfigurations.KOMI_LXC_database --apply 'x: "ok"'`
- [ ] `deploy.sh --komi --list` shows only Komi's 5 containers
- [ ] `deploy.sh --aku --list` shows only akunito's servers
- [ ] git-crypt-komi key created and exported to `~/.git-crypt/komi-key`
- [ ] No hardcoded "akunito" in any KOMI_LXC profile files
- [ ] Proxmox containers 110-114 created with correct specs and static IPs
- [ ] Each container boots and is reachable via `ssh admin@192.168.1.{10-14}`
- [ ] First `install.sh` succeeds on each container
- [ ] Documentation complete in `docs/komi/infrastructure/`
- [ ] CLAUDE.md updated with KOMI_LXC scoping rules
