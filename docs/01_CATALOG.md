⚠️ **AUTO-GENERATED**: Do not edit manually. Regenerate with `python3 scripts/generate_docs_index.py`

# Documentation Catalog

This catalog provides a hierarchical navigation tree for AI context retrieval.
Prefer routing via `docs/00_ROUTER.md`, then consult this file if you need the full listing.

## Flake Architecture

- **flake.nix**: Main flake entry point defining inputs and outputs
- **lib/flake-base.nix**: Base flake module shared by all profiles
- **lib/defaults.nix**: Default system and user settings
- **flake.AGA.nix**: Profile-specific flake configuration
- **flake.AGADESK.nix**: Profile-specific flake configuration
- **flake.DESK.nix**: Profile-specific flake configuration
- **flake.HOME.nix**: Profile-specific flake configuration
- **flake.LAPTOP.nix**: Profile-specific flake configuration
- **flake.ORIGINAL.nix**: Profile-specific flake configuration
- **flake.VMDESK.nix**: Profile-specific flake configuration
- **flake.VMHOME.nix**: Profile-specific flake configuration
- **flake.WSL.nix**: Profile-specific flake configuration
- **flake.YOGAAKU.nix**: Profile-specific flake configuration
- **flake.nix**: Profile-specific flake configuration

## Profiles

- **profiles/AGA-config.nix**: AGA Profile Configuration
- **profiles/AGADESK-config.nix**: AGADESK Profile Configuration
- **profiles/DESK-config.nix**: DESK Profile Configuration
- **profiles/HOME-config.nix**: HOME Profile Configuration
- **profiles/LAPTOP-config.nix**: LAPTOP Profile Configuration
- **profiles/VMDESK-config.nix**: VMDESK Profile Configuration
- **profiles/VMHOME-config.nix**: VMHOME Profile Configuration
- **profiles/WSL-config.nix**: WSL Profile Configuration
- **profiles/YOGAAKU-config.nix**: YOGAAKU Profile Configuration

## System Modules

### App

- **system/app/appimage.nix**: System module: appimage.nix
- **system/app/docker.nix**: Allow dockerd to be restarted without affecting running container. *Enabled when:* `userSettings.dockerEnable == true`
- **system/app/flatpak.nix**: Need some flatpaks
- **system/app/gamemode.nix**: Feral GameMode *Enabled when:* `systemSettings.gamemodeEnable == true`
- **system/app/grafana.nix**: environment.etc."nginx/certs/akunito.org.es.cert".source = /home/akunito/.nginx/nginx-certs/akunito.org.es.crt;
- **system/app/prismlauncher.nix**: System module: prismlauncher.nix
- **system/app/samba.nix**: System module: samba.nix
- **system/app/starcitizen.nix**: To install the launcher, use flatpak instructions:
- **system/app/steam.nix**: hardware.graphics.enable32Bit = true; # already in opengl.nix
- **system/app/virtualization.nix**: Virt-manager doc > https://nixos.wiki/wiki/Virt-manager *Enabled when:*
   - `userSettings.virtualizationEnable == true`
   - `userSettings.qemuGuestAddition == true`

### Bin

- **system/bin/phoenix.nix**: TODO make this work on nix-on-droid!

### Dm

- **system/dm/sddm.nix**: KWallet PAM integration for automatic wallet unlocking on login *Enabled when:* `primary for graphical sessions`

### Hardware

- **system/hardware/bluetooth.nix**: hardware.bluetooth.enable = true;
- **system/hardware/drives.nix**: Enable SSH server to unlock LUKS drives on BOOT *Enabled when:*
   - `systemSettings.bootSSH == true`
   - `systemSettings.disk1_enabled`
   - `systemSettings.disk2_enabled`
   - `systemSettings.disk3_enabled`
   - `systemSettings.disk4_enabled`
   - `systemSettings.disk5_enabled`
   - `systemSettings.disk6_enabled`
   - `systemSettings.disk7_enabled`
