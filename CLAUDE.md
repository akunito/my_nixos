## Overview (for Claude Code)

This is a NixOS flake-based dotfiles repo. Prefer NixOS/Home-Manager modules over imperative commands.

## Critical workflow & invariants

- **Immutability**: never suggest editing `/nix/store` or using `nix-env`, `nix-channel`, `apt`, `yum`.
- **Source of truth**: `flake.nix` and its `inputs` define dependencies.
- **Application workflow**: apply changes via `install.sh` (or `aku sync`), not manual systemd enable/start.
- **Flake purity**: prefer repo-relative paths (`./.`) and `self`; avoid absolute host paths inside Nix.

## Profile Architecture Principles (CRITICAL)

This repository follows a **hierarchical, modular, and centralized** profile architecture:

### 1. Base + Override Pattern
- **Base profiles** (`LAPTOP-base.nix`, `LXC-base-config.nix`) contain common settings
- **Specific profiles** (`LAPTOP_L15-config.nix`, `LXC_plane-config.nix`) override only what's unique
- Each flake file (`flake.LAPTOP_L15.nix`) points to the specific profile config

### 2. Profile Type Inheritance Hierarchy

```
lib/defaults.nix (global defaults)
    │
    ├─► personal/configuration.nix ◄─── work/configuration.nix
    │        │
    │        ├─► DESK-config.nix
    │        ├─► LAPTOP-base.nix ◄─── LAPTOP_L15-config.nix
    │        │                    ◄─── LAPTOP_YOGAAKU-config.nix
    │        ├─► AGA-config.nix
    │        └─► AGADESK-config.nix
    │
    ├─► homelab/configuration.nix
    │        │
    │        └─► VMHOME-config.nix
    │
    └─► LXC-base-config.nix ◄─── LXC_HOME-config.nix
                             ◄─── LXC_plane-config.nix
                             ◄─── LXC_portfolioprod-config.nix
                             ◄─── LXC_mailer-config.nix
                             ◄─── LXC_liftcraftTEST-config.nix
                             ◄─── LXC_monitoring-config.nix
                             ◄─── LXC_proxy-config.nix
```

### 3. Centralized Software Management (CRITICAL)

All software-related flags MUST be grouped in **two centralized sections**:

#### A. System Settings Section (in systemSettings)
```nix
# ============================================================================
# SOFTWARE & FEATURE FLAGS - Centralized Control
# ============================================================================

# === Package Modules ===
systemBasicToolsEnable = true;      # Basic system tools
systemNetworkToolsEnable = true;    # Advanced networking tools

# === Desktop Environment & Theming ===
enableSwayForDESK = true;
stylixEnable = true;
swwwEnable = true;

# === System Services & Features ===
sambaEnable = true;
sunshineEnable = true;
wireguardEnable = true;
xboxControllerEnable = true;
appImageEnable = true;
gamemodeEnable = true;

# === Development Tools & AI ===
developmentToolsEnable = true;
aichatEnable = true;
nixvimEnabled = true;
lmstudioEnabled = true;
```

#### B. User Settings Section (in userSettings)
```nix
# ============================================================================
# SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
# ============================================================================

# === Package Modules (User) ===
userBasicPkgsEnable = true;         # Basic user packages (browsers, office, etc.)
userAiPkgsEnable = true;            # AI & ML packages (lmstudio, ollama-rocm)

# === Gaming & Entertainment ===
protongamesEnable = true;
starcitizenEnable = true;
GOGlauncherEnable = true;
steamPackEnable = true;
dolphinEmulatorPrimehackEnable = true;
rpcs3Enable = true;
```

### 4. Package Module System

Software is organized into **4 core package modules**:

**System Level:**
- `system/packages/system-basic-tools.nix` (systemBasicToolsEnable)
  - Essential CLI tools: vim, wget, zsh, rsync, cryptsetup, etc.
- `system/packages/system-network-tools.nix` (systemNetworkToolsEnable)
  - Advanced networking: nmap, traceroute, dnsutils, etc.

**User Level:**
- `user/packages/user-basic-pkgs.nix` (userBasicPkgsEnable)
  - Standard applications: browsers, office, communication, etc.
- `user/packages/user-ai-pkgs.nix` (userAiPkgsEnable)
  - AI/ML tools: lmstudio, ollama-rocm

### 5. Profile Configuration Rules

**MUST follow:**
- Software flags MUST be in centralized sections (after systemPackages/homePackages)
- Flags MUST be grouped by topic with clear headers
- Each flag MUST have a descriptive comment
- Base profiles define NO software flags (only common settings)
- Specific profiles explicitly enable what they need
- NEVER duplicate flags across profile and base

