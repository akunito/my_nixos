# Handoff 2026-09-22 (main) — AkuWM cloaks/tiles a WPF modal: NordVPN "Add apps" unusable

## The symptom (user-visible)

NordVPN 8.11.1.0 → Settings → Split tunneling → **Add apps**. The modal:
1. first run: rendered, stuck on "Loading..." forever;
2. later runs: **rendered translucent/invisible but still hit-testable** — Diego clicked
   blind, closed it, and found PowerToys had been selected by that blind click;
3. after removing that entry: the modal renders but the window is stuck.

## TWO INDEPENDENT DEFECTS — do not conflate them

### Defect A — AkuWM (ours). The invisible / stuck window.

AkuWM manages the NordVPN window and fights it. Its own log says so, verbatim:

```
11:36:52.680 WRN [akuwm-wm] NordVPN "NordVPN " will not go to 1926,42 1914x2118 (it is at 1926,42 1230x952); AkuWM has stopped asking
11:45:06.935 WRN [.NET TP Worker] could not recover NordVPN "NordVPN ": still cloaked
11:47:18.479 WRN [akuwm-wm] showing NordVPN "NordVPN " did not take (the call reported success)   (x14 across the session)
11:51:53.903 DBG [akuwm-wm] refused the focus for 0x3b0c3e (hidden, or a window moved under a still pointer)
11:51:54.006 INF [akuwm-wm] focus 0x20888: InjectedInput -- a dummy keystroke was needed to claim the foreground right
```

`still cloaked` + `showing ... did not take (the call reported success)` **is** the
one-way-cloak trap already recorded in the AkuWM plan: the uncloak API returns success
and does nothing, so the HWND stays composited-out — present, hit-testable, not painted.
That is exactly the reported symptom, and it is a complete explanation of it.

At 11:51:51–54 AkuWM ran **8 `1 to place` redraws inside one second** on NordVPN
(94 ms and 314 ms placements among them), plus a `drag-tile`. `0x3b0c3e` — almost
certainly the modal, a second HWND of the same process — ended hidden and focus-refused.

**Why it is managed at all:** `templates/windows/DESK_W11/akuwm/common.json` has 21 rules
(zebar, PowerToys ×2, Command Palette, ShareX, AutoHotkey64_UIA, WindowsTerminal, …) and
**none matches `nord`**. NordVPN therefore falls through to the default = tiled. A WPF
modal with a fixed size refuses the tile geometry (`will not go to 1914x2118`), AkuWM
retries, and the window ends in the broken cloak state.

### Defect B — NordVPN's own bug. The empty app list.

Independent of AkuWM, and NOT ours:

