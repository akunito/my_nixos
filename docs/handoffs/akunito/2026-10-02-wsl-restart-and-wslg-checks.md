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
