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
| Claude Code | native install only to bootstrap (PowerShell) | the real one: `claude` wrapper, claude-sync identity `DESK_W11`, `ENV_PROFILE=DESK_W11` |
| Docker | – | native `virtualisation.docker` (rootful), no Docker Desktop |
| Local LLM | none (VRAM stays for games) | none |
| Bitwarden, Obsidian, Telegram, Element, Spotify, DBeaver | winget | – |

Not replicated on purpose: Sway/waybar, gamescope/Steam-on-Linux, Sunshine,
Ollama/llama.cpp, printing, Bluetooth tooling, the harmonia cache server.

## Files in the repo

- `profiles/DESK_W11-config.nix` — flag sheet (hostname `nixosw11aku`, `envProfile = "DESK_W11"`, `wslWindowsUser`)
- `profiles/wsl/configuration.nix`, `profiles/wsl/home.nix` — the module set (`profile = "wsl"`)
- `flake.nix` — input `nixos-wsl` (pinned rev) + `DESK_W11` entry
- `templates/windows/DESK_W11/` — `bootstrap.ps1`, `debloat.ps1`, `.wslconfig`, `hyper-desktops.ahk`, `windows-terminal.settings.json`
- Keys: `~/Nextcloud/backups/w11-bootstrap/w11-keys.tar.gpg` (W11 ssh key + claude-sync key, symmetric gpg). The public halves are already in every `authorizedKeys` list (VPS, NAS, DESK, X13) and in `claudeSyncHubKeys`.

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
2. `.\bootstrap.ps1` — Fast Startup off, RTC in UTC, high-performance plan, winget
   apps (Terminal, PowerShell 7, VS Code, Zen, Vivaldi, Nextcloud, Tailscale,
   AutoHotkey, Bitwarden, Obsidian, Telegram, Element, Spotify, DBeaver,
   PowerToys, JetBrainsMono Nerd Font, Claude Code), WSL platform, `.wslconfig`,
   AutoHotkey Startup shortcut (UI-Access binary).
3. `.\debloat.ps1` — Copilot/Recall/Windows AI off, telemetry/ads/Spotlight/widgets
   off, Delivery Optimization P2P off, ten safe services disabled, store bloat and
   OneDrive removed, Edge background off, Game Mode on. Nothing touches Defender,
   Update, Xbox services, audio, Bluetooth or printing. Reboot.
4. Download `VirtualDesktopAccessor.dll` from
   https://github.com/Ciantic/VirtualDesktopAccessor/releases into the same
   folder as `hyper-desktops.ahk`, then double-click the Startup shortcut once.
   Test: Hyper+2 creates and jumps to desktop 2, Hyper+Shift+1 moves the window back,
   Alt+drag moves, Alt+right-drag resizes. Hyper+Shift+Escape suspends everything for games.
5. Tailscale: log in against `https://<headscaleDomain>` (Settings → Use a custom
   coordination server), name it `DESK_W11`. On the Headscale side add the node to
   `group:family` (see `reference_headscale_guest_acl`), or it cannot reach anything.
6. Nextcloud Desktop: server `https://nextcloud.local.akunito.com` (the public host
   is behind Cloudflare Access, native clients cannot pass it), local folder
   `C:\Users\<you>\Nextcloud`, sync everything you use on DESK (`myLibrary`,
   `git_repos`, `backups` at least).
7. Zen: sign in to Zen Sync with the account DESK uses. Install Sine, then the
   web-panels mod from `akunito/sine-web-panels`, by hand (no Nix here).
8. Windows Terminal: paste `windows-terminal.settings.json` pieces into Settings →
   Open JSON file. The `NixOS` profile appears by itself once the distro exists.
9. Keyboard layouts: Settings → Time & language → Language → add English (US-International),
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
