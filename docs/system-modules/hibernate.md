---
id: hibernate
summary: Hibernation with LUKS-encrypted swap for laptops and desktops
tags: [hibernation, suspend, luks, swap, encryption, power, laptop, desktop, sway, idle, lid, acpid]
related_files:
  - system/hardware/hibernate.nix
  - system/hardware/power.nix
  - lib/defaults.nix
  - profiles/LAPTOP-base.nix
  - profiles/LAPTOP_L15-config.nix
  - profiles/DESK-config.nix
  - user/wm/sway/swayfx-config.nix
---

# Power, Suspend & Hibernation Guide

## Overview

This document covers the **complete power management system** for Sway devices in this repo: idle timeouts, suspend, hibernate, lid behavior, and the power button. It is the single reference for setting up a new Desktop or Laptop with Sway.

Three layers work together:

1. **system/hardware/power.nix** — TLP power saving, logind lid/power-button policy, sleep mode
2. **system/hardware/hibernate.nix** — LUKS-encrypted swap, resume device, acpid, polkit
3. **user/wm/sway/swayfx-config.nix** — swayidle (screen lock, monitor off, suspend), lid handler

## Sway Power System Architecture

### How the Layers Interact

```
                         ┌─────────────────────────────────────┐
                         │         lib/defaults.nix            │
                         │  (all flags default to safe values) │
                         └──────────┬──────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
            ┌──────────────┐ ┌──────────┐  ┌───────────────────┐
            │ LAPTOP-base  │ │   DESK   │  │  (other profiles) │
            │ hibernateEn… │ │ hibern…  │  │  defaults apply   │
            │ powerKey     │ │ powerKey │  │                   │
            │ swayIdle…    │ │          │  │                   │
            └──────┬───────┘ └─────┬────┘  └───────────────────┘
                   │               │
                   ▼               ▼
          ┌────────────────────────────────────────┐
          │         NixOS Module Evaluation         │
          └──────┬─────────────┬───────────────────┘
                 │             │
     ┌───────────▼──┐  ┌──────▼──────────┐
     │  power.nix   │  │ hibernate.nix   │
     │  TLP/logind  │  │ LUKS/acpid      │
     │  lid policy  │  │ (overrides      │
     │  powerKey    │  │  logind powerKey │
     └──────────────┘  │  with mkForce)  │
                       └─────────────────┘
                 │
     ┌───────────▼──────────────────────────┐
     │     swayfx-config.nix (user-level)   │
     │                                      │
     │  sway-power-swayidle ─► swayidle     │
     │    ├─ lock (swaylock-with-grace)     │
     │    ├─ monitors off                   │
     │    └─ sway-idle-suspend ─►           │
     │        hibernate? + battery? →       │
     │          suspend-then-hibernate      │
     │        else → suspend                │
     │                                      │
     │  sway-lid-handler                    │
     │    ├─ ext monitor? → disable eDP-1   │
     │    └─ no ext + battery? →            │
     │        hibernate? →                  │
     │          suspend-then-hibernate      │
     │        else → suspend                │
     │                                      │
     │  sway-power-monitor                  │
     │    └─ AC↔battery change →            │
     │        restart swayidle.service      │
     │        (applies new timeouts)        │
     └─────────────────────────────────────┘
```

### Feature Flags Reference

#### Power & Sleep (lib/defaults.nix → power.nix)

| Flag | Default | Description |
|------|---------|-------------|
| `powerManagement_ENABLE` | `false` | NixOS `powerManagement.enable` |
| `power-profiles-daemon_ENABLE` | `false` | power-profiles-daemon (mutually exclusive with TLP) |
| `TLP_ENABLE` | `false` | TLP power management (AC/battery CPU governors, charge thresholds) |
| `LOGIND_ENABLE` | `true` | Enable logind lid/power-button handling |
| `lidSwitch` | `"ignore"` | Lid close action (logind). `"ignore"` = Sway handles it |
| `lidSwitchExternalPower` | `"ignore"` | Lid close on AC (logind) |
| `lidSwitchDocked` | `"ignore"` | Lid close docked (logind) |
| `powerKey` | `"ignore"` | Power button action (logind). Laptops set `"suspend"` |
| `MEM_SLEEP_ON_AC` | `"deep"` | Sleep mode on AC (`"deep"` = S3, `"s2idle"` = S0ix) |
| `MEM_SLEEP_ON_BAT` | `"deep"` | Sleep mode on battery |

