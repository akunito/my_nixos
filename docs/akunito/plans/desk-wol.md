---
title: "Enable Wake-on-LAN for DESK"
status: planned
created: 2026-04-06
ticket: AINF-335
tags: [infrastructure, networking, wol, desk]
---

# Plan: Enable Wake-on-LAN for DESK

## Context

DESK has 2x Intel 82599ES 10GbE SFP+ cards (bonded as `bond0`) which do NOT support WOL. However, the onboard **Realtek RTL8125B 2.5GbE** NIC (`eno1`) supports WOL magic packets (`Supports Wake-on: pumbg`). It's currently unused and uncabled.

**Goal**: Enable WOL on `eno1` so DESK can be woken from both shutdown (S5) and suspend (S3) via VPS → pfSense → magic packet chain.

**Confirmed via diagnostics on DESK (2026-04-06)**:
- `eno1`: RTL8125B, driver `r8169`, MAC `08:bf:b8:6c:ab:92`, WOL capable but disabled (`Wake-on: d`)
- Intel 10GbE: `Supports Wake-on: d` — no WOL at all

## Implementation Steps

### 1. Add feature flags to `lib/defaults.nix` (after line 153)

```nix
# Wake-on-LAN
wolEnable = false;
wolInterface = "eno1";
wolMacAddress = "";
```

### 2. Enable flags in `profiles/DESK-config.nix`

Add to `systemSettings` block (after the networkBonding section):

```nix
wolEnable = true;
wolInterface = "eno1";
wolMacAddress = "08:bf:b8:6c:ab:92";
```

### 3. Create `system/hardware/wake-on-lan.nix` — NixOS module

Gated by `wolEnable`. Three components:

1. **NetworkManager connection profile** for `eno1` (autoconnect, method=disabled — link-up, no IP)
2. **`wol-enable` systemd service** (oneshot, after `network-online.target`): runs `ip link set eno1 up` + `ethtool -s eno1 wol g`
3. **`wol-enable-resume` systemd service** (after `sleep.target`): re-runs `ethtool -s eno1 wol g` since r8169 may reset WOL state on resume
4. Adds `ethtool` to system packages
5. NM reload activation script (separate name from bonding's: `reloadNetworkManagerWol`)

### 4. Import module in `profiles/personal/configuration.nix` (after line 30)

```nix
++ lib.optional (systemSettings.wolEnable or false) ../../system/hardware/wake-on-lan.nix
```

### 5. Create `scripts/desk-wol.sh` — Wake script

Based on existing `scripts/truenas-wol.sh` pattern. Supports:
- `--check` — ping test + SSH uptime
- (default) — send WOL via wakeonlan / pfSense SSH relay / etherwake, 3 retries, verify with ping
- `--suspend` — SSH to DESK and run `systemctl suspend`

Constants: MAC `08:bf:b8:6c:ab:92`, IP `192.168.8.96`, broadcast `192.168.8.255`.

### 6. Create `.claude/commands/wake-on-lan-desk.md` — Claude skill

Invokes `scripts/desk-wol.sh` with appropriate args based on user intent.

## Files to modify

| File | Action |
|------|--------|
| `lib/defaults.nix` | Add 3 WOL flags after line 153 |
| `profiles/DESK-config.nix` | Enable WOL flags in systemSettings |
| `system/hardware/wake-on-lan.nix` | **Create** — NixOS module |
| `profiles/personal/configuration.nix` | Add conditional import (line 31) |
| `scripts/desk-wol.sh` | **Create** — WOL script |
| `.claude/commands/wake-on-lan-desk.md` | **Create** — Claude skill |

## Manual prerequisites (user must do)

1. **Plug Ethernet cable** from DESK `eno1` (motherboard I/O panel, 2.5GbE port) to a LAN switch port
2. **Enable WOL in BIOS**: Enter UEFI (DEL at POST) → Advanced → APM Configuration → Enable "Power On By PCI-E" / "Wake on LAN"

## Verification procedure

After deploying (`./install.sh ~/.dotfiles DESK -s -u`):

```bash
# 1. Check systemd service
systemctl status wol-enable

# 2. Verify WOL is active
ethtool eno1 | grep "Wake-on"
# Expected: Wake-on: g

# 3. Check NM shows eno1 connected
nmcli device status | grep eno1

# 4. Test from another LAN machine (after poweroff)
wakeonlan -i 192.168.8.255 08:bf:b8:6c:ab:92

# 5. Test full chain from VPS
bash scripts/desk-wol.sh --check
bash scripts/desk-wol.sh
```

## Known limitations

- **WOL from S3 suspend**: May be unreliable — r8169 driver can drop NIC link during suspend. WOL from S5 (full power-off) is the reliable path.
- **Physical cable required**: eno1 must be connected to a LAN switch port
- **BIOS setting required**: Cannot be configured from NixOS
