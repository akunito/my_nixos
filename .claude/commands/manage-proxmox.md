# Manage Proxmox

Skill for managing Proxmox VE, including LXC container operations, LVM storage, and cloning.

## Purpose

Use this skill to:
- Clone LXC containers with encrypted storage
- Manage LVM thin provisioning
- Resize container disks
- Create and restore snapshots
- Monitor Proxmox resources

---

## Connection Details

| Host | SSH Command | Repository |
|------|-------------|------------|
| Proxmox VE | `ssh -A root@192.168.8.82` | `/root/` |

**Important**: Always use `-A` flag for SSH agent forwarding.

---

## LXC Container Management

### List All Containers

```bash
ssh -A root@192.168.8.82 "pct list"
```

### Container Status

```bash
# Single container
ssh -A root@192.168.8.82 "pct status <CTID>"

# All containers with resources
ssh -A root@192.168.8.82 "pct list && echo '---' && pvesh get /cluster/resources --type vm --output-format table"
```

### Start/Stop/Restart Container

```bash
ssh -A root@192.168.8.82 "pct start <CTID>"
ssh -A root@192.168.8.82 "pct stop <CTID>"
ssh -A root@192.168.8.82 "pct reboot <CTID>"
```

### Enter Container Console

```bash
ssh -A root@192.168.8.82 "pct enter <CTID>"
```

---

## Cloning Containers with Encrypted Storage

### Method: Clone Encrypted LVM Volume

When cloning a container with LUKS-encrypted LVM storage, you must clone the LVM volume directly (not using `pct clone`) to preserve encryption.

### Step-by-Step Clone Process

#### 1. Identify Source Container Storage

```bash
ssh -A root@192.168.8.82 "pct config <SOURCE_CTID> | grep rootfs"
# Example output: rootfs: zfspool:subvol-285-disk-0,size=24G
# or: rootfs: pve/vm-285-disk-0,size=24G
```

#### 2. Stop Source Container (if needed for consistency)

```bash
ssh -A root@192.168.8.82 "pct stop <SOURCE_CTID>"
```

#### 3. Clone LVM Volume

```bash
# For LVM thin volumes
ssh -A root@192.168.8.82 "lvcreate -s -n vm-<NEW_CTID>-disk-0 pve/vm-<SOURCE_CTID>-disk-0"

# Example: Clone container 285 to new container 204
ssh -A root@192.168.8.82 "lvcreate -s -n vm-204-disk-0 pve/vm-285-disk-0"
```

#### 4. Create Container Config

```bash
# Copy and modify config
ssh -A root@192.168.8.82 "cp /etc/pve/lxc/<SOURCE_CTID>.conf /etc/pve/lxc/<NEW_CTID>.conf"

# Edit config (change hostname, IP, etc.)
ssh -A root@192.168.8.82 "nano /etc/pve/lxc/<NEW_CTID>.conf"
```

Config modifications needed:
- Change `hostname`
- Update `rootfs` to point to new volume
- Remove any bind mounts that shouldn't be cloned
- Update network configuration if needed

#### 5. Resize Disk (if needed)

```bash
# Extend LVM volume
ssh -A root@192.168.8.82 "lvextend -L +46G pve/vm-<NEW_CTID>-disk-0"

# Resize filesystem (must stop container first, or do from inside)
# From host (container stopped):
ssh -A root@192.168.8.82 "e2fsck -f /dev/pve/vm-<NEW_CTID>-disk-0 && resize2fs /dev/pve/vm-<NEW_CTID>-disk-0"

# From inside container (container running):
ssh -A root@192.168.8.82 "pct exec <NEW_CTID> -- resize2fs /dev/sda"
```

#### 6. Start New Container

```bash
ssh -A root@192.168.8.82 "pct start <NEW_CTID>"
```

---

## LVM Storage Management

### View LVM Volumes

```bash
# List all logical volumes
ssh -A root@192.168.8.82 "lvs"

# Detailed view
ssh -A root@192.168.8.82 "lvs -o +devices"

# View thin pool status
ssh -A root@192.168.8.82 "lvs -o lv_name,data_percent,metadata_percent pve/data"
```

### Resize LVM Volume

```bash
# Extend by amount
ssh -A root@192.168.8.82 "lvextend -L +20G pve/vm-<CTID>-disk-0"

# Set absolute size
ssh -A root@192.168.8.82 "lvextend -L 70G pve/vm-<CTID>-disk-0"
```

### Delete LVM Volume

```bash
# WARNING: Destructive!
ssh -A root@192.168.8.82 "lvremove pve/vm-<CTID>-disk-0"
```

---

## Container Configuration

### View Config

```bash
ssh -A root@192.168.8.82 "pct config <CTID>"
```

### Edit Config

```bash
# Direct edit
ssh -A root@192.168.8.82 "nano /etc/pve/lxc/<CTID>.conf"

# Or via pct set
ssh -A root@192.168.8.82 "pct set <CTID> --memory 16384 --cores 6"
```

### Common Config Settings

```conf
# Example LXC config (/etc/pve/lxc/204.conf)
arch: amd64
cores: 6
features: nesting=1
hostname: database
memory: 16384
net0: name=eth0,bridge=vmbr0,hwaddr=BC:24:11:DB:04:01,ip=dhcp,type=veth
ostype: nixos
rootfs: pve/vm-204-disk-0,size=70G
swap: 512
unprivileged: 1
```

