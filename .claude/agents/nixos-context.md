# NixOS Agent Context

This context applies when working with NixOS/flake files: `**/*.nix`, `flake.nix`, `flake.*.nix`, `flake.lock`

## Invariants (always follow)

- **Immutability**: never suggest editing `/nix/store` or running imperative package managers (`nix-env`, `nix-channel`, `apt`, `yum`).
- **Source of truth**: `flake.nix` + `inputs` control dependencies; use Nix options/modules, not ad-hoc system changes.
- **Apply workflow**: apply changes via `install.sh` (or `aku sync`), not manual `systemctl enable`/`systemctl start`.
- **Flake purity**: prefer repo-relative paths (`./.`) and `self`; avoid absolute host paths in Nix expressions.

## System vs User Boundaries

- system-wide packages: `environment.systemPackages`
- per-user packages: `home.packages`
- system services: `services.*`
- user services/programs: `systemd.user.*` / `programs.*` (Home Manager)

## Home Manager Updates

When modifying Home Manager configuration (user-level modules), apply changes using:

```bash
cd /home/akunito/.dotfiles && ./sync-user.sh
```

## Unified Flake Architecture

```
flake.nix                    # Unified flake with all profiles and inputs
├── lib/flake-unified.nix    # Generates nixosConfigurations/darwinConfigurations
├── lib/flake-base.nix       # Profile builder (unchanged)
└── profiles/*-config.nix    # Profile configurations (unchanged)
```

**Usage:**
```bash
# Rebuild specific profile (local machine only — NEVER on remote!)
sudo nixos-rebuild switch --flake .#DESK --impure

# Backward compatible (uses .active-profile)
sudo nixos-rebuild switch --flake .#system --impure

# List available profiles
nix eval .#nixosConfigurations --apply 'x: builtins.attrNames x'

# darwin (macOS)
darwin-rebuild switch --flake .#MACBOOK-KOMI
```

## Profile Type Inheritance Hierarchy

```
lib/defaults.nix (global defaults)
    │
    ├─► personal/configuration.nix ◄─── work/configuration.nix
    │        │
    │        ├─► DESK-config.nix
    │        │        ├─► DESK_A-config.nix
    │        │        └─► DESK_VMDESK-config.nix
    │        │
    │        ├─► LAPTOP-base.nix ◄─── LAPTOP_X13-config.nix
    │        │                    ◄─── LAPTOP_YOGA-config.nix
    │        │                    ◄─── LAPTOP_A-config.nix
    │
    ├─► homelab/configuration.nix
    │        │
    │        └─► VMHOME-config.nix
    │
    ├─► LXC-base-config.nix  (akunito LXCs — ALL SHUT DOWN, profiles archived)
    │                        ◄─── LXC_HOME-config.nix        (archived)
    │                        ◄─── LXC_database-config.nix    (archived)
    │                        ◄─── LXC_liftcraftTEST-config.nix (archived)
    │                        ◄─── LXC_mailer-config.nix      (archived)
    │                        ◄─── LXC_matrix-config.nix      (archived)
    │                        ◄─── LXC_monitoring-config.nix  (archived)
    │                        ◄─── LXC_plane-config.nix       (archived)
    │                        ◄─── LXC_portfolioprod-config.nix (archived)
    │                        ◄─── LXC_proxy-config.nix       (archived)
    │                        ◄─── LXC_tailscale-config.nix   (archived)
    │
    ├─► KOMI_LXC-base-config.nix ◄─── KOMI_LXC_database-config.nix
    │                             ◄─── KOMI_LXC_mailer-config.nix
    │                             ◄─── KOMI_LXC_monitoring-config.nix
    │                             ◄─── KOMI_LXC_proxy-config.nix
    │                             ◄─── KOMI_LXC_tailscale-config.nix
    │
    ├─► VPS-base-config.nix ◄─── VPS_PROD-config.nix
    │
    ├─► WSL-config.nix (standalone)
    │
    └─► darwin/configuration.nix (macOS/nix-darwin)
             │
             └─► MACBOOK-base.nix ◄─── MACBOOK-KOMI-config.nix
```

## Modular Configuration (CRITICAL)

**NEVER** hardcode hostname or profile checks in modules. Use feature flags instead:

### BAD (hardcoded):
```nix
lib.mkIf (systemSettings.hostname == "nixosaku") { ... }
lib.mkIf (systemSettings.profile == "personal") { ... }
```

### GOOD (feature flags):
```nix
lib.mkIf systemSettings.sddmBreezePatchedTheme { ... }
lib.mkIf systemSettings.atuinAutoSync { ... }
```

### Rules:
1. **All conditional features must use flags** defined in `lib/defaults.nix`
2. **Flags default to `false`** (or safe value) - profiles explicitly enable what they need
3. **GPU-specific code** must check `systemSettings.gpuType` (values: "amd", "intel", "nvidia", "none")
4. **Profile configs set flags** - modules just consume them
5. **Profile checks are OK** for broad categories (e.g., `profile == "homelab"` for server tuning)

### Examples of correct flags:
- `gpuType` - GPU driver selection ("amd", "intel", "nvidia", "none")
- `enableDesktopPerformance` / `enableLaptopPerformance` - Performance tuning
- `sddmForcePasswordFocus` / `sddmBreezePatchedTheme` - SDDM customization
- `atuinAutoSync` - Shell history cloud sync
- `amdLACTdriverEnable` - AMD GPU control application

## Centralized Software Management (CRITICAL)

All software-related flags MUST be grouped in **two centralized sections**:

### A. System Settings Section (in systemSettings)
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

### B. User Settings Section (in userSettings)
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

## Package Module System

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

## Profile Configuration Rules

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

## Secrets Management

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

## LXC Container Pattern

For Proxmox LXC containers, use the **Base + Override** pattern:
- Common settings in `profiles/LXC-base-config.nix`
- Hostname/specific overrides in `profiles/<NAME>-config.nix`

## When Unsure

Use `docs/00_ROUTER.md` to pick the right doc node, then read only the relevant docs/code.
