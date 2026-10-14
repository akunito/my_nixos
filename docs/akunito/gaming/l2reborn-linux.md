---
id: gaming.l2reborn-linux
summary: L2 Reborn (Interlude/Classic private server) on NixOS via umu/Proton — everything runs except the SmartGuard anti-cheat, which refuses to start under Wine (Code 1004); measurements, logs, staff statements, options
tags: [gaming, lineage2, l2reborn, proton, umu, wine, smartguard, anticheat]
related_files: [user/wm/sway/sway-apps/tests/live/README.md]
date: 2026-10-14
status: blocked  # by the server's anti-cheat, not by Linux
---

# L2 Reborn on NixOS/Linux — why it does not run (2026-10-14)

Measured on DESK (NixOS, RX 9070 XT, Sway/Wayland) with umu-launcher 1.4.4 + GE-Proton11-5, steamrt4 4.0.20261007. Everything below is what was actually observed, not forum lore. Memory: `project_l2reborn_linux_attempt.md` in the dotfiles memory; previous server-choice report in `docs/guides/l2/`.

## TL;DR

The whole Windows stack works under Proton: installer, Reborn Launcher (WPF + embedded WebView2), 22 GB client download, and `L2.exe` itself starts. The client then stops **before the login screen** with the guard dialog **"Could not start. Report this code to your server administrator. [Code 1004]"**. That is SmartGuard, the client-side anti-cheat every Reborn server ships, deciding that this environment is not allowed. Reborn staff answered **"No"** to "can we run Reborn on Linux" on 2026-10-11. It is a policy/vendor limit, not a Wine bug, and nothing in Wine, DXVK or Proton settings changes it.

## What was tested, in order

