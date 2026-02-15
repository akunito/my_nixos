# Proxmox Server Guide for ko-mi

## Hardware

- **Machine**: Laptop running as headless server (lid closed)
- **CPU**: 8 cores
- **RAM**: 16 GB
- **Storage**: 512 GB NVMe (WDC SN730)
  - `/` (root): 21.5 GB (ext4, unencrypted)
  - swap: 6 GB
  - **Encrypted storage**: ~404 GB LUKS2-encrypted thin pool for LXC containers

## Network

The server is currently configured for the **192.168.8.0/24** network:

| What | Current Value |
|------|---------------|
| Proxmox IP | 192.168.8.3 |
| Gateway | 192.168.8.1 |
| Bridge | vmbr0 (on enp0s31f6) |
| Container 102 | DHCP (currently 192.168.8.201) |

### Changing the network for your home (IMPORTANT)

When you move this to your own network (e.g., 192.168.1.0/24 or 192.168.0.0/24), you need to update:

#### 1. Proxmox host IP
SSH in (or connect a monitor/keyboard) and edit:
```bash
nano /etc/network/interfaces
```
Change the `address` and `gateway` lines:
```
auto vmbr0
iface vmbr0 inet static
    address 192.168.1.3/24       # <-- your new IP
    gateway 192.168.1.1           # <-- your router IP
    bridge-ports enp0s31f6
    bridge-stp off
    bridge-fd 0
```

#### 2. DNS servers
```bash
nano /etc/resolv.conf
```
Change to:
```
nameserver 192.168.1.1            # your router
nameserver 8.8.8.8                # Google fallback
```

#### 3. Reboot
```bash
reboot
```

#### 4. Container networking
Container 102 uses DHCP, so it will get a new IP automatically from your router. You can set a static DHCP reservation on your router using the container's MAC address: `BC:24:11:DB:03:9B`.

To check what IP it got:
```bash
pct exec 102 -- sh -c 'export PATH=/run/current-system/sw/bin:$PATH; ip addr show eth0'
```

## Architecture Overview

```
┌──────────────────────────────────────────────────┐
│  Proxmox VE 8.3 (Debian Bookworm)               │
│  Kernel: 6.8.12-18-pve                           │
│  IP: 192.168.8.3 (change for your network)       │
│                                                   │
│  ┌─────────────────────────────────────────────┐ │
│  │  NVMe 512 GB                                │ │
│  │  ├── /boot/efi (1 GB, FAT32)               │ │
│  │  └── pve VG (476 GB LVM)                   │ │
│  │      ├── pve/root (21.5 GB, ext4, /)       │ │
│  │      ├── pve/swap (6 GB)                    │ │
│  │      └── pve/encrypted_lxc (426 GB)         │ │
│  │          └── 🔒 LUKS2 encrypted             │ │
│  │              └── vg_encrypted_lxc VG        │ │
│  │                  └── encrypted-lxc-pool     │ │
│  │                      (404 GB thin pool)     │ │
│  │                      └── CT 102 (24 GB)     │ │
│  └─────────────────────────────────────────────┘ │
│                                                   │
│  Network: vmbr0 bridge on enp0s31f6              │
└──────────────────────────────────────────────────┘
```

## Daily Operations

### After every reboot: Unlock encrypted storage

The encrypted storage is **locked** after every reboot. Containers on it won't start until you unlock it.

```bash
ssh root@<PROXMOX_IP>
/root/scripts/unlock_luks.sh
```

Enter your LUKS passphrase when prompted. The script will:
1. Unlock the LUKS volume
2. Activate the LVM volume group
3. Start container 102

### Access the Proxmox Web UI

Open a browser and go to: `https://<PROXMOX_IP>:8006`

Login with `root` and the root password.

### Enter a container

```bash
# From Proxmox host
pct enter 102

# Or SSH directly (after setting up SSH keys)
ssh akunito@<CONTAINER_IP>
```

### Start/stop containers

