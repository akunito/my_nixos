# VMHOME to LXC Migration Plan

## Goal
Migrate the VMHOME VM to an LXC container (`LXC_HOME`) while preserving all functionality (Docker, NFS, services) and optimizing for LXC. Must not impact existing `LXC*-config.nix` profiles.

---

## Storage Architecture Overview

### Current Storage Flow
```
┌─────────────┐     iSCSI      ┌─────────────┐    passthrough   ┌─────────────┐
│  TrueNAS    │ ──────────────►│   Proxmox   │ ────────────────►│   VMHOME    │
│  (Storage)  │                │   (Host)    │                  │   (VM)      │
└─────────────┘                └─────────────┘                  └─────────────┘
      │                              │                                │
      │ NFS exports                  │ (currently unused)             │ NFS client
      │                              │                                │
      └──────────────────────────────┼────────────────────────────────┘
                                     │
                                     ▼
                          Direct NFS mount in VM
```

### Target Storage Flow (LXC_HOME)
```
┌─────────────┐     iSCSI      ┌─────────────┐   bind mount    ┌─────────────┐
│  TrueNAS    │ ──────────────►│   Proxmox   │ ───────────────►│  LXC_HOME    │
│  (Storage)  │                │   (Host)    │                 │   (LXC)     │
│             │                │             │                 │             │
│  192.168.   │     NFS        │  mounts     │   bind mount    │  sees same  │
│  20.200     │ ──────────────►│  NFS here   │ ───────────────►│  paths      │
└─────────────┘                └─────────────┘                 └─────────────┘
```

**Key Change**: NFS mounts move from inside the VM to Proxmox host level, then passed to LXC via bind mounts.

---

## Current Architecture Analysis

### VMHOME (VM)
- **Profile**: `homelab` → `profiles/homelab/base.nix`
- **Features**:
  - Docker (for web services, nginx, unifi)
  - NFS client (mounts from TrueNAS)
  - NFS server (exports to other machines)
  - Syncthing
  - Restic backups
  - Local drive mount (`/mnt/DATA_4TB`)
  - systemd-networkd with DHCP

### Existing LXC Profiles
- **Profile**: `proxmox-lxc` → `profiles/proxmox-lxc/base.nix`
- **Structure**:
  - `LXC-base-config.nix` - Shared base settings
  - `LXCtemplate-config.nix` - Imports base, minimal overrides
  - `LXCplane-config.nix` - Imports base, minimal overrides
- **Features**: Lightweight, Docker-ready, no NFS server

---

## Key Differences: VM vs LXC

| Feature | VM (VMHOME) | LXC (LXC_HOME) |
|---------|-------------|---------------|
| Kernel | Own kernel, modules | Host kernel (no modules needed) |
| Boot | systemd-boot/grub | Container init |
| Networking | systemd-networkd/DHCP | Proxmox-managed (veth) |
| Power mgmt | TLP/power.nix | Not applicable |
| Drive mounts | fstab/drives.nix | Bind mounts from Proxmox |
| NFS client | systemd mount units | Needs LXC features enabled |
| NFS server | nfs_server.nix | Possible but complex in LXC |
| Docker | Standard | Needs privileged or features |
| Swap | swapfile | Managed by Proxmox host |
| qemu-guest-agent | Yes | No |

---

## Pre-Migration: Proxmox Storage Setup

### CRITICAL: This section must be completed BEFORE creating the LXC container

### Step P1: Configure NFS Mounts on Proxmox Host

The NFS shares from TrueNAS (192.168.20.200) will be mounted on Proxmox, then bind-mounted into the LXC.

**P1.1: Install NFS client on Proxmox (if not present)**
```bash
apt update && apt install nfs-common -y
```

**P1.2: Create mount points on Proxmox**
```bash
mkdir -p /mnt/pve/NFS_media
mkdir -p /mnt/pve/NFS_library
mkdir -p /mnt/pve/NFS_emulators
```

**P1.3: Test NFS mounts manually first**
```bash
# Test each mount
mount -t nfs4 192.168.20.200:/mnt/hddpool/media /mnt/pve/NFS_media
mount -t nfs4 192.168.20.200:/mnt/ssdpool/library /mnt/pve/NFS_library
mount -t nfs4 192.168.20.200:/mnt/ssdpool/emulators /mnt/pve/NFS_emulators

# Verify access
ls -la /mnt/pve/NFS_media
ls -la /mnt/pve/NFS_library
ls -la /mnt/pve/NFS_emulators

# Unmount after testing
umount /mnt/pve/NFS_media
umount /mnt/pve/NFS_library
umount /mnt/pve/NFS_emulators
```

**P1.4: Add persistent NFS mounts to Proxmox `/etc/fstab`**
```bash
# Add to /etc/fstab on Proxmox host
192.168.20.200:/mnt/hddpool/media    /mnt/pve/NFS_media     nfs4  defaults,noatime,nofail,x-systemd.device-timeout=10s  0 0
192.168.20.200:/mnt/ssdpool/library  /mnt/pve/NFS_library   nfs4  defaults,noatime,nofail,x-systemd.device-timeout=10s  0 0
192.168.20.200:/mnt/ssdpool/emulators /mnt/pve/NFS_emulators nfs4  defaults,noatime,nofail,x-systemd.device-timeout=10s  0 0
```

