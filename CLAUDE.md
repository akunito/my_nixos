## Overview (for Claude Code)

This is a NixOS flake-based dotfiles repo. Prefer NixOS/Home-Manager modules over imperative commands.

## Critical workflow & invariants

- **Immutability**: never suggest editing `/nix/store` or using `nix-env`, `nix-channel`, `apt`, `yum`.
- **Source of truth**: `flake.nix` and its `inputs` define dependencies.
- **Application workflow**: apply changes via `install.sh` (or `aku sync`), not manual systemd enable/start.
- **Unified flake**: use `nixos-rebuild switch --flake .#PROFILE` (e.g., `.#DESK`, `.#LXC_monitoring`). The `#system` alias uses `.active-profile` for backward compatibility.
- **Flake purity**: prefer repo-relative paths (`./.`) and `self`; avoid absolute host paths inside Nix.
- **SSH agent forwarding**: Always use `-A` flag when connecting to remote machines where git operations may be needed. This forwards your local SSH keys to the remote machine.
  ```bash
  ssh -A user@host    # Enables git push/pull on remote without copying keys
  ```

### Remote Deployment (CRITICAL — NEVER skip)

**NEVER** run bare `git pull && nixos-rebuild switch` on remote machines. This breaks because:
- `hardware-configuration.nix` is machine-specific; `git pull` may overwrite it with another machine's UUIDs
- `install.sh` handles hardware-config regeneration, file hardening/softening, docker handling, and rollback

**Always use `deploy.sh` or the `install.sh` pattern:**

```bash
# Option A: Use deploy.sh from the local machine (preferred)
./deploy.sh --profile LAPTOP_L15

# Option B: For LXC containers (passwordless sudo) — single SSH command
ssh -A akunito@<IP> "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles <PROFILE> -s -u -q"

# Option C: For physical machines (laptops/desktops) — requires sudo password
# Tell the user to run on the target machine:
cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles <PROFILE> -s -u
```

**Key points:**
- `git fetch origin && git reset --hard origin/main` (NOT `git pull`) ensures clean state
- `install.sh` regenerates `hardware-configuration.nix` for the current machine
- `-q` (quick mode) skips docker handling and hardware-config regeneration (safe for LXC/quick updates)
- Physical machines (DESK, LAPTOP_*) need sudo password — ask user to run manually or provide password
- See `deploy-servers.conf` for the full server inventory and IP addresses

## Profile Architecture Principles (CRITICAL)

This repository follows a **hierarchical, modular, and centralized** profile architecture:

### 1. Base + Override Pattern
- **Base profiles** (`LAPTOP-base.nix`, `LXC-base-config.nix`) contain common settings
- **Specific profiles** (`LAPTOP_L15-config.nix`, `LXC_plane-config.nix`) override only what's unique
- The unified `flake.nix` contains all profile outputs (e.g., `nixosConfigurations.LAPTOP_L15`)

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
    ├─► LXC-base-config.nix ◄─── LXC_HOME-config.nix
    │                        ◄─── LXC_plane-config.nix
    │                        ◄─── LXC_portfolioprod-config.nix
    │                        ◄─── LXC_mailer-config.nix
    │                        ◄─── LXC_liftcraftTEST-config.nix
    │                        ◄─── LXC_monitoring-config.nix
    │                        ◄─── LXC_proxy-config.nix
    │                        ◄─── LXC_tailscale-config.nix
    │
    └─► darwin/configuration.nix (macOS/nix-darwin)
             │
             └─► MACBOOK-base.nix ◄─── MACBOOK-KOMI-config.nix
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

### Unified Flake Architecture

This repository uses a **unified flake.nix** with all profiles and inputs defined in one place:

```
flake.nix                    # Unified flake with all profiles and inputs
├── lib/flake-unified.nix    # Generates nixosConfigurations/darwinConfigurations
├── lib/flake-base.nix       # Profile builder (unchanged)
└── profiles/*-config.nix    # Profile configurations (unchanged)
```