### Key Features

| Feature | Config | Purpose |
|---------|--------|---------|
| Nesting | `features: nesting=1` | Docker inside LXC |
| Memory | `memory: 16384` | RAM in MB |
| Cores | `cores: 6` | vCPU count |
| Swap | `swap: 512` | Swap in MB |

---

## Snapshots

### Create Snapshot

```bash
# Container must be stopped for consistent snapshots
ssh -A root@192.168.8.82 "pct stop <CTID>"
ssh -A root@192.168.8.82 "pct snapshot <CTID> <snapshot_name> --description 'Description'"
ssh -A root@192.168.8.82 "pct start <CTID>"
```

### List Snapshots

```bash
ssh -A root@192.168.8.82 "pct listsnapshot <CTID>"
```

### Rollback to Snapshot

```bash
ssh -A root@192.168.8.82 "pct stop <CTID>"
ssh -A root@192.168.8.82 "pct rollback <CTID> <snapshot_name>"
ssh -A root@192.168.8.82 "pct start <CTID>"
```

### Delete Snapshot

```bash
ssh -A root@192.168.8.82 "pct delsnapshot <CTID> <snapshot_name>"
```

---

## Monitoring

### Resource Usage

```bash
# CPU, memory, disk for all VMs/containers
ssh -A root@192.168.8.82 "pvesh get /cluster/resources --type vm --output-format table"
```

### Storage Usage

```bash
# Storage pools
ssh -A root@192.168.8.82 "pvesm status"

# Detailed storage info
ssh -A root@192.168.8.82 "df -h /var/lib/vz"
```

### Network

```bash
# Check container network
ssh -A root@192.168.8.82 "pct exec <CTID> -- ip addr"
```

---

## LUKS Encryption (LXC_database)

The LXC_database container uses LUKS encryption managed at the LVM level.

### Check Encryption Status

```bash
# View LUKS info (if applicable)
ssh -A root@192.168.8.82 "cryptsetup status pve-vm--<CTID>--disk--0 2>/dev/null || echo 'Not a LUKS device (encryption at different layer)'"
```

### Unlock Script Location

For containers with encrypted root, the unlock script is at:
- `/root/unlock_luks.sh` on Proxmox host

---

## Common Operations Checklist

### New Container from Template

1. `pct clone <template_id> <new_id> --full --storage local-lvm`
2. `pct set <new_id> --hostname <name> --memory <MB> --cores <N>`
3. `pct start <new_id>`

### Clone Encrypted Container

1. Stop source: `pct stop <source_id>`
2. Clone LVM: `lvcreate -s -n vm-<new_id>-disk-0 pve/vm-<source_id>-disk-0`
3. Copy config: `cp /etc/pve/lxc/<source_id>.conf /etc/pve/lxc/<new_id>.conf`
4. Edit config: hostname, rootfs path
5. Resize if needed: `lvextend` + `resize2fs`
6. Start: `pct start <new_id>`

### Resize Disk

1. Extend LVM: `lvextend -L +<size>G pve/vm-<id>-disk-0`
2. Resize FS: `resize2fs /dev/pve/vm-<id>-disk-0` (from host, container stopped)
3. Or from inside: `resize2fs /dev/sda`

---

## Container Inventory

| CTID | Name | IP | Purpose |
|------|------|-----|---------|
| 80 | LXC_HOME | 192.168.8.80 | Media/Homelab services |
| 85 | LXC_monitoring | 192.168.8.85 | Grafana/Prometheus |
| 86 | LXC_plane | 192.168.8.86 | Plane project management |
| 87 | LXC_liftcraftTEST | 192.168.8.87 | LiftCraft test |
| 88 | LXC_portfolioprod | 192.168.8.88 | Portfolio production |
| 89 | LXC_mailer | 192.168.8.89 | Postfix/Kuma |
| 102 | LXC_proxy | 192.168.8.102 | NPM/Cloudflared |
| 204 | LXC_database | 192.168.8.103 | PostgreSQL/MariaDB/Redis |
| 251 | LXC_matrix | 192.168.8.104 | Matrix Synapse/Element/Claude Bot |
| 205 | LXC_tailscale | 192.168.8.105 | Tailscale subnet router |
| 285 | Template | - | NixOS template (encrypted) |

---

## Troubleshooting

### Container Won't Start

```bash
# Check config syntax
ssh -A root@192.168.8.82 "pct config <CTID>"

# Check logs
ssh -A root@192.168.8.82 "journalctl -u pve-container@<CTID> --no-pager | tail -50"

# Check storage exists
ssh -A root@192.168.8.82 "lvs | grep vm-<CTID>"
```

### Disk Full

```bash
# Check disk usage inside container
ssh -A root@192.168.8.82 "pct exec <CTID> -- df -h"

# Extend disk
ssh -A root@192.168.8.82 "lvextend -L +10G pve/vm-<CTID>-disk-0"
ssh -A root@192.168.8.82 "pct exec <CTID> -- resize2fs /dev/sda"
```

### Network Issues

```bash
# Check network config
ssh -A root@192.168.8.82 "pct config <CTID> | grep net"

# Check from inside
ssh -A root@192.168.8.82 "pct exec <CTID> -- ip addr"
ssh -A root@192.168.8.82 "pct exec <CTID> -- ip route"
```
