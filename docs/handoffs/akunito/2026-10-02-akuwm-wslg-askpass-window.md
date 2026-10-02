# Handoff 2026-10-02 (main) — AkuWM: the WSLg sudo askpass window (zenity via msrdc) is never seen

## The symptom (user-visible)

`install.sh` launched from a Windows-side session (Claude Code on Windows calling
`wsl.exe`, detached with `setsid` so sudo uses `SUDO_ASKPASS`) pops zenity
*"sudo: Authentication Required"* through WSLg. Diego never sees it: "apareció un segundo
y se fue". The deploy sits on `sudo -v` until sudo's 5-minute timeout, three times in a row
today. Typing the password in a WSL terminal (`sudo true`, ticket is global 180 min) is the
workaround; the real fix is in AkuWM.

## What was measured (14:48–14:55, AkuWM 0.2.4 dev build, `%LOCALAPPDATA%\Programs\AkuWM`)

The Windows-side window is WSLg's RAIL host:

```
msrdc.exe pid 36000  hwnd 0x1f0890
title  "[WARN:COPY MODE] sudo: Authentication Required (NixOS)"
rect   3072,-298 .. 4224,1430   (1152x1728)  visible=True  DWMWA_CLOAKED=0
```

That rectangle is **DISPLAY2, the portrait monitor (3072,-326, 1152x2048)**, with the
window stretched to the whole screen -- a zenity password box is ~400x150. AkuWM's log
for the handle, complete:

```
14:48:02.440 DBG [akuwm-wm]   decorate 0x1f0890 msrdc Decoration { Border = 4294967294, Corners = Round, TitleBar = False, Opacity = 1 }
14:48:02.640 DBG [akuwm-wm]   band 0x1f0890 topmost=True
14:48:04.845 DBG [akuwm-wm]   foreground -> 0x1f0890 msrdc
14:48:06.082 DBG [akuwm-wm]   foreground -> 0x1f0890 msrdc
```

No `place`, no rule hit, no workspace line: AkuWM treated it as a floating topmost window
and left the geometry alone. `SetWindowPos` from PowerShell (600x300, centre of the
primary) succeeded and the window was back at 3072,-298 within seconds **with no AkuWM
log line at all** -- so either msrdc re-syncs the RAIL geometry from the X server on its
own, or AkuWM moved it without logging. Not settled; this is the first thing to find out.

`templates/windows/DESK_W11/akuwm/common.json` has no rule for `msrdc` (checked: no
`msrdc`, `wslg`, `RAIL`). The X side is fine: `DISPLAY=:0`, `/tmp/.X11-unix/X0` present,
zenity 4.2.1 running.

## What to try (from the WSL session, AkuWM repo `~/Projects/AkuWM`)

1. Reproduce without a deploy:
   `wsl.exe -d NixOS -- bash -lc "setsid -f zenity --password --title=test < /dev/null"`
   and watch `akuwm.log` + `GetWindowRect` on the `msrdc` hwnd.
2. Decide who stretches it to DISPLAY2: run the same with AkuWM stopped
   (`akuwm-switch.ps1` / Rescue) -- if it still lands there, it is WSLg
   (`WSLg` chooses the monitor the X root maps; check `wsl --version` 2.7.14 RAIL
   behaviour and whether DISPLAY2 being portrait is the trigger).
3. If AkuWM: a rule for process `msrdc` -- float, place on the **focused** monitor at the
   window's requested size, never band topmost (the band may be what fights the RAIL
   geometry sync). The 2026-09-22 handoff (NordVPN WPF modal) is the sibling case:
   fixed-size windows that must not be tiled.
4. Regression test in `tests/wm/` next to `openwith-test.ahk`: a zenity window must be
   on the focused monitor, fully on-screen, within 1 s.

## Related

- Runbook `docs/akunito/infrastructure/desk-w11-wsl.md`, "The restart loop of
  2026-10-02" (why the deploy was running from Windows, and the `setsid` rule).
- `docs/handoffs/akunito/2026-09-22-akuwm-nordvpn-modal.md`.

## Resolved 2026-10-02 15:16 (from the WSL session)

Step 1 reproduced it and settled the open question in one log read: **AkuWM
moved it, and it did log** -- `place 0x600cec msrdc -> 3840,-373 1440x2525`,
then `will not go to ... (it is at 3840,-373 1440x2160)`. The window is born
370x317; AkuWM tiled it like any other window. (The 14:48 trace had no `place`
line only because that build's log was read for one handle after the fact.)

Fix, AkuWM **0.2.6**: rule action `center` (implies float, skips the placement
journal and the app memory, centres at the window's own size on the monitor
under the pointer), and rule `r-wslg` (`msrdc` -> `center`) in `common.json`.
Unit `CenterRuleTests`; driven `tests/wm wslg` 8/8 on the signed build: with
the pointer on the main monitor the window is at 1735,942 370x317 (workspace
11), with it on the portrait one at 4375,731 370x317 (workspace 22).

Also found on the way: WSL came back from the 14:47 restart without the
`WSLInterop` binfmt entry (every `.exe` from WSL: "cannot execute binary
file"). Restored from PowerShell with `wsl.exe -u root` (no password);
declarative from the next deploy (`wsl.interop.register = true`).

The sudo ticket was primed at 15:16 (the old askpass closed). The deploy of
the resource guards is still the Windows-side session's to finish.