**Example Profile Structure:**
```nix
{
  systemSettings = {
    hostname = "nixosaku";
    profile = "personal";
    # ... network, security, etc ...

    systemPackages = pkgs: pkgs-unstable: [
      # Profile-specific packages only
    ];

    # ========================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ========================================================================
    systemBasicToolsEnable = true;
    # ... all system software flags grouped here ...
  };

  userSettings = {
    # ... user config ...

    homePackages = pkgs: pkgs-unstable: [
      # Profile-specific packages only
    ];

    # ========================================================================
    # SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
    # ========================================================================
    userBasicPkgsEnable = true;
    # ... all user software flags grouped here ...
  };
}
```

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
- **Apply workflow**: apply changes via `install.sh` (or `aku sync`), not manual `systemctl enable`/`systemctl start`.
- **Flake purity**: prefer repo-relative paths (`./.`) and `self`; avoid absolute host paths in Nix expressions.
- **System vs user**:
  - system-wide packages: `environment.systemPackages`
  - per-user: `home.packages`
  - system services: `services.*`
  - user services/programs: `systemd.user.*` / `programs.*` (Home Manager)
- **Modular configuration (CRITICAL)**:
  - **NEVER** hardcode hostname or profile checks in modules (e.g., `hostname == "nixosaku"`)
  - Use feature flags defined in `lib/defaults.nix` instead
  - Flags default to `false` (or safe value) - profiles explicitly enable what they need
  - GPU-specific code must check `systemSettings.gpuType` ("amd", "intel", "nvidia", "none")
  - Profile configs set flags - modules just consume them
  - Example flags: `gpuType`, `enableDesktopPerformance`, `sddmBreezePatchedTheme`, `atuinAutoSync`

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

### Infrastructure documentation (applies to: `docs/infrastructure/**`, `profiles/LXC*-config.nix`)

- **Read first**: `docs/infrastructure/INFRASTRUCTURE.md` (public) and `docs/infrastructure/INFRASTRUCTURE_INTERNAL.md` (encrypted)
- **Update on changes**: When modifying LXC profiles, docker-compose files, or monitoring configs, update the relevant infrastructure docs
- **SSH audit**: When adding/removing services, SSH to the affected container to verify actual state
- **Key locations per container**:
  - LXC_HOME (192.168.8.80): `~/.homelab/` (homelab, media, nginx-proxy, unifi docker-compose files)
  - LXC_proxy (192.168.8.102): `~/npm/` (NPM config), cloudflared via NixOS
  - LXC_mailer (192.168.8.89): `~/homelab-watcher/` (postfix, kuma)
  - LXC_monitoring (192.168.8.85): NixOS native (grafana.nix, prometheus-*.nix)
  - LXC_plane (192.168.8.86): `~/PLANE/`
  - LXC_portfolioprod (192.168.8.88): `~/portfolioPROD/`
  - LXC_liftcraftTEST (192.168.8.87): `~/leftyworkout_TEST/`
  - VPS (ssh -p 56777 root@172.26.5.155): `/opt/wireguard-ui/`, `/opt/postfix-relay/`, `/etc/nginx/sites-enabled/`
- **Verify commands**:
  - Docker containers: `docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.Networks}}'`
  - Docker networks: `docker network ls` and `docker network inspect <network>`
  - Prometheus targets: `curl -s http://192.168.8.85:9090/api/v1/targets | jq`
- **Service-specific docs**: See `docs/infrastructure/services/` for detailed service documentation

### Secrets management (applies to: `secrets/*.nix`, `profiles/*-config.nix`, `system/**/*.nix`)

- **Read first**: `docs/security/git-crypt.md`
- **Encrypted secrets**: `secrets/domains.nix` contains sensitive data (domains, IPs, SNMP, emails)
- **Public template**: `secrets/domains.nix.template` shows structure without real values
- **Import pattern for profiles**:
  ```nix
  let
    secrets = import ../secrets/domains.nix;
  in
  {
    systemSettings = {
      notificationToEmail = secrets.alertEmail;
      prometheusSnmpCommunity = secrets.snmpCommunity;
    };
  }
  ```
- **Import pattern for system modules**:
  ```nix
  let
    secrets = import ../../secrets/domains.nix;
  in
  {
    services.grafana.settings.server.domain = "monitor.${secrets.localDomain}";
  }
  ```
- **Key location**: `~/.git-crypt/dotfiles-key`
- **Unlock on fresh clone**: `git-crypt unlock ~/.git-crypt/dotfiles-key`
- **NEVER commit**: git-crypt keys, plaintext secrets, or credentials

## Multi-agent instructions

For complex tasks, see `.claude/agents/` for agent-specific context and patterns.
