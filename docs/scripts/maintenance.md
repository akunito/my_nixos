---
id: scripts.maintenance
summary: Maintenance and automated update scripts — maintenance.sh, autoSystemUpdate.sh, autoUserUpdate.sh
tags: [scripts, maintenance, cleanup, garbage-collection, automation]
related_files: [maintenance.sh, autoSystemUpdate.sh, autoUserUpdate.sh]
date: 2026-02-15
status: published
---

# Maintenance Scripts

## maintenance.sh

**Purpose**: Automated system maintenance and cleanup.

**Usage**:
```sh
./maintenance.sh [-s|--silent]
```

**Options**:
- `-s, --silent` - Run all tasks silently without menu

**What It Does**:
1. **System Generations Cleanup**: Keeps last 6 generations (count-based), removes older
2. **Home Manager Generations Cleanup**: Keeps last 4 generations (count-based), removes older
3. **User Generations Cleanup**: Removes generations older than 15 days (time-based)
4. **Garbage Collection**: Collects unused Nix store entries orphaned by generation deletion

**Configuration**:
```sh
SystemGenerationsToKeep=6      # Keep last 6 system generations (count-based: +N)
HomeManagerGenerationsToKeep=4 # Keep last 4 home-manager generations (count-based: +N)
UserGenerationsKeepOnlyOlderThan="15d"  # Delete user generations older than 15 days (time-based: Nd)
```

**Logging**: All actions logged to `maintenance.log` with timestamps. Includes summary statistics.

**Interactive Menu**:
- `1` - Run all tasks
- `2` - Prune system generations (Keep last 6)
- `3` - Prune home-manager generations (Keep last 4)
- `4` - Remove user generations older than 15d
- `5` - Run garbage collection
- `Q` - Quit

**Note**: The script must be run as a normal user (not root). It uses `sudo` internally when needed.

### Sudo prompt behavior (DESK + LAPTOP)

On DESK and LAPTOP profiles, sudo is configured to keep the authentication timestamp cached longer (3 hours) to reduce repeated password prompts during long maintenance / install operations.

## autoSystemUpdate.sh

**Purpose**: Automated system update script for SystemD timers.

**Usage**: Designed to be called by SystemD timer

**What It Does**:
1. Updates flake.lock (`update.sh`)
2. Rebuilds system (`nixos-rebuild switch`)
3. Runs maintenance script silently (`maintenance.sh -s`)

**Requirements**: Must run as root

**Example SystemD Timer**:
```nix
systemd.timers.auto-system-update = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};

systemd.services.auto-system-update = {
  serviceConfig.Type = "oneshot";
  script = ''
    ${pkgs.bash}/bin/bash ${./autoSystemUpdate.sh} $DOTFILES_DIR
  '';
};
```

## autoUserUpdate.sh

**Purpose**: Automated user/home-manager update script for SystemD timers.

**Usage**: Designed to be called by SystemD timer

**What It Does**:
- Updates Home Manager configuration
- Uses `nix run home-manager/master` with experimental features

**Requirements**: Must run as regular user (not root)

**Example SystemD Timer**:
```nix
systemd.timers.auto-user-update = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};

systemd.services.auto-user-update = {
  serviceConfig = {
    Type = "oneshot";
    User = "username";
  };
  script = ''
    ${pkgs.bash}/bin/bash ${./autoUserUpdate.sh} $DOTFILES_DIR
  '';
};
```
