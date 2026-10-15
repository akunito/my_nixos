---
id: akunito.infrastructure.desk-win11-vm
summary: The `win11` libvirt guest on DESK (qemu:///system) — Windows 11 Pro 25H2 test VM for L2 Reborn / Lu4 — how it is defined, how Claude controls it headless (ssh + guest-agent + QMP input), the 2026-10-15 audit/fixes (Secure Boot keys, virtio, CPU topology, NTFS discard), the safe debloat and the open items
tags: [desk, libvirt, qemu, windows11, vm, secure-boot, virtio, debloat, l2]
related_files: [scripts/win11-vm/**, system/app/virtualization.nix, docs/akunito/plans/l2-proton-linux-compat.md]
date: 2026-10-15
status: published
---

# DESK `win11` VM (libvirt, qemu:///system)

Purpose (Diego, 2026-10-15): an undisguised Windows 11 guest on DESK to test L2 Reborn and L2lu4 under a hypervisor before looking at other options (plan: `docs/akunito/plans/l2-proton-linux-compat.md`, "VM track"). No GPU passthrough: QXL 2D only, so the games run on WARP/software D3D9 — the test answers "does the launcher/anti-cheat accept an undisguised VM", not "is it playable".

## Where things are

| Item | Location |
|------|----------|
| Definition (source of truth, `virsh define` it after edits) | `scripts/win11-vm/win11.xml` |
| Disk | `/home/akunito/VMs/win11/win11.qcow2` on **virtio-scsi** (btrfs, `chattr +C`, 256 GiB virtual, 79 GiB on disk after the 2026-10-15 move + zero-fill) — moved from `/mnt/DATA_SATA3/VirtPool/` (NTFS); the old 256 GiB copy there is the pre-move backup |
| NVRAM | `/var/lib/libvirt/qemu/nvram/win11_VARS.fd` (+ `.bak-2026-10-15-setupmode` = the pre-fix copy) |
| ISOs | `/mnt/DATA_SATA3/VirtPool/virtio-win-0.1.302.iso` (attached), 0.1.285 / 0.1.271 kept |
| Guest | `winVMaku`, user `diego` (Microsoft account, admin), Windows 11 Pro 25H2 build 26200.9711, activated |
| Network | libvirt `default` NAT, `192.168.122.108` (DHCP lease by MAC `52:54:00:75:63:43`) |
| Viewer | `virt-viewer --connect qemu:///system --domain-name win11 --attach`; sway-apps rule `r-125d3a18` puts `app_id=virt-viewer` on WS 13 (Samsung DP-1), Diego's standing request |

## Controlling it headless (what Claude uses)

- **SSH**: `ssh diego@192.168.122.108` → PowerShell (DefaultShell). Win32-OpenSSH 10.0.0.0p2 in `C:\Program Files\OpenSSH` (the `Add-WindowsCapability` route hung for 30 min: it pulled the whole monthly CU first), key in `C:\ProgramData\ssh\administrators_authorized_keys` (Diego's agent ed25519). `scp` works. `sshd` is delayed-auto; it logs one "terminated unexpectedly" per boot and recovers — harmless so far.
- **Guest agent**: channel `org.qemu.guest_agent.0`; `virsh qemu-agent-command win11 '{"execute":"guest-ping"}'`, `virsh shutdown --mode agent win11`, `virsh reboot --mode agent win11`. ACPI `virsh shutdown` is IGNORED by Windows while a session is open (measured 2026-10-15, 20 min) — always use `--mode agent` or `shutdown /s` over ssh.
- **Screen + input without a session**: `scripts/win11-vm/vm.py` (`shot PATH`, `type "text"`, `key meta_l+x`, `click X Y W H`) — `virsh screenshot` + QMP `input-send-event` (abs tablet coords, qcodes). Gotchas: the PS/2 keyboard FIFO is 16 bytes, so >1 char per QMP call drops keys (vm.py sends one key per call); the guest keyboard layout is US-International (dead keys `' " \` ^ ~` — vm.py follows them with a space); a virtio keyboard is also attached now.
- **Bootstrapping a fresh guest**: serve `scripts/win11-vm/bootstrap-openssh.ps1` (public key filled in; plus `dl/OpenSSH-Win64.zip`) as `s2.ps1` from the host on `192.168.122.1:8765` (`python3 -m http.server 8765 --bind 192.168.122.1`) and type `irm http://192.168.122.1:8765/s2.ps1 | iex` in an admin terminal. Needs `iptables -I nixos-fw -i virbr0 -p tcp --dport 8765 -j ACCEPT` on the host (temporary; not in the NixOS config on purpose). The auto-mode classifier refused to (a) accept the UAC prompt via injected keys, (b) run a downloaded script and (c) add the firewall rule — Diego did those three by hand; everything after that ran over ssh.

## 2026-10-15 audit and what was changed

Found: Secure Boot in Setup Mode (NVRAM had no PK/KEK/db, only a dbx Windows had pushed → Windows reported Secure Boot off = the "certificate" warnings); host TPM `/dev/tpm0` passthrough; disk + NIC on SATA/e1000e; Windows 22H2 install ISO still attached; 16 GiB balloon; **no CPU topology → libvirt exposed 8 sockets and Windows 11 Pro (2-socket licence) used 2 of the 8 vCPUs**; qcow2 fully allocated (256 GiB on disk) because the pool sits on NTFS (`ntfs3` has no punch-hole: `fallocate -p` → "keep size mode is unsupported", so every discard fails and the guest's retrim ends with CRC error 0x80070017).

Changed (all in `win11.xml`): Secure Boot keys enrolled with `virt-fw-vars --enroll-generate 'nixosaku win11 PK' --microsoft-kek all --secure-boot` (own PK, KEK = own + MS 2011 + MS 2023, db = Windows 2011 + Windows 2023 + MS UEFI 2011 + MS UEFI 2023, dbx kept) → `Confirm-SecureBootUEFI` = True, bootmgfw (PCA 2011-signed, July 2026) boots. `<topology sockets=1 cores=4 threads=2>` + `topoext` + vcpus pinned to host cores 4-7/12-15, emulator/iothread on 0-3 → 8 CPUs visible. boot disk on **virtio-scsi** (`cache=none io=native discard=unmap detect_zeroes=unmap`, controller `queues=4` + iothread). virtio-blk was tried first: viostor's discard path makes Windows retrim fail with CRC error 0x80070017 on NTFS *and* btrfs, vioscsi UNMAP works (delete-notify TRIM shrinks the file). Each driver was made Boot-start before the switch by hot-plugging a 1 GiB probe disk on that bus (otherwise INACCESSIBLE_BOOT_DEVICE). `Optimize-Volume -ReTrim` is still reported "Not Supported"/skipped by Windows on this device, so to reclaim already-freed space zero-fill C: from the guest (64 MiB zero buffer in a loop to `C:\zerofill.bin`, then delete it): `detect_zeroes=unmap` turns the zero writes into holes — 199 GiB → 79 GiB in ~5 min. virtio-net (same MAC), virtio keyboard, guest-agent channel, `freePageReporting`, memory fixed at 8 GiB, Windows ISO removed, virtio-win 0.1.302 attached. Guest: virtio-win-guest-tools 0.1.285 (drivers, QEMU-GA, balloon), OpenSSH, UAC `ConsentPromptBehaviorAdmin=0` (admins elevate silently, `EnableLUA` untouched), `DevicePasswordLessBuildVersion=0` so `netplwiz` shows the autologon checkbox. Not changed: TPM stays host passthrough until Diego decides (swtpm invalidates the Windows Hello PIN → password sign-in once).

Debloat (`scripts/win11-vm/debloat.ps1`, idempotent, log `C:\vmdebloat.log`): telemetry/CEIP/feedback policies, advertising id, content delivery, Bing/Cortana search, widgets, Copilot, Game DVR; 11 scheduled tasks; 22 services disabled (DiagTrack, dmwappush, SysMain, WSearch, Spooler, Xbox*, Phone, WER, Maps, SSDP/FD, WpnService, CDP…); ~40 consumer Appx removed (Copilot, Teams, Outlook, Mail, Xbox, Clipchamp, Bing*, YourPhone, Solitaire, widgets, DevHome, QuickAssist, OneDrive…); OneDrive uninstalled; hibernation off, High Performance plan, no display/sleep timeouts, visual effects = performance. Kept: Defender, Store, Edge/WebView2 (the Reborn launcher is WPF+WebView2), Terminal, winget, 7-Zip, Vivaldi, Power BI, Windows Update.

Measured (guest idle at the lock screen, after reboot): before 168 processes / 108 services / 2 usable CPUs / 256 GiB on disk; after 91 / 76, 1.6 GB used of 8 GB, 8 CPUs, 79 GiB on disk. Host: qemu RSS ≈ 8.2-8.6 GB (guest touched all pages; free-page reporting returns them slowly), ~5-15 % of one core idle.

## Open items

- Autologon: Diego runs `netplwiz` (checkbox now visible) with the Microsoft-account password — Claude never asks for or stores it.
- TPM → swtpm (`<tpm model='tpm-crb'><backend type='emulator' version='2.0'/>`): pending Diego's OK (PIN reset).
- Old disk `/mnt/DATA_SATA3/VirtPool/win11.qcow2` (256 GiB) is the pre-move copy; delete when Diego confirms the moved VM works.
- Firewall rule for 8765 lives until the next rebuild; nothing depends on it.
- Next: install L2 Reborn and L2lu4 clients in the guest (`winget` minimal set as needed) and run the undisguised-VM test from the plan.
