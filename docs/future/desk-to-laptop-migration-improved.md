# Desktop to Laptop Migration - Final Plan

## Decisions Made

| Decision | Answer |
|----------|--------|
| Rename `enableSwayForDESK` to `enableSway`? | **NO** - Use existing flag directly |
| Want Sway on LAPTOP? | **YES** |
| Need LAPTOP-base.nix? | **YES** |
| Refactor hostname checks to flags? | **YES** |
| Accept git rollback as safety? | **YES** |

---

## Phase 1: Refactor Hostname Checks to Feature Flags

### Goal
Replace hardcoded hostname checks in `io-scheduler.nix` and `performance.nix` with feature flags managed in profile configs.

### 1.1 Add New Flags to lib/defaults.nix

```nix
# Add to systemSettings in lib/defaults.nix:

# Performance profile flags (default false, profiles enable as needed)
enableDesktopPerformance = false;   # Aggressive desktop tuning (DESK, AGADESK)
enableLaptopPerformance = false;    # Battery-conscious laptop tuning (LAPTOP, YOGAAKU)
# Note: homelab profile already uses `profile == "homelab"` check, no change needed
```

### 1.2 Refactor system/hardware/io-scheduler.nix

**Before:**
```nix
(lib.mkIf (systemSettings.hostname == "nixosaku" || systemSettings.hostname == "nixosaga") {
  # Desktop rules
})
(lib.mkIf (systemSettings.hostname == "nixolaptopaku" || systemSettings.hostname == "yogaaku") {
  # Laptop rules
})
```

**After:**
```nix
(lib.mkIf systemSettings.enableDesktopPerformance {
  # Desktop I/O scheduler rules
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="mq-deadline"
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="bfq"
  '';
})

(lib.mkIf systemSettings.enableLaptopPerformance {
  # Laptop I/O scheduler rules
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="mq-deadline"
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="bfq"
  '';
})

# Server (homelab) - already uses profile check, no change needed
(lib.mkIf (systemSettings.profile == "homelab") {
  # Server I/O scheduler rules
})
```

### 1.3 Refactor system/hardware/performance.nix

**Before:**
```nix
(lib.mkIf (systemSettings.hostname == "nixosaku" || systemSettings.hostname == "nixosaga") {
  # Desktop performance
})
(lib.mkIf (systemSettings.hostname == "nixolaptopaku" || systemSettings.hostname == "yogaaku") {
  # Laptop performance
})
```

**After:**
```nix
(lib.mkIf systemSettings.enableDesktopPerformance {
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.dirty_ratio" = 15;
    "vm.dirty_background_ratio" = 5;
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    "net.core.netdev_max_backlog" = 5000;
    "net.ipv4.tcp_fastopen" = 3;
  };
  services.ananicy.enable = true;
})

(lib.mkIf systemSettings.enableLaptopPerformance {
  boot.kernel.sysctl = {
    "vm.swappiness" = 20;
    "vm.dirty_ratio" = 20;
    "vm.dirty_background_ratio" = 10;
    "net.core.rmem_max" = 8388608;
    "net.core.wmem_max" = 8388608;
    "net.ipv4.tcp_rmem" = "4096 65536 8388608";
    "net.ipv4.tcp_wmem" = "4096 32768 8388608";
    "net.core.netdev_max_backlog" = 3000;
    "net.ipv4.tcp_fastopen" = 3;
  };
  services.ananicy.enable = true;
})

# Server (homelab) - already uses profile check, no change needed
```

### 1.4 Update Profile Configs to Enable Flags

**DESK-config.nix:**
```nix
enableDesktopPerformance = true;
```

**AGADESK-config.nix:**
```nix
enableDesktopPerformance = true;
```

**LAPTOP-config.nix** (will be in LAPTOP-base.nix after Phase 2):
```nix
enableLaptopPerformance = true;
```

**YOGAAKU-config.nix** (will be in LAPTOP-base.nix after Phase 2):
```nix
enableLaptopPerformance = true;
```

### 1.5 Verification

```bash
# Test DESK build (you're on DESK)
nix flake check --no-build
nixos-rebuild build --flake .#DESK

# Test LAPTOP build
nixos-rebuild build --flake .#LAPTOP

# Verify no hostname checks remain
grep -r "nixolaptopaku\|yogaaku" system/hardware/io-scheduler.nix system/hardware/performance.nix
# Should return nothing

# Apply to DESK
sudo nixos-rebuild switch --flake .#DESK
```

---

## Phase 2: Create LAPTOP-base.nix

### Goal
Create shared laptop configuration base that LAPTOP and YOGAAKU can inherit from.

### 2.1 Create profiles/LAPTOP-base.nix

