---
id: akunito.infrastructure.nas-bios-b550-aorus-elite-v2
summary: NAS_PROD firmware settings (Gigabyte B550 AORUS ELITE V2) — where each option lives and why it has its value; the iGPU-forced setup for the RTX 3090
tags: [nas, bios, hardware, gpu, power, wol, rtc]
related_files: [system/app/nas-services.nix, system/hardware/nvidia.nix, profiles/NAS_PROD-config.nix]
date: 2026-10-02
status: published
---

# NAS BIOS — Gigabyte B550 AORUS ELITE V2

Board in NAS_PROD (Ryzen 5 5600G, RTX 3090 in PCIEX16 since 2026-10-01). Advanced Mode (F2 toggles
Easy/Advanced), **Del** enters setup, **F12** boot menu, **F10** save & exit. Values below were read
from the screen on 2026-10-01/02. "Keep" means it is load-bearing — changing it breaks something.

## Settings → IO Ports

| Option | Value | Why |
|---|---|---|
| Initial Display Output | **IGD Video** | console + LUKS prompt on the board HDMI/DP, not on the 3090 |
| Integrated Graphics | **Forces** | **Keep.** On `Auto` the firmware switches the iGPU OFF when a dGPU is present: no picture on the board output and Jellyfin loses VAAPI (`renderD128`) |
| Above 4G Decoding | **Enabled** | 3090 BARs above 4G (`BAR 1 0x7fc0000000`) |
| Re-Size BAR Support | Disabled | no gain for CUDA inference; one variable less |

## Settings → Miscellaneous

| Option | Value | Why |
|---|---|---|
| LEDs in System Power On State | **Off** | board accent LEDs (AINF-403). Verified 2026-10-02: the **front power LED stays on** (it is on F_PANEL, not on this option) |
| LEDs in Sleep, Hibernation, and Soft Off States | Off | why the box shows **no LEDs in S3** — it is suspended, not off; never pull power at night |
| PCIEX16 / PCIe Slot Configuration | Auto | |
| PCIe ASPM Mode | **Disabled** | keep: RTL8125 and X520 have link-drop history with ASPM; saving would be 1-5 W (estimate) |
| IOMMU | Auto | |
| AMD CPU fTPM | Enabled | |

## Settings → Platform Power

| Option | Value | Why |
|---|---|---|
| AC BACK | Always Off | a power cut needs the LUKS passphrase at the console anyway |
| ErP | **Disabled** | **Keep.** Enabled cuts standby power and kills the RTC wake (16:00) and Wake-on-LAN |
| Soft-Off by PWR-BTTN | Instant-Off | |
| Power Loading | Auto | |
| Resume by Alarm | **Enabled** (day 0, 11:00:00) | **Keep Enabled**: `nas-rtc-wake` programs the RTC (16:00) before every suspend and the firmware only honours it with this on. The 11:00 is the firmware default; Linux overwrites the alarm |
| Wake on LAN | Enabled | `/wake-on-lan-nas` |
| High Precision Event Timer | Enabled | |
| CEC 2019 Ready | **Disabled** | keep: low-standby mode breaks WoL/RTC wake |

## Tweaker → Advanced CPU Settings

Core Performance Boost Auto, SVM Mode Disabled (no VMs on the NAS), AMD Cool&Quiet Enabled,
PPC Adjustment PState 0, Global C-state Control Auto, Power Supply Idle Control Auto, Downcore
Auto, SMT Auto. All stock; do not undervolt/tune a storage server for a few watts.
Tweaker main page: everything Auto (PBO Auto = off, voltages Auto).

## Boot

Boot Option #1 `Linux Boot Manager (Samsung SSD 980 500GB)` (systemd-boot on the 980's ESP).
Fast Boot Disabled. CSM Support Enabled — harmless (boots pure UEFI, Above 4G works); left alone
to avoid another variable. Storage/Other PCI ROM = UEFI Only.

## Not in the firmware

No RGB control for the 3090 or the RGB headers here. Linux does it: `system/hardware/rgb-off.nix`
runs OpenRGB at boot and after every resume (3090 = MSI i2c on the NVIDIA adapter, `direct` black;
board = IT5702 USB `048d:5702`, `static` black). The 3090's native `off` mode left a white LED on.
