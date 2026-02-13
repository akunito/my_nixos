---
id: hibernate
summary: Hibernation with LUKS-encrypted swap for laptops and desktops
tags: [hibernation, suspend, luks, swap, encryption, power, laptop, desktop]
related_files:
  - system/hardware/hibernate.nix
  - lib/defaults.nix
  - profiles/LAPTOP-base.nix
  - profiles/LAPTOP_L15-config.nix
  - profiles/DESK-config.nix
  - user/wm/sway/swayfx-config.nix
---

# Hibernation with LUKS-Encrypted Swap

## Overview

Hibernation (suspend-to-disk) writes RAM contents to swap and powers off the machine completely — zero battery drain. Since the RAM image may contain LUKS keys, passwords, and other sensitive data, the swap partition **must** be encrypted.

This module (`system/hardware/hibernate.nix`) provides:
- LUKS2 encryption for the swap partition (reuses root passphrase — no extra prompt at boot)
- Resume-from-hibernate support via `boot.resumeDevice`
- Configurable suspend-then-hibernate delay (`HibernateDelaySec`)
- Power-aware power button via acpid (battery → hibernate, AC → suspend)
- Polkit rules for unprivileged hibernate

## Architecture

### Feature Flags

| Flag | Default | Description |
|------|---------|-------------|
| `hibernateEnable` | `false` | Enable hibernate support |
| `hibernateSwapLuksUUID` | `null` | LUKS UUID of encrypted swap partition (per-machine) |
| `hibernateDelaySec` | `600` | Seconds of suspend before auto-hibernate (10 min) |

The module is **gated** by both flags: `hibernateEnable && hibernateSwapLuksUUID != null`. When either is false/null, the module doesn't load and behavior is unchanged.

### Profile Inheritance

```
lib/defaults.nix          hibernateEnable = false, hibernateSwapLuksUUID = null
    │
    ├── LAPTOP-base.nix       hibernateEnable = true
    │   └── LAPTOP_L15        hibernateSwapLuksUUID = "a3d7d48f-..."
    │   └── LAPTOP_YOGAAKU    (set UUID after encrypting swap)
    │
    └── DESK-config.nix       hibernateEnable = true, hibernateSwapLuksUUID = "6439621e-..."
```

### Desktop vs Laptop Behavior

| Scenario | Desktop (DESK) | Laptop (LAPTOP_L15) |
|----------|---------------|---------------------|
| Idle timeout | suspend | **suspend-then-hibernate** (on battery) |
| Lid close (no ext monitor) | N/A | **suspend-then-hibernate** (on battery) |
| Power button (battery) | N/A (always AC) | **hibernate immediately** |
| Power button (AC) | **suspend** (via acpid) | **suspend** (via acpid) |
| On-demand | `systemctl hibernate` | `systemctl hibernate` |
| After suspend on battery | N/A | **auto-hibernate after 10 min** |

On desktops (no battery), the acpid handler always detects "AC" (BAT0 fallback = "Full"), so the power button always suspends. Hibernate is on-demand only via `systemctl hibernate`.

On laptops, the Sway idle and lid scripts check battery status at runtime and use `suspend-then-hibernate` when discharging.

## Module Components

### system/hardware/hibernate.nix

1. **LUKS swap unlock**: `boot.initrd.luks.devices."luks-swap"` — unlocked in initrd using `reusePassphrases` (same passphrase as root, no second prompt)
2. **Swap override**: `swapDevices = lib.mkForce [{ device = "/dev/mapper/luks-swap"; }]` — overrides the old unencrypted UUID in `hardware-configuration.nix`
3. **Resume device**: `boot.resumeDevice = "/dev/mapper/luks-swap"` — tells the kernel where to find the hibernate image
4. **Sleep config**: `HibernateDelaySec` for suspend-then-hibernate timing
5. **acpid**: Power-aware power button handler (battery → hibernate, AC → suspend)
6. **logind override**: `services.logind.powerKey = lib.mkForce "ignore"` — lets acpid handle the power button instead
7. **Polkit**: Allows `users` group to trigger hibernate without password

### Sway Integration (swayfx-config.nix)

Two scripts check `hibernateEnable` at build time:

- **`sway-idle-suspend`**: When `hibernateEnable = true`, checks battery at runtime. Discharging → `suspend-then-hibernate`, AC → plain `suspend`.
- **`sway-lid-handler`**: Same battery check for lid close with no external monitor.

The `sway-power-swayidle` and `sway-power-monitor` scripts don't need changes — they call `sway-idle-suspend` which handles the logic.

