---
paths:
  - "user/wm/sway/**"
  - "user/wm/waybar/**"
---

# Sway/Wayland Rules

Before making changes, read: `docs/user-modules/sway-daemon-integration.md`

## Critical Rules

### Systemd-First Architecture
Sway session services are managed by systemd user units bound to `sway-session.target`.

### Single Lifecycle Manager
Do not start the same service via both Sway startup `exec` and systemd; pick one (prefer systemd user services).

### Source of Truth
Treat `user/wm/sway/default.nix` as the source of truth; keep service wiring there.

## Safety Constraints (do not regress)

- Avoid adding startup sleeps/delays unless strictly necessary
- Timing is sensitive in Wayland sessions
- Test changes across reloads and rebuilds