```nix
# LAPTOP Base Profile Configuration
# Shared settings for all laptop profiles (LAPTOP, YOGAAKU, future laptops)
# Individual laptop configs import this and override hardware-specific settings

{
  systemSettings = {
    # Performance - laptop-optimized
    enableLaptopPerformance = true;

    # Sway/SwayFX as second WM option
    enableSwayForDESK = true;

    # Theming
    stylixEnable = true;

    # Wallpaper manager for Sway
    swwwEnable = true;
    swaybgPlusEnable = false;

    # Nextcloud desktop client
    nextcloudEnable = true;

    # Polkit (common rules for all laptops)
    polkitEnable = true;
    polkitRules = ''
      polkit.addRule(function(action, subject) {
        if (
          subject.isInGroup("users") && (
            // Allow reboot and power-off actions
            action.id == "org.freedesktop.login1.reboot" ||
            action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
            action.id == "org.freedesktop.login1.power-off" ||
            action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
            action.id == "org.freedesktop.login1.suspend" ||
            action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
            action.id == "org.freedesktop.login1.logout" ||
            action.id == "org.freedesktop.login1.logout-multiple-sessions" ||

            // Allow managing specific systemd units
            (action.id == "org.freedesktop.systemd1.manage-units" &&
              action.lookup("verb") == "start" &&
              action.lookup("unit") == "mnt-NFS_Backups.mount") ||

            // Allow running rsync and restic
            (action.id == "org.freedesktop.policykit.exec" &&
              (action.lookup("command") == "/run/current-system/sw/bin/rsync" ||
              action.lookup("command") == "/run/current-system/sw/bin/restic"))
          )
        ) {
          return polkit.Result.YES;
        }
      });
    '';

    # Power management - TLP for laptops
    powerManagement_ENABLE = false;  # TLP handles this
    power-profiles-daemon_ENABLE = false;  # Disabled in favor of TLP
    TLP_ENABLE = true;

    # Battery thresholds (Health preservation - can be overridden per laptop)
    START_CHARGE_THRESH_BAT0 = 75;
    STOP_CHARGE_THRESH_BAT0 = 80;

    # Lid behavior (default: ignore - override if needed)
    lidSwitch = "ignore";
    lidSwitchExternalPower = "ignore";
    lidSwitchDocked = "ignore";
    powerKey = "ignore";

    # WiFi power save (battery optimization)
    wifiPowerSave = true;

    # NFS client enabled by default for laptops
    nfsClientEnable = true;

    # SSH keys (common across all laptops)
    authorizedKeys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfNRaYr4LSuhcXgI97o2cRfW0laPLXg7OzwiSIuV9N7cin0WC1rN1hYi6aSGAhK+Yu/bXQazTegVhQC+COpHE6oVI4fmEsWKfhC53DLNeniut1Zp02xLJppHT0TgI/I2mmBGVkEaExbOadzEayZVL5ryIaVw7Op92aTmCtZ6YJhRV0hU5MhNcW5kbUoayOxqWItDX6ARYQov6qHbfKtxlXAr623GpnqHeH8p9LDX7PJKycDzzlS5e44+S79JMciFPXqCtVgf2Qq9cG72cpuPqAjOSWH/fCgnmrrg6nSPk8rLWOkv4lSRIlZstxc9/Zv/R6JP/jGqER9A3B7/vDmE8e3nFANxc9WTX5TrBTxB4Od75kFsqqiyx9/zhFUGVrP1hJ7MeXwZJBXJIZxtS5phkuQ2qUId9zsCXDA7r0mpUNmSOfhsrTqvnr5O3LLms748rYkXOw8+M/bPBbmw76T40b3+ji2aVZ4p4PY4Zy55YJaROzOyH4GwUom+VzHsAIAJF/Tg1DpgKRklzNsYg9aWANTudE/J545ymv7l2tIRlJYYwYP7On/PC+q1r/Tfja7zAykb3tdUND1CVvSr6CkbFwZdQDyqSGLkybWYw6efVNgmF4yX9nGfOpfVk0hGbkd39lUQCIe3MzVw7U65guXw/ZwXpcS0k1KQ+0NvIo5Z1ahQ== akunito@Diegos-MacBook-Pro.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPp/10TlSOte830j6ofuEQ21YKxFD34iiyY55yl6sW7V diego88aku@gmail.com"
    ];

    # Features commonly enabled on laptops
    wireguardEnable = true;
    xboxControllerEnable = true;
    appImageEnable = true;
    aichatEnable = true;
    nixvimEnabled = true;

    # i2c modules removed (not needed for most laptops)
    kernelModules = [ ];

    # Sudo UX
    sudoTimestampTimeoutMinutes = 180;

    # Profile base
    profile = "personal";

    # Stable by default (can override for unstable)
    systemStable = false;
  };

  userSettings = {
    username = "akunito";
    name = "akunito";
    email = "diego88aku@gmail.com";
    dotfilesDir = "/home/akunito/.dotfiles";

    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "dialout"
    ];

    theme = "miramare";
    wm = "plasma6";
    wmEnableHyprland = false;

    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    browser = "vivaldi";
    spawnBrowser = "vivaldi";
    defaultRoamDir = "Personal.p";
    term = "kitty";
    font = "Intel One Mono";

    dockerEnable = false;  # Override if needed
    virtualizationEnable = true;
    qemuGuestAddition = false;

    zshinitContent = ''
      PROMPT=" ◉ %U%F{cyan}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';

    sshExtraConfig = ''
      Host github.com
        HostName github.com
        User akunito
        IdentityFile ~/.ssh/id_ed25519
        AddKeysToAgent yes
    '';
  };
}
```