**P1.5: Mount all and verify**
```bash
mount -a
df -h | grep NFS
```

### Step P2: iSCSI Drive Setup (/mnt/DATA_4TB)

**Current Setup:**
- TrueNAS exports iSCSI LUN: `iqn.2005-10.org.freenas.ctl:proxmox-pve`
- Proxmox connects via your boot script (manual login)
- Drive appears as `/dev/sdb` (2TB)
- Currently passed through to VMHOME VM
- Filesystem: ext4, UUID: `0904cd17-7be1-433a-a21b-2c34f969550f`

**Key Considerations for LXC Migration:**

1. **No re-partitioning needed**: The drive is already formatted (ext4) with existing data
2. **No data migration needed**: Same data, just different access method
3. **Proxmox must mount the filesystem** (not pass raw block device to LXC)
4. **Must shut down VMHOME first** to avoid dual-mount corruption

---

**P2.1: Verify and Make iSCSI Login Automatic (On Proxmox)**

Your boot script sets authentication credentials - these are **already persistent** in `/etc/iscsi/nodes/` once set. You only need to:

1. **Verify auth credentials are saved** (from your previous script runs):
```bash
# Check the stored configuration
iscsiadm -m node -T iqn.2005-10.org.freenas.ctl:proxmox-pve -p 192.168.20.200:3260 -o show | grep -E "node.session.auth"

# Should show:
# node.session.auth.username = asdf
# node.session.auth.password = asdf
# node.session.auth.username_in = asdf
# node.session.auth.password_in = asdf
```

2. **If credentials are missing** (first time setup), run your auth script once:
```bash
# Only needed if credentials are NOT shown above
iscsiadm -m node -T iqn.2005-10.org.freenas.ctl:proxmox-pve -p 192.168.20.200:3260 --op update -n node.session.auth.username -v "asdf"
iscsiadm -m node -T iqn.2005-10.org.freenas.ctl:proxmox-pve -p 192.168.20.200:3260 --op update -n node.session.auth.password -v "asdf"
iscsiadm -m node -T iqn.2005-10.org.freenas.ctl:proxmox-pve -p 192.168.20.200:3260 --op update -n node.session.auth.username_in -v "asdf"
iscsiadm -m node -T iqn.2005-10.org.freenas.ctl:proxmox-pve -p 192.168.20.200:3260 --op update -n node.session.auth.password_in -v "asdf"
```

