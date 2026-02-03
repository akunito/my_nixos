⚠️ **AUTO-GENERATED**: Do not edit manually. Regenerate with `python3 scripts/generate_docs_index.py`

# Documentation Catalog

This catalog provides a hierarchical navigation tree for AI context retrieval.
Prefer routing via `docs/00_ROUTER.md`, then consult this file if you need the full listing.

## Flake Architecture

- **flake.nix**: Main flake entry point defining inputs and outputs
- **lib/flake-base.nix**: Base flake module shared by all profiles
- **lib/defaults.nix**: Default system and user settings
- **flake.DESK.nix**: Profile-specific flake configuration
- **flake.HOME.nix**: Profile-specific flake configuration
- **flake.VMHOME.nix**: Profile-specific flake configuration
- **flake.WSL.nix**: Profile-specific flake configuration
- **flake.LXC.nix**: Profile-specific flake configuration
- **flake.LXC_plane.nix**: Profile-specific flake configuration
- **flake.ORIGINAL.nix**: Profile-specific flake configuration
- **flake.DESK_AGA.nix**: Profile-specific flake configuration
- **flake.DESK_VMDESK.nix**: Profile-specific flake configuration
- **flake.LAPTOP_L15.nix**: Profile-specific flake configuration
- **flake.LAPTOP_YOGAAKU.nix**: Profile-specific flake configuration
- **flake.LAPTOP_AGA.nix**: Profile-specific flake configuration
- **flake.LXC_HOME.nix**: Profile-specific flake configuration
- **flake.LXC_liftcraftTEST.nix**: Profile-specific flake configuration
- **flake.LXC_portfolioprod.nix**: Profile-specific flake configuration
- **flake.LXC_mailer.nix**: Profile-specific flake configuration
- **flake.LXC_monitoring.nix**: Profile-specific flake configuration
- **flake.LXC_proxy.nix**: Profile-specific flake configuration
- **flake.nix**: Profile-specific flake configuration

## Profiles

- **profiles/DESK-config.nix**: DESK Profile Configuration
- **profiles/DESK_AGA-config.nix**: DESK_AGA Profile Configuration (nixosaga)
- **profiles/DESK_VMDESK-config.nix**: DESK_VMDESK Profile Configuration (nixosdesk)
- **profiles/LAPTOP_AGA-config.nix**: LAPTOP_AGA Profile Configuration (nixosaga)
- **profiles/LAPTOP_L15-config.nix**: LAPTOP Profile Configuration (nixolaptopaku)
- **profiles/LAPTOP_YOGAAKU-config.nix**: YOGAAKU Profile Configuration
- **profiles/LXC-base-config.nix**: LXC Base Profile Configuration
- **profiles/LXC_HOME-config.nix**: LXC_HOME Profile Configuration
- **profiles/LXC_liftcraftTEST-config.nix**: LXC liftcraftTEST Profile Configuration
- **profiles/LXC_mailer-config.nix**: LXC mailer Profile Configuration
- **profiles/LXC_monitoring-config.nix**: LXC_monitoring Profile Configuration
- **profiles/LXC_plane-config.nix**: LXC Default Profile Configuration
- **profiles/LXC_portfolioprod-config.nix**: LXC portfolioprod Profile Configuration
- **profiles/LXC_proxy-config.nix**: LXC_proxy Profile Configuration
- **profiles/VMHOME-config.nix**: VMHOME Profile Configuration
- **profiles/WSL-config.nix**: WSL Profile Configuration

## System Modules

### App