## Setup: Encrypting Swap on a New Machine

### Prerequisites

- Existing LUKS-encrypted root partition
- Unencrypted swap partition
- Know the root LUKS passphrase

### Step-by-Step

```bash
# 1. Disable current swap
sudo swapoff -a

# 2. Encrypt the partition with LUKS2
# CRITICAL: Use the SAME passphrase as root LUKS
sudo cryptsetup luksFormat --type luks2 /dev/<swap-partition>

# 3. Get the new LUKS UUID
sudo cryptsetup luksDump /dev/<swap-partition> | grep UUID
# → Note this UUID

# 4. Open, format swap inside, verify, close
sudo cryptsetup luksOpen /dev/<swap-partition> luks-swap
sudo mkswap /dev/mapper/luks-swap
sudo cryptsetup luksClose luks-swap

# 5. Set UUID in profile config
#    Edit profiles/<PROFILE>-config.nix:
#    hibernateSwapLuksUUID = "<UUID-from-step-3>";

# 6. Build (use 'boot' not 'switch' — LUKS swap can only unlock in initrd)
sudo nixos-rebuild boot --flake .#<PROFILE> --impure
sudo reboot
```

**After reboot**: Enter root LUKS passphrase once — swap auto-unlocks via `reusePassphrases` (no second prompt).

### Important Notes

- **Use `boot` not `switch`**: A live `switch` will fail because systemd tries to unlock LUKS swap immediately (no cached passphrase outside initrd)
- **Same passphrase**: The swap MUST use the same passphrase as root for `reusePassphrases` to work
- **hardware-configuration.nix**: The old unencrypted swap UUID becomes invalid after encryption. `hibernate.nix` uses `swapDevices = lib.mkForce` which overrides it. Optionally run `sudo nixos-generate-config` for cleanliness
- **GPT auto-generator**: systemd's `systemd-gpt-auto-generator` may detect the LUKS swap and try to unlock it post-boot (separate from initrd). If this happens, ensure `nixos-rebuild boot` was used so the initrd includes the luks-swap device

## Verification

After reboot:

```bash
# Swap is active on encrypted device
swapon --show
# → /dev/dm-N partition SIZE ...

# Resume device is set (non-zero major:minor)
cat /sys/power/resume
# → 254:N

# System reports hibernate capability
busctl call org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager CanHibernate
# → s "yes"

# acpid is active (handles power button)
systemctl is-active acpid
# → active

# Mapper device exists
ls -la /dev/mapper/luks-swap
# → lrwxrwxrwx ... luks-swap -> ../dm-N

# Test hibernate (saves to disk, powers off)
systemctl hibernate
# → Press power button to resume, enter LUKS passphrase
```

## Current Machine Configuration

| Machine | Swap Partition | Swap Size | LUKS UUID | Status |
|---------|---------------|-----------|-----------|--------|
| DESK | `/dev/nvme1n1p3` | 39.1 GB | `6439621e-01dc-4710-adb8-8894fc6ce585` | Active |
| LAPTOP_L15 | `/dev/nvme0n1p3` | 15.6 GB | `a3d7d48f-c0eb-4655-9a30-6ea9f580ec0d` | Active |
| LAPTOP_YOGAAKU | — | — | — | Not configured |

## Troubleshooting

### Double passphrase prompt at boot

The initrd didn't include `luks-swap`. This happens when:
- Built with `nixos-rebuild switch` instead of `boot` (stale generation)
- Flake evaluation cached an old config where `hibernateSwapLuksUUID = null`

**Fix**: Rebuild with `sudo nixos-rebuild boot --flake .#PROFILE --impure && sudo reboot`

### `/sys/power/resume` shows `0:0`

The resume device wasn't set, usually because `/dev/mapper/luks-swap` didn't exist at boot (same root cause as double prompt).

**Fix**: Same as above — rebuild with `boot` and reboot.

### `CanHibernate` returns "no"

Check:
1. `swapon --show` — swap must be active
2. Swap size must be >= RAM size (kernel compresses, but swap should be at least equal)
3. Polkit rules must allow hibernate for `users` group

### Hibernate resumes but session is broken

GPU driver reinitialization can be slow, especially on AMD. This is expected behavior — the session should recover after a few seconds.

## Related Documentation

- [LUKS Encryption & Remote Unlocking](../security/luks-encryption.md)
- [Power Management](../../system/hardware/power.md)
- [Sway Daemon Integration](../user-modules/sway-daemon-integration.md)
