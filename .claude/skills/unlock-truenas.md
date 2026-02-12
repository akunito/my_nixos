---
name: unlock-truenas
description: Unlock encrypted TrueNAS datasets via API
---

# Unlock TrueNAS Encrypted Datasets

This skill unlocks encrypted datasets on TrueNAS via the API.

## Usage

```bash
/unlock-truenas [pool-name]
```

If no pool name is provided, unlocks all locked pools.

## What This Skill Does

1. Connects to TrueNAS via SSH/API
2. Identifies locked encrypted datasets
3. Unlocks datasets using provided passphrase
4. Verifies unlock status
5. Reports results

## Parameters

- `pool-name` (optional): Specific pool to unlock (e.g., `hddpool`, `ssdpool`)
- If omitted, unlocks all locked pools

## Requirements

- SSH access to TrueNAS (truenas_admin@192.168.20.200)
- Encryption passphrase
- TrueNAS API access

## Network Access

TrueNAS is on VLAN 100 (Storage), accessible from:
- **DESK**: via bond0.100 (192.168.20.96) — direct L2
- **Proxmox**: via vmbr10.100 (192.168.20.82) — direct L2
- **pfSense**: via ix0.100 (192.168.20.1) — VLAN gateway
- **LXC containers**: via Proxmox host (bind mount NFS shares)

## Example Output

```
Locked datasets found:
- hddpool/media
- hddpool/proxmox_backups
- ssdpool/library

Unlocking hddpool...
✓ hddpool/media unlocked
✓ hddpool/proxmox_backups unlocked

Unlocking ssdpool...
✓ ssdpool/library unlocked

All datasets unlocked successfully!
```

## Implementation

When invoked, this skill will:
1. Query for locked datasets
2. Request passphrase if not provided
3. Unlock pools recursively (children inherit from parent)
4. Verify all datasets are unlocked
5. Report any failures

## Security Note

- **Passphrase Storage**: Encrypted in `secrets/truenas-encryption-passphrase.txt` (git-crypt)
- **Transmission**: Securely transmitted via SSH
- **Access**: Read from encrypted secrets file when needed
- **Permissions**: File has 600 permissions (owner read/write only)