```bash
pct start 102
pct stop 102
pct restart 102
```

### Check container status

```bash
pct list
pct status 102
```

## NixOS Dotfiles & Profile System

The container runs **NixOS** managed by a flake-based dotfiles repo at `/home/akunito/.dotfiles` on the `komi` branch.

### How profiles work

Each machine/container has a **profile** that defines its configuration:

```
flake.nix                          # Main entry point
├── lib/defaults.nix               # Default values for all settings
├── profiles/LXC-base-config.nix   # Base config for all LXC containers
└── profiles/LXC_*-config.nix      # Specific container profiles
```

### Creating a new LXC profile

1. **Copy an existing LXC profile** as a template:
   ```bash
   cd ~/.dotfiles
   cp profiles/LXC_liftcraftTEST-config.nix profiles/LXC_komi-config.nix
   ```

2. **Edit the new profile** — change at minimum:
   - `hostname`
   - `envProfile` (e.g., `"LXC_komi"`)
   - `profile` to the correct base (usually `"personal"` or `"homelab"`)
   - Enable/disable feature flags as needed

3. **Register the profile in flake.nix** — add to `nixosConfigurations`:
   ```nix
   LXC_komi = mkSystem "LXC_komi" ./profiles/LXC_komi-config.nix;
   ```

4. **Build and apply**:
   ```bash
   cd ~/.dotfiles
   sudo nixos-rebuild switch --flake .#LXC_komi --impure
   ```

### Key NixOS commands

```bash
# Rebuild after config changes
sudo nixos-rebuild switch --flake .#LXC_komi --impure

# Test a build without switching
sudo nixos-rebuild build --flake .#LXC_komi --impure

# Update flake inputs (Nix packages, etc.)
nix flake update

# Garbage collect old generations
sudo nix-collect-garbage -d
```

### Git workflow (komi branch)

```bash
cd ~/.dotfiles
git status
git add -A
git commit -m "description of changes"
git push origin komi
```

**Note**: The `secrets/` directory is encrypted with git-crypt. You don't have the dotfiles git-crypt key, so those files will appear as binary. This is fine — you don't need the secrets from the main repo. If you need secrets for your own services, create your own `secrets/` structure on the komi branch.

## Creating New LXC Containers

### From Proxmox Web UI
1. Go to the web UI → Create CT
2. **Storage**: Select `encrypted-lxc` for the root disk
3. **Network**: Bridge `vmbr0`, DHCP
4. **Features**: Enable `nesting=1` if you need Docker inside the container

### From command line
```bash
# Download a NixOS template first (if not already available)
pveam update
pveam available | grep nixos

# Create a new container
pct create <CTID> <TEMPLATE> \
    --storage encrypted-lxc \
    --hostname <NAME> \
    --memory 2048 \
    --cores 2 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp,type=veth \
    --features nesting=1 \
    --unprivileged 1 \
    --rootfs encrypted-lxc:24

pct start <CTID>
```

### Adding new containers to the unlock script

Edit `/root/scripts/unlock_luks.sh` and add the CTID to `ENCRYPTED_LXC_CONTAINERS`:

```bash
ENCRYPTED_LXC_CONTAINERS="102 103 104"
```

## SSH Keys