**Key benefits:**
- No more `flake.PROFILE.nix` → `flake.nix` copy workflow
- Single `flake.lock` for atomic dependency updates
- Direct rebuild: `nixos-rebuild switch --flake .#DESK`
- Backward compat: `.#system` alias reads `.active-profile`

**Usage:**
```bash
# Rebuild specific profile
sudo nixos-rebuild switch --flake .#DESK --impure
sudo nixos-rebuild switch --flake .#LXC_monitoring --impure

# Backward compatible (uses .active-profile)
sudo nixos-rebuild switch --flake .#system --impure

# List available profiles
nix eval .#nixosConfigurations --apply 'x: builtins.attrNames x'

# darwin (macOS)
darwin-rebuild switch --flake .#MACBOOK-KOMI
```

### NixOS / flake invariants (applies to: `**/*.nix`, `flake.nix`, `flake.lock`)

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
  - LXC_database (192.168.8.103): PostgreSQL + Redis (NixOS native services)
  - LXC_matrix (192.168.8.104): `~/.homelab/matrix/` (Synapse, Element), `~/.claude-matrix-bot/` (Claude bot)
  - LXC_tailscale (192.168.8.105): Tailscale subnet router (NixOS native services)
  - VPS (ssh -p 56777 root@172.26.5.155):
    - Repository: `/root/vps_wg/` (git-crypt encrypted, `git@github.com:akunito/vps_wg.git`)
    - Git-crypt key: `/root/.git-crypt-key`
    - Unlock: `git-crypt unlock /root/.git-crypt-key`
    - Services: `/opt/wireguard-ui/`, `/opt/postfix-relay/`, `/etc/nginx/sites-enabled/`
- **Verify commands**:
  - Docker containers: `docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.Networks}}'`
  - Docker networks: `docker network ls` and `docker network inspect <network>`
  - Prometheus targets: `curl -s http://192.168.8.85:9090/api/v1/targets | jq`
- **Service-specific docs**: See `docs/infrastructure/services/` for detailed service documentation

### Docker-based projects (applies to: Portfolio, LiftCraft, Plane, and other containerized apps)

- **Use wrapper scripts**: Projects with docker-compose use wrapper scripts (`./docker-compose.sh`, `./docker-compose.dev.sh`). NEVER run `npm`, `yarn`, or `bundle` directly on the host - use the wrapper to execute inside the container.
  ```bash
  # WRONG - host doesn't have node_modules
  npm install ioredis

  # CORRECT - runs inside container
  ./docker-compose.sh exec portfolio npm install ioredis
  ./docker-compose.sh exec backend bundle install
  ```
- **Config file locations**: Container configs are typically mounted from the host. Changes persist across restarts:
  - Nextcloud: `/mnt/DATA_4TB/myServices/nextcloud-data/config/config.php`
  - Portfolio: `.env.dev`, `.env.prod` in project root
  - LiftCraft: `.env.test`, `.env.prod` in project root
  - Plane: `.env` in `~/PLANE/`
- **Restart patterns**: For config changes to take effect:
  ```bash
  # Simple restart (keeps volumes)
  ./docker-compose.sh restart service-name

  # Full recreate (reloads everything)
  ./docker-compose.sh stop service-name && ./docker-compose.sh rm -f service-name && ./docker-compose.sh up -d service-name
  ```
- **Environment variables**: Pass through docker-compose.yml `environment` section. Secrets should be in `.env.*` files (gitignored).
- **Health checks**: Many projects have `/api/health` endpoints to verify service status including external dependencies like Redis.
- **Disk cleanup**: If builds fail with "no space left", run NixOS garbage collection and Docker prune:
  ```bash
  sudo nix-collect-garbage -d && docker system prune -af --volumes
  ```

### Redis database allocation (applies to: all services using centralized Redis on LXC_database)

- **Centralized Redis**: All services connect to `192.168.8.103:6379` with database separation
- **Database allocation**:
  | db | Service | Config Key |
  |----|---------|------------|
  | 0 | Plane | (default, no explicit config) |
  | 1 | Nextcloud | `'dbindex' => 1` in config.php |
  | 2 | LiftCraft | `/2` in REDIS_URL |
  | 3 | Portfolio | `/3` in REDIS_URL |
  | 4 | Matrix Synapse | `dbid: 4` in homeserver.yaml |
