⚠️ **AUTO-GENERATED**: Do not edit manually. Regenerate with `python3 scripts/generate_docs_index.py`

# Router Index

Use this file to select the best node ID(s), then read the referenced docs/files.

| ID | Summary | Tags | Primary Path |
|---|---|---|---|
| audits.pfsense.2026-02-04 | Security, performance, and reliability audit of pfSense firewall | audit, security, performance, pfsense, firewall | docs/akunito/infrastructure/audits/pfsense-audit-2026-02-04.md |
| audits.truenas.2026-02-12 | Performance, reliability, and configuration audit of TrueNAS storage server | audit, performance, truenas, zfs, storage, network, iscsi | docs/akunito/infrastructure/audits/truenas-audit-2026-02-12.md |
| claude-code-setup | Claude Code CLI configuration guide — permissions, hooks, and MCP servers | claude-code, setup, permissions, hooks, mcp, tooling | ~/.claude/settings.json |
| desk-vs-laptop-packages | Complete package and feature comparison between DESK and LAPTOP_L15 profiles | packages, profiles, comparison, DESK, LAPTOP | docs/future/archived/desk-vs-laptop-packages.md |
| docs.agent-context | How this repo manages AI agent context (Router/Catalog + Cursor rules + AGENTS.md + Claude Code) and a reusable template for other projects. | cursor, claude-code, agents, docs, routing, rules | docs/00_ROUTER.md |
| docs.navigation | User guide for navigating this repository's documentation using the Router and Catalog system. | docs, navigation, router, catalog, user-guide | docs/00_ROUTER.md |
| docs.nix-quote-escaping | Guide to properly escaping quotes and special characters in Nix strings to avoid common syntax errors. | nix, nixos, home-manager, syntax, escaping, quotes, strings, troubleshooting | docs/nix-quote-escaping.md |
| docs.profile-feature-flags | Guide to creating and using feature flags for profile-specific module enabling. Explains the pattern of setting defaults to false and enabling features only in specific profiles. | profiles, feature-flags, modules, nixos, home-manager, configuration, best-practices | lib/defaults.nix |
| docs.proxmox-lxc | Guide to managing Proxmox LXC containers using a Base + Override pattern. Explains how to create and install new container profiles while keeping configuration DRY. | proxmox, lxc, virtualization, profiles, modularity, dry | profiles/LXC-base-config.nix |
| future.incident-waybar-slow-relog-xdg-portal-gtk-2026-01-08 | Waybar delayed 2–4 minutes after fast relog in Sway due to xdg-desktop-portal-gtk failures + systemd start-limit lockout; fixed via portal-gtk drop-in (UnsetEnvironment=DISPLAY + no start-limit + restart). | incident, sway, swayfx, waybar, xdg-desktop-portal, xdg-desktop-portal-gtk, systemd-user, dbus, relog | user/wm/sway/session-env.nix |
| future.router-drift-audit-2026-01-08 | Audit findings for Router/Catalog doc drift vs current repo state (install.sh + Sway daemon system). | router, catalog, audit, docs, drift | docs/00_ROUTER.md |
| future.waybar-drawer-and-idle-toggle | Notes on Waybar group drawer usage for tray+notifications and a custom idle-inhibit toggle (keybinding + Waybar module) used in SwayFX. | waybar, sway, swayfx, keybindings, systemd-user | user/wm/sway/waybar.nix |
| future.waybar-sov-debug-analysis-2026-01-07 | Historical debug analysis of Waybar/Sov startup failures from the legacy daemon-manager era (kept for reference; systemd-first is now canonical). | waybar, sov, sway, swayfx, debug, incident, deprecated, daemon-manager | user/wm/sway/** |
| hardware.thunderbolt-dock | Thunderbolt dock setup, OWC Dock 96W, ATTO ThunderLink NS 3102 (Linux incompatible), PS/2 keyboard/touchpad fixes | thunderbolt, dock, owc, atto, 10gbe, thinkpad, keyboard, touchpad, ps2, hardware | system/hardware/thunderbolt.nix |
| hibernate | Hibernation with LUKS-encrypted swap for laptops and desktops | hibernation, suspend, luks, swap, encryption, power, laptop, desktop, sway, idle, lid, acpid | system/hardware/hibernate.nix |
| infrastructure.database-redis | Centralized PostgreSQL and Redis services on LXC_database | infrastructure, database, redis, postgresql, lxc, caching | profiles/LXC_database-config.nix |
| infrastructure.docker-projects | Docker-based project conventions - wrapper scripts, config locations, restart patterns | infrastructure, docker, projects, portfolio, liftcraft, plane | profiles/LXC_portfolioprod-config.nix |
| infrastructure.internal | Complete internal infrastructure documentation with sensitive details (ENCRYPTED) | infrastructure, audit, security, monitoring, proxmox, lxc, secrets | profiles/LXC*-config.nix |
| infrastructure.overview | Public infrastructure overview with architecture diagram and component descriptions | infrastructure, architecture, proxmox, lxc, monitoring, homelab, pfsense, gateway | profiles/LXC*-config.nix |
| infrastructure.services.homelab | Homelab stack services - Nextcloud, Syncthing, FreshRSS, Calibre-Web, EmulatorJS | infrastructure, homelab, docker, nextcloud, syncthing | profiles/LXC_HOME-config.nix |
| infrastructure.services.kuma | Uptime Kuma monitoring - local homelab and public VPS status pages with API integration | infrastructure, kuma, uptime-kuma, monitoring, status-pages, lxc_mailer, vps, docker | profiles/LXC_mailer-config.nix |
| infrastructure.services.liftcraft | LiftCraft (LeftyWorkout) - Training plan management Rails application | infrastructure, liftcraft, leftyworkout, rails, docker, redis | profiles/LXC_liftcraftTEST-config.nix |
| infrastructure.services.media | Media stack services - Jellyfin, Sonarr, Radarr, Prowlarr, Bazarr, Jellyseerr, qBittorrent | infrastructure, media, docker, jellyfin, arr, plex-alternative | profiles/LXC_HOME-config.nix |
| infrastructure.services.monitoring | Monitoring stack - Prometheus, Grafana, exporters, alerting | infrastructure, monitoring, prometheus, grafana, alerting | profiles/LXC_monitoring-config.nix |
| infrastructure.services.network-switching | Physical switching layer documentation - USW Aggregation, USW-24-G2, 10GbE LACP bonds, ARP flux | infrastructure, network, switching, 10gbe, lacp, sfp, aggregation, arp | profiles/DESK-config.nix |
| infrastructure.services.pfsense | pfSense firewall - gateway, DNS resolver, WireGuard, DHCP, NAT, pfBlockerNG, SNMP | infrastructure, pfsense, firewall, gateway, wireguard, dns, dhcp, snmp, pfblockerng, openvpn | docs/akunito/infrastructure/INFRASTRUCTURE.md |
| infrastructure.services.proxy | Proxy stack - NPM, cloudflared, ACME certificates | infrastructure, proxy, nginx, cloudflare, ssl, certificates | profiles/LXC_proxy-config.nix |
| infrastructure.services.truenas | TrueNAS storage server operations, monitoring, and maintenance | infrastructure, storage, truenas, zfs, monitoring, nas | system/app/prometheus-graphite.nix |
| infrastructure.services.vps | VPS WireGuard server - VPN hub, WGUI, Cloudflare tunnel, nginx, monitoring | infrastructure, vps, wireguard, vpn, cloudflare, nginx, monitoring | system/app/prometheus-node-exporter.nix |
| keybindings.mouse-button-mapping | Quick guide to mapping mouse side buttons to modifier keys using keyd. | keyd, mouse, keybindings, modifiers | system/wm/keyd.nix |
| keybindings.sway | SwayFX keybindings reference, including unified rofi launcher and window overview. | sway, swayfx, keybindings, rofi, wayland | user/wm/sway/swayfx-config.nix |
| lxc-deployment | Centralized deployment script for managing multiple LXC containers | lxc, deployment, automation, proxmox, containers | deploy.sh |
| network-bonding | Network bonding (LACP link aggregation) for increased bandwidth and failover | networking, bonding, lacp, performance, failover | system/hardware/network-bonding.nix |
| scripts | Complete reference for all shell scripts — installation, sync, update, maintenance, security, and utilities | scripts, automation, installation, maintenance, deployment | *.sh |
| scripts.installation | Installation and deployment scripts — install.sh, deploy.sh, set_environment.sh, flatpak-reconcile.sh | scripts, installation, deployment, flatpak | install.sh |
| scripts.maintenance | Maintenance and automated update scripts — maintenance.sh, autoSystemUpdate.sh, autoUserUpdate.sh | scripts, maintenance, cleanup, garbage-collection, automation | maintenance.sh |
| scripts.security | Security scripts — harden.sh, soften.sh, cleanIPTABLESrules.sh for file permissions and firewall management | scripts, security, permissions, firewall, hardening | harden.sh |
| scripts.sync-update | Synchronization and update scripts — sync.sh, sync-system.sh, sync-user.sh, update.sh, upgrade.sh, pull.sh | scripts, sync, update, upgrade, flake | sync.sh |
| scripts.utility | Utility and helper scripts — fix-terminals, generate_docs_index.py, handle_docker.sh, Plasma/Sway/Ranger helpers | scripts, utility, helper, docker, themes, plasma, sway, ranger | handle_docker.sh |
| security.git-crypt | Git-crypt encryption for sensitive configuration data (domains, IPs, credentials) | git-crypt, secrets, encryption, security, domains, credentials | secrets/*.nix |
| security.hardening | Security hardening guidelines for NixOS homelab infrastructure | security, hardening, firewall, services, credentials | system/app/*.nix |
| security.incident-response | Security incident response procedures for NixOS homelab infrastructure | security, incident-response, credentials, rotation, recovery | secrets/*.nix |
| setup.grafana-dashboards | Comprehensive reference for all Grafana dashboards including metrics sources, panel specifications, alert rules, and verification procedures. | grafana, prometheus, dashboards, monitoring, alerting, metrics, truenas, wireguard, pfsense, exportarr | system/app/grafana.nix |
| shell-multiline-input | Multi-line shell input with Shift+Enter configuration | shell, zsh, terminal, keyboard, keybindings | lib/defaults.nix |
| system-modules | Complete reference for system-level NixOS modules — app, hardware, security, WM, and utility modules | system-modules, nixos, configuration, modules | system/**/*.nix |
| system-modules.app | System application modules — Docker, Virtualization (QEMU/KVM/SPICE), Flatpak, Steam, Gamemode, Samba, AppImage | system-modules, docker, virtualization, flatpak, steam, gamemode, samba, appimage | system/app/*.nix |
| system-modules.hardware | System hardware modules — drives, power, kernel, Bluetooth, printing, OpenGL, Xbox, NFS, SystemD, time | system-modules, hardware, drives, power, kernel, bluetooth, printing, opengl, nfs | system/hardware/*.nix |
| system-modules.security-wm-utils | Security, window manager, and utility modules — SSH, firewall, sudo, Polkit, Restic, WMs, keyd, aku wrapper | system-modules, security, ssh, firewall, sudo, polkit, restic, wm, keyd, aku | system/security/*.nix |
| tailscale-headscale | Tailscale mesh VPN with self-hosted Headscale coordination server | tailscale, headscale, vpn, mesh, networking, wireguard | profiles/LXC_tailscale-config.nix |
| user-modules | Complete reference for user-level Home Manager modules — applications, shells, window managers, theming, and packages | user-modules, home-manager, configuration, modules | user/**/*.nix |
| user-modules.db-credentials | Home Manager module for database credential files (pgpass, my.cnf, redis) | database, credentials, postgresql, mariadb, redis, dbeaver, home-manager | user/app/database/db-credentials.nix |
| user-modules.doom-emacs | Doom Emacs user module and config layout, including Stylix theme templates and profile integration. | emacs, doom-emacs, editor, stylix, user-modules | user/app/doom-emacs/** |
| user-modules.gaming | Implementation details for Gaming on NixOS, covering Lutris/Bottles wrappers, Vulkan/RDNA 4 driver fixes, and Wine troubleshooting. | gaming, lutris, bottles, wine, vulkan, amd, rdna4, wrappers, antimicrox, controllers | user/app/games/games.nix |
| user-modules.lmstudio | LM Studio user module, including MCP server setup templates and web-search tooling integration guidance. | lmstudio, mcp, ai, user-modules | user/app/lmstudio/** |
| user-modules.nixvim | NixVim configuration module providing a Cursor IDE-like Neovim experience with AI-powered features (Avante + Supermaven), LSP intelligence, and modern editor UX. | nixvim, neovim, editor, ai, lsp, cursor-ide, user-modules | user/app/nixvim/** |
| user-modules.nixvim-beginners-guide | Beginner's guide to using NixVim and Avante, including Vim navigation basics for users new to Vim/Neovim. | nixvim, neovim, vim, beginners, tutorial, avante, user-modules | user/app/nixvim/** |
| user-modules.ollama | Ollama local LLM server configuration, RDNA4 Vulkan backend workaround, and model recommendations for RX 9070 XT. | ollama, ai, vulkan, rocm, rdna4, gpu, llm, user-modules | user/packages/user-ai-pkgs.nix |
| user-modules.picom | Picom compositor module overview and where its config and Nix module live. | picom, compositor, x11, animations, user-modules | user/wm/picom/** |
| user-modules.plasma6 | Plasma 6 configuration integration for NixOS/Home Manager with export/import and symlink-based mutability. | plasma6, kde, desktop, home-manager, configuration | user/wm/plasma6/** |
| user-modules.ranger | Ranger TUI file manager module overview, keybindings, and where configuration lives in this repo. | ranger, tui, file-manager, user-modules | user/app/ranger/** |
| user-modules.rofi | Rofi configuration (Stylix-templated theme, unified combi launcher, power script-mode, and grouped window overview). | rofi, launcher, sway, swayfx, wayland, stylix, base16, scripts | user/wm/sway/rofi.nix |
| user-modules.stylix-containment | Stylix theming containment in this repo (Sway gets Stylix; Plasma 6 does not) via env isolation + session-scoped systemd. | stylix, sway, swayfx, plasma6, qt, gtk, containment, systemd-user, home-manager | user/style/stylix.nix |
| user-modules.sway-daemon-integration | Sway session services are managed via systemd --user units bound to sway-session.target (official/systemd approach; no custom daemon-manager). | sway, swayfx, systemd-user, waybar, home-manager, session | user/wm/sway/** |
| user-modules.sway-output-layout-kanshi | Complete Sway/SwayFX output management with kanshi (monitor config) + swaysome (workspaces), ensuring stability across reloads/rebuilds. | sway, swayfx, wayland, kanshi, outputs, monitors, workspaces, swaysome, home-manager, systemd-user, plasma6, profiles, reload | user/wm/sway/kanshi.nix |
| user-modules.sway-to-hyprland-migration | Guide to replicate SwayFX workspace and window management semantics in Hyprland using scripts and conventions. | sway, swayfx, hyprland, migration, wayland, workspaces | user/wm/hyprland/** |
| user-modules.swaybgplus | GUI multi-monitor wallpapers for SwayFX/Wayland via SwayBG+ (Home-Manager/NixOS-safe; no Stylix/Plasma conflicts). | sway, swayfx, wayland, wallpapers, swaybg, home-manager, stylix, systemd-user, gtk3 | user/pkgs/swaybgplus.nix |
| user-modules.swww | Robust wallpapers for SwayFX via swww (daemon + oneshot restore; rebuild/reboot safe; no polling/flicker). | swww, sway, swayfx, wayland, wallpapers, systemd-user, home-manager, stylix | user/app/swww/** |
| user-modules.tmux | Tmux terminal multiplexer module with custom keybindings, SSH smart launcher, and Stylix integration for modern terminal workflow. | tmux, terminal, multiplexer, ssh, keybindings, user-modules, stylix | user/app/terminal/tmux.nix |
| user-modules.tmux-persistent-sessions | Complete guide to tmux persistent sessions with automatic save/restore across reboots using tmux-continuum and tmux-resurrect plugins | tmux, persistent, sessions, restore, reboot, systemd, continuum, resurrect | user/app/terminal/tmux.nix |
| user-modules.windows11-qxl-setup | Complete guide for setting up QXL display drivers in Windows 11 VMs with SPICE for bidirectional clipboard and dynamic resolution support. Includes troubleshooting for resolution issues and driver installation. | virtualization, windows11, qxl, spice, vm, qemu, kvm, virt-manager, display, resolution, clipboard | system/app/virtualization.nix |
| user-modules.xmonad | XMonad tiling window manager module overview, auxiliary tools, and config layout in this repo. | xmonad, x11, window-manager, haskell, user-modules | user/wm/xmonad/** |
| waypaper | Waypaper GUI wallpaper manager — single source of truth for wallpaper restore in Sway (swww backend) | waypaper, wallpaper, sway, swww, gui, stylix, systemd-user | user/app/waypaper/waypaper.nix |
| workflow.komi-onboarding | Quick guide for ko-mi on the multi-user branch setup and what changed | komi, onboarding, multi-user, darwin | docs/komi/komi-onboarding.md |
| workflow.multi-user | Multi-user branch management workflow for akunito (main) and ko-mi (komi) | git, workflow, multi-user, branches, merge | profiles/MACBOOK-KOMI-config.nix |

## Notes

- If a document is missing `related_files`, the generator falls back to using the document’s own path as the default scope.