```
[11:48:58.467] [SelectedAppsViewModel] SplitTunnelingAddAppsClicked
[11:48:58.469] [DialogService] Showing modal `AppSelectViewModel`.
[11:48:58.763] [ERR]  [AppSelectViewModel] Failed to load processes for app selection
System.ArgumentException: Destination array was not long enough...
   at System.Collections.Generic.List`1.CopyTo(T[] array, Int32 arrayIndex)
   at System.Collections.Generic.EnumerableHelpers.ToArray[T](IEnumerable`1 source)
   at NordVpn.Shared.CollectionExtensions.RemoveAll[T](ICollection`1 source, Func`2 predicate)
   at AppSelectViewModel.PopulateProcessesInChunks(CancellationToken cancellationToken)
```

`EnumerableHelpers.ToArray` reads `.Count`, allocates, then `CopyTo`. The collection grew
in between → concurrent mutation of the collection `PopulateProcessesInChunks` is filling
by chunks. Their race, their code. 308 processes on this box makes it near-deterministic:
**3 attempts, 3 failures** (11:30:40, 11:48:58, and the log-errors file counts one on
2026-09-21 too — i.e. every single time the dialog has ever been opened here).

## A hypothesis that was tested and FALSIFIED — do not revisit it

"Claude's WSL→Windows interop churn (a `powershell.exe` per Bash call) trips the race."
**False.** The 11:48:58 failure landed inside a 17-minute window (11:32:49 → 11:50:12) in
which this session ran no command at all. Process churn from WSL is not the trigger.

Also falsified earlier the same session: "PowerShell/cmd are hijacked into WSL". No
`$PROFILE` file exists (4 paths for PS 5.1, pwsh 7, Documents, OneDrive — all absent),
`HKCU`/`HKLM` `Command Processor\AutoRun` both empty, and `powershell.exe -Command`
without `-NoProfile` returns `Windows_NT`. The WSL start lives only in the Windows
Terminal `defaultProfile`, which is the documented design (`desk-w11-wsl.md:74`).

## Tailscale: checked, NOT implicated

Asked for explicitly, checked read-only, nothing touched.

```
NordLynx  NordLynx Tunnel   Disconnected
Tailscale Tailscale Tunnel  Up
```

Zero occurrences of `tailscale` across all four NordVPN logs for 2026-09-22. The failure
is a .NET `ArgumentException` in a UI ViewModel plus a DWM cloak state — no network path
is involved. **Caveat for later:** NordVPN and Tailscale are two WFP/route-owning VPNs,
so a real conflict is plausible *once split tunneling actually runs*. That is a separate
question from this bug and unproven either way.

## Repro

1. AkuWM running, NordVPN 8.11.1.0 open, many processes alive (308 here).
2. Settings → Split tunneling → Add apps.
3. Modal opens; AkuWM logs `placing 1 window(s) ...: NordVPN`; app log logs
   `Failed to load processes for app selection`.

## Fix options (none applied — see below)

- **Unblock now, one line:** add a `{"process": "NordVPN"}` → `["ignore"]` rule to
  `common.json`, next to the ShareX/zebar ones. Takes NordVPN out of tiling entirely.
  Cheap, and consistent with how every other misbehaving app here was handled.
- **Real fix:** AkuWM should not tile owned modal/dialog HWNDs at all — an owner-window
  check (`GetWindow(hwnd, GW_OWNER) != 0`) or `WS_EX_DLGMODALFRAME` would catch this class
  of window generically, instead of one rule per app that ever ships a modal.
- **Defect B has no fix on our side.** Workaround is the modal's **"Browse apps"** button,
  which opens a file picker and bypasses the process enumeration completely. Diego has not
  confirmed it works yet — it needs Defect A resolved first to be clickable.

## NOT applied on purpose

`common.json` is AkuWM's config and AkuWM is being developed in a **parallel session on
this same repo**. That session has already swept an unrelated in-progress edit of mine
into one of its `git add -A` commits today (`c5481c4e`). Editing its config file from here
would risk the same collision in reverse, so the rule above is written down, not applied.

## Blocked downstream

Diego's actual goal — split-tunnel the Purple/Aion 2 installer and then its installed
binary — is blocked on more than this: **Purple is not installed**. No `Purple`, `NCSOFT`
or `Aion` entry in any of the three uninstall registry hives; only the installers sit in
`C:\Users\diego\Downloads\` (`PURPLE_Installer_26_9_2_1.exe`,
`PurpleInstaller_2_26_223_12.exe`). There is no installed binary to add yet.

Also note: the Split tunneling master toggle was `Off` in the last screenshot. Apps added
while it is off change nothing.

## Environment

- AkuWM PID 28996, started 11:45:28, `C:\Users\diego\AppData\Local\Programs\AkuWM\akuwm.exe`
- Logs: `C:\Users\diego\AppData\Local\AkuWM\logs\akuwm.log`, `session.json` beside it
- NordVPN logs: `C:\Users\diego\AppData\Local\NordVPN\logs\app-*-2026092{1,2}.log`
- Config read: `templates/windows/DESK_W11/akuwm/common.json` (21 rules, `rules[]`)
- Plan: `docs/akunito/infrastructure/desk-w11-akuwm-plan.md`
