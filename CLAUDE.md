## Overview (for Claude Code)

This is a NixOS flake-based dotfiles repo. Prefer NixOS/Home-Manager modules over imperative commands.

## Critical workflow & invariants

- **Immutability**: never suggest editing `/nix/store` or using `nix-env`, `nix-channel`, `apt`, `yum`.
- **Source of truth**: `flake.nix` and its `inputs` define dependencies.
- **Application workflow**: apply changes via `install.sh` (or `phoenix sync`), not manual systemd enable/start.
- **Flake purity**: prefer repo-relative paths (`./.`) and `self`; avoid absolute host paths inside Nix.
- **LXC Container Modularity**: For Proxmox LXC containers, use the **Base + Override** pattern:
  - Common settings in `profiles/LXC-base-config.nix`.
  - Hostname/specific overrides in `profiles/<NAME>-config.nix`.
  - Point `flake.<NAME>.nix` to the override.

## Home Manager updates

When modifying Home Manager configuration (user-level modules), apply changes using:

```bash
cd /home/akunito/.dotfiles && ./sync-user.sh
```

This command updates the Home Manager configuration and applies changes without requiring a full system rebuild. Use this for:
- User application configurations (tmux, nixvim, etc.)
- User shell configurations
- User window manager settings
- Any changes in `user/` directory

## Router-first retrieval protocol (CRITICAL)

Before answering any architectural or implementation question:

1) Read `docs/00_ROUTER.md` and select the most relevant `ID`(s).
2) Read the documentation file(s) corresponding to those IDs.
3) Only then read the related source files (prefer the `Primary Path` scopes from the Router).
4) Only if still needed: search, but keep it scoped to the selected node's directories.

## Docs index maintenance

- The router/catalog are auto-generated. After adding major docs/modules or restructuring docs, run:
  - `python3 scripts/generate_docs_index.py`

## Domain-specific rules

### NixOS / flake invariants (applies to: `**/*.nix`, `flake.nix`, `flake.*.nix`, `flake.lock`)

- **Immutability**: never suggest editing `/nix/store` or running imperative package managers (`nix-env`, `nix-channel`, `apt`, `yum`).
- **Source of truth**: `flake.nix` + `inputs` control dependencies; use Nix options/modules, not ad-hoc system changes.
- **Apply workflow**: apply changes via `install.sh` (or `phoenix sync`), not manual `systemctl enable`/`systemctl start`.
- **Flake purity**: prefer repo-relative paths (`./.`) and `self`; avoid absolute host paths in Nix expressions.
- **System vs user**:
  - system-wide packages: `environment.systemPackages`
  - per-user: `home.packages`
  - system services: `services.*`
  - user services/programs: `systemd.user.*` / `programs.*` (Home Manager)

### Documentation maintenance (applies to: `docs/**`, `scripts/generate_docs_index.py`)

- **Frontmatter required for key docs**: when editing or creating major docs, include YAML frontmatter:
  - `id` (stable unique ID)
  - `summary` (1-line)
  - `tags` (keyword list)
  - `related_files` (globs/paths this doc governs; if omitted, router falls back to doc path)
- **Index generation**: after reorganizing docs or adding major modules/docs, regenerate:
  - `python3 scripts/generate_docs_index.py`
  - This produces:
    - `docs/00_ROUTER.md` (routing table)
    - `docs/01_CATALOG.md` (full catalog)
    - `docs/00_INDEX.md` (shim)

### Sway daemon integration (applies to: `user/wm/sway/**`)

- **Read first**: `docs/user-modules/sway-daemon-integration.md`
- **Systemd-first**: Sway session services are managed by systemd user units bound to `sway-session.target`.
- **Single lifecycle manager**: do not start the same service via both Sway startup `exec` and systemd; pick one (prefer systemd user services).
- **DRY**: treat `user/wm/sway/default.nix` as the source of truth; keep service wiring there.
- **Safety constraints**: Avoid adding startup sleeps/delays unless strictly necessary; timing is sensitive in Wayland sessions.

### Energy/Power profiles (applies to: `system/hardware/power.nix`, `profiles/*-config.nix`)

- **Profile-specific settings**: Each profile (DESK, AGA, LAPTOP, YOGAAKU, VMHOME) can have different TLP/power settings.
- **Key settings in profile configs**:
  - `TLP_ENABLE`: Enable/disable TLP power management (disable for VMs/desktops)
  - `CPU_SCALING_GOVERNOR_ON_AC/BAT`: powersave, performance, schedutil
  - `START/STOP_CHARGE_THRESH_BAT0`: Battery charge thresholds for longevity
  - `PROFILE_ON_AC/BAT`: Platform power profiles (performance, balanced, low-power)
- **VMs (VMHOME)**: Disable TLP - hypervisor manages power
- **Desktops (DESK)**: May disable TLP if no battery
- **Laptops (AGA, LAPTOP, YOGAAKU)**: Enable TLP with appropriate thresholds

### Gaming modules (applies to: `user/app/games/**`, `system/app/proton.nix`, `system/app/starcitizen.nix`)

- **Read first**: `docs/user-modules/gaming.md`
- **Feature flags**: `protongamesEnable`, `starcitizenEnable`, `steamPackEnable` in profile configs
- **proton.nix**: System-level Bottles overlay and `BOTTLES_IGNORE_SANDBOX` env var (no packages installed)
- **starcitizen.nix**: Kernel tweaks for Star Citizen performance
- **games.nix**: User-level packages (Lutris, Bottles, Heroic, antimicrox) with AMD/Vulkan wrappers

## Multi-agent instructions

For complex tasks, see `.claude/agents/` for agent-specific context and patterns.