### Container SSH key
The container has a fresh SSH keypair at `/home/akunito/.ssh/id_ed25519`:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN1U/cTits//ScDxZg54sudN64DDHbPlkRDbRhHFcyia komi@leftyworkout
```

This key needs to be added as a **deploy key** on GitHub for the `leftyworkout` repository so the container can pull/push.

### Your personal SSH key
Add your own public key to the container's authorized_keys so you can SSH in:
```bash
# From Proxmox host
pct exec 102 -- sh -c 'export PATH=/run/current-system/sw/bin:$PATH; echo "YOUR_PUBLIC_KEY_HERE" >> /home/akunito/.ssh/authorized_keys'
```

## Automatic Maintenance (Updates & Upgrades)

A cron job runs every **Sunday at 8:00 AM** to automatically update and upgrade Proxmox packages.

### What it does
1. `apt update` — refreshes package lists
2. `apt upgrade -y` — upgrades installed packages
3. `apt full-upgrade -y` — handles kernel and distribution upgrades
4. `apt autoremove -y` — removes unused packages
5. `apt autoclean` — cleans package cache
6. Removes old kernels (keeps the running one)
7. Checks if a reboot is required (logs a message, does NOT auto-reboot)

### Files
| File | Purpose |
|------|---------|
| `/root/scripts/maintenance/maintenance.sh` | The maintenance script |
| `/root/scripts/maintenance/maintenance.log` | Output log (auto-rotated at 1 MB) |
| `/root/scripts/maintenance/cronjob.log` | Cron execution log |

### Checking logs
```bash
# View the latest maintenance log
cat /root/scripts/maintenance/maintenance.log

# Check if a reboot is pending (new kernel installed)
cat /root/scripts/maintenance/maintenance.log | grep -i reboot
```

### Running manually
```bash
/root/scripts/maintenance/maintenance.sh
```

### Important: Reboot after kernel upgrades
The script does NOT auto-reboot. If it logs "Please reboot the system!", you need to:
1. Plan a maintenance window (containers will stop)
2. `reboot`
3. SSH back in and run `/root/scripts/unlock_luks.sh` (encrypted storage needs unlocking after every reboot)

## Troubleshooting

### Can't connect after reboot
1. Connect a monitor + keyboard to the laptop
2. Login as root
3. Check: `ip addr show vmbr0` — does it have the right IP?
4. Check: `ping <YOUR_ROUTER_IP>` — is the network working?
5. Run: `/root/scripts/unlock_luks.sh`

### Container won't start
```bash
# Check if storage is unlocked
pvesm status
# If encrypted-lxc shows "inactive", run the unlock script first

# Check container logs
pct start 102 --debug
journalctl -u pve-container@102
```

### Storage is full
```bash
# Check storage usage
lvs
df -h

# Inside the container — garbage collect NixOS
pct exec 102 -- sh -c 'export PATH=/run/current-system/sw/bin:$PATH; nix-collect-garbage -d'
```

### Forgot LUKS passphrase
**There is no recovery.** All data on the encrypted storage will be lost. You would need to recreate the LUKS volume and restore from backups.

### DNS not working after network change
```bash
nano /etc/resolv.conf
# Set nameserver to your router IP and 8.8.8.8
```

## Quick Reference

| Task | Command |
|------|---------|
| Unlock storage after reboot | `/root/scripts/unlock_luks.sh` |
| Web UI | `https://<IP>:8006` |
| Enter container | `pct enter 102` |
| Start container | `pct start 102` |
| Stop container | `pct stop 102` |
| Check container IP | `pct exec 102 -- sh -c 'export PATH=/run/current-system/sw/bin:$PATH; ip addr show eth0'` |
| Rebuild NixOS | Inside container: `sudo nixos-rebuild switch --flake .#PROFILE --impure` |
| Container MAC (for DHCP reservation) | `BC:24:11:DB:03:9B` |
| Check maintenance logs | `cat /root/scripts/maintenance/maintenance.log` |
| Run maintenance manually | `/root/scripts/maintenance/maintenance.sh` |

## Onboarding Checklist

- [ ] Set DHCP reservation on your router for container MAC `BC:24:11:DB:03:9B`
- [ ] Add your SSH public key to container's `authorized_keys`
- [ ] Set your git user name/email (via NixOS profile or `git config --global`)
- [ ] Add container SSH key as GitHub deploy key for leftyworkout repo
- [ ] Remember your LUKS passphrase (no recovery if forgotten!)
- [ ] Know to run `/root/scripts/unlock_luks.sh` after each Proxmox reboot
- [ ] Update network config (IP, gateway, DNS) for your home network
- [ ] Create your own LXC profile on the `komi` branch
