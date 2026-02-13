---
id: hardware.thunderbolt-dock
summary: Thunderbolt dock setup, OWC Dock 96W, ATTO ThunderLink NS 3102 (Linux incompatible), PS/2 keyboard/touchpad fixes
tags: [thunderbolt, dock, owc, atto, 10gbe, thinkpad, keyboard, touchpad, ps2, hardware]
related_files: [system/hardware/thunderbolt.nix, system/hardware/thinkpad.nix, profiles/LAPTOP_L15-config.nix]
---

# Thunderbolt Dock & 10GbE Setup (LAPTOP_L15)

## Overview

The LAPTOP_L15 (ThinkPad L15 Gen 2 Intel, 20X4S3UD20) uses an OWC Thunderbolt Dock 96W for docking with peripherals. A separate ATTO ThunderLink NS 3102 was tested for 10GbE but is **not Linux-compatible**.

## Hardware

### ThinkPad L15 Gen 2 Intel (20X4) Ports

| Port | Type | Location |
|------|------|----------|
| USB-C | USB-C 3.2 Gen 1 (data, PD 3.0, DP 1.4) | Left side |
| Thunderbolt 4 | USB4/TB4 40Gbps (data, PD 3.0, DP 1.4) | Left side |
| RJ45 | Intel I219-V Gigabit Ethernet | Left side |
| USB-A x2 | USB 3.2 Gen 1 | Right side |
| HDMI | HDMI 2.0 | Left side |

**Important:** Only ONE USB-C port supports Thunderbolt 4. The other is USB-C 3.2 Gen 1 only.

### OWC Thunderbolt Dock 96W

- Connected to the TB4 port
- Operates in **USB mode** (not full Thunderbolt PCIe tunneling)
- Provides: USB hub, Realtek RTL8153 Gigabit Ethernet, display output
- Dock ethernet interface: `enp0s13f0u3u4u5` (name may vary)
- Dock ethernet MAC: `00:23:a4:0b:02:d6`
- DHCP lease: 192.168.8.92 (set in pfSense)

### ATTO ThunderLink NS 3102 (TLNS-3102-D00) - NOT LINUX COMPATIBLE

**Status: Does not work on Linux. No driver available.**

- Thunderbolt 3 to dual 10GbE (SFP+) adapter
- USB vendor ID: `065d:0015`
- Serial: `4FE11011A080FDB5504D92A7BB04B259`
- **Problem:** Requires proprietary ATTO driver to establish Thunderbolt PCIe tunnel. Without the driver, only a USB management endpoint appears — the 10GbE NIC never enumerates on the PCI bus.
- ATTO only provides macOS and Windows drivers for 10GbE ThunderLink models
- Linux drivers exist only for Fibre Channel ThunderLink models (FC 3162, FC 3322)
- Works fine on macOS with ATTO kernel extension driver

**10GbE alternatives for Linux (if needed in future):**
- OWC Thunderbolt 3 10G Ethernet Adapter (Aquantia chipset, native Linux support)
- Sonnet Solo 10G TB3 adapter (Aquantia AQC107, native `atlantic` driver)
- USB 3.2 to 5GbE adapter (Realtek RTL8156, native `r8152` driver, ~5Gbps)
- Intel X550 or Aquantia AQC107 PCIe card in a TB3-to-PCIe enclosure

## NixOS Configuration

### Thunderbolt Module (`system/hardware/thunderbolt.nix`)

Enabled via `thunderboltEnable = true` in profile config. Provides:
- `services.hardware.bolt.enable` — bolt daemon for device authorization
- `boot.kernelModules = [ "thunderbolt" ]`
- Udev rule for automatic device authorization
- Packages: `usbutils`, `thunderbolt` (boltctl)

### ThinkPad PS/2 Keyboard/Touchpad Fix (`system/hardware/thinkpad.nix`)

**Problem (kernel 6.19+):** On kernel 6.19, `i8042`, `atkbd`, and `psmouse` are loadable modules (not built-in). Without explicit configuration:
- Built-in keyboard doesn't work at LUKS password prompt (modules not in initrd)
- i8042 AUX port doesn't initialize (touchpad not detected)
- psmouse not auto-loaded (touchpad driver missing)

**Fix applied in `thinkpad.nix`:**
```nix
boot.initrd.availableKernelModules = [ "i8042" "atkbd" ];  # Keyboard at LUKS prompt
boot.kernelModules = [ "psmouse" ];                         # Touchpad driver
boot.kernelParams = [ "i8042.reset=1" "i8042.nomux=1" ];   # Fix AUX port init
```

### Touchpad Speed (`user/wm/sway/swayfx-config.nix`)

```
input "type:touchpad" {
    dwt enabled
    tap enabled
    natural_scroll enabled
    middle_emulation enabled
    accel_profile adaptive    # Precise for slow, fast for big movements
    pointer_accel 0.5         # Base speed boost
}
```

Only affects touchpads — USB mice use their own defaults.

## Troubleshooting

### Dock not providing data (power only)
1. Check `number_of_alternate_modes` in `/sys/class/typec/port*/partner/`
2. If 0: reseat cable, try other port, power cycle dock (unplug AC 30s)
3. Verify dock interface: `lsusb | grep "Other World Computing"`

### Keyboard not working at LUKS prompt
- Ensure `i8042` and `atkbd` are in `boot.initrd.availableKernelModules`
- Requires reboot after config change (initrd is baked at build time)

### Touchpad not detected
1. Check `lsmod | grep psmouse` — should be loaded
2. Check `ls /sys/bus/serio/devices/` — should have `serio0` (KBD) and `serio1` (AUX/touchpad)
3. If serio1 missing: verify `i8042.reset=1` in `/proc/cmdline`
4. Manual test: `sudo modprobe psmouse`

### ATTO ThunderLink shows USB only
- This is expected on Linux — no driver available
- USB management interface (`065d:0015`) appears but PCIe tunnel never forms
- The device requires ATTO's proprietary driver to establish TB PCIe tunneling