| Step | Command / action | Result |
|---|---|---|
| Installer integrity | `sha256sum setup.exe` = `159a9dd072ef1fbed32f2cc46d3e6cf436c8717feb1af25e2819ba3d92e41464`; `osslsigncode verify`; VirusTotal by hash | Authenticode EV signature valid (GlobalSign, subject LAB RIVAS SL, Torremolinos; timestamp 2026-03-05, inside the cert validity 2023-04-19 → 2026-04-19); VirusTotal 0/67; same 329 788 144-byte file that `https://l2reborn.org/installer` serves (301 → `/setup.exe`, last-modified 2026-03-05) |
| What the installer is | `exiftool`, `strings` | .NET 8 x86 single-file host wrapping **Velopack 0.0.1298** (Squirrel successor); payload `RebornLauncher` 1.2.12; declares prerequisites vcredist 140-144 x86/x64, WindowsDesktop runtime 8.0.15, WebView2 Evergreen |
| Install | `WINEPREFIX=~/Games/l2reborn/prefix GAMEID=umu-0 PROTONPATH=…/GE-Proton11-5-x86_64 umu-run setup.exe` | WPF setup dialog appears, installs to `C:\Games\RebornLauncher` (~220 MB), no prerequisite installer ran (none needed: the launcher is self-contained, WebView2 143.0.3650.66 is bundled under `current/runtimes/win-x86/native`) |
| Launcher | `~/Games/l2reborn/run-launcher.sh` | Starts, self-update check OK (`http://launcher.rebornalt.click/selfupdate`), loads games manifest `http://cdn.rebornalt.click/deploy/bootstrap-v3.json`, remote UI `http://launcher.reborncdn.net/ui/v3/` renders in WebView2. Logs: `C:\ProgramData\RebornLauncher\logs\launcher_*.log`, `C:\Games\RebornLauncher\velopack.log` |
| Client download (Eternal x10) | Launcher → Install → `C:\Games\Reborn\Eternal` | Manifest v33, 3683 files / 134 packages; 10 326 621 236 bytes downloaded, 23 260 055 447 extracted, 7366 files verified, **93 s** from `r2cdn.l2reborn.org`, 0 CDN switches. Log: `C:\ProgramData\RebornLauncher\logs\download_eternal-live_*.log` |
| Launcher quirk | — | The WebView UI stayed on "Verifying branch.ukx" after the backend logged "Download completed successfully"; restarting the launcher shows **Play**. The WPF→WebView2 completion message gets lost under Wine; harmless |
| Game start | `~/Games/l2reborn/run-game.sh` (runs `system-eu/L2.exe` directly; the launcher's run config for Eternal is `exe=system-eu/l2.exe, args=""`, so nothing is bypassed) | `L2.exe` starts, loads its DLLs, opens a 203×70 "Lineage II" window, then shows **Code 1004** and waits for OK. Process stays alive; no crash |
| Wine side | `PROTON_LOG=1` → `~/Games/l2reborn/steam-0.log` (554 KB) | Only noise: `err:openxr`, `err:hid … Failed to get parent device`, `err:ntoskrnl … winebth` (Bluetooth driver), `err:system:NtUserChangeDisplaySettings`. No unhandled exception from the client, no DXVK/D3D error, no missing DLL |

Client facts from the download manifest (file names only): it is the **modern Classic client** (protocol 110, `system-eu/`: `D3DDrv.dll`, `D3DX9_40.dll` → Direct3D 9, `Awesomium.dll`, `L2CefSubProcess.exe`, `discord_game_sdk.dll`, `Maps/*_Classic.unr`, Kamael/Ertheia animation packs). The guard lives in `system-eu/SmartGuard.ini` and `system-eu/SmartGuard/Plugins/{client.dll, SafeAuth.dll, SafeAuth.dat}`. The old d3d8/DXVK-d8vk tweaks for Interlude clients do not apply.

## Why it stops: the anti-cheat, with sources

- **Every Reborn server ships SmartGuard**, in Reborn's own private branch: each server-features page on l2reborn.org says *"Anti Cheat: Smartguard, where we have our own private branch with plenty of custom improvements done for an absolute bot-free server"*. The vendor (smart-guard.eu) lists supported clients as Windows 7 → 11 only, advertises HWID-spoof and emulated-keystroke detection, and says nothing about Linux or Wine.
- **Code 1004** is the guard's refusal at startup, before any network login. Searching the Reborn Discord for "1004" finds nothing relevant, so it is not a documented user-side error; it is "report to the server administrator".
- **Reborn staff position** (Discord "Reborn - Home of Lineage", read 2026-10-14):
  - #general-chat 2026-10-11 19:53, Klaboor: *"Is there a chance to run reborn on linux? I don't have Windows machine. I could probably run KVM, but these options are very last."* → 19:55 **Seriel [RBRN], Reborn Staff: "No"**.
  - #legacy-chat 2026-10-11 16:19–16:27: portwine asks for Mac/Linux support in the upcoming multiplatform Unity client, noting *"you've banned playing via virtual machines"*; BASS1st [RBRN] replies *"I'm Linux"* (user, not a policy); Arthur: *"if they keep using the same anti-cheat provider I don't think changing the client will change mac/linux compatibility"*.
  - #guardian-chat 2026-10-07, Eirial [RBRN] (staff): *"if the day linux takes over ever arrives i sell computer"*.
- **Community measurements matching ours:** Vanitasss (Reborn Star) 2026-08-29: *"client itself works with proton layer afaik, its smartguard that is not compatible"*; 2026-02-19: *"Installer works and installs game on cachyos proton slr runner, but that is as far as you gonna go"*. Silent_36 2026-03-17: launcher yes, no client under Proton, "due to the anti-cheat". Mesok 2026-03-06: *"proton seems not allowed"*. freeVMs 2026-03-03: Windows natively only, no VM, no Wine. Ghast, forum thread "L2 Reborn on Mac" 2026-08-07: same for macOS. neiz 2026-10-05: *"not until smartguard supports linux"*.
- **Outside Reborn:** Steam Deck thread (steamcommunity.com/app/1675200/discussions/0/3269060963456261569/): *"on steam deck you can play any L2 server where there is no any anti-cheat … Asterios / Reborn / Scryde / Battleclub — unfortunately, you can't play"*. github.com/achrafsoltani/lineage2-linux lists L2Reborn under "Avoid on Linux: SmartGuard — still blocked".
- **Rules:** the global rules (2026-02-27) forbid automation and dualbox; they do not mention Wine or VMs — the VM ban is enforced by the guard and stated by staff in chat, not in the rules text.

What this means technically: a client-side guard that checks it is running on a real Windows kernel (and, per staff, rejects VMs) cannot be satisfied by Wine, which has no Windows kernel. Wine version, DXVK/wined3d, winetricks verbs, `winecfg` Windows version, Lutris vs umu, or Steam Deck make no difference — the client never reaches the part where those matter.

## Options that do not end in a ban

1. **Feature request — POSTED 2026-10-14 17:06 in Reborn Discord #general-chat** (Nikita was active in the channel minutes before). Text (ES + EN) in `~/Documents/reborn-feature-request-linux.txt`; it cites the measurements above, EAC/BattlEye developer opt-in for Proton (partner.steamgames.com/doc/steamdeck/proton) and Aion 2 on ProtonDB Platinum (67 reports, no NCSoft whitelist exists — it just works). Watch the thread for Nikita's answer; the support answer alone is still "No".
2. **Play a server whose guard tolerates Wine.** ElmoreLab Teon (x1, C4→Interlude, no dualbox) is the closest to Reborn Signature and runs under Wine per lineage2-linux; Erica/Median as well. Our own September report (`docs/guides/l2/`) has the wider list.
3. **Windows on another box, streamed.** The September decision: Windows 11 on DESK_A + Sunshine/Moonlight. Not Windows on this PC.
4. **Watch the Unity client — it is official.** #announcements 2026-08-25, Nikita [RBRN] (Project Manager), "THE FUTURE OF REBORN: UNITY ENGINE GAME CLIENT": *"We are developing our own Unity Engine game client"*, dedicated team, 1:1 recreation plus an optional modern graphics pack; *"Why Unity instead of Unreal Engine? … the best balance between visual quality, performance, hard[ware] … **multiplatform** support"*; first migration targeted for **2027**, rollout order Legacy → Signature → Eternal → Arena → Origins → Guardian. Dev channel `#🛠️│l2-unity` (opened 2026-10-14): Unity 6.3, devlogs #1–#8 by Shnok (YouTube channel UCjOcFWAxB-JAy_uPTgNbH6A; #7 = 800 players/180 NPCs stress test, 75–90 FPS, < 3 GB RAM). Nothing published yet about which anti-cheat the new client will use; staff (Arthur, 2026-10-11) expects no Linux change if the provider stays. Re-testing costs one `run-game.sh` once a build exists.

## What Claude will not do, and why

Diego asked (2026-10-14) to use REA to find how the guard detects a non-Windows environment and emulate it. Not done: that is anti-cheat evasion — outside the legal line written in the REA skill ("never anti-cheat bypass, never online-game clients"), and the guard's HWID-spoof detection plus Reborn's permanent HWID bans would hit his own accounts. Aion 2 working on Linux is a different vendor's choice (NC Guard whitelists Proton); it does not make SmartGuard's refusal circumventable. Ordinary Wine/Proton compatibility work was done to the end; that is where this document stops.

## Files and cleanup

- Prefix and client: `~/Games/l2reborn/` (prefix 22 GB + launcher). Scripts: `run-launcher.sh`, `run-game.sh` (export `WINEPREFIX`, `GAMEID=umu-0`, `PROTONPATH`, `PROTON_LOG=1 PROTON_LOG_DIR=~/Games/l2reborn`). Logs: `install.log`, `launcher-run1.log`, `game-run1.log`, `steam-0.log`.
- Windows-side logs inside the prefix: `drive_c/ProgramData/RebornLauncher/logs/` (launcher + downloader), `drive_c/Games/RebornLauncher/velopack.log`.
- Research extracts (session scratch, not kept): Discord search for "linux" (652 hits), "proton" (101), "1004" (1 unrelated crash log).
- Remove everything: `rm -rf ~/Games/l2reborn` (the account on l2reborn.org is unaffected).
- Driving the Wine windows from Claude (clicks into Xwayland): `user/wm/sway/sway-apps/tests/live/README.md`, section "Driving Wine / Proton (Xwayland) windows".
