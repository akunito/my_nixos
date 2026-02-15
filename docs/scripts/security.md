---
id: scripts.security
summary: Security scripts — harden.sh, soften.sh, cleanIPTABLESrules.sh for file permissions and firewall management
tags: [scripts, security, permissions, firewall, hardening]
related_files: [harden.sh, soften.sh, cleanIPTABLESrules.sh]
date: 2026-02-15
status: published
---

# Security Scripts

## harden.sh

**Purpose**: Makes system-level configuration files read-only for unprivileged users.

**Usage**:
```sh
sudo ./harden.sh [path]
# Or via aku
aku harden
```

**What It Does**:
- Changes ownership of system files to root (UID 0, GID 0)
- Prevents unprivileged users from modifying:
  - `system/` directory
  - `profiles/*/configuration.nix` files
  - `flake.nix` and `flake.lock`
  - `patches/` directory
  - Installation and update scripts

**Security Note**: Assumes user has UID/GID 1000. After hardening, `nix flake update` requires root.

**When to Use**:
- After installation
- After making configuration changes
- Before leaving system unattended

## soften.sh

**Purpose**: Relaxes file permissions to allow editing by unprivileged user.

**Usage**:
```sh
sudo ./soften.sh [path]
# Or via aku
aku soften
```

**What It Does**:
- Changes ownership of all files to user (UID 1000, GID users)
- Allows unprivileged user to edit all files

**Security Warning**: After running this, unprivileged users can modify system configuration files, which may compromise system security after `nixos-rebuild switch`.

**When to Use**:
- Temporarily for git operations
- When editing configuration files
- Before running `pull.sh`

**Important**: Always run `harden.sh` again after editing!

## cleanIPTABLESrules.sh

**Purpose**: Clears all iptables and ip6tables rules.

**Usage**:
```sh
sudo ./cleanIPTABLESrules.sh
```

**What It Does**:
- Sets default policies to ACCEPT for INPUT, FORWARD, OUTPUT
- Flushes all tables (nat, mangle, filter)
- Deletes all custom chains
- Clears both IPv4 (iptables) and IPv6 (ip6tables) rules

**When to Use**:
- Before installation if using custom iptables rules
- When switching to NixOS firewall configuration
- To reset firewall to default state
- When iptables rules conflict with NixOS firewall

**Warning**: This removes all firewall rules. Make sure you have alternative protection or will configure firewall immediately after.

**Note**: Called automatically by `install.sh` if user confirms.
