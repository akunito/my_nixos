# VMHOME to LXC Migration Plan

## Goal
Migrate the VMHOME VM to an LXC container (`LXCHOME`) while preserving all functionality (Docker, NFS, services) and optimizing for LXC. Must not impact existing `LXC*-config.nix` profiles.

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

### Target Storage Flow (LXCHOME)
```
┌─────────────┐     iSCSI      ┌─────────────┐   bind mount    ┌─────────────┐
│  TrueNAS    │ ──────────────►│   Proxmox   │ ───────────────►│  LXCHOME    │
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

| Feature | VM (VMHOME) | LXC (LXCHOME) |
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

### Step P2: iSCSI Drive Considerations (/mnt/DATA_4TB)

**Current Setup:**
- TrueNAS exports an iSCSI LUN
- Proxmox connects as iSCSI initiator
- Drive appears as a block device on Proxmox
- Currently passed through to VMHOME VM

**Key Considerations for LXC Migration:**

1. **No re-partitioning needed**: The drive is already formatted (ext4) with existing data
2. **No data migration needed**: Same data, just different access method
3. **Proxmox must mount the filesystem** (not pass raw block device to LXC)

**P2.1: Verify current iSCSI mount on Proxmox**
```bash
# Check if DATA_4TB is already mounted on Proxmox host
lsblk
mount | grep DATA_4TB
```

**P2.2: If NOT already mounted on Proxmox, add to fstab**

First, identify the iSCSI device:
```bash
# List iSCSI devices
iscsiadm -m session -P 3 | grep -E "Target|disk"
ls -la /dev/disk/by-id/ | grep iscsi
```

Then add to Proxmox `/etc/fstab`:
```bash
# Example - adjust device path based on your setup
# Using by-id is more reliable than /dev/sdX
/dev/disk/by-id/scsi-XXXXX  /mnt/pve/DATA_4TB  ext4  defaults,nofail,x-systemd.device-timeout=30s  0 0
```

**P2.3: Create mount point and mount**
```bash
mkdir -p /mnt/pve/DATA_4TB
mount -a
ls -la /mnt/pve/DATA_4TB
```

**IMPORTANT**: If the iSCSI drive is currently in use by VMHOME:
- Option A: Shut down VMHOME first, then mount on Proxmox
- Option B: Run both in parallel temporarily (risky - can cause data corruption if both write)
- **Recommended**: Shut down VMHOME before mounting on Proxmox to avoid dual-mount issues

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

## Migration Impact Analysis

### What Does NOT Need Migration (Data Already Accessible)

If your service data is stored on `/mnt/DATA_4TB`, these require **no migration**:

| Data | Location | Migration Needed? |
|------|----------|-------------------|
| Docker volumes | `/mnt/DATA_4TB/docker/` | ❌ No - same path in LXCHOME |
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

Create `LXCHOME-config.nix` that:
1. Imports `LXC-base-config.nix` as base
2. Adds VMHOME-specific features via overrides
3. Does NOT modify shared `LXC-base-config.nix` or `proxmox-lxc/base.nix`

### File Structure
```
profiles/
├── LXC-base-config.nix          # Unchanged (shared by all LXC)
├── LXCtemplate-config.nix       # Unchanged
├── LXCplane-config.nix          # Unchanged
├── LXCHOME-config.nix           # NEW - extends LXC-base for homelab
└── proxmox-lxc/
    ├── base.nix                 # May need minor conditionals
    └── configuration.nix        # Unchanged
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

## Phase 2: Create LXCHOME-config.nix

### 2.1 New Configuration File

```nix
# LXCHOME Profile Configuration
# Homelab services in LXC container
# Extends LXC-base-config.nix with VMHOME functionality

let
  base = import ./LXC-base-config.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "lxchome";
    profile = "proxmox-lxc";  # Use LXC profile base
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXCHOME -s -u";
    systemStateVersion = "24.11";

    # Network - LXC uses Proxmox-managed networking
    # networkManager handled by proxmox-lxc profile
    resolvedEnable = true;

    # Firewall ports (same as VMHOME)
    allowedTCPPorts = [
      22
      443
      8043      # nginx
      22000     # syncthing
      111 4000 4001 4002 2049  # NFS server (if enabled)
      8443 8080 8843 8880 6789  # unifi controller
    ];
    allowedUDPPorts = [
      22000 21027  # syncthing
      111 4000 4001 4002  # NFS server (if enabled)
      3478 10001 1900 5514  # unifi controller
    ];

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

Add conditionals for LXCHOME-specific features without breaking other LXC profiles:

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
- LXCHOME is just a client

### Option B: NFS Server in LXC
- Requires privileged container
- Requires `nfsd` kernel module on Proxmox host
- Add to Proxmox LXC config:
  ```
  lxc.apparmor.profile: unconfined
  lxc.cap.drop:
  ```
- Add `nfsServerEnable = true` to LXCHOME-config.nix
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

**On LXCHOME**: Docker will find existing data at same path.

### 5.3 Scenario B: Docker Data on VM Root (Migration Required)

If Docker uses default `/var/lib/docker/`:

**Option B1: Export/Import images (quick, loses layers)**
```bash
# On VMHOME before shutdown
docker save $(docker images -q) > /mnt/DATA_4TB/docker-images.tar