- **Connection URL format**: `redis://:PASSWORD@192.168.8.103:6379/DB_NUMBER`
- **Password location**: `secrets/domains.nix` (git-crypt encrypted)
- **Troubleshooting**: Use `check-redis` skill or connect via LXC_HOME's redis-local container:
  ```bash
  ssh -A akunito@192.168.8.80
  docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n 3 KEYS '*'
  ```

### VPS WireGuard troubleshooting (applies to: VPS server, `scripts/vps-wireguard-optimize.sh`)

- **VPS access**: `ssh -A -p 56777 root@172.26.5.155`
- **VPS repo location**: The git repo is at `/root/vps_wg/` (git-crypt encrypted)
- **Tunnel diagnostics checklist**:
  1. Check handshake: `wg show` (look for latest-handshakes timestamp)
  2. Check interface stats: `ip -s link show wg0` (TX dropped = problem)
  3. Check kernel tuning: `sysctl net.netfilter.nf_conntrack_max` (should be 65536)
  4. Check qdisc: `tc qdisc show dev wg0` (should show fq_codel)
  5. Check monitor logs: `cat /var/log/wg-tunnel-monitor.log`
- **Optimization script**: Use `scripts/vps-wireguard-optimize.sh` for applying performance tuning
- **pfSense peer key**: `hWv3ipsMkY6HA2fRe/hO7UI4oWeYmfke4qX6af/5SjY=`

### LUKS swap encryption & hibernation (applies to: `system/hardware/hibernate.nix`, `profiles/*-config.nix`)

- **Manual prerequisite**: Encrypting a swap partition requires running commands on the target machine **before** deploying NixOS config. Claude cannot run `sudo cryptsetup` — always provide the commands to the user.
- **Steps for encrypting swap on a new machine**:
  1. `sudo swapoff -a`
  2. `sudo cryptsetup luksFormat --type luks2 /dev/<swap-partition>` — **use the SAME passphrase as root LUKS** (enables `reusePassphrases` auto-unlock)
  3. `sudo cryptsetup luksDump /dev/<swap-partition> | grep UUID` — note the UUID
  4. `sudo cryptsetup luksOpen /dev/<swap-partition> luks-swap && sudo mkswap /dev/mapper/luks-swap && sudo cryptsetup luksClose luks-swap`
  5. Set `hibernateSwapLuksUUID = "<UUID>"` in the profile config
  6. `sudo nixos-rebuild switch --flake .#<PROFILE> --impure && sudo reboot`
- **After reboot**: Enter root LUKS passphrase once — swap auto-unlocks via `reusePassphrases` (no second prompt)
- **hardware-configuration.nix**: Must be regenerated (`sudo nixos-generate-config`) after encrypting swap, as the old unencrypted swap UUID becomes invalid. However, `hibernate.nix` uses `swapDevices = lib.mkForce` which overrides hardware-configuration.nix anyway.
- **Feature flags**: `hibernateEnable` (opt-in per profile), `hibernateSwapLuksUUID` (per-machine), `hibernateDelaySec` (default 600s)
- **Desktop vs laptop behavior**: On desktops (no battery), hibernate is on-demand only (`systemctl hibernate`). On laptops, idle/lid actions use `suspend-then-hibernate` on battery.

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

### Documentation encryption (applies to: `docs/**/*.md`, `.gitattributes`)

- **Public docs are OK for**: Internal IPs (192.168.x.x, 172.x.x.x, 10.x.x.x), email addresses, service descriptions, interface names
- **MUST encrypt**: Public IPs, WireGuard keys, passwords, API tokens, SNMP community strings
- **Encryption methods**:
  1. Add sensitive content to `docs/infrastructure/INFRASTRUCTURE_INTERNAL.md` (already encrypted)
  2. Or add new file to `.gitattributes` with `filter=git-crypt diff=git-crypt`
