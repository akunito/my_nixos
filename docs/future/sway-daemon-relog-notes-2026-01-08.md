# Sway daemon relog instability — runtime notes (2026-01-08)

This document captures **runtime observations** and **log evidence** from debugging the SwayFX daemon integration system on **NixOS**.

## Archived incident report (post-mortem)

If you need the final root cause + fix summary (Waybar slow after fast relog due to portal-gtk failures), see:

- `docs/future/incident-waybar-slow-relog-xdg-portal-gtk-2026-01-08.md`

## User-observed behavior (session relog cycle)

Observed across 4 consecutive logins (logout to SDDM, then login):

- **Login 1 (post-rebuild, ~10s in SDDM)**:
  - Cursor: “already running” (new instance didn’t start)
  - Flatpak Vivaldi: ~1 minute to open
  - Waybar: ~3–4 minutes to appear / become correct
- **Login 2 (~10s in SDDM)**:
  - Everything started fast and worked fine
- **Login 3 (~15–20s in SDDM)**:
  - Flatpak Vivaldi: <1 minute (slow)
  - Waybar: ~2–3 minutes (slow)
- **Login 4 (very fast, ~2–5s in SDDM)**:
  - Everything started fast and worked fine

Across **all** logins:

- Sunshine tray icon was **missing** from Waybar’s tray.

## Key journald evidence (what can cause 2–4 minute delays)

### 1) `daemon-health-monitor` can delay a Waybar restart by ~150 seconds

Current `daemon-health-monitor` behavior:

- Waits **60 seconds grace period** after start
- Then checks every **30 seconds**
- For Waybar, requires **3 consecutive misses** before restart (strike system)

That yields a worst-case restart delay of:

\[
60s + (3 \times 30s) = 150s \approx 2.5\text{ minutes}
\]

This matches the *order of magnitude* of “Waybar appears after 2–4 minutes”.

Evidence excerpt (from `journalctl --user -t sway-daemon-monitor`):
- `Health monitor: Waiting 60 seconds grace period for system initialization`
- `Waybar pattern not found (failure count: 1)` … `Skipping restart (1/3)`
- `Waybar pattern not found (failure count: 3)` … `Threshold reached (3 failures), proceeding with restart`
- `SUCCESS: waybar restarted successfully`

### 2) `daemon-manager` sometimes exits due to startup lock contention

Evidence excerpt (from `journalctl --user -t sway-daemon-mgr`):
- `Another startup process is running, exiting`

If the “winner” instance is blocked or exits early, this can leave the session without a timely `waybar` start, forcing the health monitor fallback (which may be delayed per above).

### 3) Some daemons start before Wayland is ready (symptom: “No such file or directory”)

Evidence excerpt (from `journalctl --user -t sway-daemon-mgr`):
- `Failed to connect to a Wayland server: No such file or directory`

This indicates that, at least in some sessions, the startup sequence is attempting to launch Wayland-dependent daemons before the Wayland socket is available, which can lead to early crashes and later restarts.

### 4) StatusNotifierWatcher not ready (tray timing / missing icons)

Evidence excerpt (from `journalctl --user -t sway-daemon-mgr`):
- `WARNING: StatusNotifierWatcher not ready after ~15 seconds, starting daemon anyway: ... nm-applet`
- `NOTE: Tray icon may not appear until waybar's tray module initializes`

This suggests either:
- Waybar (or its tray module) is not ready when tray apps start, **or**
- The DBus/session environment required for tray registration is not stable during some relogs.

## Sunshine icon missing (most likely cause candidates)

From `sway-daemon-monitor` logs, there are lines such as:
- `WARNING: sunshine is not running (restart attempt: 1)`
- `ERROR: sunshine restart failed`

This points to a simpler possibility than “tray broken”: sunshine may not be running successfully in the session, so there is no tray item to show.

## Working hypotheses to validate next (need fresh NDJSON run)

We need a clean `debug.log` run during a **bad** login to decide which hypothesis is real:

- **H1 (lock overlap)**: A previous session’s startup/monitor is still alive during fast relog; new startup exits early due to lock contention.
- **H2 (Wayland/IPC readiness)**: Some session starts run before `WAYLAND_DISPLAY` socket / `SWAYSOCK` are valid, causing waybar (or dependencies) to crash, then the health monitor restarts it minutes later.
- **H3 (health-monitor policy side-effect)**: Waybar fails early, but the 60s+strike policy delays recovery by ~150s, producing the observed “minutes to appear”.
- **H4 (tray / StatusNotifierWatcher timing)**: Tray host isn’t ready when tray apps register; some apps never re-register, yielding persistent missing icons.
- **H5 (sunshine not running)**: Sunshine fails to start; missing tray icon is a symptom of the app not running, not a Waybar tray defect.

## Next reproduction requirement

For the next run, we must ensure:

- `/home/akunito/.dotfiles/.cursor/debug.log` is cleared **before** login reproduction
- We capture a **bad** relog and then compare:
  - `debug.log` NDJSON
  - `journalctl --user -t sway-daemon-mgr`
  - `journalctl --user -t sway-daemon-monitor`

## Systemd-first regression debug run (2026-01-08, follow-up)

This run targets the case where **systemd-first is enabled** but on logout→login, **Waybar takes 2–4 minutes** to appear (while after a full reboot everything starts fast).

### Instrumentation added (temporary)

- `user/wm/sway/debug/relog-instrumentation.nix` (kept unlinked by default; can be imported/wired during regressions)
  - Wraps the two Sway startup commands:
    - env snapshot writer → `write-sway-session-env-debug`
    - `systemctl --user start sway-session.target` → `sway-session-start-debug` (records duration + unit states)
  - Adds `ExecStartPre` for `waybar.service` to log whether `SWAYSOCK` exists and whether `%t/sway-session.env` exists right before Waybar launches.

### What to look for in `debug.log`

- **H_SYSTEMD**: whether `systemctl --user start sway-session.target` blocks for a long time (duration_ms)
- **H_ENV**: whether `%t/sway-session.env` is missing/empty or written too early
- **H_WAYBAR**: whether `SWAYSOCK` is unset or points to a missing socket at Waybar ExecStartPre