# On LXCHOME after setup
docker load < /mnt/DATA_4TB/docker-images.tar
```

**Option B2: Move Docker root to DATA_4TB (recommended)**
```bash
# On VMHOME - stop Docker and move data
systemctl stop docker
mv /var/lib/docker /mnt/DATA_4TB/docker
```

Then configure LXCHOME to use `/mnt/DATA_4TB/docker` as data-root (see Phase 2).

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
# New LXCHOME will have different MAC address
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
| SSH keys | `/home/akunito/.ssh/` | 📋 Copy to LXCHOME |
| NFS media/library | `/mnt/NFS_*` | ✅ Bind mount from Proxmox |
| Syncthing data | Check location | Likely on DATA_4TB |
| Restic repos | Check location | Likely on DATA_4TB |

---

## Phase 6: Testing Checklist

- [ ] LXC container boots successfully
- [ ] NixOS rebuild works: `nixos-rebuild switch --flake .#LXCHOME`
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
| `profiles/LXCHOME-config.nix` | CREATE | New file |
| `profiles/proxmox-lxc/base.nix` | MODIFY (optional) | Add journald, nix optimize |
| `flake.nix` | MODIFY | Add LXCHOME output |
| `LXC-base-config.nix` | NO CHANGE | Preserve for other LXC profiles |

---

## Rollback Plan

1. Keep VMHOME running until LXCHOME is fully tested
2. If issues: revert DNS/IP to VMHOME
3. VMHOME configuration remains unchanged

---

## Questions to Decide Before Implementation

### Decided ✅

1. **NFS Client**: ✅ **Use Proxmox bind mounts** - NFS mounted on Proxmox, passed to LXC via bind mounts. Simpler and avoids NFS permissions in LXC.

2. **iSCSI Drive**: ✅ **Mount on Proxmox, bind mount to LXC** - Same approach as NFS. No migration needed for data on `/mnt/DATA_4TB`.

3. **Privileged vs Unprivileged**: ✅ **Start privileged** - Easier for Docker. Can optimize later.

### Still To Decide ⏳

4. **NFS Server**: Do you need NFS server in LXCHOME, or can TrueNAS handle all exports?
   - If LXCHOME currently re-exports data to other machines, need to decide if TrueNAS should take over

5. **IP Address**: Keep same IP (192.168.8.80) or new IP for LXCHOME during testing?
   - Same IP: Simpler, but can't run both in parallel
   - New IP: Can test with both running, then swap

6. **Timeline**: Run both in parallel during testing, or hard cutover?
   - Parallel: Safer, but iSCSI drive can only be mounted by one at a time
   - **Recommendation**: Shut down VMHOME, mount iSCSI on Proxmox, start LXCHOME

7. **Docker data-root**: Is Docker currently using `/mnt/DATA_4TB/docker/` or default `/var/lib/docker/`?
   - Check before migration - affects how much data needs to be moved

---

## Estimated Resource Savings (VM → LXC)

| Resource | VMHOME (VM) | LXCHOME (LXC) | Savings |
|----------|-------------|---------------|---------|
| RAM overhead | ~512MB (hypervisor) | ~50MB | ~460MB |
| Disk (OS) | ~10GB | ~5GB | ~5GB |
| Boot time | ~30-60s | ~5-10s | 6x faster |
| Kernel | Separate | Shared | Less memory |

---

## Next Steps

### Pre-Migration (On Proxmox Host)
1. ☐ **Answer remaining questions** (NFS server, IP address, timeline)
2. ☐ **Verify data locations on VMHOME** - Run Phase 5.1 commands to check Docker data-root
3. ☐ **Install NFS client on Proxmox** (Step P1.1)
4. ☐ **Create NFS mount points** (Step P1.2)
5. ☐ **Test NFS mounts manually** (Step P1.3)
6. ☐ **Add NFS to Proxmox fstab** (Step P1.4)
7. ☐ **Shut down VMHOME** (required for iSCSI handover)
8. ☐ **Configure iSCSI mount on Proxmox** (Step P2.1-P2.3)
9. ☐ **Verify all Proxmox mounts** (Step P3)

### LXC Setup
10. ☐ **Create LXC container** (Phase 1.1)
11. ☐ **Configure bind mounts** (Phase 1.2)
12. ☐ **Verify bind mounts inside LXC** (Phase 1.3)

### NixOS Configuration
13. ☐ **Create LXCHOME-config.nix** (Phase 2)
14. ☐ **Add LXCHOME to flake.nix**
15. ☐ **nixos-rebuild switch --flake .#LXCHOME**

### Data & Testing
16. ☐ **Copy SSH keys** (Phase 5.4)
17. ☐ **Run testing checklist** (Phase 6)
18. ☐ **Update DNS/DHCP** (Phase 5.5)

### Cutover
19. ☐ **Delete or archive VMHOME** (after successful testing)