#### Sway Idle (lib/defaults.nix → swayfx-config.nix)

| Flag | Default | Description |
|------|---------|-------------|
| `swayIdleLockTimeout` | `720` | Seconds before lock (AC) — 12 min |
| `swayIdleMonitorOffTimeout` | `900` | Seconds before monitors off (AC) — 15 min |
| `swayIdleSuspendTimeout` | `3600` | Seconds before suspend (AC) — 60 min |
| `swayIdleDisableMonitorPowerOff` | `false` | Skip monitor-off step (for DPMS-broken monitors) |
| `swaySmartLidEnable` | `false` | Context-aware lid: disable display if docked, suspend if not |
| `swayIdlePowerAwareEnable` | `false` | Different timeouts for AC vs battery |
| `swayIdleLockTimeoutBat` | `180` | Battery: lock after 3 min |
| `swayIdleMonitorOffTimeoutBat` | `210` | Battery: monitors off after 3.5 min |
| `swayIdleSuspendTimeoutBat` | `480` | Battery: suspend after 8 min |

#### Hibernate (lib/defaults.nix → hibernate.nix + swayfx-config.nix)

| Flag | Default | Description |
|------|---------|-------------|
| `hibernateEnable` | `false` | Enable hibernate/suspend-then-hibernate |
| `hibernateSwapLuksUUID` | `null` | LUKS UUID of encrypted swap partition (per-machine) |
| `hibernateDelaySec` | `600` | Seconds of suspend before auto-hibernate (10 min) |

The hibernate module is **gated** by both flags: `hibernateEnable && hibernateSwapLuksUUID != null`. When either is false/null, the module doesn't load and behavior is unchanged.

### Profile Inheritance

```
lib/defaults.nix          hibernateEnable = false, hibernateSwapLuksUUID = null
    │                     powerKey = "ignore", swayIdlePowerAwareEnable = false
    │
    ├── LAPTOP-base.nix       hibernateEnable = true
    │   │                     powerKey = "suspend"
    │   │                     swayIdlePowerAwareEnable = true
    │   │                     swaySmartLidEnable = true
    │   │
    │   ├── LAPTOP_L15        hibernateSwapLuksUUID = "a3d7d48f-..."
    │   │                     MEM_SLEEP = "s2idle" (Tiger Lake — no S3)
    │   │
    │   └── LAPTOP_YOGAAKU    (set UUID after encrypting swap)
    │
    └── DESK-config.nix       hibernateEnable = true, hibernateSwapLuksUUID = "6439621e-..."
                              powerKey = "suspend"
                              (no swayIdlePowerAwareEnable — always on AC)
```

## Desktop Behavior (DESK)

Desktops have no battery. The acpid handler reads BAT0 status — no BAT0 file means fallback to `"Full"` (= AC).

| Event | Action | Mechanism |
|-------|--------|-----------|
| Idle (12 min) | Lock screen (swaylock-with-grace) | swayidle |
| Idle (15 min) | Monitors off | swayidle |
| Idle (60 min) | Suspend (plain) | swayidle → `sway-idle-suspend` → `systemctl suspend` |
| Power button | Suspend (plain) | acpid (BAT0 fallback = "Full" → AC path) |
| On-demand | Hibernate | `systemctl hibernate` (polkit allows it) |
| Resume from suspend | Monitors on + wallpaper restore | swayidle after-resume |

**Key settings in DESK-config.nix:**
- `powerKey = "suspend"` — base logind setting (overridden by hibernate.nix `mkForce "ignore"` + acpid)
- `hibernateEnable = true` + `hibernateSwapLuksUUID = "..."` — activates hibernate module
- No `swayIdlePowerAwareEnable` — single set of AC timeouts used
- No `swaySmartLidEnable` — no lid on desktops

## Laptop Behavior (LAPTOP_L15, LAPTOP_YOGAAKU)

Laptops have a battery. Scripts check `/sys/class/power_supply/BAT0/status` at runtime.

### On AC (Docked/Charging)