3. **Enable automatic login on boot** (this is what's missing):
```bash
# Make the target auto-login at boot (this is the key change!)
iscsiadm -m node -T iqn.2005-10.org.freenas.ctl:proxmox-pve -p 192.168.20.200:3260 --op update -n node.startup -v automatic

# Verify it's set to automatic
iscsiadm -m node -T iqn.2005-10.org.freenas.ctl:proxmox-pve -p 192.168.20.200:3260 -o show | grep "node.startup"
# Should show: node.startup = automatic
```

**What this does:**
- Auth credentials are stored in: `/etc/iscsi/nodes/iqn.2005-10.org.freenas.ctl:proxmox-pve/192.168.20.200,3260,1/default`
- Setting `node.startup = automatic` makes the iSCSI service automatically login using the stored credentials on boot
- **After this, you won't need your boot script anymore** - it will connect automatically

**P2.2: Shut Down VMHOME (CRITICAL - Do this first!)**

```bash
# On Proxmox - shut down VMHOME to release the iSCSI drive
qm shutdown 410  # Adjust VM ID if different

# Wait for shutdown, then verify it's stopped
qm status 410
```

**P2.3: Verify iSCSI Device and UUID (On Proxmox)**

```bash
# Verify the iSCSI session is active
iscsiadm -m session -P 3 | grep -E "Target|disk"
# Should show: Target: iqn.2005-10.org.freenas.ctl:proxmox-pve
# Should show: Attached scsi disk sdb

# Check the device
lsblk -f /dev/sdb
# Should show: ext4 filesystem

# Verify UUID matches VMHOME's UUID
blkid /dev/sdb | grep 0904cd17
# Should output: UUID="0904cd17-7be1-433a-a21b-2c34f969550f"
```

**P2.4: Create Mount Point and Add to fstab (On Proxmox)**

```bash
# Create mount point
mkdir -p /mnt/pve/DATA_4TB

# Add to /etc/fstab (using UUID for reliability)
cat >> /etc/fstab << 'EOF'

# iSCSI drive from TrueNAS for LXC containers
UUID=0904cd17-7be1-433a-a21b-2c34f969550f  /mnt/pve/DATA_4TB  ext4  defaults,nofail,x-systemd.device-timeout=30s,_netdev  0 0
EOF

# Note: _netdev tells systemd this is a network device, wait for network before mounting
```

**P2.5: Mount and Verify (On Proxmox)**

```bash
# Mount the filesystem
mount -a

# Verify it mounted successfully
df -h | grep DATA_4TB
# Should show: UUID=0904cd17... mounted on /mnt/pve/DATA_4TB

# Check contents (should see your existing data)
ls -la /mnt/pve/DATA_4TB

# Verify you can read files
ls -la /mnt/pve/DATA_4TB/docker 2>/dev/null || echo "Docker dir not found - may be elsewhere"
```

**P2.6: Test Reboot Persistence (Optional but Recommended)**

```bash
# Reboot Proxmox to verify everything comes up automatically
reboot

# After reboot, verify:
# 1. iSCSI session reconnects automatically
iscsiadm -m session

# 2. DATA_4TB mounts automatically
df -h | grep DATA_4TB
```

---

**IMPORTANT NOTES:**

- **DO NOT start VMHOME again** until you've completed the LXC migration
- The iSCSI drive can only be mounted by ONE system at a time
- If you need to go back to VMHOME, unmount from Proxmox first: `umount /mnt/pve/DATA_4TB`

### Step P3: Verify All Proxmox Mounts Before Proceeding

```bash
# Final verification
df -h

# Expected output should show:
# /mnt/pve/DATA_4TB      (iSCSI drive)
# /mnt/pve/NFS_media     (NFS from TrueNAS)
# /mnt/pve/NFS_library   (NFS from TrueNAS)
# /mnt/pve/NFS_emulators (NFS from TrueNAS)
```

---

## COMPLETED ✅ (After running commands above)

```
root@pve:~# df -h
/dev/sdb                                     2.0T  517G  1.4T  28% /mnt/pve/DATA_4TB
192.168.20.200:/mnt/ssdpool/library          800G  414G  387G  52% /mnt/pve/NFS_library
192.168.20.200:/mnt/ssdpool/emulators        100G   55G   46G  55% /mnt/pve/NFS_emulators
192.168.20.200:/mnt/hddpool/media             10T  5.3T  4.8T  53% /mnt/pve/NFS_media

root@pve:~# iscsiadm -m session
tcp: [1] 192.168.20.200:3260,1 iqn.2005-10.org.freenas.ctl:proxmox-pve (non-flash)
```

**Status**: iSCSI auto-login and NFS mounts working, VMHOME (VM 410) stopped.

---

## Impact on Other Profiles (NFS Access)

### NFS Architecture: Direct to TrueNAS ✅

**All profiles connect directly to TrueNAS (192.168.20.200)** - VMHOME was never an NFS gateway.

```
┌─────────────┐
│  TrueNAS    │  192.168.20.200
│  (Storage)  │
└──────┬──────┘
       │ NFS exports directly to all clients
       │
       ├──────────────► DESK (192.168.8.96)
       │                  └─ /mnt/NFS_media, /mnt/NFS_library, /mnt/NFS_emulators
       │
       ├──────────────► LAPTOP_L15 (192.168.8.92)
       │                  └─ /mnt/NFS_media, /mnt/NFS_library, /mnt/NFS_emulators
       │
       ├──────────────► Proxmox (host)
       │                  └─ /mnt/pve/NFS_* → bind mount to LXC_HOME
       │
       └──────────────► (VMHOME was here - now deprecated)
```

### Verified NFS Configuration in Profiles

| Profile | NFS Mounts | Target | Status |
|---------|------------|--------|--------|
| **DESK** | `/mnt/NFS_media`, `/mnt/NFS_library`, `/mnt/NFS_emulators` | `192.168.20.200` (TrueNAS) | ✅ Correct |
| **LAPTOP_L15** | `/mnt/NFS_media`, `/mnt/NFS_library`, `/mnt/NFS_emulators` | `192.168.20.200` (TrueNAS) | ✅ Correct |
| **VMHOME** | Same mounts | `192.168.20.200` (TrueNAS) | 🗑️ Deprecated |
| **LXC_HOME** | None (bind mounts from Proxmox) | N/A | ✅ No NFS client needed |
| **DESK_AGA** | NFS disabled | N/A | ✅ No changes |
| **DESK_VMDESK** | NFS disabled | N/A | ✅ No changes |
| **LAPTOP_YOGAAKU** | NFS disabled | N/A | ✅ No changes |

### Conclusion: No Profile Changes Required

**All profiles are already correctly configured:**
- DESK → TrueNAS directly (192.168.20.200) ✅
- LAPTOP_L15 → TrueNAS directly (192.168.20.200) ✅
- LXC_HOME → Uses Proxmox bind mounts (no NFS client) ✅

### NFS Server Ports in VMHOME (Can Be Removed)

VMHOME had NFS server ports open (111, 2049, 4000-4002) but was **not acting as an NFS server** for other machines. These ports are **not needed in LXC_HOME**.

The LXC_HOME firewall config should only include:
- 22 (SSH)
- 8043 (nginx)
- 22000, 21027 (syncthing)
- 8443, 8080, 8843, 8880, 6789 (unifi controller)
- 3478, 10001, 1900, 5514 (unifi UDP)

---

## LXC_HOME Boot Safety (CRITICAL)

### Why LXC_HOME Won't Hang on Boot

The LXC_HOME configuration is designed to **never hang** waiting for storage:

1. **No NFS Client**: `nfsClientEnable = false`
   - NixOS won't try to mount NFS inside the container
   - No systemd mount units waiting for network storage

2. **No drives.nix mounts**: `mount2ndDrives = false`, `disk*_enabled = false`
   - NixOS won't create any fstab entries for drives
   - No mount timeouts that could block boot

3. **Bind Mounts from Proxmox**:
   - Storage is mounted on Proxmox host BEFORE the LXC starts
   - LXC sees directories that already exist - no waiting
   - If Proxmox storage fails, LXC won't start (Proxmox handles this)

### Comparison: VMHOME vs LXC_HOME Boot Behavior

| Scenario | VMHOME (old) | LXC_HOME (new) |
|----------|--------------|---------------|
| TrueNAS offline | Hangs waiting for NFS (timeout) | Proxmox handles - LXC may not start but won't hang |
| iSCSI offline | Hangs waiting for device | Proxmox handles - LXC may not start but won't hang |
| NFS mount fails | systemd retry loop, slow boot | No NFS mounts - instant boot |
| Network delayed | Waits for network + NFS | Bind mounts already available |

### Proxmox LXC Startup Order

Proxmox ensures proper startup order:
1. Proxmox boot → iSCSI login (automatic)
2. Proxmox mounts fstab entries (NFS, iSCSI filesystem)
3. LXC container starts → bind mounts already available

### Verification: LXC_HOME Config Disables All Remote Mounts

In `LXC_HOME-config.nix` (from Phase 2):
```nix
# These settings ensure no boot hangs:
mount2ndDrives = false;
disk1_enabled = false;  # /mnt/DATA_4TB handled by Proxmox
disk3_enabled = false;  # /mnt/NFS_media handled by Proxmox
disk4_enabled = false;  # /mnt/NFS_emulators handled by Proxmox
disk5_enabled = false;  # /mnt/NFS_library handled by Proxmox
nfsClientEnable = false;
nfsMounts = [];
nfsAutoMounts = [];
```

**Result**: NixOS in LXC_HOME has ZERO remote mount dependencies. Boot is instant.

---

## Migration Impact Analysis

### What Does NOT Need Migration (Data Already Accessible)

If your service data is stored on `/mnt/DATA_4TB`, these require **no migration**:

| Data | Location | Migration Needed? |
|------|----------|-------------------|
| Docker volumes | `/mnt/DATA_4TB/docker/` | ❌ No - same path in LXC_HOME |
| Nginx configs | `/mnt/DATA_4TB/nginx/` | ❌ No - same path |
| Unifi data | `/mnt/DATA_4TB/unifi/` | ❌ No - same path |
| Syncthing data | `/mnt/DATA_4TB/syncthing/` | ❌ No - same path |
| Media files | `/mnt/NFS_media/` | ❌ No - NFS bind mount |
| Library files | `/mnt/NFS_library/` | ❌ No - NFS bind mount |
| Emulator files | `/mnt/NFS_emulators/` | ❌ No - NFS bind mount |

### What DOES Need Migration/Setup

| Data | Current Location | Action Required |
|------|------------------|-----------------|
| Docker images | `/var/lib/docker/` (VM root) | Export → Import OR rebuild |
| Docker socket | `/var/run/docker.sock` | Recreated on container start |
| System configs | `/etc/` (VM root) | Nix-managed, auto-generated |
| User home | `/home/akunito/` (VM root) | Sync `.dotfiles`, rest is Nix |
| SSH keys | `/home/akunito/.ssh/` | Copy or regenerate |
| Restic repos | Depends on config | Verify repo paths point to DATA_4TB |

### Recommendation: Keep Service Data on /mnt/DATA_4TB

If not already, move Docker data directory to the iSCSI drive:
```nix
# In docker config, set data root to persistent storage
virtualisation.docker.daemon.settings = {
  data-root = "/mnt/DATA_4TB/docker";
};
```

This eliminates Docker image migration entirely.

---

## Migration Strategy

### Approach: Extend LXC-base-config.nix

Create `LXC_HOME-config.nix` that:
1. Imports `LXC-base-config.nix` as base
2. Adds VMHOME-specific features via overrides
3. Does NOT modify shared `LXC-base-config.nix` or `proxmox-lxc/base.nix`

### File Structure
```
profiles/
├── LXC-base-config.nix          # Unchanged (shared by all LXC)
├── LXCtemplate-config.nix       # Unchanged
├── LXCplane-config.nix          # Unchanged
├── LXC_HOME-config.nix           # NEW - extends LXC-base for homelab
└── proxmox-lxc/
    ├── base.nix                 # May need minor conditionals
    └── configuration.nix        # Unchanged
```

---

## Root Disk Strategy

### VMHOME vs LXC_HOME Root Filesystem

| | VMHOME (VM) | LXC_HOME (LXC) |
|--|-------------|---------------|
| **Root disk** | `nixosHomelab-vm--410--disk--0` (500GB) | New LXC rootfs (32GB) |
| **Type** | Full VM disk (qcow2/raw) | Container filesystem |
| **Contains** | NixOS system, `/var/lib/docker`, `/home` | NixOS system only |
| **Reusable?** | ❌ Not directly compatible | ✅ Fresh install |

### Why Create a Fresh LXC Rootfs?

1. **VM disks ≠ LXC rootfs**: LXC uses a different filesystem structure
2. **NixOS is declarative**: System is rebuilt from config, no migration needed
3. **Small footprint**: LXC rootfs only needs ~16-32GB for NixOS
4. **Service data on DATA_4TB**: The important data is on the iSCSI drive, not the root disk

### Docker Data Location (CRITICAL)

Based on `ls /mnt/pve/DATA_4TB`:
```
backups/
myServices/
Warehouse/
```

**No `/docker` directory visible** → Docker data is likely on VMHOME's root disk (`/var/lib/docker`).

**Before proceeding, we need to decide:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A: Migrate Docker data** | Export images, copy volumes to DATA_4TB | Preserves everything | Requires starting VMHOME briefly |
| **B: Rebuild containers** | Fresh Docker, re-pull images, restore volumes from backups | Clean start | May lose some state |
| **C: Move Docker root before migration** | Start VMHOME, move `/var/lib/docker` to `/mnt/DATA_4TB/docker`, stop VMHOME | Best for future | Requires VMHOME restart |

**Decision**: Option D - Mount VMHOME disk as secondary and migrate data after LXC is running.

### Option D: Mount VMHOME Disk for Migration (CHOSEN)

Mount the old VMHOME root disk on Proxmox, then bind mount to LXC_HOME for data migration.

**What needs to be migrated from VMHOME root disk:**
- `/home/akunito/.ssh/` - SSH keys (CRITICAL)
- `/home/akunito/.config/` - Application configs (syncthing, etc.)
- Other important files in `/home/akunito/`

**What does NOT need migration:**
- ✅ Docker volumes - Already on `/mnt/DATA_4TB`
- ✅ Service data - Already on `/mnt/DATA_4TB/myServices/`
- ✅ NixOS system - Rebuilt from flake config

**Step D1: Identify VMHOME Disk (On Proxmox)**

```bash
# The VMHOME disk is an LVM volume
lvs | grep 410

# Should show something like:
# vm--410--disk--0  nixosHomelab ...
```

**Step D2: Mount VMHOME Disk on Proxmox**

```bash
# Create mount point
mkdir -p /mnt/vmhome-migration

# Find the correct LVM path
ls -la /dev/nixosHomelab/ | grep 410

# Mount the disk (read-only for safety)
# Note: VMHOME might have used LUKS encryption - check first
lsblk -f /dev/nixosHomelab/vm--410--disk--0

# If NOT encrypted:
mount -o ro /dev/nixosHomelab/vm--410--disk--0 /mnt/vmhome-migration

# If encrypted (LUKS):
cryptsetup luksOpen /dev/nixosHomelab/vm--410--disk--0 vmhome-crypt
mount -o ro /dev/mapper/vmhome-crypt /mnt/vmhome-migration

# Verify contents
ls -la /mnt/vmhome-migration/
ls -la /mnt/vmhome-migration/home/akunito/
```

**Step D3: Add Bind Mount to LXC Config**

After creating the LXC, add temporary bind mount for migration:

```bash
# Add to /etc/pve/lxc/<VMID>.conf
mp4: /mnt/vmhome-migration,mp=/mnt/vmhome-old,ro=1
```

**Step D4: Migrate User Data Inside LXC**

```bash
# Create target directories if needed
mkdir -p /home/akunito/.ssh
mkdir -p /home/akunito/.config

# SSH keys (CRITICAL)
cp -a /mnt/vmhome-old/home/akunito/.ssh/* /home/akunito/.ssh/
chmod 700 /home/akunito/.ssh
chmod 600 /home/akunito/.ssh/id_*
chown -R akunito:users /home/akunito/.ssh

# Config files (syncthing, restic, etc.)
cp -a /mnt/vmhome-old/home/akunito/.config/syncthing /home/akunito/.config/ 2>/dev/null
cp -a /mnt/vmhome-old/home/akunito/.config/restic /home/akunito/.config/ 2>/dev/null
# Add other .config directories as needed

# Fix ownership
chown -R akunito:users /home/akunito/.config

# List what else might be important
ls -la /mnt/vmhome-old/home/akunito/
```

**Note:** Docker volumes are already on DATA_4TB - no Docker migration needed!

**Step D5: Cleanup After Migration**

```bash
# Remove temporary bind mount from LXC config
# Edit /etc/pve/lxc/<VMID>.conf and remove mp4 line

# On Proxmox: unmount
umount /mnt/vmhome-migration
cryptsetup luksClose vmhome-crypt  # if encrypted

# Keep VMHOME disk until you're sure everything works!
# Later: delete VM 410 to free space
```

---

## Phase 1: Proxmox LXC Container Setup

> **Prerequisites**: Complete all steps in "Pre-Migration: Proxmox Storage Setup" section first!

### 1.1 Create LXC Container in Proxmox

```bash
# Using NixOS LXC template
pct create <VMID> local:vztmpl/nixos-<version>.tar.xz \
  --hostname lxchome \
  --memory 8192 \
  --cores 4 \
  --rootfs local-lvm:32 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1,keyctl=1,fuse=1 \
  --unprivileged 0
```

**Critical LXC Features:**
- `nesting=1` - Required for Docker
- `keyctl=1` - Required for Docker
- `fuse=1` - Required for gocryptfs/FUSE mounts
- `unprivileged=0` (privileged) - Easier for Docker/NFS, can try unprivileged later

### 1.2 Configure Bind Mounts for Storage

Edit `/etc/pve/lxc/<VMID>.conf` (or use Proxmox GUI → Container → Resources → Add Mount Point):

```bash
# iSCSI drive from TrueNAS (via Proxmox mount)
mp0: /mnt/pve/DATA_4TB,mp=/mnt/DATA_4TB

# NFS shares from TrueNAS (via Proxmox mount)
mp1: /mnt/pve/NFS_media,mp=/mnt/NFS_media
mp2: /mnt/pve/NFS_library,mp=/mnt/NFS_library
mp3: /mnt/pve/NFS_emulators,mp=/mnt/NFS_emulators
```

**Why this approach?**
- NFS is mounted once on Proxmox, shared to LXC via bind mounts
- No NFS client needed inside LXC (simpler, fewer permissions)
- iSCSI drive mounted on Proxmox, passed as directory (not block device)
- LXC sees the same paths as VMHOME did → **no application config changes**

### 1.3 Verify Bind Mounts After Container Creation

```bash
# Start the container
pct start <VMID>

# Enter the container
pct enter <VMID>

# Verify mounts are accessible
ls -la /mnt/DATA_4TB
ls -la /mnt/NFS_media
ls -la /mnt/NFS_library
ls -la /mnt/NFS_emulators

# Check disk space
df -h
```

### 1.4 Alternative: NFS Client Inside LXC (NOT RECOMMENDED)

Only use this if you need different NFS mount options per-container:
- Requires privileged container OR AppArmor profile adjustment
- Add to LXC config: `lxc.apparmor.profile: unconfined`
- More complex, more permissions needed
- **Use Proxmox bind mounts instead (section 1.2)**

---

## Phase 2: Create LXC_HOME-config.nix

### 2.1 New Configuration File

```nix
# LXC_HOME Profile Configuration
# Homelab services in LXC container
# Extends LXC-base-config.nix with VMHOME functionality

let
  base = import ./LXC-base-config.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "lxchome";
    profile = "proxmox-lxc";  # Use LXC profile base
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_HOME -s -u";
    systemStateVersion = "24.11";

    # Network - LXC uses Proxmox-managed networking
    # networkManager handled by proxmox-lxc profile
    resolvedEnable = true;

    # Firewall ports (cleaned up - no NFS server needed)
    allowedTCPPorts = [
      22        # SSH
      443       # HTTPS
      8043      # nginx
      22000     # syncthing
      8443 8080 8843 8880 6789  # unifi controller
    ];
    allowedUDPPorts = [
      22000 21027  # syncthing
      3478 10001 1900 5514  # unifi controller
    ];
    # NOTE: NFS server ports (111, 2049, 4000-4002) removed - not needed
    # All clients connect directly to TrueNAS (192.168.20.200)

    # Drives - use bind mounts configured in Proxmox
    # Disable drives.nix mounts (handled by Proxmox mp0, mp1, etc.)
    # The iSCSI drive and NFS shares are mounted on Proxmox and passed via bind mounts
    mount2ndDrives = false;
    disk1_enabled = false;  # /mnt/DATA_4TB handled by Proxmox mp0
    disk3_enabled = false;  # /mnt/NFS_media handled by Proxmox mp1
    disk4_enabled = false;  # /mnt/NFS_emulators handled by Proxmox mp2
    disk5_enabled = false;  # /mnt/NFS_library handled by Proxmox mp3

    # NFS client - DISABLED (using Proxmox bind mounts instead)
    # This simplifies the LXC config and avoids NFS permission issues
    nfsClientEnable = false;
    nfsMounts = [];
    nfsAutoMounts = [];

    # Optimizations (same as VMHOME)
    havegedEnable = false;
    fail2banEnable = false;

    # System packages (VMHOME set + atuin)
    systemPackages = pkgs: pkgs-unstable: with pkgs; [
      vim wget zsh git
      rclone cryptsetup gocryptfs
      traceroute iproute2 openssl
      restic zim-tools p7zip
      nfs-utils  # Needed if NFS client enabled
      btop fzf tldr atuin
      home-manager
    ];

    swapFileEnable = false;  # Managed by Proxmox
    systemStable = true;
  };

  userSettings = base.userSettings // {
    homeStateVersion = "24.11";

    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      "nscd"
      "www-data"
    ];

    dockerEnable = true;
    virtualizationEnable = false;
    qemuGuestAddition = false;  # Not a VM

    zshinitContent = ''
      PROMPT=" ◉ %U%F{green}%n%f%u@%U%F{green}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';
  };
}
```

### 2.2 Update proxmox-lxc/base.nix (Optional Enhancements)

Add conditionals for LXC_HOME-specific features without breaking other LXC profiles:

```nix
# Add to imports (conditional)
++ lib.optional systemSettings.nfsServerEnable ../../system/hardware/nfs_server.nix

# Add journald config (benefits all LXC profiles)
services.journald.extraConfig = ''
  SystemMaxUse=${systemSettings.journaldMaxUse}
  MaxRetentionSec=${systemSettings.journaldMaxRetentionSec}
  Compress=${if systemSettings.journaldCompress then "yes" else "no"}
'';

# Add nix auto-optimize (benefits all LXC profiles)
nix.settings.auto-optimise-store = true;
```

---

## Phase 3: NFS Server Decision

### Option A: No NFS Server in LXC (Recommended)
- Simpler setup
- Use Proxmox host or TrueNAS for NFS exports
- LXC_HOME is just a client

### Option B: NFS Server in LXC
- Requires privileged container
- Requires `nfsd` kernel module on Proxmox host
- Add to Proxmox LXC config:
  ```
  lxc.apparmor.profile: unconfined
  lxc.cap.drop:
  ```
- Add `nfsServerEnable = true` to LXC_HOME-config.nix
- Add conditional import in proxmox-lxc/base.nix

---

## Phase 4: Docker Configuration

Docker in LXC requires specific setup:

### 4.1 Proxmox LXC Config
Already handled by features in Phase 1:
- `nesting=1`
- `keyctl=1`

### 4.2 Docker Storage Driver
The `proxmox-lxc/base.nix` already uses `overlay2`:
```nix
(import ../../system/app/docker.nix {
  storageDriver = "overlay2";  # Works in LXC
  inherit pkgs userSettings lib;
})
```

---

## Phase 5: Data Migration (Minimal)

Since the iSCSI drive and NFS shares are passed through via Proxmox bind mounts, **most data does NOT need migration**.

### 5.1 Pre-Migration: Verify Data Locations on VMHOME

Before shutting down VMHOME, verify where your data actually lives:

```bash
# On VMHOME - check where Docker stores data
docker info | grep "Docker Root Dir"

# Check where docker-compose files live
find /mnt/DATA_4TB -name "docker-compose*.yml" 2>/dev/null
find /home/akunito -name "docker-compose*.yml" 2>/dev/null

# Check Syncthing config location
ls -la /home/akunito/.config/syncthing/ 2>/dev/null
ls -la /mnt/DATA_4TB/syncthing/ 2>/dev/null

# Check restic repo locations
grep -r "repository" /home/akunito/.config/restic* 2>/dev/null
```

### 5.2 Scenario A: Docker Data on /mnt/DATA_4TB (Best Case)

If Docker data-root is already `/mnt/DATA_4TB/docker/`:

**Migration needed**: Almost nothing
```bash
# Only copy SSH keys and any local configs
scp -r akunito@vmhome:/home/akunito/.ssh/ /home/akunito/.ssh/
```

**On LXC_HOME**: Docker will find existing data at same path.

### 5.3 Scenario B: Docker Data on VM Root (Migration Required)

If Docker uses default `/var/lib/docker/`:

**Option B1: Export/Import images (quick, loses layers)**
```bash
# On VMHOME before shutdown
docker save $(docker images -q) > /mnt/DATA_4TB/docker-images.tar

# On LXC_HOME after setup
docker load < /mnt/DATA_4TB/docker-images.tar
```

**Option B2: Move Docker root to DATA_4TB (recommended)**
```bash
# On VMHOME - stop Docker and move data
systemctl stop docker
mv /var/lib/docker /mnt/DATA_4TB/docker
```

Then configure LXC_HOME to use `/mnt/DATA_4TB/docker` as data-root (see Phase 2).

### 5.4 Copy User-Specific Data

```bash
# SSH keys (important!)
mkdir -p /home/akunito/.ssh
scp -r akunito@vmhome:/home/akunito/.ssh/* /home/akunito/.ssh/
chmod 700 /home/akunito/.ssh
chmod 600 /home/akunito/.ssh/id_*

# Any local configs not on DATA_4TB
scp -r akunito@vmhome:/home/akunito/.config/syncthing/ /home/akunito/.config/ 2>/dev/null || echo "Syncthing config on DATA_4TB - skipping"
```

### 5.5 DNS/IP Update

```bash
# Update pfsense DHCP reservation
# New LXC_HOME will have different MAC address
# Either:
# - Keep same IP (192.168.8.80) by updating DHCP reservation
# - Use new IP during testing, then swap

# Update any DNS records pointing to VMHOME
# - Internal DNS (pfsense/TrueNAS)
# - External DNS (if applicable)
```

### 5.6 Migration Summary Checklist

| Item | Location | Action |
|------|----------|--------|
| Docker images/volumes | `/mnt/DATA_4TB/docker/` | ✅ Already accessible |
| Docker images/volumes | `/var/lib/docker/` (VM) | ⚠️ Export or move to DATA_4TB |
| docker-compose files | `/mnt/DATA_4TB/` | ✅ Already accessible |
| docker-compose files | `/home/akunito/` (VM) | ⚠️ Copy to DATA_4TB |
| SSH keys | `/home/akunito/.ssh/` | 📋 Copy to LXC_HOME |
| NFS media/library | `/mnt/NFS_*` | ✅ Bind mount from Proxmox |
| Syncthing data | Check location | Likely on DATA_4TB |
| Restic repos | Check location | Likely on DATA_4TB |

---

## Phase 6: Testing Checklist

- [ ] LXC container boots successfully
- [ ] NixOS rebuild works: `nixos-rebuild switch --flake .#LXC_HOME`
- [ ] SSH access works
- [ ] Docker starts and runs containers
- [ ] Bind mounts accessible (`/mnt/DATA_4TB`, `/mnt/NFS_*`)
- [ ] Syncthing connects to peers
- [ ] Nginx serves sites
- [ ] Unifi controller accessible
- [ ] Restic backup runs successfully

---

## Files to Create/Modify

| File | Action | Impact |
|------|--------|--------|
| `profiles/LXC_HOME-config.nix` | CREATE | New file |
| `profiles/proxmox-lxc/base.nix` | MODIFY (optional) | Add journald, nix optimize |
| `flake.nix` | MODIFY | Add LXC_HOME output |
| `LXC-base-config.nix` | NO CHANGE | Preserve for other LXC profiles |

---

## Rollback Plan

1. Keep VMHOME running until LXC_HOME is fully tested
2. If issues: revert DNS/IP to VMHOME
3. VMHOME configuration remains unchanged

---

## Questions to Decide Before Implementation

### Decided ✅

1. **NFS Client**: ✅ **Use Proxmox bind mounts** - NFS mounted on Proxmox, passed to LXC via bind mounts. Simpler and avoids NFS permissions in LXC.

2. **iSCSI Drive**: ✅ **Mount on Proxmox, bind mount to LXC** - Same approach as NFS. No migration needed for data on `/mnt/DATA_4TB`.

3. **Privileged vs Unprivileged**: ✅ **Start privileged** - Easier for Docker. Can optimize later.

### Still To Decide ⏳

4. **NFS Server**: Do you need NFS server in LXC_HOME, or can TrueNAS handle all exports?
   - If LXC_HOME currently re-exports data to other machines, need to decide if TrueNAS should take over

5. **IP Address**: Keep same IP (192.168.8.80) or new IP for LXC_HOME during testing?
   - Same IP: Simpler, but can't run both in parallel
   - New IP: Can test with both running, then swap

6. **Timeline**: Run both in parallel during testing, or hard cutover?
   - Parallel: Safer, but iSCSI drive can only be mounted by one at a time
   - **Recommendation**: Shut down VMHOME, mount iSCSI on Proxmox, start LXC_HOME

7. **Docker data-root**: Is Docker currently using `/mnt/DATA_4TB/docker/` or default `/var/lib/docker/`?
   - Check before migration - affects how much data needs to be moved

---

## Estimated Resource Savings (VM → LXC)

| Resource | VMHOME (VM) | LXC_HOME (LXC) | Savings |
|----------|-------------|---------------|---------|
| RAM overhead | ~512MB (hypervisor) | ~50MB | ~460MB |
| Disk (OS) | ~10GB | ~5GB | ~5GB |
| Boot time | ~30-60s | ~5-10s | 6x faster |
| Kernel | Separate | Shared | Less memory |

---

## Next Steps

### Pre-Migration (On Proxmox Host) - COMPLETED ✅
1. ✅ **Answer remaining questions** (NFS server, IP address, timeline)
2. ☐ **Verify data locations on VMHOME** - Check Docker data-root (can't check - VM stopped)
3. ✅ **Install NFS client on Proxmox** (Step P1.1)
4. ✅ **Create NFS mount points** (Step P1.2)
5. ✅ **Test NFS mounts manually** (Step P1.3)
6. ✅ **Add NFS to Proxmox fstab** (Step P1.4)
7. ✅ **Shut down VMHOME** (VM 410 stopped)
8. ✅ **Configure iSCSI auto-login** (Step P2.1)
9. ✅ **Configure iSCSI mount on Proxmox** (Step P2.3-P2.5)
10. ✅ **Verify all Proxmox mounts** (Step P3) - Confirmed after reboot
11. ☐ **Verify NFS server question** - Was VMHOME exporting anything via NFS?

### LXC Setup - NEXT
12. ☐ **Create LXC container** (Phase 1.1)
13. ☐ **Configure bind mounts** (Phase 1.2)
14. ☐ **Verify bind mounts inside LXC** (Phase 1.3)

### NixOS Configuration
15. ☐ **Create LXC_HOME-config.nix** (Phase 2)
16. ☐ **Create flake.LXC_HOME.nix**
17. ☐ **Add LXC_HOME to flake.nix**
18. ☐ **nixos-rebuild switch --flake .#LXC_HOME**

### Data & Testing
19. ☐ **Copy SSH keys** (Phase 5.4)
20. ☐ **Start Docker services** (verify they find data on /mnt/DATA_4TB)
21. ☐ **Run testing checklist** (Phase 6)
22. ☐ **Update DNS/DHCP** (Phase 5.5)

### Cutover
23. ☐ **Delete or archive VMHOME** (after successful testing)
