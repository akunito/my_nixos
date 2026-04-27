---
name: unlock-nas
description: Recover NAS access when LUKS or ZFS encryption is locked. NixOS-based — does NOT use TrueNAS API.
---

# Unlock NAS (NixOS) — boot/ZFS recovery

NAS (`nas-aku`, 192.168.20.200) runs NixOS since the AINF-336 migration. Legacy TrueNAS API endpoints and `nas-unlock-pools.sh` are gone.

## Decision tree

1. **SSH works?** → run the status check below; pools may already be unlocked.
2. **SSH refused, ping works, all ports closed?** → likely stuck at LUKS prompt at console. **Physical/IPMI console required** (no remote LUKS unlock configured).
3. **SSH works but `zpool status` missing pools or `keystatus = unavailable`?** → manual ZFS key load, see below.

## Status check (read-only, from DESK)

```bash
ssh -A akunito@192.168.20.200 'sudo zpool status; sudo zfs get -H keystatus ssdpool extpool'
```

Healthy: both pools ONLINE, `keystatus = available`.

## Manual ZFS unlock (only if `nas-zfs-unlock.service` failed)

```bash
ssh -A akunito@192.168.20.200 'sudo systemctl restart nas-zfs-unlock.service'
# or per-pool:
ssh -A akunito@192.168.20.200 'sudo zfs load-key -L file:///etc/zfs/keys/ssdpool ssdpool && sudo zfs mount -a'
```

Key files live on the encrypted root at `/etc/zfs/keys/{ssdpool,extpool}`. They become accessible only after LUKS is open.

## If LUKS is locked (cannot SSH)

There is no Dropbear-in-initrd or `boot.initrd.network` configured on NAS_PROD. Remote unlock is **not** possible. Walk to the box, use IPMI/KVM if available, or power-cycle and enter passphrase at the console.

## Reference

- `profiles/NAS_PROD-config.nix` — `boot.zfs.requestEncryptionCredentials = false`, `nasZfsPools = [ "ssdpool" "extpool" ]`
- `system/app/nas-services.nix:252-279` — `nas-zfs-unlock.service` (oneshot, runs before `zfs-mount.service`)
- Slash command body: `.claude/commands/unlock-nas.md`
- Migration: `memory/project_truenas_to_nixos.md`