| Event | Action | Mechanism |
|-------|--------|-----------|
| Idle (12 min) | Lock screen | swayidle (AC timeouts) |
| Idle (15 min) | Monitors off | swayidle |
| Idle (60 min) | Suspend (plain) | swayidle → `sway-idle-suspend` (BAT="Full" → plain suspend) |
| Power button | Suspend (plain) | acpid (BAT="Full"/"Charging" → AC path) |
| Lid close (ext monitor) | Disable eDP-1 | `sway-lid-handler` → `swaymsg output eDP-1 disable` |
| Lid close (no ext, AC) | Do nothing | `sway-lid-handler` — safety: never black out only display |

### On Battery

| Event | Action | Mechanism |
|-------|--------|-----------|
| Idle (3 min) | Lock screen | swayidle (battery timeouts via `swayIdlePowerAwareEnable`) |
| Idle (3.5 min) | Monitors off | swayidle |
| Idle (8 min) | Suspend-then-hibernate | swayidle → `sway-idle-suspend` (BAT="Discharging" → `systemctl suspend-then-hibernate`) |
| After suspend (10 min) | Auto-hibernate | systemd `HibernateDelaySec=600` |
| Power button | Hibernate immediately | acpid (BAT="Discharging" → `systemctl hibernate`) |
| Lid close (ext monitor) | Disable eDP-1 | `sway-lid-handler` |
| Lid close (no ext) | Suspend-then-hibernate | `sway-lid-handler` (BAT="Discharging" + hibernateEnable → `suspend-then-hibernate`) |
| AC/battery change | Restart swayidle | `sway-power-monitor` (switches timeout set + shows notification) |

### Without Hibernate (hibernateSwapLuksUUID = null)

If a laptop has `hibernateEnable = true` (from LAPTOP-base.nix) but no `hibernateSwapLuksUUID`, the hibernate module does NOT load. Behavior falls back to:

| Event | Action |
|-------|--------|
| Idle on battery | Suspend (plain) — NOT suspend-then-hibernate |
| Power button | Suspend (logind `powerKey = "suspend"`) |
| Lid close (no ext, battery) | Suspend (plain) |

