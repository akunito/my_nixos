---
paths:
  - "**/*.nix"
  - "flake.nix"
  - "flake.lock"
  - "lib/**"
  - "profiles/**"
---

# NixOS Rules

## Profile Type Inheritance Hierarchy

```
lib/defaults.nix (global defaults)
    |
    +-> personal/configuration.nix <--- work/configuration.nix
    |        |
    |        +-> DESK-config.nix
    |        |        +-> DESK_A-config.nix
    |        |        +-> DESK_VMDESK-config.nix
    |        |
    |        +-> LAPTOP-base.nix <--- LAPTOP_X13-config.nix
    |                             <--- LAPTOP_YOGA-config.nix
    |                             <--- LAPTOP_A-config.nix
    |
    +-> homelab/configuration.nix
    |        +-> VMHOME-config.nix
    |
    +-> LXC-base-config.nix  (akunito LXCs -- ALL SHUT DOWN, archived)
    |
    +-> KOMI_LXC-base-config.nix <--- KOMI_LXC_database-config.nix
    |                             <--- KOMI_LXC_mailer-config.nix
    |                             <--- KOMI_LXC_monitoring-config.nix
    |                             <--- KOMI_LXC_proxy-config.nix
    |                             <--- KOMI_LXC_tailscale-config.nix
    |
    +-> VPS-base-config.nix <--- VPS_PROD-config.nix
    |
    +-> WSL-config.nix (standalone)
    |
    +-> darwin/configuration.nix (macOS/nix-darwin)
             +-> MACBOOK-base.nix <--- MACBOOK-KOMI-config.nix
```

## Modular Configuration (CRITICAL)

**NEVER** hardcode hostname or profile checks in modules. Use feature flags instead.

### BAD:
```nix
lib.mkIf (systemSettings.hostname == "nixosaku") { ... }
```

### GOOD:
```nix
lib.mkIf systemSettings.sddmBreezePatchedTheme { ... }
```

### Rules:
1. All conditional features must use flags defined in `lib/defaults.nix`
2. Flags default to `false` (or safe value) - profiles explicitly enable what they need
3. GPU-specific code must check `systemSettings.gpuType` ("amd", "intel", "nvidia", "none")
4. Profile configs set flags - modules just consume them

## Centralized Software Management

All software flags MUST be grouped in two centralized sections per profile config:

**System Settings** (`systemSettings`):
```nix
# ============================================================================
# SOFTWARE & FEATURE FLAGS - Centralized Control
# ============================================================================
systemBasicToolsEnable = true;
systemNetworkToolsEnable = true;
# ... grouped by topic with clear headers
```

**User Settings** (`userSettings`):
```nix
# ============================================================================
# SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
# ============================================================================
userBasicPkgsEnable = true;
userAiPkgsEnable = true;
# ... grouped by topic with clear headers
```

## Package Module System

| Level | Module | Flag |
|-------|--------|------|
| System | `system/packages/system-basic-tools.nix` | `systemBasicToolsEnable` |
| System | `system/packages/system-network-tools.nix` | `systemNetworkToolsEnable` |
| User | `user/packages/user-basic-pkgs.nix` | `userBasicPkgsEnable` |
| User | `user/packages/user-ai-pkgs.nix` | `userAiPkgsEnable` |

## Secrets Import Patterns

```nix
# In profile configs:
let secrets = import ../secrets/domains.nix;
in {
  systemSettings = {
    notificationToEmail = secrets.alertEmail;
    prometheusSnmpCommunity = secrets.snmpCommunity;
  };
}

# In system modules:
let secrets = import ../../secrets/domains.nix;
in {
  services.grafana.settings.server.domain = "monitor.${secrets.localDomain}";
}
```

- Encrypted secrets: `secrets/domains.nix` | Template: `secrets/domains.nix.template`
- Key: `~/.git-crypt/dotfiles-key` | Unlock: `git-crypt unlock ~/.git-crypt/dotfiles-key`

## LXC Container Pattern

For Proxmox LXC containers, use the **Base + Override** pattern:
- Common settings in `profiles/KOMI_LXC-base-config.nix`
- Hostname/specific overrides in `profiles/KOMI_LXC_<name>-config.nix`