- **system/hardware/gpu-monitoring.nix**: GPU Monitoring Packages based on GPU type *Enabled when:*
   - `systemSettings.gpuType == "amd"`
   - `systemSettings.gpuType == "intel"`
   - `systemSettings.gpuType != "amd" && systemSettings.gpuType != "intel"`
- **system/hardware/io-scheduler.nix**: Consolidated I/O scheduler optimization for all profile types *Enabled when:*
   - `systemSettings.hostname == "nixosaku" || systemSettings.hostname == "nixosaga"`
   - `systemSettings.hostname == "nixolaptopaku" || systemSettings.hostname == "yogaaku"`
   - `systemSettings.profile == "homelab"`
- **system/hardware/kernel.nix**: System module: kernel.nix
- **system/hardware/keychron.nix**: Grant access to Keychron keyboards for the Keychron Launcher / VIA
- **system/hardware/nfs_client.nix**: You need to install pkgs.nfs-utils *Enabled when:* `systemSettings.nfsClientEnable == true`
- **system/hardware/nfs_server.nix**: NFS *Enabled when:* `systemSettings.nfsServerEnable == true`
- **system/hardware/opengl.nix**: OpenGL (renamed to graphics) *Enabled when:* `systemSettings.amdLACTdriverEnable == true`
- **system/hardware/performance.nix**: Consolidated performance optimizations for all profile types *Enabled when:*
   - `systemSettings.hostname == "nixosaku" || systemSettings.hostname == "nixosaga"`
   - `systemSettings.hostname == "nixolaptopaku" || systemSettings.hostname == "yogaaku"`
   - `systemSettings.profile == "homelab"`
- **system/hardware/power.nix**: Overriding to disable power-profiles-daemon *Enabled when:*
   - `systemSettings.TLP_ENABLE == true`
   - `systemSettings.LOGIND_ENABLE == true`
   - `systemSettings.iwlwifiDisablePowerSave == true`
- **system/hardware/printing.nix**: https://nixos.wiki/wiki/Printing *Enabled when:*
   - `systemSettings.servicePrinting == true`
   - `systemSettings.networkPrinters == true`
   - `systemSettings.sharePrinter == true`
- **system/hardware/systemd.nix**: System module: systemd.nix
- **system/hardware/time.nix**: System module: time.nix
- **system/hardware/xbox.nix**: NOTE you might need to add xpad as Kernel Module on your flake.nix

### Hardware-Configuration.Nix

- **system/hardware-configuration.nix**: Do not modify this file!  It was generated by ‘nixos-generate-config’

### Security

- **system/security/automount.nix**: System module: automount.nix
- **system/security/autoupgrade.nix**: ====================== Auto System Update ====================== *Enabled when:*
   - `systemSettings.autoSystemUpdateEnable == true`
   - `systemSettings.autoUserUpdateEnable == true`