This is because `sway-idle-suspend` and `sway-lid-handler` check `hibernateEnable` at **build time**, and this flag is `true` from LAPTOP-base.nix. However, the systemd sleep config and acpid are NOT active (hibernate.nix didn't load), so `suspend-then-hibernate` falls back to plain suspend if the system doesn't support hibernate.

**Important**: For full hibernate support, you MUST encrypt swap and set the UUID. See [Setup](#setup-encrypting-swap-on-a-new-machine) below.

## Module Components

### system/hardware/power.nix

Handles TLP, logind, and sleep mode:
- **TLP**: CPU governors, charge thresholds, GPU power profiles, WiFi power saving
- **logind**: Lid switch policy (`lidSwitch`, `lidSwitchExternalPower`, `lidSwitchDocked`), power key
- **Sleep mode**: `MEM_SLEEP_ON_AC`/`MEM_SLEEP_ON_BAT` (some laptops only support `s2idle`)
- **iwlwifi**: Optional disable of WiFi power save (prevents disconnect on lid close)

### system/hardware/hibernate.nix

Self-contained module, gated by `hibernateEnable && hibernateSwapLuksUUID != null`:

1. **LUKS swap unlock**: `boot.initrd.luks.devices."luks-swap"` — unlocked in initrd using `reusePassphrases` (same passphrase as root, no second prompt)
2. **Swap override**: `swapDevices = lib.mkForce [{ device = "/dev/mapper/luks-swap"; }]` — overrides the old unencrypted UUID in `hardware-configuration.nix`
3. **Resume device**: `boot.resumeDevice = "/dev/mapper/luks-swap"` — tells the kernel where to find the hibernate image
4. **Sleep config**: `HibernateDelaySec` for suspend-then-hibernate timing
5. **acpid**: Power-aware power button handler (battery → hibernate, AC → suspend)
6. **logind override**: `services.logind.powerKey = lib.mkForce "ignore"` — lets acpid handle the power button instead
7. **Polkit**: Allows `users` group to trigger hibernate without password

### Sway Scripts (swayfx-config.nix)

| Script | Purpose |
|--------|---------|
| `swaylock-with-grace` | Lock screen with 4s grace period (cancel if user returns) |
| `sway-idle-monitor-off` | Turn all outputs off (`swaymsg output * power off`) |
| `sway-idle-suspend` | Suspend or suspend-then-hibernate based on `hibernateEnable` + battery |
| `sway-idle-before-sleep` | Lock screen before system sleep (swaylock) |
| `sway-resume-monitors` | Turn outputs on + restore wallpaper after resume |
| `sway-lid-handler` | Lid close: disable eDP-1 if docked, suspend/hibernate if not |
| `sway-power-swayidle` | Launch swayidle with AC or battery timeouts |
| `sway-power-monitor` | Poll BAT0 every 5s, restart swayidle on AC↔battery change |

## Setup: New Sway Device Checklist

### A. Profile Configuration (Nix)

For a **new laptop** with Sway:

1. Inherit from `LAPTOP-base.nix` (gives you `hibernateEnable = true`, `swayIdlePowerAwareEnable = true`, `swaySmartLidEnable = true`, `powerKey = "suspend"`)
2. Set `MEM_SLEEP_ON_AC` / `MEM_SLEEP_ON_BAT` — check what your hardware supports:
   ```bash
   cat /sys/power/mem_sleep
   # [s2idle] deep   ← brackets show current; available options listed
   ```
3. Optionally tune idle timeouts (`swayIdleLockTimeoutBat`, etc.)
4. Optionally set `swayIdleDisableMonitorPowerOff = true` if monitor has DPMS wake issues

For a **new desktop** with Sway:

1. Set `hibernateEnable = true` and `powerKey = "suspend"` in the profile
2. No need for `swayIdlePowerAwareEnable` (always AC) or `swaySmartLidEnable` (no lid)
3. Default AC idle timeouts (12/15/60 min) apply

### B. Encrypting Swap (One-Time Manual Steps)

**Prerequisites:**
- Existing LUKS-encrypted root partition
- Unencrypted swap partition (or willing to re-encrypt)
- Know the root LUKS passphrase
- Swap size >= RAM size (kernel compresses, so usually OK if close)

**Step-by-step (run on the target machine):**

```bash
# 1. Identify the swap partition
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
# Look for the swap partition (e.g., /dev/nvme0n1p3)

# 2. Check current RAM size vs swap size
free -h
# Swap should be >= RAM for reliable hibernate

# 3. Disable current swap
sudo swapoff -a

# 4. Encrypt the partition with LUKS2
# CRITICAL: Use the SAME passphrase as root LUKS
sudo cryptsetup luksFormat --type luks2 /dev/<swap-partition>

# 5. Get the new LUKS UUID
sudo cryptsetup luksDump /dev/<swap-partition> | grep UUID
# → Note this UUID for the profile config

# 6. Open, format swap inside, close
sudo cryptsetup luksOpen /dev/<swap-partition> luks-swap
sudo mkswap /dev/mapper/luks-swap
sudo cryptsetup luksClose luks-swap

# 7. Set UUID in profile config
#    Edit profiles/<PROFILE>-config.nix:
#    hibernateSwapLuksUUID = "<UUID-from-step-5>";

# 8. Build (use 'boot' not 'switch' — LUKS swap can only unlock in initrd)
sudo nixos-rebuild boot --flake .#<PROFILE> --impure
sudo reboot
```

**After reboot**: Enter root LUKS passphrase once — swap auto-unlocks via `reusePassphrases` (no second prompt).

### Important Notes

- **Use `boot` not `switch`**: A live `switch` will fail because systemd tries to unlock LUKS swap immediately (no cached passphrase outside initrd)
- **Same passphrase**: The swap MUST use the same passphrase as root for `reusePassphrases` to work
- **hardware-configuration.nix**: The old unencrypted swap UUID becomes invalid after encryption. `hibernate.nix` uses `swapDevices = lib.mkForce` which overrides it. Optionally run `sudo nixos-generate-config` for cleanliness
- **GPT auto-generator**: systemd's `systemd-gpt-auto-generator` may detect the LUKS swap and try to unlock it post-boot (separate from initrd). If this happens, ensure `nixos-rebuild boot` was used so the initrd includes the luks-swap device

## Verification Checklist

Run these after deploying to a new machine. All must pass.

### 1. Boot & LUKS Swap

```bash
# Single passphrase prompt at boot (no second prompt)
# → Visual check during boot

# Swap is active on encrypted device
swapon --show
# EXPECTED: /dev/dm-N  partition  SIZE  ...

# Mapper device exists
ls -la /dev/mapper/luks-swap
# EXPECTED: lrwxrwxrwx ... luks-swap -> ../dm-N

# Resume device is set (non-zero major:minor)
cat /sys/power/resume
# EXPECTED: 254:N (NOT 0:0)
```

### 2. Hibernate Capability

```bash
# System reports hibernate capability
busctl call org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager CanHibernate
# EXPECTED: s "yes"

# acpid is active (handles power button)
systemctl is-active acpid
# EXPECTED: active

# Polkit allows hibernate
pkaction --action-id org.freedesktop.login1.hibernate --verbose | grep implicit
# EXPECTED: implicit lines should show "auth_admin" (polkit rule overrides at runtime)
```

### 3. Sway Idle & Power Scripts (Laptop Only)

```bash
# Power-aware swayidle is running
systemctl --user status swayidle
# EXPECTED: active (running)

# Power monitor is running (detects AC↔battery changes)
systemctl --user status sway-power-monitor
# EXPECTED: active (running)

# Check which swayidle timeouts are active
# Unplug AC, wait 5s, check journal:
journalctl --user -u swayidle --since "1 min ago"
# EXPECTED: swayidle restarted with battery timeouts
```

### 4. Functional Tests

**Test each scenario and record pass/fail:**

#### For Laptops:

| # | Test | Steps | Expected Result | Pass? |
|---|------|-------|-----------------|-------|
| 1 | Hibernate on-demand | `systemctl hibernate` | Powers off. Press power → LUKS prompt → resumes | |
| 2 | Power button (battery) | Unplug AC, press power button | Hibernates immediately (saves to disk, powers off) | |
| 3 | Power button (AC) | Plug AC, press power button | Suspends (screen off, wakes on keypress) | |
| 4 | Lid close (docked, ext monitor) | Close lid with ext monitor | Internal display off, session continues on ext | |
| 5 | Lid close (no ext, battery) | Unplug AC, close lid (no ext monitor) | Suspend-then-hibernate | |
| 6 | Lid close (no ext, AC) | Plug AC, close lid (no ext monitor) | Nothing happens (safety) | |
| 7 | Idle lock (battery) | Unplug AC, wait 3 min idle | Screen locks (swaylock-with-grace) | |
| 8 | Idle suspend (battery) | Unplug AC, wait 8 min idle | Suspend-then-hibernate | |
| 9 | Auto-hibernate delay | After test 8, wait 10 min in suspend | System hibernates (powers off completely) | |
| 10 | AC/battery switch | Plug/unplug AC during idle | Notification shown, swayidle restarts | |
| 11 | Lid open (was docked) | Open lid after test 4 | Internal display re-enables | |

#### For Desktops:

| # | Test | Steps | Expected Result | Pass? |
|---|------|-------|-----------------|-------|
| 1 | Hibernate on-demand | `systemctl hibernate` | Powers off. Press power → LUKS prompt → resumes | |
| 2 | Power button | Press power button | Suspends (wakes on keypress) | |
| 3 | Idle lock | Wait 12 min idle | Screen locks | |
| 4 | Idle monitors off | Wait 15 min idle | Monitors off (wake on mouse/key) | |
| 5 | Idle suspend | Wait 60 min idle | Suspends | |
| 6 | Resume | Press key after suspend | Monitors on, wallpaper restored, session intact | |

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

### Swayidle not using battery timeouts

Check:
1. `systemctl --user status sway-power-monitor` — must be active
2. Unplug AC, wait 5s, check: `journalctl --user -u swayidle --since "1 min ago"`
3. If `swayIdlePowerAwareEnable = false` in profile, only AC timeouts are used

### Lid close does nothing when expected to suspend

Check:
1. `swaySmartLidEnable` must be `true` in profile (LAPTOP-base.nix sets this)
2. Logind `lidSwitch` must be `"ignore"` (Sway handles it via `bindswitch`)
3. No external monitors must be connected for suspend to trigger
4. Must be on battery (AC + no ext = intentional no-op for safety)

## Related Documentation

- [LUKS Encryption & Remote Unlocking](../security/luks-encryption.md)
- [Power Management](../../system/hardware/power.md)
- [Sway Daemon Integration](../user-modules/sway-daemon-integration.md)
