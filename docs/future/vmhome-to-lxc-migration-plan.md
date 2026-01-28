# VMHOME to LXC Migration Plan

## Goal
Migrate the VMHOME VM to an LXC container (`LXCHOME`) while preserving all functionality (Docker, NFS, services) and optimizing for LXC. Must not impact existing `LXC*-config.nix` profiles.

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

### 1.2 Bind Mounts (Replace fstab/drives.nix)

In Proxmox GUI or `/etc/pve/lxc/<VMID>.conf`:
```
# Local drive passthrough
mp0: /mnt/pve/DATA_4TB,mp=/mnt/DATA_4TB

# NFS from host (if TrueNAS NFS is mounted on Proxmox host)
mp1: /mnt/pve/NFS_media,mp=/mnt/NFS_media
mp2: /mnt/pve/NFS_library,mp=/mnt/NFS_library
mp3: /mnt/pve/NFS_emulators,mp=/mnt/NFS_emulators
```

**Alternative: NFS client inside LXC**
If NFS must be mounted inside the container (not via Proxmox bind mounts):
- Requires privileged container OR AppArmor profile adjustment
- Add to LXC config: `lxc.apparmor.profile: unconfined`

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
    mount2ndDrives = false;

    # NFS client - OPTION A: disabled, use Proxmox bind mounts
    nfsClientEnable = false;
    nfsMounts = [];
    nfsAutoMounts = [];

    # NFS client - OPTION B: enabled, mount inside container
    # nfsClientEnable = true;
    # nfsMounts = [ ... ];  # Same as VMHOME

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

## Phase 5: Data Migration

### 5.1 Docker Volumes/Data
```bash
# On VMHOME
docker save <images> > /mnt/DATA_4TB/docker-images.tar
rsync -avz /var/lib/docker/volumes/ /mnt/DATA_4TB/docker-volumes/

# On LXCHOME (after setup)
docker load < /mnt/DATA_4TB/docker-images.tar
rsync -avz /mnt/DATA_4TB/docker-volumes/ /var/lib/docker/volumes/
```

### 5.2 Service Configuration
- Copy docker-compose files
- Copy nginx configs
- Copy unifi data
- Copy syncthing config

### 5.3 DNS/IP Update
- Update pfsense DHCP reservation for new LXCHOME MAC
- Update any DNS records pointing to VMHOME

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

1. **NFS Server**: Do you need NFS server in LXCHOME, or can TrueNAS/Proxmox host handle exports?

2. **NFS Client**: Use Proxmox bind mounts (simpler) or mount NFS inside container (more flexible)?

3. **Privileged vs Unprivileged**: Start privileged (easier), optimize to unprivileged later?

4. **IP Address**: Keep same IP (.80) or new IP for LXCHOME during testing?

5. **Timeline**: Run both in parallel during testing, or hard cutover?

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

1. Answer decision questions above
2. Review and approve this plan
3. Create Proxmox LXC container
4. Implement LXCHOME-config.nix
5. Test incrementally
6. Migrate data
7. Cutover
