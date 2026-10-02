# Handoff 2026-10-02 (main) — restart WSL cleanly, then verify WSLg, interop and the guards

## Why a restart

The VM that booted at 14:47 (after the OOM loop) came up degraded in two ways, both
gone only with a new VM:

1. **WSLg in copy mode**: `/mnt/wslg/weston.log` line 67,
   `rdp_allocate_shared_memory: Failed to open "/mnt/shared_memory/{...}" with error:
   Input/output error`. Every Linux window is titled `[WARN:COPY MODE] …` and paints
   **nothing**: right place, right size, empty surface (`PrintWindow` = one colour).
   This is why the sudo askpass is "a transparent window with AkuWM's purple border".
   It happens with the AkuWM rule set to `ignore` too: not AkuWM.
2. **No `WSLInterop` binfmt entry** at boot (`.exe` from WSL: "cannot execute binary
   file"). Re-registered by hand at 15:09; declarative from the next deploy
   (`wsl.interop.register = true`, commit `7c8d50d9`).

## Order (the sudo ticket dies with the VM, so deploy FIRST)

1. **Deploy the guards while the ticket is valid** (primed 15:16, 180 min). In a WSL tab:
   ```bash
   cd ~/.dotfiles && git pull --ff-only && ./install.sh ~/.dotfiles DESK_W11 -s -d
   ```
   From a Windows-side session use the detached form in the runbook
   (`desk-w11-wsl.md`, "The restart loop of 2026-10-02").
2. **`.wslconfig`** (16 GB, the other half stays with Windows). PowerShell:
   ```powershell
   git -C $env:USERPROFILE\.dotfiles pull --ff-only
   Copy-Item $env:USERPROFILE\.dotfiles\templates\windows\DESK_W11\.wslconfig $env:USERPROFILE\.wslconfig -Force
   ```
3. **Restart.** Close the Claude sessions inside WSL first (they die with it). PowerShell:
   ```powershell
   wsl --shutdown
   Start-Sleep 10
   wsl -d NixOS -- true      # first start; then open a normal tab
   ```

## Checks after the restart (from a WSL tab)

```bash
ls /proc/sys/fs/binfmt_misc/WSLInterop && cmd.exe /c ver          # interop
grep -c "rdp_allocate_shared_memory: Failed" /mnt/wslg/weston.log  # 0 = shared memory ok
systemctl show user-1000.slice -p MemoryMax; free -g | head -2     # 12G; 16 total
setsid -f zenity --password --title=check < /dev/null              # painted, NO "[WARN:COPY MODE]", centred where the pointer is
cd ~/.dotfiles/templates/windows/DESK_W11/tests/wm && ./run-suite.sh wslg   # hands off the mouse: 10/10 incl. "it is painted"
```

If interop is missing again: PowerShell,
`wsl.exe -d NixOS -u root -- sh -c "echo ':WSLInterop:M::MZ::/init:PF' > /proc/sys/fs/binfmt_misc/register"`.
If WSLg is in copy mode again: `wsl --shutdown` once more (it is a boot-time mount race).

## State left behind

- AkuWM **0.2.6** installed (daemon, CLI, GUI): rule action `center`, rule `r-wslg`
  (`msrdc` -> `center`), light-dismiss guard for the "Open with" dialog. Unit 1114,
  `tests/wm` `openwith` 10/10, `fsdrag` 5/5, `wslg` 8/8 for place and size; its new
  "it is painted" check cannot pass until WSLg leaves copy mode.
- NOT done: the full `tests/wm` (206+) and `tests/fullscreen` runs on 0.2.6. Run them
  after the restart, in foreground chunks of two suites, nobody touching the mouse
  (`wslg` reports DISTURBED scenarios instead of judging them).
- `system/hardware-configuration.nix` is modified in the WSL clone (per-machine
  regeneration); `install.sh` resets it.

## Result of the restart (15:28, from the Windows session)

Steps 1-3 done: generation 14 carries the limits, `.wslconfig` copied, `wsl --shutdown`
+ boot. Checks after it: `WSLInterop` present and `cmd.exe /c ver` answers;
`user-1000.slice MemoryMax=12G`, `init.scope OOMPolicy=continue`, `free -g` 15 total,
`oom_kill 0`. The askpass worked for Diego (window seen, password accepted).

**Copy mode is NOT cured by a new VM.** The fresh boot's `/mnt/wslg/weston.log` has the
same line again, 15:28:54: `rdp_allocate_shared_memory: Failed to open
"/mnt/shared_memory/{fa6c95d0-…}" with error: Input/output error`, and the test window
`zenity --password --title=check` came up as `[WARN:COPY MODE] check (NixOS)` -- but
sized 296x254 and centred on the pointer (3500,585 on DISPLAY2), i.e. placed right and
painted. So the empty surfaces Diego then saw in the AkuWM tests are not explained by
copy mode alone; copy mode has been the steady state of this desk (every boot), it only
costs performance. Context for whoever digs: WSLg 1.0.73.2, `/dev/dxg` exists but the
kernel logs `dxgk: dxgkio_query_adapter_info: Ioctl failed: -22/-2` at every boot (no
usable vGPU from the RX 9070 XT / Radeon iGPU, AMD driver 32.0.31041.1004), and
`/mnt/shared_memory` is not mounted in the user distro (the system distro is where
weston opens it; not inspected). The 0 in my first grep was a race: the check ran at
15:28:15, weston wrote the line at 15:28:54.

## Closed 2026-10-02 15:50 (WSL session)

The empty windows are WSLg's on this machine: the first Linux window of a boot
paints, every later one is an empty surface -- measured with the AkuWM daemon
stopped and a fresh `msrdc.exe` (15:40). No user-space setting cured it. The
sudo askpass therefore no longer uses WSLg: `sudoAskpassWindowsNative`, a
native Windows password box through interop (`system/security/
sudo-askpass-windows.ps1`), deployed 15:46 (generation 15). `tests/wm askpass`
13/13. Plan 10.53. Still exposed: pinentry-qt through WSLg (gpg/ssh).

