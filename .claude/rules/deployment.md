---
paths:
  - "deploy.sh"
  - "deploy-servers.conf"
  - "deploy-servers-private.conf"
  - "install.sh"
  - "scripts/deploy*"
---

# Deployment Rules

## Deployment Methods

| Method | Command | Use For |
|--------|---------|---------|
| Option A | `./deploy.sh --profile LAPTOP_X13` | Local deploy (preferred) |
| Option B | `ssh -A user@<IP> "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles <PROFILE> -s -d -h"` | LXC containers |
| Option C | `ssh -A -p 56777 akunito@<VPS-IP> "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -d"` | VPS |
| Option D | `ssh -A user@<IP> "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles <PROFILE> -s"` | Physical machines (works over `ssh -A`; `sudo -n true` reporting "password required" is a false negative) |

## Workflow (MUST follow this order)

1. Make changes locally in the dotfiles repo
2. Commit and push to origin/main
3. SSH to remote and run: `git fetch origin && git reset --hard origin/main && ./install.sh ...`
4. NEVER edit files on the remote and run nixos-rebuild directly

## Deploy hygiene (from the 2026-09-22 dubious-ownership incident)

- **Never pipe the deploy chain through `tail`/`head`/`grep`**: `$?` becomes the filter's exit code
  and a failed `git fetch` reads as `EXIT=0`. Redirect the whole chain to a log file and grep the
  file afterwards.
- After `install.sh` finishes, `git -C ~/.dotfiles rev-parse HEAD` on the node must equal
  `origin/main`. If it doesn't, the chain broke before `install.sh` ran.
- **One deploy per machine at a time.** Two `install.sh` runs on one node race each other's
  `git reset --hard` and rebuild.
- On a checkout shared with another live Claude session (DESK_W11), never `git reset --hard`
  without checking that session's `git status`; when local HEAD == `origin/main`, run `install.sh`
  directly.
- The repo stays owned by the user for the whole run (harden.sh/soften.sh were retired on
  2026-09-22). Any file under `~/.dotfiles` owned by root after a deploy is a bug.

## install.sh Flag Reference

The letters do NOT mean "system" and "user" (see `install.sh:44-69`):

| Flag | Effect | Use When |
|------|--------|----------|
| `-s` / `--silent` | No prompts, defaults everywhere | Always for scripted/remote deploys |
| `-u` / `--update` | **Updates `flake.lock`** (runs `update.sh`) before the rebuild | Only when a flake update is the intent. Never by default: every non-nixpkgs branch input re-locks per machine → source builds |
| `-d` / `--skip-docker` | Skip docker container handling (keeps containers running) | LXC + VPS + NAS |
| `-h` / `--skip-hardware` | Skip hardware-config generation (refused if the committed one belongs to another machine) | LXC only (no real hardware) |
| `-q` / `--quick` | Shorthand for `-d -h` | Backward compatibility |
| `-n` / `--no-git-update` | Skip the interactive "repository behind remote" update | After `git-crypt unlock`; irrelevant with `-s` (silent already skips it) |
| `-f` / `--force` | Bypass the ENV_PROFILE check and the `-h` hardware-config check | First install on new hardware |
| `-b` / `--boot` | Use `nixos-rebuild boot` instead of `switch`; skips HM + post-sync hooks | When a "switch inhibitor" is reported (e.g. `dbus -> dbus-broker`, kernel major upgrade) that would break the running session |

System rebuild and Home Manager always both run; there is no flag to select one (`sync-user.sh`
is the Home-Manager-only path).

### `-b` boot-mode workflow

When `nixos-rebuild switch` refuses to apply changes live due to a switch
inhibitor (e.g. dbus implementation swap, kernel jump), use `-b` to stage
the new system for the next reboot:

```bash
# 1. Stage new generation, no live activation
ssh -A user@<IP> "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles <PROFILE> -s -b"

# 2. User reboots the machine (lands on the staged generation)
ssh -A user@<IP> 'sudo reboot'

# 3. Re-run install.sh WITHOUT -b to apply HM + post-sync hooks on the new generation
ssh -A user@<IP> "cd ~/.dotfiles && ./install.sh ~/.dotfiles <PROFILE> -s"
```

In boot mode install.sh **skips** Home Manager activation and post-sync hooks,
because they would run against the OLD still-running system and either fail or
duplicate work. They are applied on the second run after reboot.

## Flag Combinations by Machine Type

| Machine Type | Flags | Reason |
|-------------|-------|--------|
| **LXC containers** | `-s -d -h` | No docker, no real hardware |
| **VPS (VPS_PROD)** | `-s -d` | Skip docker, but DO regenerate hardware-config |
| **NAS (NAS_PROD)** | `-s -d` | Skip docker, DO regenerate hardware-config |
| **Laptops/Desktops** | `-s` | Full rebuild including docker and hardware |

Add `-u` to any row only when the task is a flake.lock update.

## Key Points

- `git fetch origin && git reset --hard origin/main` (NOT `git pull`) ensures clean state
- `install.sh` regenerates `hardware-configuration.nix` for the current machine
- Physical machines (DESK, LAPTOP_*) work over `ssh -A` too: sudo prompts through the cached
  timestamp / GUI askpass; the pre-check's `sudo -n true` warning is a known false negative
- See `deploy-servers.conf` for the full server inventory and IP addresses
- `hardware-configuration.nix` is tracked in git (required by flake) but regenerated by `install.sh`

## SSH Connection Quick Reference

```bash
ssh -A akunito@192.168.8.96                  # DESK
ssh -A -p 56777 akunito@100.64.0.6           # VPS_PROD (via Tailscale)
ssh -A -p 56777 akunito@172.26.5.155         # VPS_PROD (via WireGuard)
ssh -A akunito@100.64.0.1                    # NAS_PROD (Tailscale, default). LAN leg: 192.168.8.206.
                                             # NOT 192.168.20.200 unless the caller has its own VLAN 100 leg:
                                             # the NAS answers 192.168.8.x via enp10s0, so a request routed in by
                                             # pfSense to bond0 returns asymmetrically and rp_filter drops it.
ssh admin@192.168.8.1                        # pfSense
```

Always use `-A` flag for SSH agent forwarding when git operations may be needed.
