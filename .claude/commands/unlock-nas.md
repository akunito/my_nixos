# Unlock NAS (NixOS) — boot/ZFS recovery

The NAS (`nas-aku`, 192.168.20.200) runs **NixOS** (migrated from TrueNAS in AINF-336, March 2026). The legacy TrueNAS `pool.dataset.unlock` API and the `nas-unlock-pools.sh` script are gone — do **not** invoke them.

## Architecture

1. **Boot drive** is LUKS-encrypted (`cryptroot` on `sdd2`). LUKS passphrase must be entered at the **physical / IPMI console** at boot. There is **no** initrd-SSH (no Dropbear) configured — remote unlock is not possible.
2. **ZFS pools** (`ssdpool`, `extpool`) are encrypted; their key files live at `/etc/zfs/keys/<pool>` on the encrypted root. Once LUKS is open, the `nas-zfs-unlock.service` (oneshot, before `zfs-mount.service`) calls `zfs load-key -L file://...` automatically. See `system/app/nas-services.nix:252-279`.
3. `boot.zfs.requestEncryptionCredentials = false` — the boot process never prompts interactively for ZFS keys; it relies on the key file or the explicit unlock service.

## When this command applies

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ssh: connect to host nas-aku ... timed out` AND ping works AND ALL TCP ports closed | Stuck at LUKS prompt at console | Physical/IPMI console — type LUKS passphrase |
| SSH works, but `zpool status` shows pool not imported | ZFS pool unavailable | `sudo zpool import <pool>` then check key |
| `zfs get keystatus <pool>` shows `unavailable` | Key not loaded (key file missing or service skipped) | `sudo zfs load-key -L file:///etc/zfs/keys/<pool> <pool>` |

## Status check (run from DESK)

```bash
ssh -A akunito@192.168.20.200 'sudo zpool status; echo ===; sudo zfs get -H keystatus ssdpool extpool; echo ===; lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE | head -15'
```

Healthy output:
- `pool: ssdpool` / `state: ONLINE` (and same for `extpool`)
- `keystatus = available` for both pools
- `cryptroot` listed under `sdd2`, mounted at `/`

## Manual unlock (only if `nas-zfs-unlock.service` failed)

```bash
ssh -A akunito@192.168.20.200 'sudo systemctl status nas-zfs-unlock.service'
# If the service failed, check the key file exists and is readable
ssh -A akunito@192.168.20.200 'sudo ls -la /etc/zfs/keys/ && sudo cat /etc/zfs/keys/ssdpool | wc -c'
# Re-run the unlock script
ssh -A akunito@192.168.20.200 'sudo systemctl restart nas-zfs-unlock.service'
# Or manually
ssh -A akunito@192.168.20.200 'sudo zfs load-key -L file:///etc/zfs/keys/ssdpool ssdpool'
ssh -A akunito@192.168.20.200 'sudo zfs load-key -L file:///etc/zfs/keys/extpool extpool'
ssh -A akunito@192.168.20.200 'sudo zfs mount -a'
```

## If the NAS is at the LUKS prompt (cannot SSH at all)

There is **no remote unlock path**. Either:
1. Walk to the NAS and type the passphrase at the attached monitor/keyboard
2. Connect via IPMI / KVM-over-IP if the AORUS B550 board has it configured
3. As a last resort, RTC-wake or power-cycle and pre-enter passphrase via attached console

If you need remote unlock for the future, add `boot.initrd.network` + `boot.initrd.luks.devices.cryptroot.keyFile` or a Dropbear-in-initrd setup to `profiles/NAS_PROD-config.nix`. This was intentionally not configured during the migration.

## Related

- Profile: `profiles/NAS_PROD-config.nix`
- Module: `system/app/nas-services.nix` (auto-unlock service definition)
- Hardware: `cryptroot` on Samsung 840 EVO 500GB (`/dev/sdd2`)
- Migration history: `memory/project_truenas_to_nixos.md`