- **system/security/blocklist.nix**: networking.extraHosts = ''
- **system/security/fail2ban.nix**: Global settings
- **system/security/firejail.nix**: prismlauncher = {
- **system/security/firewall.nix**: Firewall settings
- **system/security/firewallBasic.nix**: Firewall
- **system/security/gpg.nix**: Some programs need SUID wrappers, can be configured further or are
- **system/security/openvpn.nix**: System module: openvpn.nix
- **system/security/polkit.nix**: System module: polkit.nix
- **system/security/restic.nix**: ====================== Wrappers ====================== *Enabled when:*
   - `systemSettings.resticWrapper == true`
   - `systemSettings.homeBackupEnable == true`
   - `systemSettings.remoteBackupEnable == true`
- **system/security/sshd.nix**: Enable incoming ssh
- **system/security/sudo.nix**: groups = [ "wheel" ]; *Enabled when:*
   - `systemSettings.sudoNOPASSWD == true`
   - `systemSettings.wrappSudoToDoas == true`

### Style

- **system/style/stylix.nix**: Use JetBrainsMono Nerd Font instead of userSettings.font (Intel One Mono) which is not available

### Wm

- **system/wm/dbus.nix**: System module: dbus.nix
- **system/wm/fonts.nix**: Fonts are nice to have
- **system/wm/gnome-keyring.nix**: System module: gnome-keyring.nix
- **system/wm/hyprland.nix**: Import wayland config
- **system/wm/keyd.nix**: Enable keyd service for keyboard remapping *Enabled when:* `userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true || userSettings.wm == "plasma6" || userSettings.wm == "hyprland" || (systemSettings ? wmEnableHyprland && systemSettings.wmEnableHyprland == true)`
- **system/wm/pipewire.nix**: Pipewire
- **system/wm/plasma6.nix**: CRITICAL: imports must be at top level, NOT inside lib.mkMerge or lib.mkIf *Enabled when:*
   - `KWallet PAM`
   - `userSettings.wm == "plasma6" || systemSettings.enableSwayForDESK == true`
   - `userSettings.wm == "plasma6"`
   - `(userSettings.wm == "plasma6" || systemSettings.enableSwayForDESK == true) && systemSettings.hostname == "nixosaku"`
   - `systemSettings.hostname == "nixosaku"`
- **system/wm/sway.nix**: Import shared dependencies *Enabled when:* `userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true`
- **system/wm/wayland.nix**: environment.systemPackages = with pkgs;
- **system/wm/x11.nix**: Configure X11
- **system/wm/xmonad.nix**: import X11 config

## User Modules

### App

- **user/app/ai/aichat.nix**: Aichat Configuration for OpenRouter
- **user/app/browser/brave.nix**: Module installing brave as default browser
- **user/app/browser/floorp.nix**: Module installing  as default browser
- **user/app/browser/librewolf.nix**: Module installing librewolf as default browser
- **user/app/browser/qute-containers.nix**: User module: qute-containers.nix
- **user/app/browser/qutebrowser.nix**: bindings from doom emacs
- **user/app/browser/vivaldi.nix**: Wrapper for Vivaldi to force KWallet 6 password store
- **user/app/dmenu-scripts/networkmanager-dmenu.nix**: gui_if_available = <True or False> (Default: True)
- **user/app/doom-emacs/doom.nix**: This block from https://github.com/znewman01/dotfiles/blob/be9f3a24c517a4ff345f213bf1cf7633713c9278/emacs/default.nix#L12-L34
- **user/app/flatpak/flatpak.nix**: services.flatpak.enable = true;
- **user/app/games/games.nix**: Games
- **user/app/gaming/mangohud.nix**: MangoHud Configuration
- **user/app/git/git.nix**: https://nixos.wiki/wiki/Git
- **user/app/keepass/keepass.nix**: nixpkgs.overlays = [
- **user/app/lmstudio/lmstudio.nix**: LM Studio Module
- **user/app/ranger/ranger.nix**: this lets my copy and paste images and/or plaintext of files directly out of ranger
- **user/app/terminal/alacritty.nix**: Explicitly install JetBrains Mono Nerd Font to ensure it's available *Enabled when:* `systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)`
- **user/app/terminal/fix-terminals.nix**: Python script to configure VS Code and Cursor terminal keybindings
- **user/app/terminal/kitty.nix**: Explicitly install JetBrains Mono Nerd Font to ensure it's available *Enabled when:* `systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)`
- **user/app/terminal/tmux.nix**: Note: Custom menu is implemented via display-menu in extraConfig (bind ?)
- **user/app/virtualization/virtualization.nix**: Various packages related to virtualization, compatability and sandboxing *Enabled when:* `userSettings.virtualizationEnable == true`

### Hardware

- **user/hardware/bluetooth.nix**: User module: bluetooth.nix

### Lang

- **user/lang/android/android.nix**: Android
- **user/lang/cc/cc.nix**: CC
- **user/lang/godot/godot.nix**: Gamedev
- **user/lang/haskell/haskell.nix**: Haskell
- **user/lang/python/python-packages.nix**: Python packages
- **user/lang/python/python.nix**: Python setup
- **user/lang/rust/rust.nix**: Rust setup

### Pkgs

- **user/pkgs/pokemon-colorscripts.nix**: User module: pokemon-colorscripts.nix
- **user/pkgs/ranger.nix**: give image previews out of the box when building with w3m
- **user/pkgs/rogauracore.nix**: THIS DOES NOT WORK YET!

### Shell

- **user/shell/cli-collection.nix**: Collection of useful CLI apps
- **user/shell/sh.nix**: My shell aliases

### Style

- **user/style/stylix.nix**: CRITICAL: Remove trailing newline from URL and SHA256 to prevent malformed URLs *Enabled when:*
   - `userSettings.wm != "plasma6"`
   - `userSettings.wm == "plasma6" && systemSettings.enableSwayForDESK == false`
   - `userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == false`

### Wm

- **user/wm/hyprland/hyprland.nix**: toolkit-specific scale
- **user/wm/hyprland/hyprland_noStylix.nix**: toolkit-specific scale
- **user/wm/hyprland/hyprprofiles/hyprprofiles.nix**: !/bin/sh
- **user/wm/input/nihongo.nix**: Enumerate when press trigger key repeatedly
- **user/wm/picom/picom.nix**: User module: picom.nix
- **user/wm/plasma6/plasma6.nix**: ++ lib.optional userSettings.wmEnableHyprland (./. + "/../hyprland/hyprland_noStylix.nix")
- **user/wm/sway/debug-qt5ct.nix**: Debug logging function for NDJSON format
- **user/wm/sway/debug-relog.nix**: Keep logging implementation centralized via existing helper script.
- **user/wm/sway/default.nix**: Import debugging utilities *Enabled when:*
   - `programs.waybar.systemd.enable = true`
   - `ExecStart is required`
   - `like Unit.Description / ExecStart`
   - `wl-paste`
   - `Qt6`
   - `useSystemdSessionDaemons && ( lib.hasInfix "laptop" (lib.toLower systemSettings.hostname) || lib.hasInfix "yoga" (lib.toLower systemSettings.hostname) )`
   - `useSystemdSessionDaemons && systemSettings.sunshineEnable == true`
   - `useSystemdSessionDaemons && systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)`
   - `systemSettings.stylixEnable == true`
   - `systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)`
- **user/wm/sway/rofi.nix**: Theme content (Stylix or fallback)
- **user/wm/sway/sway.nix**: User module: sway.nix
- **user/wm/sway/waybar.nix**: Helper function to convert hex color + alpha to rgba()
- **user/wm/xmonad/xmonad.nix**: User module: xmonad.nix

## Documentation

### Future

- **docs/future/README.md**: This directory contains temporary documentation for planning, analysis, design ideas, recommendations, bug fixes, and other topics that are under consideration and may be deleted after implementati...
- **docs/future/debug-instrumentation-analysis.md**: **Date**: 2026-01-XX
- **docs/future/debug-instrumentation-removal-plan.md**: **Date**: 2026-01-XX
- **docs/future/fix-home-manager-deprecated-install-warning.md**: During home-manager activation, you see this warning:
- **docs/future/fix-mnt-ext-mount-error.md**: The error occurs during NixOS configuration switch when systemd tries to stop `mnt-EXT.mount` from the previous generation, but the unit doesn't exist in the new generation (because we disabled dis...
- **docs/future/flake-refactoring-migration.md**: The flake profile refactoring has been successfully implemented to eliminate code duplication across multiple `flake.*.nix` files. The new structure reduces each profile file from ~750 lines to ~30...
- **docs/future/flake-scalability-analysis.md**: **Date**: 2025-01-XX
- **docs/future/improvements-analysis.md**: **Date**: 2025-01-XX
- **docs/future/improvements-implemented.md**: **Date**: 2025-01-XX
- **docs/future/improvements-summary.md**: **Date**: 2025-01-XX
- **docs/future/migration-verification-results.md**: **Date**: 2025-01-02
- **docs/future/profile-migration-status.md**: **Date**: 2025-01-02
- **docs/future/router-drift-audit-2026-01-08.md**: Audit findings for Router/Catalog doc drift vs current repo state (install.sh + Sway daemon system).
- **docs/future/sov-crash-analysis.md**: **Date**: 2026-01-07
- **docs/future/sov-dependency-analysis.md**: **Date**: 2026-01-07
- **docs/future/sway-daemon-relog-notes-2026-01-08.md**: This document captures **runtime observations** and **log evidence** from debugging the SwayFX daemon integration system on **NixOS**.
- **docs/future/vmhome-migration-test.md**: **Date**: 2025-01-XX
- **docs/future/waybar-sov-debug-analysis.md**: **Date**: 2026-01-07

### Hardware

- **docs/hardware/cpu-power-management.md**: Complete guide to CPU frequency governors and power management.
- **docs/hardware/drive-management.md**: Complete guide to managing drives, LUKS encryption, and automatic mounting.
- **docs/hardware/gpu-monitoring.md**: Complete guide to GPU monitoring tools and their configuration for different GPU types.

### Keybindings

- **docs/keybindings/hyprland.md**: Complete reference for all Hyprland keybindings in this NixOS configuration.
- **docs/keybindings/sway.md**: Complete reference for all SwayFX keybindings in this NixOS configuration.

- **docs/00_INDEX.md**: ⚠️ **AUTO-GENERATED**: Do not edit manually. Regenerate with `python3 scripts/generate_docs_index.py`
- **docs/00_ROUTER.md**: ⚠️ **AUTO-GENERATED**: Do not edit manually. Regenerate with `python3 scripts/generate_docs_index.py`
- **docs/01_CATALOG.md**: ⚠️ **AUTO-GENERATED**: Do not edit manually. Regenerate with `python3 scripts/generate_docs_index.py`
- **docs/agent-context.md**: How this repo manages AI agent context (Router/Catalog + Cursor rules + AGENTS.md) and a reusable template for other projects.
- **docs/configuration.md**: Complete guide to understanding and customizing the NixOS configuration system.
- **docs/hardware.md**: Complete guide to hardware-specific configurations and optimizations.
- **docs/installation.md**: Complete guide for installing and setting up this NixOS configuration repository.
- **docs/keybindings.md**: Complete reference for all keybindings across window managers and applications in this NixOS configuration.
- **docs/maintenance.md**: Complete guide to maintaining your NixOS configuration and using the provided scripts.
- **docs/patches.md**: Guide to understanding and using Nixpkgs patches in this configuration.
- **docs/profiles.md**: Guide to understanding and using system profiles in this NixOS configuration.
- **docs/scripts.md**: Complete reference for all shell scripts in this repository.
- **docs/security.md**: Complete guide to security configurations and features in this NixOS setup.
- **docs/system-modules.md**: Complete reference for system-level NixOS modules in this configuration.
- **docs/themes.md**: Complete guide to the theming system and available themes.
- **docs/user-modules.md**: Complete reference for user-level Home Manager modules in this configuration.

### Security

- **docs/security/luks-encryption.md**: Complete guide to setting up LUKS disk encryption with SSH remote unlock capability.
- **docs/security/polkit.md**: Guide to configuring Polkit for fine-grained permission management.
- **docs/security/restic-backups.md**: Complete guide to setting up and configuring automated backups using Restic.
- **docs/security/sudo.md**: Guide to configuring sudo for remote SSH connections and specific commands.

### User-Modules

- **docs/user-modules/doom-emacs.md**: Doom Emacs user module and config layout, including Stylix theme templates and profile integration.
- **docs/user-modules/lmstudio.md**: LM Studio user module, including MCP server setup templates and web-search tooling integration guidance.
- **docs/user-modules/picom.md**: Picom compositor module overview and where its config and Nix module live.
- **docs/user-modules/plasma6.md**: Plasma 6 configuration integration for NixOS/Home Manager with export/import and symlink-based mutability.
- **docs/user-modules/ranger.md**: Ranger TUI file manager module overview, keybindings, and where configuration lives in this repo.
- **docs/user-modules/sway-daemon-integration.md**: Sway session services are managed via systemd --user units bound to sway-session.target (official/systemd approach; no custom daemon-manager).
- **docs/user-modules/sway-to-hyprland-migration.md**: Guide to replicate SwayFX workspace and window management semantics in Hyprland using scripts and conventions.
- **docs/user-modules/xmonad.md**: XMonad tiling window manager module overview, auxiliary tools, and config layout in this repo.