### 2.2 Refactor LAPTOP-config.nix

```nix
# LAPTOP Profile Configuration (nixolaptopaku)
# Inherits from LAPTOP-base.nix, overrides hardware-specific settings

let
  base = import ./LAPTOP-base.nix;
in
{
  # Flag to use rust-overlay
  useRustOverlay = true;

  systemSettings = base.systemSettings // {
    # Hardware-specific
    hostname = "nixolaptopaku";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LAPTOP -s -u";
    gpuType = "intel";

    # Network - specific IPs for this laptop
    ipAddress = "192.168.8.92";
    wifiIpAddress = "192.168.8.93";
    nameServers = [ "192.168.8.1" "192.168.8.1" ];
    resolvedEnable = false;

    # Firewall
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];

    # NFS mounts specific to this laptop
    nfsMounts = [
      {
        what = "192.168.20.200:/mnt/hddpool/media";
        where = "/mnt/NFS_media";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.20.200:/mnt/ssdpool/library";
        where = "/mnt/NFS_library";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.20.200:/mnt/ssdpool/emulators";
        where = "/mnt/NFS_emulators";
        type = "nfs";
        options = "noatime";
      }
    ];
    nfsAutoMounts = [
      { where = "/mnt/NFS_media"; automountConfig = { TimeoutIdleSec = "600"; }; }
      { where = "/mnt/NFS_library"; automountConfig = { TimeoutIdleSec = "600"; }; }
      { where = "/mnt/NFS_emulators"; automountConfig = { TimeoutIdleSec = "600"; }; }
    ];

    # Backups
    homeBackupEnable = true;
    homeBackupOnCalendar = "0/6:00:00";
    homeBackupCallNextEnabled = false;

    # Security
    fuseAllowOther = false;
    pkiCertificates = [ /home/akunito/.myCA/ca.cert.pem ];

    # Printer
    servicePrinting = true;
    networkPrinters = true;

    # Additional features for this laptop
    sunshineEnable = true;

    # System packages specific to this laptop
    systemPackages = pkgs: pkgs-unstable: [
      pkgs.vim pkgs.wget pkgs.nmap pkgs.zsh pkgs.git
      pkgs.cryptsetup pkgs.tldr pkgs.rsync pkgs.nfs-utils
      pkgs.restic pkgs.dialog pkgs.gparted pkgs.lm_sensors
      pkgs.sshfs pkgs.qt5.qtbase
      pkgs-unstable.sunshine
    ];
  };

  userSettings = base.userSettings // {
    homePackages = pkgs: pkgs-unstable: [
      pkgs.zsh pkgs.kitty pkgs.git pkgs.syncthing
      pkgs-unstable.mission-center
      pkgs-unstable.ungoogled-chromium
      pkgs-unstable.vscode
      pkgs-unstable.logseq
      pkgs-unstable.obsidian
      pkgs-unstable.nextcloud-client
      pkgs-unstable.wireguard-tools
      pkgs-unstable.bitwarden-desktop
      pkgs-unstable.moonlight-qt
      pkgs-unstable.discord
      pkgs-unstable.kdePackages.kcalc
      pkgs-unstable.gnome-calculator
      pkgs-unstable.vivaldi
    ];
  };
}
```

### 2.3 Refactor YOGAAKU-config.nix