- **Template pattern**: For encrypted docs with complex structure, create a `.template` version showing structure without real values
- **Verify encryption**: Run `git-crypt status` to confirm files are encrypted before pushing

### pfSense troubleshooting (applies to: pfSense, `docs/infrastructure/services/pfsense.md`)

- **SSH access**: `ssh admin@192.168.8.1`
- **Web GUI**: https://192.168.8.1
- **Key services**:
  - DNS Resolver (Unbound): `*.local.akunito.com` → 192.168.8.102
  - WireGuard: VPS tunnel (172.26.5.0/24)
  - SNMP: Prometheus monitoring target
  - pfBlockerNG: DNS and IP blocklists
  - OpenVPN Client: Privacy VPN for browsing
- **Diagnostic commands**:
  - `pfctl -sr` - Show firewall rules
  - `pfctl -sn` - Show NAT rules
  - `pfctl -ss | wc -l` - Count active states
  - `wg show` - WireGuard tunnel status
  - `unbound-control status` - DNS resolver status
  - `unbound-control stats_noreset` - DNS cache statistics
  - `cat /var/db/pfblockerng/dnsbl/dnsbl.log | tail -20` - Recent DNSBL blocks
  - `pfctl -sT` - Show all firewall tables
  - `pfctl -t pfB_PRI1_v4 -T show | wc -l` - Count blocked IPs
- **Config backup**: `/conf/config.xml` (full configuration)
- **Sensitive data**: WireGuard keys and external IPs in `INFRASTRUCTURE_INTERNAL.md`

### pfSense REST API (applies to: pfSense automation and auditing)

- **Read first**: `docs/infrastructure/services/pfsense.md` (REST API section)
- **API documentation**: https://192.168.8.1/api/v2/documentation (Swagger UI)
- **Authentication header**: `x-api-key: <key-value>` (NOT `X-API-Key` or `Authorization`)
- **Credentials location**: `secrets/domains.nix` (git-crypt encrypted)
  - `pfsenseApiKey` - API key value
  - `pfsenseApiKeyName` - Key name (client-id)
  - `pfsenseHost` - pfSense IP address
- **Example API call**:
  ```bash
  curl -sk -H "x-api-key: $(grep pfsenseApiKey secrets/domains.nix | cut -d'"' -f2)" \
    https://192.168.8.1/api/v2/status/system
  ```
- **Common endpoints**:
  - `GET /api/v2/status/system` - System status (CPU, memory, uptime)
  - `GET /api/v2/status/interface` - Interface status
  - `GET /api/v2/firewall/rule` - Firewall rules
  - `GET /api/v2/firewall/alias` - Firewall aliases
  - `GET /api/v2/services/unbound` - DNS resolver config
  - `GET /api/v2/system/config` - Full configuration
