---
id: infrastructure.nodes.desk-w11
summary: DESK_W11 runbook — Windows 11 dual boot on the DESK box with NixOS-WSL; what lives on the Windows side, what lives in WSL, and the exact bootstrap order
tags: [windows, wsl, nixos-wsl, desk, claude-sync, autohotkey]
related_files: [profiles/DESK_W11-config.nix, profiles/wsl/**, templates/windows/DESK_W11/**]
date: 2026-09-13
status: published
---

# DESK_W11 — Windows 11 + NixOS-WSL on the DESK box

DESK and DESK_W11 are the same computer, never on at the same time. Windows is
there for games (Aion 2, Lineage 2). Everything else you do on DESK should feel
the same from Windows: same shell, same Claude memory and sessions, same NAS,
same shortcuts. Decisions below come from the 2026-09-13 interview.

## Who owns what

| Concern | Windows | WSL (NixOS, profile `DESK_W11`) |
|---|---|---|
| Desktop, virtual desktops, shortcuts | AutoHotkey v2 + VirtualDesktopAccessor, Hyper = Ctrl+Alt+Win | – |
| Terminal | Windows Terminal → `wsl -d NixOS` | zsh, starship, atuin, tmux + resurrect, ranger |
| Browser | Zen (winget) + Zen Sync; Vivaldi | `wslview` opens links in Zen |
| Tailscale | Windows client, node **DESK_W11** in Headscale | rides the Windows tunnel (`.wslconfig` mirrored + dnsTunneling) |
| Nextcloud | Nextcloud Desktop → `C:\Users\<you>\Nextcloud` | bind-mounted at `~/Nextcloud` (Journal memory key matches DESK) |
| NAS | `\\wsl$\NixOS\mnt\NFS_*` in Explorer | NFS 4.2 automounts `/mnt/NFS_media`, `NFS_Backups`, `NFS_downloads` like DESK |
| NTFS data drives (DATA, DATA_SATA3) | native drive letters | `/mnt/d`, `/mnt/e` via WSL automount |
| SSH to VPS / NAS / pfSense / X13 | – | `~/.ssh/config` managed (`sshHostsManaged`), gpg-agent as ssh agent, **pinentry-qt as a WSLg window** (`gpgPinentryWslg`) |
| Git, git-crypt, dotfiles | VS Code (Remote-WSL) | the repo, `install.sh DESK_W11 -s -h -d` |
| Claude Code | native install: bootstrap + elevated (admin) tasks only | the real one, from tmux: `claude` wrapper, claude-sync identity `DESK_W11`, `ENV_PROFILE=DESK_W11`; drives Windows through interop (`pwsh.exe`, `winget.exe`) |
| Docker | – | native `virtualisation.docker` (rootful), no Docker Desktop |
| Local LLM | none (VRAM stays for games) | none |
| Bitwarden, Obsidian, Telegram, Element, Spotify, DBeaver | winget | – |

Not replicated on purpose: Sway/waybar, gamescope/Steam-on-Linux, Sunshine,
Ollama/llama.cpp, printing, Bluetooth tooling, the harmonia cache server.

## Terminal and Claude workflow (decided 2026-09-13)

One terminal: **Windows Terminal**, default profile `NixOS` (WSL), tmux inside
it with resurrect, exactly like DESK. Claude Code runs **in WSL only**: that is
where `ENV_PROFILE=DESK_W11`, the `claude` wrapper, claude-sync and the DESK
paths (`/home/akunito/.dotfiles`, `~/Nextcloud`) live, so memory and sessions
are the same ones DESK sees. From that tmux you also drive Windows: WSL interop
puts `pwsh.exe`, `winget.exe`, `explorer.exe`, `reg.exe` on the PATH, so Claude
in WSL runs `pwsh.exe -c "winget install --id X"` without leaving the session.

Native Claude Code in PowerShell exists for **one** case: the bootstrap, before
WSL exists. Elevation is not a second case — interop can raise a UAC prompt, so
admin work is driveable from the WSL session too (measured 2026-09-14: the
elevated child reported `IsInRole(Administrator) = True`):

```bash
powershell.exe -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-File','C:\path\to\script.ps1'"
```

You still accept the UAC dialog by hand, and the elevated child is a separate
process, so have it write its output to a file and read that back — its stdout
does not return to WSL. Note `Out-File` writes **UTF-16LE with a BOM**; decode it
(or use `Set-Content -Encoding utf8`) or string comparisons on the result silently
fail. No kitty via WSLg: it would only add a slower forwarded window.

### Default tab = NixOS at ~/.dotfiles, PowerShell if WSL is down (2026-09-15)

The default Windows Terminal profile is **`NixOS ~/.dotfiles`**, not the WSL-generated
`NixOS` entry. It runs `templates/windows/DESK_W11/wsl-or-pwsh.ps1` (from the Windows
clone, `%USERPROFILE%\.dotfiles`) through `pwsh -NoProfile -File`: the script probes
the distro (`wsl -d NixOS -e /bin/sh -c true`, 45 s timeout), then execs
`wsl -d NixOS --cd /home/akunito/.dotfiles`, and the tab closes when zsh exits. If the
probe fails (WSL service missing, distro unregistered, VM hung) it prints wsl.exe's
own message plus `wsl --status / wsl -l -v / wsl --shutdown` and drops into a normal
interactive `pwsh` in the same tab instead of a dead "process exited" tab.
`-Test` prints the decision without starting a shell (`-Distro Nope -Test` and
`-Timeout 0 -Test` exercise the two failure paths). Not in `$PROFILE` on purpose:
every `pwsh -Command` interop call from WSL would otherwise re-enter WSL.

### Windows Terminal keys = tmux keys (2026-09-15)

`windows-terminal.settings.json` carries `actions` + `keybindings` so the tmux
root-table chords work in every Windows Terminal tab (PowerShell included).
Diego presses them from the Keychron key that sends Ctrl+Alt, so AltGr on the
en-GB layout never gets involved:

| Keys | tmux | Windows Terminal |
|------|------|------------------|
| Ctrl+Alt+Q / W | previous / next window | `prevTab` / `nextTab` |
| Ctrl+Alt+E | split -h | `splitPane right`, `splitMode: duplicate` (same profile + cwd) |
| Ctrl+Alt+R | split -v | `splitPane down`, duplicate |
| Ctrl+Alt+T | new-window | `newTab` |
| Ctrl+Alt+X | kill-pane | `closePane` |
| Ctrl+Alt+Y / Z | rename / kill window | `openTabRenamer` / `closeTab` |
| Ctrl+Alt+D / S | scroll up / down | `scrollUpPage` / `scrollDownPage` |
| Ctrl+Alt+[ / ] | copy-mode / paste | `markMode` (keyboard selection) / `paste` |
| Ctrl+Alt+P | copycat search | `find` |
| Ctrl+Alt+J K L ; | pane left/down/up/right | `moveFocus` left/down/up/right |
| Ctrl+Alt+F / G | pane left / up | `moveFocus` previousInOrder / nextInOrder (cycles through the panes, wraps) |

Keybindings are global in Windows Terminal (no per-profile keys), so in a WSL
tab these now reach the terminal, not tmux: tmux gets them only through its
prefix. Not mapped on purpose: Ctrl+Alt+A is tmux's root-table ssh-smart (host
picker from `~/.ssh/config`) and, since Windows Terminal does not bind it, it still
reaches tmux in a WSL tab; H has no root chord (the tmux menu is prefix+h) and Windows
Terminal's own palette is Ctrl+Shift+P.

### Claude Code in PowerShell: fullscreen + copying text

The native `claude.exe` (`C:\Users\diego\.local\bin`, own `C:\Users\diego\.claude`,
not synced by claude-sync) has `"tui": "fullscreen"` in its settings.json
(alternate screen buffer, like `/tui fullscreen`). Copying a response from the
terminal breaks on the rendered line wraps, so:

- `/copy` (or `/copy 2`) copies the last response, or one code block from the
  picker, without the wraps.
- Ctrl+O opens the transcript (fullscreen only); `v` there opens it in
  `$VISUAL`. `VISUAL`/`EDITOR` are set in **Claude's own settings.json `env`
  block** (`C:\PROGRA~1\Notepad++\notepad++.exe -multiInst -nosession`, 8.3 path
  so no quoting), which a new `claude` picks up without restarting the shell;
  the user env var `VISUAL` holds the same value for everything else. Ctrl+G
  edits the prompt in the same editor.
- **Ctrl+Alt+C** (AHK, only while Windows Terminal is active) types `/copy`,
  waits for the clipboard and opens the answer in a fresh Notepad++ instance
  (`%TEMP%\claude-last-response.md`). Input box must be empty; in fullscreen
  the picker may ask which block, the macro waits up to 20 s.
- **Shift+Enter** = newline: Windows Terminal keybinding `sendInput "\u001b\r"`
  (the same ESC+CR `/terminal-setup` installs for VS Code). Side effect at a
  PowerShell prompt: PSReadLine reads ESC as RevertLine, so Shift+Enter there
  clears the line instead of adding one.

## Files in the repo

- `profiles/DESK_W11-config.nix` — flag sheet (hostname `nixosw11aku`, `envProfile = "DESK_W11"`, `wslWindowsUser`)
- `profiles/wsl/configuration.nix`, `profiles/wsl/home.nix` — the module set (`profile = "wsl"`)
- `flake.nix` — input `nixos-wsl` (pinned rev) + `DESK_W11` entry
- `templates/windows/DESK_W11/` — `bootstrap.ps1`, `debloat.ps1`, `winget-packages.json`, `.wslconfig`, `hyper-desktops.ahk`, `windows-terminal.settings.json`
- Keys: `~/Nextcloud/backups/w11-bootstrap/w11-keys.tar.gpg` (W11 ssh key + claude-sync key, symmetric gpg). The public halves are already in every `authorizedKeys` list (VPS, NAS, DESK, X13) and in `claudeSyncHubKeys`.

## Windows software (declarative: `winget import`)

`templates/windows/DESK_W11/winget-packages.json` is the whole list; `bootstrap.ps1`
imports it, and re-running skips what is installed. winget ships with Windows 11
and is the native package manager (Chocolatey adds nothing here). DESK → W11:

| DESK | W11 (winget id) | Notes |
|---|---|---|
| kitty/alacritty, zsh, tmux | Microsoft.WindowsTerminal → WSL | shell lives in WSL |
| vscode, git, git-crypt, uv, dbeaver | Microsoft.VisualStudioCode (+ WSL extension), Git.Git, dbeaver.dbeaver | git-crypt/uv in WSL |
| rofi, sway shortcuts | AutoHotkey.AutoHotkey + Microsoft.PowerToys (Run) | `hyper-desktops.ahk` |
| waybar | RamenSoftware.Windhawk | see "Taskbar" below |
| grim/slurp/swappy | ShareX.ShareX | Hyper+Shift+C is bound in `hyper-desktops.ahk` (runs `ShareX -workflow "Hyper+Shift+C"`): region → editor → save → `sharex-wsl-path.ps1` puts the `/mnt/c/...` path on the clipboard for Claude in WSL. Pasting the image itself into Claude Code is **Alt+V** under WSL. **Claude in Chrome from WSL works** (verified 2026-09-15): `claude --chrome` in the distro attaches the browser MCP, and the Windows Brave extension reaches it through Anthropic's cloud bridge (`isLocal:false`), so no native-messaging host is needed. `/chrome` still prints "not supported in WSL" and "Extension: Not detected" — both cosmetic (it only scans Linux profile dirs). Pick the browser with `list_connected_browsers` → `select_browser`. |
| fd/fzf for files | voidtools.Everything | |
| Nerd font | DEVCOM.JetBrainsMonoNerdFont | |
| tailscale + trayscale | Tailscale.Tailscale | node DESK_W11 |
| nextcloud-client | Nextcloud.NextcloudDesktop | |
| bitwarden | Bitwarden.Bitwarden | |
| zen, vivaldi, brave/chromium | Zen-Team.Zen-Browser, Vivaldi.Vivaldi, Brave.Brave | |
| obsidian, telegram, element, vesktop, teams-for-linux, thunderbird, libreoffice, calibre | Obsidian.Obsidian, Telegram.TelegramDesktop, Element.Element, Discord.Discord, Microsoft.Teams, Mozilla.Thunderbird, TheDocumentFoundation.LibreOffice, calibre.calibre | Teams stays installed (interviews); `debloat.ps1` no longer removes it |
| spotify, vlc, qbittorrent, OBS (media recording) | Spotify.Spotify, VideoLAN.VLC, qBittorrent.qBittorrent, OBSProject.OBSStudio | |
| steam, GOG (Heroic), FreesmLauncher + Java 21 | Valve.Steam, GOG.Galaxy, PrismLauncher.PrismLauncher + EclipseAdoptium.Temurin.21.JRE | AkuCraft: new instance + AutoModpack, never copy jars (see memory) |
| sunshine, moonlight | LizardByte.Sunshine, MoonlightGameStreamingProject.Moonlight | Sunshine host for DESK_A/X13 — **on demand only** (2026-09-15): `SunshineService` set to Manual and stopped; start it from the Start menu (Sunshine) or `Start-Service SunshineService` elevated; not paired with any client yet |
| easyeffects | — | Equalizer APO declined 2026-09-14 (manual install + per-device setup); revisit only if an EQ is actually missed |
| mission-center | Task Manager | |
| ollama / llama.cpp | none | decided: no LLM on W11 |
| AMD driver | AMD Adrenalin (manual) | winget id unreliable |
| Aion 2, Lineage2Dex | their launchers (manual) | |

Add a package: append `{ "PackageIdentifier": "..." }` (find ids with `winget search`),
commit, re-run `bootstrap.ps1`. Remove: `winget uninstall --id ...`.

## Taskbar and look (Windhawk)

Decision 2026-09-13, re-confirmed 2026-09-14 after weighing GlazeWM/komorebi: keep the
vanilla taskbar, restyle it with Windhawk mods (actively maintained, follow every W11
update; no tiling, no conflicts with games). Tiling WMs bring their own workspaces
(not Windows virtual desktops) and have no "sticky". **GlazeWM 3.10 runs here in floating-only mode (2026-09-15)**, solely for
per-monitor, independent workspaces (10-19 main, 20-29 vertical, Sway's swaysome
numbers); Windows virtual desktops are not used. The tiling attempt of 2026-09-14
was rolled back the same evening: every config reload re-evaluates window rules
and moved windows around, floating windows fought for z-order, Alt+drag on tiled
windows needed fragile tricks. Rules now: `initial_state: floating`, no
`move --workspace` rules, no keybindings (all in `hyper-desktops.ahk` via
`glazewm command`), config loaded through the `GLAZEWM_CONFIG_PATH` user env var
from the Windows clone, Startup shortcut `GlazeWM.lnk`, native focus-follows-mouse
OFF (`focus-follows-mouse.ps1 -Off`) because GlazeWM does it. Reload the config
only when the file changes (`glazewm command wm-reload-config`). No "sticky".
`focus_follows_cursor` is **off** (2026-09-15): with it on, UAC and system consent
prompts (e.g. the location dialog) could not be clicked. Click to focus, like stock
Windows. Alt+drag never moves a window across the DPI boundary live (150 % vs 125 %
made the app rescale and GlazeWM re-place it every tick); on release over the other
monitor the window is moved once through GlazeWM (`move --workspace` + `size`).
Alt+drag gestures (2026-09-15): a maximised window restores under the cursor and
keeps dragging; dropping with the cursor in the top 6 px of a monitor's work area
maximises there (the outline turns into the whole work area); crossing to the other
monitor shows the outline and jumps once on release (`tests/` has the measurements).
Robustness (2026-09-15 pm): the whole gesture runs under `try/catch TargetError`
(no AHK error dialog; `%TEMP%\altdrag.log` says "destroyed" or "still exists,
hidden"); windows under 200x80 (tooltips, Vivaldi's 237x39 tab preview) drag their
owner or are ignored; `DetectHiddenWindows` is on inside the gesture because a
window GlazeWM parks on a non-displayed workspace is DWM-cloaked and AutoHotkey
otherwise reports it as not found — that is what crashed a drag right after resume
from sleep with the main monitor still off (Discord got cloaked 5 ms after the
placement `WinMove`). The size storm (per-monitor-DPI apps on the vertical
monitor) is contained by a storm guard in the loop plus a 1.5 s watchdog.
Capture session 2026-09-15 (37 gestures, `%TEMP%\hyper-debug.on` trace) fixed:
the watchdog now runs on a timer (blocking in the hotkey thread made AutoHotkey
drop the next Alt+drag for up to 4.5 s: 4 presses lost in 35 s); size answers
under 8 % are adopted, not fought (Windows Terminal snaps 1 px to its cell grid
on every move, real storms are +19 % to +73 %); activation uses
`SetForegroundWindow` (0 ms) instead of `WinActivate` (110 ms even when already
active, and its fallback flashed the focus to the desktop); the restore rectangle
is fitted per side instead of forced to an 80 % box (that made the size drift
1668x2160 -> 3072x1694 -> 1382x2424 across maximise/restore on both monitors).
Second capture (29 gestures): every remaining storm (7/7) fired when the window's
edge entered the virtual gap between the monitors (x 3840..4608 in AutoHotkey's
space; Windows re-evaluates the window's DPI there), so live moves and resizes
now stop at the edge facing the other monitor (`edgeL`/`edgeR` from
`GetMonitorInfo`; crossing is the outline + one jump). Activation falls back to
`AttachThreadInput` + `SetForegroundWindow` (0 ms) when another app has the
foreground. Third capture (21 gestures): no storms, no dropped presses, every
final size as expected, 13 edge clamps. Left as is: restoring from maximised
costs ~280 ms (the app's own restore time).
Debug trace: `%TEMP%\hyper-debug.on` present -> gestures, GlazeWM command
timings and window events (focus, state, size outside gestures, cloak) go to
`%TEMP%\altdrag.log`; power and display changes are logged always.
Hyper+Tab / Win+Tab = AHK list of every window in every workspace (Task View stand-in;
Ctrl+Win+D and Ctrl+Win+arrows are swallowed so no native desktop can be created).

**Zebar** (installed with GlazeWM) draws the workspaces pill at the top-left of each
monitor, over the empty end of the Windows taskbar: pack
`templates/windows/DESK_W11/zebar/akuwm/` (zpack.json + workspaces.html, vanilla JS,
`createProvider({ type: 'glazewm' })`, one widget per monitor, `top_most`), copied to
`%USERPROFILE%\.glzr\zebar\akuwm\` and selected in `.glzr\zebar\settings.json`;
Startup shortcut `Zebar.lnk`. Never run Zebar's starter "vanilla" widget: its weather
block triggers the Windows location consent prompt.
GlazeWM only manages windows on the *current native* virtual desktop: if windows end
up on other native desktops (Win+Tab → "New desktop", or leftovers from the old AHK),
focusing one of them jumps Windows to that desktop and the GlazeWM workspaces
"vanish". Fix: run `vd-merge.ahk` (merges every native desktop into the first one),
then restart GlazeWM. Never create native desktops while GlazeWM is in use.
Windhawk has no CLI for mods: open it once → Explore → install these, in order,
then set each mod's options:

| Mod | Setting (as applied 2026-09-14) |
|---|---|
| Taskbar on top (Windows 11) | on — the bar goes to the top like waybar |
| Taskbar height and icon size | height 28, icon 16 (button width 44) — slimmer than first planned |
| Taskbar clock customization | Windows date/time pictures, not strftime: `TimeFormat: HH':'mm`, `DateFormat: ddd dd MMM`, `ShowSeconds: 0`, `TopLine: '%time% \| %date%'`, `MiddleLine`/`BottomLine` empty, **`TextSpacing: -14`** (the block reserves two lines; at 28 px the top line is clipped until the spacing goes negative). `Width`/`Height` are Windows-10-only, ignored. Settings apply on save; the first save needed an explorer restart |
| Taskbar tray system icon tweaks | hide Copilot/News/Chat leftovers, keep network/volume |
| Windows 11 Taskbar Styler | theme `RosePine` |
| Taskbar labels for Windows 11 | labels on, combine never (workspace-like readability) — **not installed by choice** (2026-09-15), kept here for reference |
| Taskbar notification icon spacing | 24 px — not installed, reference |
| Taskbar button click | middle-click closes — not installed, reference |

Settings → Personalization → Taskbar: alignment **center** (apps in the middle,
metrics + clock on the right — 2026-09-14), Widgets off, Search hidden, Task view
**on** (Hyper+Tab). Dark mode, accent from wallpaper off.

**Animations off** (Start, tray flyouts and windows appear instantly, like Sway):
`pwsh -ExecutionPolicy Bypass -File templates\windows\DESK_W11\visual-effects-off.ps1`
— every SystemParametersInfo animation flag + taskbar/min-max animations, per user, no
admin, immediate; it is what the Accessibility → "Animation effects" toggle does plus
the ones that toggle misses. Re-run if a feature update turns them back on.

**Hyper shortcuts beyond Sway's** (all in `hyper-desktops.ahk`): Hyper+Space and the
**Win key tapped alone** open PowerToys Command Palette (the Start menu replacement;
PowerToys Run is disabled); Hyper+Shift+Return opens the power menu
(Lock/Logout/Reboot/Shutdown/Suspend); Hyper+Shift+C the ShareX region capture.
Windhawk mods survive updates; if one breaks after a Windows feature update,
Windhawk disables it and shows a badge — update the mod, done.

## Part A — Windows side (PowerShell as Administrator, with Claude Code if you like)

Before anything: **BIOS → disable "Fast Boot"** (UEFI skips device init; harmless
to turn off, saves surprises with USB keyboards at the LUKS prompt on the NixOS
side). The one that actually damages partitions is Windows' own Fast Startup,
handled by the script below (`powercfg /h off` + `HiberbootEnabled=0`).

1. Clone the repo (HTTPS is fine at this point, the W11 ssh key comes later):
   ```powershell
   winget install Git.Git
   git clone https://github.com/akunito/my_nixos.git $env:USERPROFILE\.dotfiles
   cd $env:USERPROFILE\.dotfiles\templates\windows\DESK_W11
   Set-ExecutionPolicy -Scope Process Bypass -Force
   ```
2. `.\bootstrap.ps1` — Fast Startup off, RTC in UTC, high-performance plan,
   `winget import` of the whole software list, native Claude Code, WSL platform,
   `.wslconfig`, AutoHotkey Startup shortcut (UI-Access binary).
3. `.\debloat.ps1` — Copilot/Recall/Windows AI off, telemetry/ads/Spotlight/widgets
   off, Delivery Optimization P2P off, ten safe services disabled, store bloat and
   OneDrive removed, Edge background off, Game Mode on. Nothing touches Defender,
   Update, Xbox services, audio, Bluetooth or printing. Reboot.
   Run 2026-09-14 (it had been skipped on W11 day). Takes ~40 min: the provisioned-
   package check calls DISM once per app. `Remove-AppxPackage -AllUsers` is denied for
   Teams/Clipchamp/Outlook and friends — finish with a plain per-user
   `Remove-AppxPackage`, `winget uninstall Microsoft.OneDrive` (per-user install) and
   delete the `OneDrive` + `MicrosoftEdgeAutoLaunch_*` values in `HKCU\...\Run`.
   **After every Windows feature update** re-run `debloat.ps1` and `ai-off.ps1`: they
   are idempotent, and updates bring back Teams/Outlook/Clipchamp/OneDrive and the
   Copilot policies. Phone Link is kept (Pixel 9a).
4. Windhawk: install the mods from the "Taskbar and look" table.
5. Download `VirtualDesktopAccessor.dll` from
   https://github.com/Ciantic/VirtualDesktopAccessor/releases into the same
   folder as `hyper-desktops.ahk`, then double-click the Startup shortcut once.
   Test: Hyper+2 creates and jumps to desktop 2, Hyper+Shift+1 moves the window back,
   Alt+drag moves, Alt+right-drag resizes. Hyper+Shift+Escape suspends everything for games.
6. Tailscale. The GUI "Log in" button does nothing useful against a custom
   coordination server, and a bare `tailscale up` hangs for 60 s and prints
   nothing. Do it from an elevated PowerShell with a preauth key instead:
   ```powershell
   # on the VPS: sudo headscale users create DESK_W11
   #             sudo headscale preauthkeys create -u <user-id> --reusable -e 24h
   & "C:\Program Files\Tailscale\tailscale.exe" up --reset `
       --login-server=https://<headscaleDomain> --authkey=<hskey-auth-...> `
       --hostname=desk-w11 --accept-routes --timeout=60s
   ```
   - **`--hostname` must be `desk-w11`, not `DESK_W11`**: an underscore is not a
     valid DNS label and Tailscale rejects it outright.
   - **`--reset` is not optional.** Without it a second attempt fails with
     *"changing settings via 'tailscale up' requires mentioning all non-default
     flags"*, and earlier half-applied prefs make it hang instead of erroring.
   - There is no log file under `C:\ProgramData\Tailscale` and nothing in the
     event log. To see what the daemon is actually doing, run
     `tailscale debug watch-ipn` in parallel: it prints the state transitions
     (`2` NeedsLogin → `LoginFinished` → `5` Starting → `6` Running).
   - **`tailscale-ipn.exe` (the tray GUI) must be running.** Windows ties the IPN
     state to the user session through the frontend; with the GUI closed the
     backend falls back to `NoState` and `tailscale status` reports
     *"Tailscale is starting"* forever, even after the node registered fine.
   Then add the node to `group:family` on Headscale, or it sees no peers at all
   (`tailscale ping` answers `no matching peer`):
   ```bash
   sudo headscale policy get > /tmp/p.json     # edit: add "DESK_W11@" to group:family
   sudo headscale policy set -f /tmp/p.json
   ```
   The policy lives in the database (`policy.mode = "database"`, see
   `system/app/headscale.nix`), **not** in the repo — there is nothing to deploy.
7. Nextcloud Desktop: server `https://nextcloud.local.akunito.com` (the public host
   is behind Cloudflare Access, native clients cannot pass it), local folder
   `C:\Users\<you>\Nextcloud`, sync everything you use on DESK (`myLibrary`,
   `git_repos`, `backups` at least).
8. Zen: sign in to Zen Sync with the account DESK uses. Then two things the
   account does NOT carry:
   - **Spaces** sync only exists from Zen **1.22.1b** (Sep 2026). Tabs, bookmarks
     and passwords sync on any version, so seeing DESK's tabs here proves
     nothing about Spaces — a machine on an older build never uploads them and
     the others have nothing to pull. Both sides need 1.22.1b+ and
     Settings → Sync → Spaces enabled.
   - **Sine and the web-panels mod** live in the profile's `chrome/` and in the
     app directory; they are never synced. Install them by hand:
     `docs/akunito/infrastructure/zen-web-panels-windows.md` (Sine installer as
     Administrator, then `scripts/zen-webpanels-install-windows.sh` from WSL).
9. Windows Terminal: paste `windows-terminal.settings.json` pieces into Settings →
   Open JSON file. The `NixOS` profile appears by itself once the distro exists.
10. Keyboard layouts: Settings → Time & language → Language → English (UK) with the
   **US-International** keyboard only (`0809:00020409`, as wanted — decided 2026-09-15; no
   Spanish/Polish layouts, dead keys cover them). Win+Space cycles if more are ever added.

## Part B — NixOS-WSL (PowerShell, then inside the distro)

1. Get `nixos.wsl` from https://github.com/nix-community/NixOS-WSL/releases/latest, then:
   ```powershell
   wsl --install --from-file .\nixos.wsl      # WSL >= 2.4.4; older: wsl --import NixOS $env:USERPROFILE\NixOS nixos.wsl --version 2
   wsl -s NixOS
   wsl -d NixOS
   ```
   You land as user `nixos`. Do NOT run `nix-channel --update`; the flake replaces channels.
2. Inside the stock distro, bootstrap the repo and the keys:
   ```bash
   sudo nix run nixpkgs#git -- clone https://github.com/akunito/my_nixos.git /tmp/dotfiles   # temporary, as nixos
   ```
   Nothing more here: the first `install.sh` switches the default user to `akunito`,
   and everything under `/home/nixos` is throwaway.
3. First switch (still as `nixos`, sudo is passwordless in the stock image):
   ```bash
   cd /tmp/dotfiles && git checkout main
   sudo nixos-rebuild switch --flake .#DESK_W11 --impure   # ONLY this once, to create user akunito; install.sh is the rule afterwards
   ```
   Why the exception: `install.sh` needs the `akunito` user, `git-crypt` and the
   secrets, none of which exist yet. This first switch fails if `secrets/domains.nix`
   is still encrypted — see step 4 first, then run it.
4. Decrypt secrets before the first switch. From Windows, the encrypted key bundle
   is already in `C:\Users\<you>\Nextcloud\backups\w11-bootstrap\` (Nextcloud synced it):
   ```bash
   mkdir -p ~/w11 && cd ~/w11
   cp /mnt/c/Users/<you>/Nextcloud/backups/w11-bootstrap/w11-keys.tar.gpg .
   gpg --decrypt w11-keys.tar.gpg > w11-keys.tar && tar xf w11-keys.tar   # passphrase: Bitwarden → "w11-bootstrap"
   # git-crypt key: encrypt it on DESK once (see "Before W11 day") into the same folder
   gpg --decrypt /mnt/c/Users/<you>/Nextcloud/backups/w11-bootstrap/dotfiles-key.gpg > dotfiles-key
   cd /tmp/dotfiles && nix run nixpkgs#git-crypt -- unlock ~/w11/dotfiles-key
   ```
5. Now step 3. Then `wsl --shutdown` from PowerShell (the default-user change needs a restart), `wsl -d NixOS` → you are `akunito`.
6. Move things into place as `akunito`:
   ```bash
   sudo mv /tmp/dotfiles ~/.dotfiles && sudo chown -R akunito:users ~/.dotfiles
   mkdir -p ~/.ssh ~/.git-crypt ~/.config/claude-sync && chmod 700 ~/.ssh ~/.git-crypt ~/.config/claude-sync
   cp /home/nixos/w11/id_ed25519* ~/.ssh/ && chmod 600 ~/.ssh/id_ed25519
   cp /home/nixos/w11/claude-sync-key ~/.config/claude-sync/key && cp /home/nixos/w11/claude-sync-key.pub ~/.config/claude-sync/key.pub && chmod 600 ~/.config/claude-sync/key
   cp /home/nixos/w11/dotfiles-key ~/.git-crypt/dotfiles-key && chmod 600 ~/.git-crypt/dotfiles-key
   cd ~/.dotfiles && git-crypt unlock ~/.git-crypt/dotfiles-key
   git remote set-url origin git@github.com:akunito/my_nixos.git
   sudo rm -rf /home/nixos/w11
   ```
   Add `~/.ssh/id_ed25519.pub` to GitHub (Settings → SSH keys) — the only key
   registration that is not declarative.
7. Set `wslWindowsUser` in `profiles/DESK_W11-config.nix` to your Windows account
   name, commit, push (`install.sh` resets to `origin/main`). Then the real deploy:
   ```bash
   ./install.sh ~/.dotfiles DESK_W11 -s -h -d
   ```
   `-h` always: NixOS-WSL supplies the hardware config; regenerating one would
   break the build. `-d`: docker runs inside WSL, never stop it.
8. Verify:
   ```bash
   echo $ENV_PROFILE                      # DESK_W11
   ls ~/Nextcloud                         # the Windows folder, bind-mounted
   ls /mnt/NFS_media | head               # NAS over NFS (NAS awake 16:00–23:00)
   ssh vps hostname                       # vps-prod through the Windows Tailscale tunnel
   claude login && claude-sync status     # reachable: yes
   claude -c                              # continues the last DESK session, forked
   ```
9. VS Code on Windows: the **WSL** extension (`ms-vscode-remote.remote-wsl`) — installed
   2026-09-16; the first `code` from the distro downloaded the VS Code Server into
   `~/.vscode-server`. `code` on the WSL PATH is the Windows binary's shim
   (`/mnt/c/Users/diego/AppData/Local/Programs/Microsoft VS Code/bin/code`), so from
   zsh — and from Claude Code in WSL — `code .`, `code <file>` or `code -g <file>:<line>`
   open the Linux path in the Windows VS Code window connected to NixOS ("WSL: NixOS" in
   the status bar); `-r` reuses the current window. That is the way to show Diego a file
   or a diff here (no GUI editor inside WSL).

## Before W11 day (on DESK, once)

- Encrypt the git-crypt key into the same Nextcloud folder as the ssh bundle
  (Claude cannot touch `~/.git-crypt`, do it yourself):
  ```bash
  gpg --symmetric --cipher-algo AES256 -o ~/Nextcloud/backups/w11-bootstrap/dotfiles-key.gpg ~/.git-crypt/dotfiles-key
  ```
  Use the same passphrase as `w11-keys.tar.gpg` (stored in Bitwarden as `w11-bootstrap`).
- NAS: the W11 ssh public key is in `profiles/NAS_PROD-config.nix`; it lands on the
  NAS at its next `install.sh`. Same for DESK and X13. The VPS was deployed on 2026-09-13.
- Delete the bundle from Nextcloud after W11 is bootstrapped.

## Backups of the Windows side (restic → NAS)

The same `home_backup` timer as DESK/X13 (17:00 and 21:00) runs
`backup-manager.sh --auto --target nfs --job windows` from WSL into
`/mnt/NFS_Backups/nixosw11aku/windows.restic`. It first exports what only lives in
the registry into `C:\Users\<user>\AppData\Local\w11-backup\` (`windhawk.reg` = mods +
their settings, `explorer-advanced.reg` = taskbar prefs, `winget-installed.json`), then
snapshots Windows Terminal, ShareX, PowerToys, Command Palette, Zen profiles, Vivaldi
`User Data`, Telegram `tdata`, Obsidian, DBeaver, `ProgramData\Windhawk` and Steam
`userdata` (caches excluded; ~1.8 GB, 21 s over the tailnet). Browsers hold LOCK,
Cookies and Sessions open, so restic exits 3 ("some files unreadable") — the job treats
that as a warning; run it with the browsers closed for a complete snapshot.
Needs `~/myScripts/restic.key` in WSL (same key as the other workstations).

Restore on a fresh W11: `bootstrap.ps1` (winget import), `reg import windhawk.reg` +
`explorer-advanced.reg` (elevated), then `restic restore latest --target /` from WSL for
the AppData/Documents paths. Status: `backup-manager.sh --status` or
`systemctl status home_backup`.

## Windows Update policy (AINF-396, applied 2026-09-15)

`windows-update-policy.ps1` (elevated) — Pro group policies under
`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate`: release pinned to **25H2**
(`TargetReleaseVersionInfo`; quality updates for it keep coming), feature updates
deferred 365 days, quality updates deferred 7 days (a broken cumulative is usually
pulled within days), no preview builds, no drivers from WU (AMD/Realtek installers
instead), active hours 08-23 and no automatic reboot with a user logged on. To move to
a new release: raise `TargetReleaseVersionInfo`, wait for the update, then re-run
`debloat.ps1` + `ai-off.ps1` and check Windhawk mods.

## Steam library shared with NixOS

`D:\SteamLibrary` is `/mnt/DATA` on NixOS (ntfs3, `uid=1000`): BG3, AoE2 DE, Proton 10,
plus their `compatdata`/`shadercache`. Windows Steam lists the folder too, so both
clients see the same installs — Proton titles use the Windows depots, nothing to
sync. Rules: only Proton titles there (force Proton on Linux for games with a native
Linux build, or Windows re-downloads them); never switch OS mid-download; Windows
must never hibernate with the drive mounted (Fast Startup is off). Saves do not cross
over (Proton prefix vs `C:\Users`) unless Steam Cloud handles the title (AINF-392).
Steam Cloud has to be on in **both** clients: Steam → Settings → Cloud → *Enable Steam
Cloud*, then per game Library → Properties → General → *Keep games saves in the Steam
Cloud* (BG3, AoE2 DE, Skyrim SE and Starfield all support it). Test: save on one OS,
quit the game and wait for the library cloud icon to settle before rebooting, load on
the other OS. Steam maps the Windows save path into the Proton prefix by itself.
Empty leftovers: `D:\Steam\SteamLibrary`, `C:\Games\steamapps`.

## Known limits

- **`RegisterHotKey` refuses Ctrl+Alt+Shift+Win+<letter>** (Windows keeps that modifier
  set for the "Office key"), so no app can own a Hyper+Shift+letter hotkey itself —
  ShareX logs *Unable to register hotkey*. Bind it in `hyper-desktops.ahk` (keyboard
  hook) and have AHK launch the app's workflow from the command line.
- Vivaldi was a Chocolatey install; `winget install Vivaldi.Vivaldi --scope user`
  adopted it in place (2026-09-14, profile kept). Chocolatey itself is still present
  with a handful of records; winget is the source of truth.

- WSL has no AMD GPU: no Vulkan/ROCm, hence no local LLM there.
- NFS from WSL uses the WSL2 kernel's client; `nfsvers=4.2` works, `soft` mounts
  keep Explorer from freezing when the NAS sleeps.
- Elevated windows and AutoHotkey: the script runs through `AutoHotkey64_UIA.exe`
  (UI Access), never "as administrator". Admin AHK breaks drag-and-drop into
  normal apps and cannot autostart from the Startup folder.
- `wsl --shutdown` after any change to `wsl.defaultUser` or `/etc/wsl.conf`.
- Docker inside WSL uses the WSL2 kernel; `dockerFirewallEnable` stays off there.
- **The Intel X520 10GbE is unusable under Windows.** Its two SFP+ ports are an
  802.3ad LAG on the USW Aggregation (ports 7+8, `lag_idx 1`), which is what the
  DESK NixOS bond talks to. A LAG member whose partner does not speak LACP never
  reaches forwarding state, so the adapter negotiates 10 Gbps and receives zero
  frames. Windows 11 Pro cannot speak LACP — verified, elevated:
  `New-NetLbfoTeam … -WhatIf` → *"LBFO is not supported on this SKU"*; Intel
  discontinued PROSet/ANS (teaming and VLAN) for Windows 11, X520 included; WSL2
  cannot take a PCIe NIC (Hyper-V vSwitch shares USB adapters only); and UniFi has
  no LACP fallback. **Windows therefore uses the Realtek, which links at 1 Gbps**
  (the USW-24-G2 has no 2.5G port). The fix, if ever wanted, costs DESK its 20 Gbps
  aggregate: free the dead Proxmox LAG (ports 3+4), give SFP+ 3 the `VLAN100` port
  profile and move one DAC there — DESK's LAG 1 is left untouched and keeps working
  on the single remaining link. Declined 2026-09-14 to preserve the aggregate.
- **WSL runs in NAT, not mirrored**, despite `networkingMode=mirrored` in
  `.wslconfig` (`ip route get` goes via the Hyper-V vSwitch at `172.17.16.1`). It
  still reaches the tailnet because it egresses through the Windows stack and
  inherits its routes.
- **NFS mounts the NAS at its tailnet address** (`100.64.0.1`), not
  `192.168.20.200`. Windows has no storage-VLAN interface, so the LAN address would
  be reached through the pfSense subnet router, which SNATs every client to
  `192.168.20.1` — authorising that would open the export to anything routing
  through pfSense. Going node-to-node keeps the real source (`100.64.0.15`).
- **Passphrase prompts are WSLg windows, never TTY prompts** (2026-09-16).
  `SSH_AUTH_SOCK` is gpg-agent's; the agent runs as a user service with no
  `DISPLAY`, and the ssh protocol carries no tty, so with `gpgPinentryCurses` the
  prompt for an `ssh` started by a non-TTY process (Claude Code's Bash tool, a
  deploy to the VPS/NAS) was drawn into `GPG_TTY` = the pane Claude Code was
  rendering: invisible, passphrase typed blind. Now `gpgPinentryWslg = true`
  wraps `pinentry-qt` with `DISPLAY=:0` / `WAYLAND_DISPLAY=wayland-0` pinned
  (`system/security/gpg.nix`), so the prompt is a window on the Windows desktop
  and the answer is cached for 400 days (`gpgCacheTtlSeconds` / `gpgMaxCacheTtlSeconds`
  = 34560000): one prompt per WSL boot, since the cache lives in the agent's memory
  and dies with `wsl --shutdown` or a Windows reboot. The same wrapper falls
  back to pinentry-curses when the WSLg X socket is missing. Sudo without a TTY
  goes the same way: `sudoAskpassEnable` (zenity via WSLg), and
  `sshAgentSudoEnable` signs with the now-unlockable agent key. claude-sync is
  unaffected — it uses its own key in `~/.config/claude-sync/key`.
  After a config change to the agent: `gpgconf --kill gpg-agent` (socket-activated,
  restarts on the next use).
