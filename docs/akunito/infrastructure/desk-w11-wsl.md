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
| SSH to VPS / NAS / pfSense / X13 | – | `~/.ssh/config` managed (`sshHostsManaged`), gpg-agent as ssh agent, pinentry-curses |
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

Native Claude Code in PowerShell exists for two cases only: the bootstrap (no
WSL yet) and anything that needs **elevation** (admin), which interop cannot do —
open Windows Terminal's PowerShell profile as administrator for those. No kitty
via WSLg: it would only add a slower forwarded window.

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
| grim/slurp/swappy | ShareX.ShareX | |
| fd/fzf for files | voidtools.Everything | |
| Nerd font | DEVCOM.JetBrainsMonoNerdFont | |
| tailscale + trayscale | Tailscale.Tailscale | node DESK_W11 |
| nextcloud-client | Nextcloud.NextcloudDesktop | |
| bitwarden | Bitwarden.Bitwarden | |
| zen, vivaldi, brave/chromium | Zen-Team.Zen-Browser, Vivaldi.Vivaldi, Brave.Brave | |
| obsidian, telegram, element, vesktop, teams-for-linux, thunderbird, libreoffice, calibre | Obsidian.Obsidian, Telegram.TelegramDesktop, Element.Element, Discord.Discord, Microsoft.Teams, Mozilla.Thunderbird, TheDocumentFoundation.LibreOffice, calibre.calibre | |
| spotify, vlc, qbittorrent, OBS (media recording) | Spotify.Spotify, VideoLAN.VLC, qBittorrent.qBittorrent, OBSProject.OBSStudio | |
| steam, GOG (Heroic), FreesmLauncher + Java 21 | Valve.Steam, GOG.Galaxy, PrismLauncher.PrismLauncher + EclipseAdoptium.Temurin.21.JRE | AkuCraft: new instance + AutoModpack, never copy jars (see memory) |
| sunshine, moonlight | LizardByte.Sunshine, MoonlightGameStreamingProject.Moonlight | Sunshine host for DESK_A/X13 |
| easyeffects | Equalizer APO (manual) | not on winget |
| mission-center | Task Manager | |
| ollama / llama.cpp | none | decided: no LLM on W11 |
| AMD driver | AMD Adrenalin (manual) | winget id unreliable |
| Aion 2, Lineage2Dex | their launchers (manual) | |

Add a package: append `{ "PackageIdentifier": "..." }` (find ids with `winget search`),
commit, re-run `bootstrap.ps1`. Remove: `winget uninstall --id ...`.

## Taskbar and look (Windhawk)

Decision 2026-09-13: keep the vanilla taskbar, restyle it with Windhawk mods
(actively maintained, follow every W11 update; no tiling, no conflicts with games).
Windhawk has no CLI for mods: open it once → Explore → install these, in order,
then set each mod's options:

| Mod | Setting |
|---|---|
| Taskbar on top (Windows 11) | on — the bar goes to the top like waybar |
| Taskbar height and icon size | height 36, icon 20 |
| Taskbar clock customization | `%H:%M  %a %d %b`, top-right like waybar's clock |
| Taskbar labels for Windows 11 | labels on, combine never (workspace-like readability) |
| Taskbar tray system icon tweaks | hide Copilot/News/Chat leftovers, keep network/volume |
| Taskbar notification icon spacing | 24 px |
| Taskbar button click | middle-click closes |
| Start menu styler / Taskbar styler (optional) | a dark theme close to `ashes` |

Settings → Personalization → Taskbar: alignment **left**, Widgets off, Search
hidden, Task view **on** (Hyper+Tab). Dark mode, accent from wallpaper off.
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
8. Zen: sign in to Zen Sync with the account DESK uses. Install Sine, then the
   web-panels mod from `akunito/sine-web-panels`, by hand (no Nix here).
9. Windows Terminal: paste `windows-terminal.settings.json` pieces into Settings →
   Open JSON file. The `NixOS` profile appears by itself once the distro exists.
10. Keyboard layouts: Settings → Time & language → Language → add English (US-International),
   Spanish, Polish. Win+Space cycles, same as Hyper+Return on Sway.

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
9. VS Code on Windows: install the WSL extension, `code .` from the distro.

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

## Known limits

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
- **After `wsl --shutdown`, the first agent-backed `ssh` needs a terminal**:
  `SSH_AUTH_SOCK` is gpg-agent's, and with `gpgPinentryCurses` it needs a TTY to
  re-unlock, so non-interactive calls fail with *"agent refused operation"*.
  `ssh -o IdentityAgent=none` works meanwhile. claude-sync is unaffected — it uses
  its own key in `~/.config/claude-sync/key`.