- **system/app/appimage.nix**: System module: appimage.nix
- **system/app/cloudflared.nix**: Cloudflare Tunnel Service (Remotely Managed) *Enabled when:* `systemSettings.cloudflaredEnable or false`
- **system/app/docker.nix**: Allow dockerd to be restarted without affecting running container. *Enabled when:* `userSettings.dockerEnable == true`
- **system/app/flatpak.nix**: Need some flatpaks
- **system/app/gamemode.nix**: Feral GameMode *Enabled when:* `systemSettings.gamemodeEnable == true`
- **system/app/grafana.nix**: Grafana & Prometheus Monitoring Stack
- **system/app/homelab-docker.nix**: Homelab Docker Stacks - Systemd service to start docker-compose stacks on boot *Enabled when:* `systemSettings.homelabDockerEnable or false`
- **system/app/portals.nix**: XDG Desktop Portal Configuration
- **system/app/prismlauncher.nix**: System module: prismlauncher.nix
- **system/app/prometheus-blackbox.nix**: Blackbox Exporter for HTTP/HTTPS probes, ICMP ping checks, and TLS certificate monitoring *Enabled when:*
   - `systemSettings.prometheusBlackboxEnable or false`
   - `tlsTargets != [] || httpTargets != []`
- **system/app/prometheus-exporters.nix**: Prometheus Exporters Module *Enabled when:*
   - `systemSettings.prometheusExporterEnable or false`
   - `systemSettings.prometheusExporterCadvisorEnable or false`
- **system/app/prometheus-graphite.nix**: Graphite Exporter for TrueNAS Metrics *Enabled when:* `systemSettings.prometheusGraphiteEnable or false`
- **system/app/prometheus-pve.nix**: Proxmox VE Exporter for VM/container metrics *Enabled when:* `systemSettings.prometheusPveExporterEnable or false`
- **system/app/prometheus-snmp.nix**: SNMP Exporter for pfSense and network devices *Enabled when:* `systemSettings.prometheusSnmpExporterEnable or false`
- **system/app/proton.nix**: Only applying the overlay to fix Bottles warning globally (system-wide) *Enabled when:* `userSettings.protongamesEnable == true`
- **system/app/samba.nix**: System module: samba.nix
- **system/app/starcitizen.nix**: Kernel tweaks for Star Citizen (system-level requirement) *Enabled when:* `userSettings.starcitizenEnable == true`
- **system/app/steam.nix**: Steam configuration *Enabled when:* `userSettings.steamPackEnable == true`
- **system/app/virtualization.nix**: Virt-manager doc > https://nixos.wiki/wiki/Virt-manager *Enabled when:*
   - `userSettings.virtualizationEnable == true`
   - `userSettings.qemuGuestAddition == true`

### Bin

- **system/bin/aku.nix**: TODO make this work on nix-on-droid!

### Dm

- **system/dm/sddm-breeze-patched-theme.nix**: Copy upstream Breeze SDDM theme from Plasma Desktop
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
   - `better than none for modern NVMe`
   - `same as desktop - good for interactive workloads`
   - `systemSettings.profile == "homelab"`
- **system/hardware/kernel.nix**: System module: kernel.nix
- **system/hardware/keychron.nix**: Grant access to Keychron keyboards for the Keychron Launcher / VIA
- **system/hardware/nfs_client.nix**: You need to install pkgs.nfs-utils *Enabled when:* `systemSettings.nfsClientEnable == true`
- **system/hardware/nfs_server.nix**: NFS *Enabled when:* `systemSettings.nfsServerEnable == true`
- **system/hardware/opengl.nix**: OpenGL (renamed to graphics) *Enabled when:*
   - `systemSettings.gpuType == "amd"`
   - `systemSettings.amdLACTdriverEnable == true`
- **system/hardware/performance.nix**: Consolidated performance optimizations for all profile types *Enabled when:*
   - `desktop-optimized`
   - `battery-focused`
   - `systemSettings.profile == "homelab"`
- **system/hardware/power.nix**: Overriding to disable power-profiles-daemon *Enabled when:*
   - `systemSettings.TLP_ENABLE == true`
   - `systemSettings.LOGIND_ENABLE == true`
   - `systemSettings.iwlwifiDisablePowerSave == true`
- **system/hardware/printing.nix**: https://nixos.wiki/wiki/Printing *Enabled when:*
   - `systemSettings.servicePrinting == true`
   - `systemSettings.networkPrinters == true`
   - `systemSettings.sharePrinter == true`
- **system/hardware/systemd.nix**: Journald limits - prevent disk thrashing and limit log size
- **system/hardware/thinkpad.nix**: Lenovo Thinkpad hardware optimizations via nixos-hardware
- **system/hardware/time.nix**: System module: time.nix
- **system/hardware/xbox.nix**: NOTE you might need to add xpad as Kernel Module on your flake.nix