- **Package management**:
  - Install: `pkg-static add https://github.com/pfrest/pfSense-pkg-RESTAPI/releases/download/v2.4.3/pfSense-2.7.2-pkg-RESTAPI.pkg`
  - Must reinstall after pfSense updates (unofficial package)
  - Check [releases](https://github.com/pfrest/pfSense-pkg-RESTAPI/releases) for version compatibility

### Environment Awareness (CRITICAL - applies to: all profiles, remote operations)

- **ENV_PROFILE variable**: Every profile sets `envProfile` in `systemSettings`, which gets exported as `ENV_PROFILE`
- **Check before changes**: Before making ANY changes, determine the current environment:
  ```bash
  echo $ENV_PROFILE
  ```
- **Profile identification**:
  | ENV_PROFILE | Machine | Type | IP |
  |-------------|---------|------|-----|
  | DESK | nixosaku | Desktop | 192.168.8.96 |
  | LAPTOP_L15 | nixolaptopaku | Laptop | 192.168.8.92 |
  | LAPTOP_AGA | nixosaga | Laptop | 192.168.8.78 |
  | LXC_HOME | nixosLabaku | LXC Container | 192.168.8.80 |
  | LXC_database | database | LXC Container | 192.168.8.103 |
  | LXC_monitoring | monitoring | LXC Container | 192.168.8.85 |
  | LXC_proxy | proxy | LXC Container | 192.168.8.102 |
  | LXC_matrix | matrix | LXC Container | 192.168.8.104 |
  | LXC_tailscale | tailscale | LXC Container | 192.168.8.105 |
  | VMHOME | nixosLabaku | VM | 192.168.8.80 |

- **Remote operations**: When working from a remote node (e.g., LXC_matrix via Matrix bot):
  ```bash
  # SSH to other nodes for operations
  ssh -A akunito@192.168.8.50  # DESK
  ssh -A akunito@192.168.8.80  # LXC_HOME
  ssh -A akunito@192.168.8.103 # LXC_database
  ssh -A root@192.168.8.82     # Proxmox
  ```
- **Context-aware behavior**:
  - If `ENV_PROFILE == "LXC_matrix"`: Use SSH for operations on other nodes
  - If `ENV_PROFILE == "DESK"` or `"LAPTOP_*"`: Direct access to local files
  - Always verify profile before destructive operations

### Matrix Server (applies to: `profiles/LXC_matrix-config.nix`, `docs/infrastructure/services/matrix.md`)

- **Read first**: `docs/infrastructure/services/matrix.md`
- **SSH access**: `ssh -A akunito@192.168.8.104`
- **Services**:
  - Matrix Synapse: 8008 (homeserver)
  - Element Web: 8080 (client)
  - Claude Bot: Systemd user service
- **Database**: PostgreSQL `matrix` on LXC_database:5432
- **Redis**: db4 on LXC_database:6379
- **Docker compose location**: `~/.homelab/matrix/`
- **Verify services**:
  ```bash
  docker ps  # Synapse + Element containers
  systemctl --user status claude-matrix-bot  # Bot service
  curl http://localhost:8008/_matrix/client/versions  # Synapse health
  ```

### Tailscale/Headscale mesh VPN (applies to: `profiles/LXC_tailscale-config.nix`, `system/app/tailscale.nix`, `docs/infrastructure/services/tailscale-headscale.md`)

- **Read first**: `docs/infrastructure/services/tailscale-headscale.md`
- **Use skill**: `/manage-tailscale` for operations
- **Components**:
  - **Headscale (VPS)**: Coordination server at `https://headscale.akunito.com`
  - **LXC_tailscale**: Subnet router at 192.168.8.105 (CTID 205)
- **SSH access**:
  - Headscale: `ssh -A -p 56777 root@172.26.5.155`
  - Subnet router: `ssh -A akunito@192.168.8.105`
- **Advertised routes**: 192.168.8.0/24 (LAN), 192.168.20.0/24 (Storage)
- **Key commands**:
  ```bash
  # Check Headscale nodes
  docker exec headscale headscale nodes list
  # Check routes
  docker exec headscale headscale routes list
  # Enable a route
  docker exec headscale headscale routes enable -r <id>
  # Check Tailscale status on subnet router
  ssh -A akunito@192.168.8.105 "tailscale status"
  ```
- **NixOS configuration flags**:
  - `tailscaleEnable`: Enable Tailscale client
  - `tailscaleLoginServer`: Headscale URL
  - `tailscaleAdvertiseRoutes`: Subnets to advertise
  - `tailscaleExitNode`: Act as exit node
  - `tailscaleAcceptRoutes`: Accept routes from other nodes

### Infrastructure audits (applies to: `docs/infrastructure/audits/`)

- **Audit reports**: Stored in `docs/infrastructure/audits/` with date-stamped filenames
- **Latest pfSense audit**: `docs/infrastructure/audits/pfsense-audit-2026-02-04.md`
  - Security score: 7/10 (SNMPv2c and DNSSEC are main concerns)
  - Performance score: 9/10 (excellent headroom)
  - Reliability score: 7/10 (backup automation needed)
- **Completed remediations** (pfSense - 2026-02-07):
  1. ✅ **High**: SEC-001 - Upgraded SNMP to SNMPv3 (NET-SNMP + NixOS config)
  2. ✅ **Medium**: SEC-002 - DNSSEC enabled in DNS Resolver
  3. ✅ **Medium**: REL-002 - unbound-control enabled via custom options
- **Open remediations** (pfSense):
  1. **Medium**: REL-001 - Configure AutoConfigBackup (not in CE, use local backup script)
  2. **Low**: SEC-003 - Restrict anti-lockout rule to admin IPs
- **Performance baseline** (2026-02-04):
  - State table: 770 / 1.6M (0.05% usage)
  - DNS cold query: 33ms, cached: 0ms
  - CPU load: 0.17, Memory free: 14GB
  - pfBlockerNG IPs: 16,242, Rules: 168

### Network switching & 10GbE (applies to: `profiles/DESK-config.nix`, `system/hardware/network-bonding.nix`, `docs/infrastructure/services/network-switching.md`)

- **Read first**: `docs/infrastructure/services/network-switching.md`
- **Use commands**: `/network-performance` for testing, `/manage-truenas` for TrueNAS, `/manage-pfsense` for pfSense
- **Physical topology**:
  - **USW Aggregation** (192.168.8.180): 8x SFP+ 10G switch
  - **USW-24-G2** (192.168.8.181): 24x 1G RJ45 + 2x 1G SFP
  - Inter-switch uplink: SFP+ 1 → USW-24-G2 SFP 2 (1G bottleneck)
- **LACP bonds**:
  - DESK: SFP+ 7+8 → enp11s0f0 + enp11s0f1 (NixOS `networkBondingEnable`)
  - Proxmox: SFP+ 3+4 → enp4s0f0 + enp4s0f1 (bond0 → vmbr10)
  - TrueNAS: SFP+ 5+6 → enp8s0f0 + enp8s0f1 (VLAN-NAS 100 access mode)
  - pfSense: SFP+ 2 → ix0 (single 10G link, VLAN trunk)
- **VLAN 100 (Storage)**: 192.168.20.0/24 — direct L2 between DESK, Proxmox, and TrueNAS (bypasses pfSense)
  - DESK: bond0.100 = 192.168.20.96 (NixOS `networkBondingVlans`)
  - Proxmox: vmbr10.100 = 192.168.20.82
  - TrueNAS: bond0 = 192.168.20.200 (access mode, untagged)
  - pfSense: ix0.100 = 192.168.20.1 (gateway)
- **ARP flux warning**: Proxmox dual-bridge (vmbr0 1G + vmbr10 10G) causes ARP flux without sysctl fix. Symptoms: 940 Mbps instead of 6.8 Gbps. Fix is on Proxmox (`/etc/sysctl.d/99-arp-fix.conf`), not NixOS
- **Performance baselines** (2026-02-12): DESK → Proxmox 6.84 Gbps (1 stream), ~9.4 Gbps (4 streams). DESK → TrueNAS (VLAN 100) 6.81 Gbps. DESK → LXC_HOME 6.83 Gbps
- **NIC tuning**: Ring buffers (4096) and TCP buffers (16 MB) configured declaratively via `networkBondingRingBufferSize` in `network-bonding.nix`
- **UniFi Controller**: https://192.168.8.206:8443 (2FA enabled, use `unifises` session cookie from `secrets/domains.nix`)
- **DAC cables**: Mellanox MCP2104-X001B (1m, pfSense), OFS-DAC-10G-2M (2m, Proxmox), OFS-DAC-10G-1M (1m, TrueNAS + inter-switch), OFS-DAC-10G-3M (3m, DESK)

### Thunderbolt dock & 10GbE (applies to: `system/hardware/thunderbolt.nix`, `system/hardware/thinkpad.nix`, `profiles/LAPTOP_L15-config.nix`)

- **Read first**: `docs/user-modules/thunderbolt-dock.md`
- **LAPTOP_L15 ports**: 1x USB-C 3.2 Gen 1 + 1x Thunderbolt 4 (only ONE port is TB4)
- **OWC Thunderbolt Dock 96W**: Connected via TB4 port, operates in USB mode
  - Dock ethernet: `enp0s13f0u3u4u5`, MAC `00:23:a4:0b:02:d6`, DHCP lease 192.168.8.92
  - WiFi fallback: `wlp9s0` at 192.168.8.91
- **ATTO ThunderLink NS 3102 (TLNS-3102-D00): NOT Linux compatible**
  - Requires proprietary ATTO driver for TB PCIe tunneling (macOS/Windows only)
  - On Linux: only USB management endpoint (`065d:0015`) appears, NIC never enumerates
  - No Linux driver available for 10GbE ThunderLink models
- **PS/2 keyboard/touchpad fix (kernel 6.19+)**: `thinkpad.nix` adds `i8042`/`atkbd` to initrd, `psmouse` to boot modules, `i8042.reset=1`/`i8042.nomux=1` kernel params
- **NixOS feature flags**: `thunderboltEnable`, `thinkpadEnable` in profile config

### Grafana/Prometheus monitoring (applies to: `system/app/grafana.nix`, `system/app/prometheus-*.nix`, `system/app/grafana-dashboards/**`)

- **Read first**: `docs/infrastructure/services/monitoring-stack.md`
- **Access URLs**:
  - Local: `https://grafana.local.akunito.com` (nginx SSL on port 443)
  - Public: `https://grafana.akunito.com` (Cloudflare Tunnel → nginx HTTP on port 80)
  - Prometheus: `https://prometheus.local.akunito.com` (local only, basic auth + IP whitelist)
- **Declarative provisioning**: All Grafana config is managed in `grafana.nix`:
  - **Dashboards**: JSON files in `system/app/grafana-dashboards/` (custom/ and community/)
  - **Datasources**: `provision.datasources.settings` (Prometheus with fixed UID)
  - **Contact points**: `provision.alerting.contactPoints.settings` (email-alerts)
  - **Notification policies**: `provision.alerting.policies.settings`
  - **Alert rules**: Prometheus `ruleFiles` (NOT Grafana UI)
- **Dashboard workflow**:
  1. Edit dashboard in Grafana UI (enabled via `allowUiUpdates = true`)
  2. Export JSON: Dashboard Settings (⚙️) → JSON Model → Copy
  3. Save to `system/app/grafana-dashboards/custom/<name>.json`
  4. Register in `environment.etc` section of `grafana.nix`
  5. Commit, push, deploy: `ssh -A 192.168.8.85 "cd ~/.dotfiles && git pull && sudo nixos-rebuild switch --flake .#LXC_monitoring"`
- **Alert rules format**: Use Prometheus-style rules in `ruleFiles`, NOT Grafana alerting UI
  ```nix
  ruleFiles = [(pkgs.writeText "alerts.yml" (builtins.toJSON {
    groups = [{ name = "alerts"; rules = [{ alert = "..."; expr = "..."; }]; }];
  }))];
  ```
- **Contact point format**: For Grafana 12+, use this structure:
  ```nix
  alerting.contactPoints.settings = {
    apiVersion = 1;
    contactPoints = [{
      orgId = 1;
      name = "email-alerts";
      receivers = [{ uid = "..."; type = "email"; settings = { addresses = "..."; }; }];
    }];
  };
  ```
- **Notification policy format**: Keep it simple (avoid nested routes):
  ```nix
  alerting.policies.settings = {
    apiVersion = 1;
    policies = [{
      orgId = 1;
      receiver = "email-alerts";
      group_by = ["alertname" "severity"];
    }];
  };
  ```
- **Deployment**: `ssh -A 192.168.8.85 "cd ~/.dotfiles && git pull && sudo nixos-rebuild switch --flake .#LXC_monitoring"`
- **Verification commands**:
  - Check service: `systemctl status grafana prometheus`
  - Check provisioning: `journalctl -u grafana | grep provision`
  - Check targets: `curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'`
  - Test contact point: Grafana UI → Alerting → Contact points → Test

### Uptime Kuma troubleshooting (applies to: `docs/infrastructure/services/kuma.md`, LXC_mailer, VPS)

- **Read first**: `docs/infrastructure/services/kuma.md`
- **Two instances**:
  1. **Kuma 1 (Local)**: `http://192.168.8.89:3001` on LXC_mailer
     - SSH: `ssh -A akunito@192.168.8.89`
     - Repo: `~/homelab-watcher/`
     - Auth: Username/password (no 2FA)
  2. **Kuma 2 (Public)**: `https://status.akunito.com` on VPS
     - SSH: `ssh -A -p 56777 root@172.26.5.155`
     - Repo: `/opt/postfix-relay/`
     - Auth: JWT token (2FA enabled)
- **Quick health check**:
  ```bash
  # Kuma 1
  curl -s http://192.168.8.89:3001/api/status-page/globalservices | jq '.ok'
  # Kuma 2
  curl -s -o /dev/null -w '%{http_code}' https://status.akunito.com
  ```
- **API integration**: Uses `uptime-kuma-api` Python library
  - Portfolio project scripts: `~/Projects/portfolio/scripts/kuma/`
  - Password auth (Kuma 1): `api.login(username, password)`
  - JWT auth (Kuma 2): `api.login_by_token(jwt_token)` (token from browser localStorage)
- **Credentials**: Stored in `secrets/domains.nix` (kuma1Username, kuma1Password, kuma2JwtToken)
- **Common issues**:
  - Container not running: Check `docker ps`, restart with `docker compose up -d uptime-kuma`
  - JWT expired (Kuma 2): Re-extract from browser DevTools after 2FA login
  - CSS not applying: Run portfolio scripts with `--force` flag
- **Iframe embedding**: Requires `UPTIME_KUMA_DISABLE_FRAME_SAMEORIGIN=true` in docker-compose
- **Prometheus monitoring**: Kuma 1 monitored via blackbox exporter (http_2xx_nossl module)

### Darwin/macOS rules (applies to: `profiles/darwin/**`, `system/darwin/**`, `profiles/MACBOOK*-config.nix`)

- **Read first**: `docs/macos-installation.md` and `docs/macos-komi-migration.md`
- **nix-darwin + Home Manager**: macOS uses nix-darwin for system config, Home Manager for user config (same as NixOS pattern)
- **Homebrew for GUI apps**: Use `systemSettings.darwin.homebrewCasks` for GUI apps (e.g., Arc, Discord), Nix for CLI tools
- **Touch ID**: Enabled via `security.pam.enableSudoTouchIdAuth` in `system/darwin/security.nix`
- **Hammerspoon**: Window management and app switching managed via `user/app/hammerspoon/hammerspoon.nix`
- **Profile pattern**: Same as Linux - `MACBOOK-base.nix` contains shared settings, specific profiles inherit and override
- **osType flag**: Darwin profiles MUST set `systemSettings.osType = "darwin"` and `system = "aarch64-darwin"` (or x86_64-darwin for Intel)
- **Apply workflow**: `darwin-rebuild switch --flake .#MACBOOK-KOMI` (not install.sh after initial setup)
- **Cross-platform modules**: When making modules work on both Linux and macOS:
  - Use `pkgs.stdenv.isDarwin` for platform detection
  - Use `lib.mkIf (!pkgs.stdenv.isDarwin)` for Linux-only config (e.g., systemd services)
  - Use `lib.mkIf pkgs.stdenv.isDarwin` for macOS-only config (e.g., launchd agents)
  - Never break existing Linux functionality when adding darwin support
- **Key darwin settings** (in `systemSettings.darwin.*`):
  - `homebrewCasks`: List of GUI apps to install via Homebrew
  - `dockAutohide`, `dockOrientation`: Dock preferences
  - `finderShowExtensions`, `finderShowHiddenFiles`: Finder preferences
  - `touchIdSudo`: Enable Touch ID for sudo
  - `keyboardKeyRepeat`, `keyboardInitialKeyRepeat`: Fast keyboard settings
- **Verification after darwin changes**:
  - Test darwin profile: `nix build .#darwinConfigurations.system.system`
  - Test existing Linux profiles still work (see task #11 verification)

## Multi-agent instructions

For complex tasks, see `.claude/agents/` for agent-specific context and patterns.
