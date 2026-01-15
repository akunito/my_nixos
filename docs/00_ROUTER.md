⚠️ **AUTO-GENERATED**: Do not edit manually. Regenerate with `python3 scripts/generate_docs_index.py`

# Router Index

Use this file to select the best node ID(s), then read the referenced docs/files.

| ID | Summary | Tags | Primary Path |
|---|---|---|---|
| docs.agent-context | How this repo manages AI agent context (Router/Catalog + Cursor rules + AGENTS.md) and a reusable template for other projects. | cursor, agents, docs, routing, rules | docs/00_ROUTER.md |
| future.incident-waybar-slow-relog-xdg-portal-gtk-2026-01-08 | Waybar delayed 2–4 minutes after fast relog in Sway due to xdg-desktop-portal-gtk failures + systemd start-limit lockout; fixed via portal-gtk drop-in (UnsetEnvironment=DISPLAY + no start-limit + restart). | incident, sway, swayfx, waybar, xdg-desktop-portal, xdg-desktop-portal-gtk, systemd-user, dbus, relog | user/wm/sway/session-env.nix |
| future.router-drift-audit-2026-01-08 | Audit findings for Router/Catalog doc drift vs current repo state (install.sh + Sway daemon system). | router, catalog, audit, docs, drift | docs/00_ROUTER.md |
| future.waybar-drawer-and-idle-toggle | Notes on Waybar group drawer usage for tray+notifications and a custom idle-inhibit toggle (keybinding + Waybar module) used in SwayFX. | waybar, sway, swayfx, keybindings, systemd-user | user/wm/sway/waybar.nix |
| future.waybar-sov-debug-analysis-2026-01-07 | Historical debug analysis of Waybar/Sov startup failures from the legacy daemon-manager era (kept for reference; systemd-first is now canonical). | waybar, sov, sway, swayfx, debug, incident, deprecated, daemon-manager | user/wm/sway/** |
| keybindings.sway | SwayFX keybindings reference, including unified rofi launcher and window overview. | sway, swayfx, keybindings, rofi, wayland | user/wm/sway/swayfx-config.nix |
| user-modules.doom-emacs | Doom Emacs user module and config layout, including Stylix theme templates and profile integration. | emacs, doom-emacs, editor, stylix, user-modules | user/app/doom-emacs/** |
| user-modules.lmstudio | LM Studio user module, including MCP server setup templates and web-search tooling integration guidance. | lmstudio, mcp, ai, user-modules | user/app/lmstudio/** |
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
| user-modules.xmonad | XMonad tiling window manager module overview, auxiliary tools, and config layout in this repo. | xmonad, x11, window-manager, haskell, user-modules | user/wm/xmonad/** |

## Notes

- If a document is missing `related_files`, the generator falls back to using the document’s own path as the default scope.