### Hardware-Configuration.Nix

- **system/hardware-configuration.nix**: Do not modify this file!  It was generated by ‘nixos-generate-config’

### Packages

- **system/packages/system-basic-tools.nix**: === Basic CLI Tools === *Enabled when:* `systemSettings.systemBasicToolsEnable or true`
- **system/packages/system-network-tools.nix**: === Networking Tools (Advanced) === *Enabled when:* `systemSettings.systemNetworkToolsEnable or false`

### Security

- **system/security/acme.nix**: ACME Certificate Management (Let's Encrypt) *Enabled when:* `systemSettings.acmeEnable or false`
- **system/security/automount.nix**: System module: automount.nix
- **system/security/autoupgrade.nix**: ====================== Auto System Update ====================== *Enabled when:*
   - `systemSettings.autoSystemUpdateEnable == true`
   - `systemSettings.notificationOnFailureEnable or false`
   - `systemSettings.autoUserUpdateEnable == true`
- **system/security/blocklist.nix**: networking.extraHosts = ''
- **system/security/fail2ban.nix**: Global settings
- **system/security/firejail.nix**: prismlauncher = {
- **system/security/firewall.nix**: Firewall settings
- **system/security/firewallBasic.nix**: Firewall
- **system/security/gpg.nix**: Some programs need SUID wrappers, can be configured further or are
- **system/security/openvpn.nix**: System module: openvpn.nix
- **system/security/polkit.nix**: System module: polkit.nix
- **system/security/restic.nix**: Script to export backup metrics for Prometheus textfile collector *Enabled when:*
   - `systemSettings.resticWrapper == true`
   - `systemSettings.homeBackupEnable == true`
   - `systemSettings.remoteBackupEnable == true`
   - `systemSettings.backupMonitoringEnable or false`
- **system/security/sshd.nix**: Enable incoming ssh
- **system/security/sudo.nix**: groups = [ "wheel" ]; *Enabled when:*
   - `systemSettings.sudoNOPASSWD == true`
   - `systemSettings.wrappSudoToDoas == true`
- **system/security/update-failure-notification.nix**: Email notification service for auto-update failures *Enabled when:* `systemSettings.notificationOnFailureEnable or false`

### Style

- **system/style/stylix.nix**: CRITICAL: Use "JetBrainsMono Nerd Font Mono" (the Mono variant) for terminals

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
   - `userSettings.wm == "plasma6" && !(systemSettings.enableSwayForDESK or false)`
   - `userSettings.wm == "plasma6"`
   - `(userSettings.wm == "plasma6" || systemSettings.enableSwayForDESK == true) && systemSettings.sddmBreezePatchedTheme`
   - `systemSettings.sddmSetupScript != null`
   - `(userSettings.wm == "plasma6" || systemSettings.enableSwayForDESK == true) && systemSettings.sddmSetupScript != null`
   - `systemSettings.hostname == "nixosaku"`
- **system/wm/sway.nix**: Import shared dependencies *Enabled when:*
   - `userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true`
   - `(userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) && systemSettings.gpuType == "amd"`
- **system/wm/wayland.nix**: environment.systemPackages = with pkgs;
- **system/wm/x11.nix**: Configure X11
- **system/wm/xmonad.nix**: import X11 config

## User Modules

### App

- **user/app/ai/aichat.nix**: Aichat Module
- **user/app/browser/brave.nix**: Module installing brave as default browser
- **user/app/browser/floorp.nix**: Module installing  as default browser
- **user/app/browser/librewolf.nix**: Module installing librewolf as default browser
- **user/app/browser/qute-containers.nix**: User module: qute-containers.nix
- **user/app/browser/qutebrowser.nix**: bindings from doom emacs
- **user/app/browser/vivaldi.nix**: Wrapper for Vivaldi to force KWallet 6 password store
- **user/app/development/development.nix**: Development tools and IDEs
- **user/app/dmenu-scripts/networkmanager-dmenu.nix**: gui_if_available = <True or False> (Default: True)
- **user/app/doom-emacs/doom.nix**: This block from https://github.com/znewman01/dotfiles/blob/be9f3a24c517a4ff345f213bf1cf7633713c9278/emacs/default.nix#L12-L34
- **user/app/file-manager/file-manager.nix**: File manager configuration module
- **user/app/flatpak/flatpak.nix**: services.flatpak.enable = true;
- **user/app/games/games.nix**: Conditional wrapper arguments for AMD GPUs to fix Vulkan driver discovery *Enabled when:* `userSettings.protongamesEnable == true`
- **user/app/gaming/mangohud.nix**: MangoHud Configuration
- **user/app/git/git.nix**: https://nixos.wiki/wiki/Git
- **user/app/keepass/keepass.nix**: nixpkgs.overlays = [
- **user/app/lmstudio/lmstudio.nix**: LM Studio Module
- **user/app/nixvim/nixvim.nix**: AI "Composer" Agent: Avante with OpenRouter
- **user/app/ranger/ranger.nix**: this lets my copy and paste images and/or plaintext of files directly out of ranger
- **user/app/swaybgplus/swaybgplus.nix**: !/bin/sh *Enabled when:* `systemSettings.swaybgPlusEnable or false`
- **user/app/swww/swww.nix**: !/bin/sh *Enabled when:*
   - `wallpaper backend for SwayFX`
   - `SwayFX`
   - `lib.hm.dag.entryAfter [ "reloadSystemd" ] '' RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" ENV_FILE="$RUNTIME_DIR/sway-session.env" if [ -r "$ENV_FILE" ]; then # shellcheck disable=SC1090 . "$ENV_FILE" fi if [ -n "''${SWAYSOCK:-}" ] && [ -S "''${SWAYSOCK:-}" ]; then ${pkgs.systemd}/bin/systemctl --user start swww-restore.service >/dev/null 2>&1 || true else CAND="$(ls -t "$RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n1 || true)" if [ -n "$CAND" ] && [ -S "$CAND" ]; then ${pkgs.systemd}/bin/systemctl --user start swww-restore.service >/dev/null 2>&1 || true fi fi ''`
- **user/app/terminal/alacritty.nix**: Wrapper script to auto-start tmux with alacritty session *Enabled when:* `systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)`
- **user/app/terminal/fix-terminals.nix**: Python script to configure VS Code and Cursor terminal keybindings
- **user/app/terminal/kitty.nix**: Wrapper script to auto-start tmux with kitty session *Enabled when:* `systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)`
- **user/app/terminal/tmux.nix**: ssh-smart script: reads hosts from .ssh/config and provides interactive selection
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

### Packages

- **user/packages/user-ai-pkgs.nix**: === AI & Machine Learning === *Enabled when:* `userSettings.userAiPkgsEnable or false`
- **user/packages/user-basic-pkgs.nix**: === Basic User Packages === *Enabled when:* `userSettings.userBasicPkgsEnable or true`

### Pkgs

- **user/pkgs/pokemon-colorscripts.nix**: User module: pokemon-colorscripts.nix
- **user/pkgs/ranger.nix**: give image previews out of the box when building with w3m
- **user/pkgs/rogauracore.nix**: THIS DOES NOT WORK YET!
- **user/pkgs/swaybgplus.nix**: NOTE: fetchFromGitHub hashes the *unpacked* content (like `nix store prefetch-file --unpack`).

### Shell

- **user/shell/cli-collection.nix**: Collection of useful CLI apps
- **user/shell/sh.nix**: Basic aliases that don't depend on external packages
- **user/shell/starship.nix**: Write starship.toml directly with proper Unicode escapes for Nerd Font icons

### Style

- **user/style/stylix.nix**: CRITICAL: Remove trailing newline from URL and SHA256 to prevent malformed URLs *Enabled when:*
   - `userSettings.wm != "plasma6"`
   - `userSettings.wm == "plasma6" && systemSettings.enableSwayForDESK == false`
   - `userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true`

### Wm

- **user/wm/hyprland/hyprland.nix**: toolkit-specific scale
- **user/wm/hyprland/hyprland_noStylix.nix**: toolkit-specific scale
- **user/wm/hyprland/hyprprofiles/hyprprofiles.nix**: !/bin/sh
- **user/wm/input/nihongo.nix**: Enumerate when press trigger key repeatedly
- **user/wm/picom/picom.nix**: User module: picom.nix
- **user/wm/plasma6/plasma6.nix**: ++ lib.optional userSettings.wmEnableHyprland (./. + "/../hyprland/hyprland_noStylix.nix")
- **user/wm/sway/debug-qt5ct.nix**: Debug logging function for NDJSON format
- **user/wm/sway/debug-relog.nix**: Keep logging implementation centralized via existing helper script.
- **user/wm/sway/debug/relog-instrumentation.nix**: NDJSON sink for this repo (debug-mode compatible).
- **user/wm/sway/default.nix**: Internal cross-module wiring (kept minimal).
- **user/wm/sway/extras.nix**: Btop theme configuration (Stylix colors) *Enabled when:* `systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)`
- **user/wm/sway/kanshi.nix**: Official/standard dynamic output configuration for Sway/SwayFX (wlroots): kanshi. *Enabled when:* `wlroots`
- **user/wm/sway/rofi.nix**: Theme content (Stylix or fallback)
- **user/wm/sway/session-env.nix**: Script to sync theme variables with D-Bus activation environment
- **user/wm/sway/session-systemd.nix**: Volume/brightness OSD (matches Hyprland behavior) *Enabled when:*
   - `lib.hasInfix "laptop" (lib.toLower systemSettings.hostname) || lib.hasInfix "yoga" (lib.toLower systemSettings.hostname)`
   - `systemSettings.sunshineEnable == true`
   - `systemSettings.stylixEnable == true && (systemSettings.swaybgPlusEnable or false) != true && (systemSettings.swwwEnable or false) != true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)`
   - `systemSettings.nextcloudEnable == true`
- **user/wm/sway/startup-apps.nix**: CRITICAL: Restore qt5ct files on Sway startup to ensure correct content
- **user/wm/sway/sway.nix**: User module: sway.nix
- **user/wm/sway/swayfx-config.nix**: Hyper key combination (Super+Ctrl+Alt) *Enabled when:*
   - `systemSettings.stylixEnable == true`
   - `systemSettings.gamemodeEnable == true`
- **user/wm/sway/waybar.nix**: Some GPU tooling is optional depending on hardware / nixpkgs settings.
- **user/wm/xmonad/xmonad.nix**: User module: xmonad.nix

## Documentation

### Future

- **docs/future/README.md**: This directory contains temporary documentation for planning, analysis, design ideas, recommendations, bug fixes, and other topics that are under consideration and may be deleted after implementati...
- **docs/future/aga-to-laptop-base-migration-plan.md**: This document outlines the plan to migrate AGA from a standalone profile under Personal Profile to inherit from LAPTOP-base.nix, following the same pattern as LAPTOP_L15 and LAPTOP_YOGAAKU.
- **docs/future/agadesk-to-desk-inheritance-plan.md**: This document outlines the plan to migrate AGADESK from a standalone profile under Personal Profile to inherit from DESK-config.nix, following the same pattern as LAPTOP profiles inherit from LAPTO...
- **docs/future/debug-instrumentation-analysis.md**: **Date**: 2026-01-XX
- **docs/future/debug-instrumentation-removal-plan.md**: **Date**: 2026-01-XX
- **docs/future/desk-to-laptop-migration-improved.md**: **Status: IMPLEMENTED** (2026-01-28)
- **docs/future/desk-vs-laptop-packages.md**: Complete package and feature comparison between DESK and LAPTOP_L15 profiles
- **docs/future/fix-home-manager-deprecated-install-warning.md**: During home-manager activation, you see this warning:
- **docs/future/fix-mnt-ext-mount-error.md**: The error occurs during NixOS configuration switch when systemd tries to stop `mnt-EXT.mount` from the previous generation, but the unit doesn't exist in the new generation (because we disabled dis...
- **docs/future/flake-refactoring-migration.md**: The flake profile refactoring has been successfully implemented to eliminate code duplication across multiple `flake.*.nix` files. The new structure reduces each profile file from ~750 lines to ~30...
- **docs/future/flake-scalability-analysis.md**: **Date**: 2025-01-XX
- **docs/future/improvements-analysis.md**: **Date**: 2025-01-XX
- **docs/future/improvements-implemented.md**: **Date**: 2025-01-XX
- **docs/future/improvements-summary.md**: **Date**: 2025-01-XX
- **docs/future/incident-waybar-slow-relog-xdg-portal-gtk-2026-01-08.md**: Waybar delayed 2–4 minutes after fast relog in Sway due to xdg-desktop-portal-gtk failures + systemd start-limit lockout; fixed via portal-gtk drop-in (UnsetEnvironment=DISPLAY + no start-limit + restart).
- **docs/future/lxc-shell-improvements-implementation.md**: **Date:** 2026-01-29
- **docs/future/lxc-shell-improvements.md**: **Created:** 2026-01-29
- **docs/future/migration-verification-results.md**: **Date**: 2025-01-02
- **docs/future/phoenix-to-aku-rename-plan.md**: This document outlines the plan to replace all "phoenix" command references with "aku" throughout the dotfiles repository. The rename affects 33 files with 128 total occurrences.
- **docs/future/profile-comparison-desk-laptop-analysis.md**: This document provides a comprehensive analysis of the differences between three key profiles in the NixOS configuration hierarchy:
- **docs/future/profile-migration-status.md**: **Date**: 2025-01-02
- **docs/future/router-drift-audit-2026-01-08.md**: Audit findings for Router/Catalog doc drift vs current repo state (install.sh + Sway daemon system).
- **docs/future/sov-crash-analysis.md**: **Date**: 2026-01-07
- **docs/future/sov-dependency-analysis.md**: **Date**: 2026-01-07
- **docs/future/stylix-verification-and-fix.md**: Verified that **all Stylix configurations are properly controlled by the `stylixEnable` flag**. Found one issue: **DESK_AGA** should disable Stylix but currently inherits it enabled from DESK.
- **docs/future/sway-daemon-relog-notes-2026-01-08.md**: This document captures **runtime observations** and **log evidence** from debugging the SwayFX daemon integration system on **NixOS**.
- **docs/future/syncthing-nextcloud-integration.md**: The Syncthing to Nextcloud integration was not working. Files synced from phones via Syncthing were not appearing in Nextcloud's web interface or mobile apps.
- **docs/future/terraform-proxmox-integration-plan.md**: **Created:** 2026-01-29
- **docs/future/vmdesk-to-desk-inheritance-plan.md**: This document outlines the plan to migrate VMDESK from a standalone profile under Personal Profile to inherit from DESK-config.nix, following the same pattern as DESK_AGA.
- **docs/future/vmhome-migration-test.md**: **Date**: 2025-01-XX
- **docs/future/vmhome-to-lxc-migration-plan.md**: Migrate the VMHOME VM to an LXC container (`LXC_HOME`) while preserving all functionality (Docker, NFS, services) and optimizing for LXC. Must not impact existing `LXC*-config.nix` profiles.
- **docs/future/waybar-drawer-and-idle-toggle.md**: Notes on Waybar group drawer usage for tray+notifications and a custom idle-inhibit toggle (keybinding + Waybar module) used in SwayFX.
- **docs/future/waybar-sov-debug-analysis.md**: Historical debug analysis of Waybar/Sov startup failures from the legacy daemon-manager era (kept for reference; systemd-first is now canonical).

### Hardware

- **docs/hardware/cpu-power-management.md**: Complete guide to CPU frequency governors and power management.
- **docs/hardware/drive-management.md**: Complete guide to managing drives, LUKS encryption, and automatic mounting.
- **docs/hardware/gpu-monitoring.md**: Complete guide to GPU monitoring tools and their configuration for different GPU types.

### Infrastructure

- **docs/infrastructure/INFRASTRUCTURE.md**: Public infrastructure overview with architecture diagram and component descriptions
- **docs/infrastructure/INFRASTRUCTURE_INTERNAL.md**: Complete internal infrastructure documentation with sensitive details (ENCRYPTED)

### Infrastructure / Services

- **docs/infrastructure/services/homelab-stack.md**: Homelab stack services - Nextcloud, Syncthing, FreshRSS, Calibre-Web, EmulatorJS
- **docs/infrastructure/services/media-stack.md**: Media stack services - Jellyfin, Sonarr, Radarr, Prowlarr, Bazarr, Jellyseerr, qBittorrent
- **docs/infrastructure/services/monitoring-stack.md**: Monitoring stack - Prometheus, Grafana, exporters, alerting
- **docs/infrastructure/services/proxy-stack.md**: Proxy stack - NPM, cloudflared, ACME certificates
- **docs/infrastructure/services/vps-wireguard.md**: VPS WireGuard server - VPN hub, WGUI, Cloudflare tunnel, nginx, monitoring

### Keybindings

- **docs/keybindings/hyprland.md**: Complete reference for all Hyprland keybindings in this NixOS configuration.
- **docs/keybindings/mouse-button-mapping.md**: Quick guide to mapping mouse side buttons to modifier keys using keyd.
- **docs/keybindings/sway.md**: SwayFX keybindings reference, including unified rofi launcher and window overview.

- **docs/00_INDEX.md**: ⚠️ **AUTO-GENERATED**: Do not edit manually. Regenerate with `python3 scripts/generate_docs_index.py`
- **docs/00_ROUTER.md**: ⚠️ **AUTO-GENERATED**: Do not edit manually. Regenerate with `python3 scripts/generate_docs_index.py`
- **docs/01_CATALOG.md**: ⚠️ **AUTO-GENERATED**: Do not edit manually. Regenerate with `python3 scripts/generate_docs_index.py`
- **docs/agent-context.md**: How this repo manages AI agent context (Router/Catalog + Cursor rules + AGENTS.md + Claude Code) and a reusable template for other projects.
- **docs/configuration.md**: Complete guide to understanding and customizing the NixOS configuration system.
- **docs/hardware.md**: Complete guide to hardware-specific configurations and optimizations.
- **docs/installation.md**: Complete guide for installing and setting up this NixOS configuration repository.
- **docs/keybindings.md**: Complete reference for all keybindings across window managers and applications in this NixOS configuration.
- **docs/lxc-deployment.md**: Centralized deployment script for managing multiple LXC containers
- **docs/maintenance.md**: Complete guide to maintaining your NixOS configuration and using the provided scripts.
- **docs/navigation.md**: User guide for navigating this repository's documentation using the Router and Catalog system.
- **docs/nix-quote-escaping.md**: Guide to properly escaping quotes and special characters in Nix strings to avoid common syntax errors.
- **docs/patches.md**: Guide to understanding and using Nixpkgs patches in this configuration.
- **docs/profile-feature-flags.md**: Guide to creating and using feature flags for profile-specific module enabling. Explains the pattern of setting defaults to false and enabling features only in specific profiles.
- **docs/profiles.md**: Guide to understanding and using system profiles in this NixOS configuration.
- **docs/proxmox-lxc.md**: Guide to managing Proxmox LXC containers using a Base + Override pattern. Explains how to create and install new container profiles while keeping configuration DRY.
- **docs/scripts.md**: Complete reference for all shell scripts in this repository.
- **docs/security.md**: Complete guide to security configurations and features in this NixOS setup.
- **docs/system-modules.md**: Complete reference for system-level NixOS modules in this configuration.
- **docs/themes.md**: Complete guide to the theming system and available themes.
- **docs/user-modules.md**: Complete reference for user-level Home Manager modules in this configuration.

### Security

- **docs/security/git-crypt.md**: Git-crypt encryption for sensitive configuration data (domains, IPs, credentials)
- **docs/security/hardening.md**: Security hardening guidelines for NixOS homelab infrastructure
- **docs/security/incident-response.md**: Security incident response procedures for NixOS homelab infrastructure
- **docs/security/luks-encryption.md**: Complete guide to setting up LUKS disk encryption with SSH remote unlock capability.
- **docs/security/polkit.md**: Guide to configuring Polkit for fine-grained permission management.
- **docs/security/restic-backups.md**: Complete guide to setting up and configuring automated backups using Restic.
- **docs/security/sudo.md**: Guide to configuring sudo for remote SSH connections and specific commands.

### Setup

- **docs/setup/grafana-dashboards-alerting.md**: This guide documents how to configure Grafana dashboards and alerting for the homelab monitoring stack at `https://monitor.akunito.org.es`.
- **docs/setup/ubuntu-node-exporter.md**: This guide documents how to install and configure Prometheus Node Exporter on Ubuntu LXC containers (like cloudflared at 192.168.8.102) for monitoring with the homelab Prometheus/Grafana stack.

### User-Modules

- **docs/user-modules/doom-emacs.md**: Doom Emacs user module and config layout, including Stylix theme templates and profile integration.
- **docs/user-modules/gaming.md**: Implementation details for Gaming on NixOS, covering Lutris/Bottles wrappers, Vulkan/RDNA 4 driver fixes, and Wine troubleshooting.
- **docs/user-modules/lmstudio.md**: LM Studio user module, including MCP server setup templates and web-search tooling integration guidance.
- **docs/user-modules/nixvim-beginners-guide.md**: Beginner's guide to using NixVim and Avante, including Vim navigation basics for users new to Vim/Neovim.
- **docs/user-modules/nixvim.md**: NixVim configuration module providing a Cursor IDE-like Neovim experience with AI-powered features (Avante + Supermaven), LSP intelligence, and modern editor UX.
- **docs/user-modules/picom.md**: Picom compositor module overview and where its config and Nix module live.
- **docs/user-modules/plasma6.md**: Plasma 6 configuration integration for NixOS/Home Manager with export/import and symlink-based mutability.
- **docs/user-modules/ranger-guide.md**: Ranger is a minimalistic TUI (Terminal User Interface) file manager controlled with vim keybindings, making it extremely efficient for file management tasks.
- **docs/user-modules/ranger.md**: Ranger TUI file manager module overview, keybindings, and where configuration lives in this repo.
- **docs/user-modules/rofi.md**: Rofi configuration (Stylix-templated theme, unified combi launcher, power script-mode, and grouped window overview).
- **docs/user-modules/stylix-containment.md**: Stylix theming containment in this repo (Sway gets Stylix; Plasma 6 does not) via env isolation + session-scoped systemd.
- **docs/user-modules/sway-daemon-integration.md**: Sway session services are managed via systemd --user units bound to sway-session.target (official/systemd approach; no custom daemon-manager).
- **docs/user-modules/sway-output-layout-kanshi.md**: Complete Sway/SwayFX output management with kanshi (monitor config) + swaysome (workspaces), ensuring stability across reloads/rebuilds.
- **docs/user-modules/sway-to-hyprland-migration.md**: Guide to replicate SwayFX workspace and window management semantics in Hyprland using scripts and conventions.
- **docs/user-modules/swaybgplus.md**: GUI multi-monitor wallpapers for SwayFX/Wayland via SwayBG+ (Home-Manager/NixOS-safe; no Stylix/Plasma conflicts).
- **docs/user-modules/swww.md**: Robust wallpapers for SwayFX via swww (daemon + oneshot restore; rebuild/reboot safe; no polling/flicker).
- **docs/user-modules/tmux-persistent-sessions.md**: Complete guide to tmux persistent sessions with automatic save/restore across reboots using tmux-continuum and tmux-resurrect plugins
- **docs/user-modules/tmux.md**: Tmux terminal multiplexer module with custom keybindings, SSH smart launcher, and Stylix integration for modern terminal workflow.
- **docs/user-modules/unified-dark-theme-portals.md**: **ID:** `user-modules.unified-dark-theme-portals`
- **docs/user-modules/windows11-qxl-setup.md**: Complete guide for setting up QXL display drivers in Windows 11 VMs with SPICE for bidirectional clipboard and dynamic resolution support. Includes troubleshooting for resolution issues and driver installation.
- **docs/user-modules/xmonad.md**: XMonad tiling window manager module overview, auxiliary tools, and config layout in this repo.
