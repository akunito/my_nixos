# Configuration Guide

Complete guide to understanding and customizing the NixOS configuration system.

## Table of Contents

- [Configuration Structure](#configuration-structure)
- [Flake Management](#flake-management)
- [Variables and Settings](#variables-and-settings)
- [System Settings](#system-settings)
- [User Settings](#user-settings)
- [Module System](#module-system)
- [Profile Selection](#profile-selection)
- [Best Practices](#best-practices)

## Configuration Structure

The configuration uses a modular architecture:

```
flake.nix (or flake.PROFILE.nix)
├── System Configuration (configuration.nix)
│   └── system/ modules
└── User Configuration (home.nix)
    └── user/ modules
```

### Flake Files

- **`flake.nix`** - Active configuration (copied from profile-specific flake)
- **`flake.*.nix`** - Profile-specific configurations (e.g., `flake.DESK.nix`, `flake.HOME.nix`)
- **`flake.lock`** - Locked dependency versions

### Configuration Files

- **`profiles/*/configuration.nix`** - System-level configuration for each profile
- **`profiles/*/home.nix`** - User-level configuration for each profile
- **`system/*/*.nix`** - System-level modules
- **`user/*/*.nix`** - User-level modules

## Flake Management

### Profile-Specific Flakes

Each machine/profile has its own flake file:

- `flake.DESK.nix` - Desktop computer
- `flake.HOME.nix` - Home server
- `flake.LAPTOP.nix` - Laptop
- `flake.WSL.nix` - WSL installation
- etc.

### Switching Profiles

The `install.sh` script automatically switches profiles:

```sh
./install.sh ~/.dotfiles "DESK"
# Copies flake.DESK.nix → flake.nix
```

### Manual Profile Switch

```sh
cp flake.DESK.nix flake.nix
phoenix sync
```

## Variables and Settings

Variables are centralized in the flake file's `let` binding, allowing configuration in one place that propagates throughout the system.

### Variable Categories

1. **System Settings** - Hardware, boot, network, security
2. **User Settings** - Username, email, dotfiles directory
3. **Profile Settings** - Profile-specific overrides

## System Settings

System settings control low-level system behavior. They're passed to system modules via `specialArgs`.

### Boot Configuration

```nix
systemSettings = {
  bootMode = "uefi";  # or "bios"
  bootMountPath = "/boot";  # EFI partition mount point
  grubDevice = "";  # Device for BIOS boot (e.g., "/dev/sda")
  kernelPackages = pkgs.linuxPackages_latest;
  kernelModules = [ "i2c-dev" "xpadneo" ];
};
```

### Hardware Configuration

```nix
systemSettings = {
  system = "x86_64-linux";  # System architecture
  hostname = "nixosaku";
  gpuType = "amd";  # "amd", "intel", or "nvidia"
  amdLACTdriverEnable = true;
};
```

### Network Configuration

```nix
systemSettings = {
  networkManager = true;
  ipAddress = "192.168.8.96";
  wifiIpAddress = "192.168.8.98";
  defaultGateway = null;
  nameServers = [ "192.168.8.1" ];
  wifiPowerSave = true;
};
```

### Security Configuration

```nix
systemSettings = {
  # SSH
  authorizedKeys = [ "ssh-rsa ..." ];
  bootSSH = false;  # SSH server on boot for LUKS unlock
  
  # Sudo/Doas
  sudoEnable = true;
  sudoNOPASSWD = false;  # NOT recommended
  sudoCommands = [
    {
      command = "/run/current-system/sw/bin/systemctl suspend";
      options = [ "NOPASSWD" ];
    }
  ];
  
  # Polkit
  polkitEnable = true;
  polkitRules = ''...'';
  
  # Firewall
  firewall = true;
  allowedTCPPorts = [ 22 80 443 ];
  allowedUDPPorts = [ ];
};
```

### Drive Configuration

```nix
systemSettings = {
  mount2ndDrives = true;
  
  # Disk 1
  disk1_enabled = true;
  disk1_name = "/mnt/DATA";
  disk1_device = "/dev/mapper/DATA";
  disk1_fsType = "ext4";
  disk1_options = [ "nofail" "x-systemd.device-timeout=3s" ];
  
  # Additional disks (disk2_*, disk3_*, etc.)
};
```

### Backup Configuration

```nix
systemSettings = {
  # Restic wrapper
  resticWrapper = true;
  rsyncWrapper = true;
  
  # Home backup
  homeBackupEnable = true;
  homeBackupDescription = "Backup Home Directory";
  homeBackupExecStart = "/run/current-system/sw/bin/sh /path/to/script.sh";
  homeBackupUser = "username";
  homeBackupOnCalendar = "0/6:00:00";  # Every 6 hours
  
  # Remote backup
  remoteBackupEnable = false;
  remoteBackupExecStart = "/path/to/remote-backup.sh";
};
```

### Application Configuration

```nix
systemSettings = {
  # Docker
  dockerEnable = true;
  
  # Virtualization
  virtualizationEnable = true;
  
  # Printing
  servicePrinting = true;
  networkPrinters = true;
  sharePrinter = false;
  
  # NFS
  nfsServerEnable = false;
  nfsClientEnable = true;
};
```

### Power Management

```nix
systemSettings = {
  # Intel WiFi power save
  iwlwifiDisablePowerSave = false;
  
  # TLP
  TLP_ENABLE = false;
  PROFILE_ON_BAT = "performance";
  PROFILE_ON_AC = "performance";
  
  # logind
  LOGIND_ENABLE = false;
  lidSwitch = "ignore";
  powerManagement_ENABLE = true;
};
```

## User Settings

User settings control user-level configuration and are passed to Home Manager modules via `extraSpecialArgs`.

### Basic User Settings

```nix
userSettings = {
  username = "akunito";
  name = "Akunito";
  email = "user@example.com";
  dotfilesDir = "/home/akunito/.dotfiles";
  theme = "catppuccin-mocha";
  editor = "emacs";
  shell = "zsh";
};
```

### Application Preferences

```nix
userSettings = {
  browser = "firefox";
  terminal = "alacritty";
  wm = "plasma6";  # or "hyprland", "xmonad"
};
```

## Module System

### System Modules

System modules are located in `system/` and imported in profile `configuration.nix`:

```nix
imports = [
  ../../system/app/docker.nix
  ../../system/hardware/drives.nix
  ../../system/security/sshd.nix
];
```

### User Modules

User modules are located in `user/` and imported in profile `home.nix`:

```nix
imports = [
  ../../user/app/git/git.nix
  ../../user/wm/plasma6/plasma6.nix
  ../../user/shell/sh.nix
];
```

### Accessing Variables in Modules

**System modules** receive variables via function arguments:

```nix
{ lib, systemSettings, pkgs, ... }:
{
  # Use systemSettings.*
  services.docker.enable = systemSettings.dockerEnable;
}
```

**User modules** receive variables via `extraSpecialArgs`:

```nix
{ lib, userSettings, pkgs, ... }:
{
  # Use userSettings.*
  home.username = userSettings.username;
}
```

## Profile Selection

Profiles are selected in the flake file:

```nix
systemSettings = {
  profile = "personal";  # Selects profiles/personal/
};
```

Available profiles:
- `personal` - Personal laptop/desktop
- `work` - Work laptop/desktop
- `homelab` - Server/homelab
- `worklab` - Work server
- `wsl` - Windows Subsystem for Linux
- `nix-on-droid` - Android device

See [Profiles Documentation](profiles.md) for details.

## Best Practices

### 1. Use Variables, Not Hardcoded Values

✅ Good:
```nix
home.username = userSettings.username;
```

❌ Bad:
```nix
home.username = "akunito";
```

### 2. Keep Profile-Specific Settings in Flake Files

Profile-specific configurations should be in `flake.PROFILE.nix`, not in modules.

### 3. Use Conditional Enabling

```nix
services.docker.enable = lib.mkIf systemSettings.dockerEnable true;
```

### 4. Document Custom Settings

Add comments explaining non-obvious configurations:

```nix
# Disable power save for Intel WiFi to prevent connection drops
# when laptop lid is closed
iwlwifiDisablePowerSave = true;
```

### 5. Test Incrementally

After making changes:
1. Test syntax: `nix flake check`
2. Build dry-run: `nixos-rebuild build --flake .#system`
3. Apply: `phoenix sync`

### 6. Version Control

- Commit `flake.nix` and `flake.lock`
- Don't commit `local/` directory (gitignored)
- Use descriptive commit messages

## Related Documentation

- [Installation Guide](installation.md) - Setting up the configuration
- [Profiles Guide](profiles.md) - Understanding profiles
- [System Modules](system-modules.md) - System-level modules
- [User Modules](user-modules.md) - User-level modules

