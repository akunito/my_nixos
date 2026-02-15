---
id: system-modules.security-wm-utils
summary: Security, window manager, and utility modules — SSH, firewall, sudo, Polkit, Restic, WMs, keyd, aku wrapper
tags: [system-modules, security, ssh, firewall, sudo, polkit, restic, wm, keyd, aku]
related_files: [system/security/*.nix, system/wm/*.nix, system/bin/*.nix]
date: 2026-02-15
status: published
---

# Security, Window Manager & Utility Modules

## Security Modules (`system/security/`)

### SSH Server (`system/security/sshd.nix`)

**Settings**:
- `systemSettings.bootSSH` - Enable SSH on boot (for LUKS unlock)
- `systemSettings.authorizedKeys` - SSH public keys
- `systemSettings.hostKeys` - SSH host keys

**Documentation**: See [LUKS Encryption](../security/luks-encryption.md)

### Firewall (`system/security/firewall.nix`)

**Settings**:
- `systemSettings.firewall` - Enable firewall
- `systemSettings.allowedTCPPorts`, `systemSettings.allowedUDPPorts`

**Features**: nftables firewall, port management

### Sudo (`system/security/sudo.nix`)

**Settings**:
- `systemSettings.sudoEnable`
- `systemSettings.sudoNOPASSWD` - Allow passwordless sudo (NOT recommended)
- `systemSettings.sudoCommands` - Commands with special sudo rules

**Documentation**: See [Sudo Configuration](../security/sudo.md)

### Polkit (`system/security/polkit.nix`)

**Settings**:
- `systemSettings.polkitEnable`
- `systemSettings.polkitRules` - Polkit rules (JavaScript)

**Documentation**: See [Polkit Configuration](../security/polkit.md)

### Restic (`system/security/restic.nix`)

**Settings**:
- `systemSettings.resticWrapper` - Enable Restic wrapper
- `systemSettings.homeBackupEnable` - Enable home backup
- `systemSettings.homeBackupExecStart` - Backup script path
- `systemSettings.homeBackupOnCalendar` - Backup schedule

**Documentation**: See [Restic Backups](../security/restic-backups.md)

### GPG (`system/security/gpg.nix`)

GPG agent configuration and key management.

### Fail2ban (`system/security/fail2ban.nix`)

Automated ban of malicious IPs, SSH protection, service monitoring.

### Firejail (`system/security/firejail.nix`)

Application sandboxing with security profiles.

### Blocklist (`system/security/blocklist.nix`)

DNS blocklist for ad blocking, malware blocking, DNS filtering.

### OpenVPN (`system/security/openvpn.nix`)

VPN client support and connection management.

### Automount (`system/security/automount.nix`)

Automatic USB drive mounting with security restrictions.

## Window Manager Modules (`system/wm/`)

### Plasma 6 (`system/wm/plasma6.nix`)

**Settings**: `systemSettings.desktopManager`

**Features**:
- Plasma 6 installation, SDDM display manager
- Auto-focus password field on login screen
- Monitor rotation script for multi-monitor setups (uses EDID/model name matching)
- Wayland session support enabled

### Hyprland (`system/wm/hyprland.nix`)

Wayland compositor with GPU acceleration requirements.

### XMonad (`system/wm/xmonad.nix`)

XMonad tiling window manager, X11 support.

### Wayland (`system/wm/wayland.nix`)

Wayland session support and compositor integration.

### keyd (`system/wm/keyd.nix`)

**Purpose**: Keyboard and mouse remapping at kernel level

**Features**:
- Caps Lock → Hyper key (held) / Escape (tapped)
- Mouse side button (mouse1) → Control+Alt when held
- Works at kernel input level (Sway, Plasma, Hyprland, console, TTY, login screens)

**Configuration**:
- Caps Lock uses `overload(hyper, esc)` syntax
- Mouse uses `overload(combo_C_A, noop)` — `noop` prevents unwanted key events on release
- Mouse devices require explicit vendor:product IDs (keyd's `*` wildcard only matches keyboards)

**Debugging**: Use `.cursor/debug-keyd-nixos.sh`, `systemctl status keyd`, `sudo keyd monitor`, `sudo keyd check /etc/keyd/default.conf`

### X11 (`system/wm/x11.nix`)

X11 server and legacy application support.

### Pipewire (`system/wm/pipewire.nix`)

Audio/video server with low-latency audio.

### Fonts (`system/wm/fonts.nix`)

System font installation and configuration.

### D-Bus (`system/wm/dbus.nix`)

D-Bus message bus for inter-process communication.

### GNOME Keyring (`system/wm/gnome-keyring.nix`)

Password storage and key management.

## Utility Modules (`system/bin/`)

### Aku Wrapper (`system/bin/aku.nix`)

**Purpose**: Nix command wrapper script

**Commands**:
- `aku sync` - Synchronize system and home-manager
- `aku update` - Update flake inputs
- `aku upgrade` - Update and synchronize
- `aku gc` - Garbage collection
- `aku harden` - Secure system files
- `aku soften` - Relax file permissions

**Documentation**: See [Maintenance Guide](../maintenance.md#aku-wrapper)