```nix
# YOGAAKU Profile Configuration (yogaaku)
# Inherits from LAPTOP-base.nix, overrides hardware-specific settings

let
  base = import ./LAPTOP-base.nix;
in
{
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    # Hardware-specific
    hostname = "yogaaku";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles YOGAAKU -s -u";
    bootMode = "bios";
    gpuType = "intel";

    # Kernel modules specific to this laptop
    kernelModules = [
      "cpufreq_powersave"
      "xpadneo"
    ];

    # Network
    ipAddress = "192.168.8.xxx";
    wifiIpAddress = "192.168.8.xxx";
    nameServers = [ "192.168.8.1" "192.168.8.1" ];
    resolvedEnable = false;

    # NFS disabled for this laptop
    nfsClientEnable = false;
    nfsMounts = [
      # Old mounts commented or kept for reference
    ];

    # Backups disabled
    homeBackupEnable = false;

    # Printer
    servicePrinting = false;
    networkPrinters = false;

    # Fonts override
    fonts = [
      pkgs.nerdfonts
      pkgs.powerline
    ];

    # System packages
    systemPackages = pkgs: pkgs-unstable: [
      pkgs.vim pkgs.wget pkgs.nmap pkgs.zsh pkgs.git
      pkgs.cryptsetup pkgs.tldr pkgs.rsync pkgs.nfs-utils
      pkgs.restic pkgs.qt5.qtbase
      pkgs-unstable.sunshine
    ];

    # Features
    sunshineEnable = false;
  };

  userSettings = base.userSettings // {
    theme = "io";  # Different theme for YOGAAKU
    email = "";

    dockerEnable = false;
    virtualizationEnable = true;
    qemuGuestAddition = true;

    homePackages = pkgs: pkgs-unstable: [
      pkgs.zsh pkgs.kitty pkgs.git pkgs.syncthing
      pkgs-unstable.ungoogled-chromium
      pkgs-unstable.vscode
      pkgs-unstable.logseq
      pkgs-unstable.nextcloud-client
      pkgs-unstable.wireguard-tools
      pkgs-unstable.bitwarden-desktop
      pkgs-unstable.moonlight-qt
      pkgs-unstable.discord
      pkgs-unstable.kdePackages.kcalc
      pkgs-unstable.gnome-calculator
    ];

    zshinitContent = ''
      PROMPT=" ◉ %U%F{magenta}%n%f%u@%U%F{blue}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';
  };
}
```

### 2.4 Verification

```bash
# Test all builds
nix flake check --no-build
nixos-rebuild build --flake .#DESK
nixos-rebuild build --flake .#LAPTOP
nixos-rebuild build --flake .#YOGAAKU

# Apply to DESK (you're testing from DESK)
sudo nixos-rebuild switch --flake .#DESK
```

---

## Phase 3: Update DESK and AGADESK with Desktop Flag

### 3.1 Update DESK-config.nix

Add to systemSettings:
```nix
enableDesktopPerformance = true;
```

### 3.2 Update AGADESK-config.nix

Add to systemSettings:
```nix
enableDesktopPerformance = true;
```

### 3.3 Verification

```bash
nixos-rebuild build --flake .#DESK
nixos-rebuild build --flake .#AGADESK

# Apply to DESK
sudo nixos-rebuild switch --flake .#DESK
```

---

## Implementation Order

```
Phase 1: Refactor hostname checks to flags
├── 1.1 Add flags to lib/defaults.nix
├── 1.2 Refactor io-scheduler.nix
├── 1.3 Refactor performance.nix
├── 1.4 Add enableDesktopPerformance to DESK-config.nix
├── 1.5 Add enableDesktopPerformance to AGADESK-config.nix
├── 1.6 Test DESK build & switch
└── 1.7 Git commit

Phase 2: Create LAPTOP-base.nix structure
├── 2.1 Create profiles/LAPTOP-base.nix
├── 2.2 Refactor LAPTOP-config.nix to import base
├── 2.3 Refactor YOGAAKU-config.nix to import base
├── 2.4 Test LAPTOP build
├── 2.5 Test YOGAAKU build
└── 2.6 Git commit

Phase 3: Final verification
├── 3.1 Test all profiles build
├── 3.2 Apply to DESK (current machine)
├── 3.3 Test Sway works on DESK
└── 3.4 Git commit (ready for laptop testing)
```

---

## Files to Modify/Create Summary

| File | Action | Phase |
|------|--------|-------|
| lib/defaults.nix | ADD flags | 1 |
| system/hardware/io-scheduler.nix | MODIFY | 1 |
| system/hardware/performance.nix | MODIFY | 1 |
| profiles/DESK-config.nix | ADD flag | 1 |
| profiles/AGADESK-config.nix | ADD flag | 1 |
| profiles/LAPTOP-base.nix | CREATE | 2 |
| profiles/LAPTOP-config.nix | REFACTOR | 2 |
| profiles/YOGAAKU-config.nix | REFACTOR | 2 |

---

## Rollback Strategy

```bash
# If anything breaks
git stash  # or git reset --hard HEAD~1

# Rebuild with previous config
sudo nixos-rebuild switch --flake .#DESK
```

---

## Success Criteria

- [ ] DESK builds and boots with `enableDesktopPerformance = true`
- [ ] LAPTOP builds with inherited base + Sway enabled
- [ ] YOGAAKU builds with inherited base
- [ ] No hostname checks remain in io-scheduler.nix and performance.nix
- [ ] Ananicy running on DESK
- [ ] Sway accessible from DESK login screen
