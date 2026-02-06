{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Script to sync theme variables with D-Bus activation environment
  # Note: Variables are set via extraSessionCommands, this script only syncs with D-Bus.
  set-sway-theme-vars = pkgs.writeShellScriptBin "set-sway-theme-vars" ''
    # Sync with D-Bus activation environment
    # Variables are already set by extraSessionCommands, we just need to sync them
    # persistent systemd --user manager environment (which can leak into Plasma 6 if lingering is enabled).
    # CRITICAL: Include ALL theme variables so apps launched via Rofi/D-Bus see dark mode settings
    # XDG_DATA_DIRS and VK_ICD_FILENAMES are critical for Vulkan ICD discovery (Lutris, Wine, games)
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_DATA_DIRS VK_ICD_FILENAMES \
      QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE \
      GTK_THEME GTK_APPLICATION_PREFER_DARK_THEME GTK_USE_PORTAL \
      CUPS_SERVER PATH
  '';

  # Ensure core Wayland session vars are visible to systemd --user units launched via DBus activation
  # (e.g. xdg-desktop-portal). Now includes theme vars to ensure dark mode works for Rofi-launched apps.
  set-sway-systemd-session-vars = pkgs.writeShellScriptBin "set-sway-systemd-session-vars" ''
    #!/bin/sh
    # XDG_DATA_DIRS and VK_ICD_FILENAMES are critical for Vulkan ICD discovery (Lutris, Wine, games)
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_DATA_DIRS VK_ICD_FILENAMES PATH \
      QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE \
      GTK_THEME GTK_APPLICATION_PREFER_DARK_THEME GTK_USE_PORTAL
  '';

  # Write a session-scoped environment file for systemd --user services started from Sway.
  # This preserves the Stylix containment model:
  # - Global Home Manager session vars remain forced-empty to avoid Plasma 6 leakage
  # - Sway injects the desired vars (extraSessionCommands), and we snapshot them into %t/sway-session.env
  # - Systemd units use EnvironmentFile=%t/sway-session.env (no global systemd import-environment needed)
  write-sway-session-env = pkgs.writeShellScriptBin "write-sway-session-env" ''
        #!/bin/sh
        ENV_FILE="/run/user/$(id -u)/sway-session.env"
        umask 077
        mkdir -p "$(dirname "$ENV_FILE")" 2>/dev/null || true
        cat >"$ENV_FILE" <<EOF
    WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-}
    SWAYSOCK=''${SWAYSOCK:-}
    XDG_CURRENT_DESKTOP=''${XDG_CURRENT_DESKTOP:-sway}
    QT_QPA_PLATFORMTHEME=''${QT_QPA_PLATFORMTHEME:-}
    GTK_THEME=''${GTK_THEME:-}
    GTK_APPLICATION_PREFER_DARK_THEME=''${GTK_APPLICATION_PREFER_DARK_THEME:-}
    QT_STYLE_OVERRIDE=''${QT_STYLE_OVERRIDE:-}
    CUPS_SERVER=localhost:631
    EOF
  '';

  # Write a Sway-only portal environment file.
  #
  # Why: systemd --user currently has DISPLAY=:0 even in Sway, and xdg-desktop-portal-gtk may try X11
  # and fail early during relog ("cannot open display: :0"). We do NOT want to clear DISPLAY globally
  # because tray apps may need Xwayland. Instead we provide a portal-scoped env file that forces GTK
  # to prefer Wayland when the file exists (Sway session).
  write-sway-portal-env = pkgs.writeShellScriptBin "write-sway-portal-env" ''
        #!/bin/sh
        ENV_FILE="/run/user/$(id -u)/sway-portal.env"
        umask 077
        mkdir -p "$(dirname "$ENV_FILE")" 2>/dev/null || true
        cat >"$ENV_FILE" <<EOF
    WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-}
    XDG_CURRENT_DESKTOP=''${XDG_CURRENT_DESKTOP:-sway}
    XDG_SESSION_TYPE=wayland
    GDK_BACKEND=wayland
    EOF
  '';

  # Wrapper for xdg-desktop-portal-gtk to force Wayland in Sway sessions.
  #
  # Runtime evidence:
  # - systemd --user manager can have DISPLAY=:0 even in Sway
  # - xdg-desktop-portal-gtk sometimes starts with X11 and fails: "cannot open display: :0"
  # This wrapper unsets DISPLAY *only for this service* when we detect a Sway session.
  xdg-desktop-portal-gtk-wrapper = pkgs.writeShellScriptBin "xdg-desktop-portal-gtk-wrapper" ''
    #!/bin/sh
    COREUTILS="${pkgs.coreutils}/bin"

    XDG_CD="''${XDG_CURRENT_DESKTOP:-}"
    SWAYSOCK_VAL="''${SWAYSOCK:-}"
    WAYLAND_VAL="''${WAYLAND_DISPLAY:-}"
    XDR_VAL="''${XDG_RUNTIME_DIR:-/run/user/$($COREUTILS/id -u)}"

    WAYLAND_SOCK="$XDR_VAL/$WAYLAND_VAL"
    SWAYSOCK_EXISTS=false
    if [ -n "$SWAYSOCK_VAL" ] && [ -S "$SWAYSOCK_VAL" ]; then
      SWAYSOCK_EXISTS=true
    fi
    WAYLAND_SOCK_EXISTS=false
    if [ -n "$WAYLAND_VAL" ] && [ -S "$WAYLAND_SOCK" ]; then
      WAYLAND_SOCK_EXISTS=true
    fi

    IS_SWAY=false
    # IMPORTANT:
    # On fast relog, systemd --user may retain stale env like XDG_CURRENT_DESKTOP=sway and WAYLAND_DISPLAY=wayland-1
    # even while the compositor/socket is gone. Forcing Wayland in that window makes portal-gtk fail and blocks
    # org.freedesktop.portal.Desktop activation (Waybar then crash-loops).
    #
    # So we only treat it as "real Sway" when we see an actual live socket.
    if [ "$SWAYSOCK_EXISTS" = "true" ]; then
      IS_SWAY=true
    elif [ "$WAYLAND_SOCK_EXISTS" = "true" ] && echo "$XDG_CD" | ${pkgs.gnugrep}/bin/grep -qi "sway"; then
      IS_SWAY=true
    fi

    if [ "$IS_SWAY" = "true" ]; then
      export GDK_BACKEND=wayland
      export XDG_SESSION_TYPE=wayland
      unset DISPLAY
    fi

    exec ${pkgs.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk
  '';

  # Start the Sway session target (systemd-first daemons).
  sway-session-start = pkgs.writeShellScriptBin "sway-session-start" ''
    #!/bin/sh
    set -eu

    # IMPORTANT: Sway executes startup commands asynchronously (it does not wait for each command).
    # On cold boot this means `systemctl --user start sway-session.target` can run before SWAYSOCK
    # exists and before %t/sway-session.env is written, causing Sway-only services to race and skip.
    #
    # Fix: wait for a live SWAYSOCK (or an IPC socket in %t), then write %t/sway-session.env, then
    # start the target.
    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

    i=0
    while [ "$i" -lt 240 ]; do
      if [ -n "''${SWAYSOCK:-}" ] && [ -S "''${SWAYSOCK:-}" ]; then
        break
      fi
      CAND="$(ls -t "$RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n1 || true)"
      if [ -n "$CAND" ] && [ -S "$CAND" ]; then
        export SWAYSOCK="$CAND"
        break
      fi
      i=$((i + 1))
      sleep 0.25
    done

    if [ -z "''${SWAYSOCK:-}" ] || [ ! -S "''${SWAYSOCK:-}" ]; then
      # Not a Sway session (or compositor not ready); don't fail the session.
      exit 0
    fi

    "${write-sway-session-env}/bin/write-sway-session-env" >/dev/null 2>&1 || true
    exec ${pkgs.systemd}/bin/systemctl --user start sway-session.target
  '';

  # Refresh session environment without restarting the target.
  # Safe to run on config reload - only updates env file if session is already active.
  # This prevents duplicate waybar instances caused by target restart on every reload.
  sway-session-refresh-env = pkgs.writeShellScriptBin "sway-session-refresh-env" ''
    #!/bin/sh
    # Only refresh env if session already active (safe for reload)
    if ! ${pkgs.systemd}/bin/systemctl --user is-active sway-session.target >/dev/null 2>&1; then
      exit 0
    fi
    "${write-sway-session-env}/bin/write-sway-session-env" >/dev/null 2>&1 || true
  '';

  # Rebuild KDE system configuration cache to populate Dolphin menus
  # This ensures Dolphin's "Open With" dialog shows installed applications
  rebuild-ksycoca = pkgs.writeShellScriptBin "rebuild-ksycoca" ''
    #!/bin/sh
    # Rebuild KDE system configuration cache to populate Dolphin menus.
    # We explicitly use the Nix store path to ensure availability.
    # This requires 'plasma-applications.menu' to exist in XDG_CONFIG_DIRS.

    if [ -x "${pkgs.kdePackages.kservice}/bin/kbuildsycoca6" ]; then
      "${pkgs.kdePackages.kservice}/bin/kbuildsycoca6" --noincremental || true
    fi
  '';
in
{
  # Internal script handles used by `swayfx-config.nix` startup commands.
  user.wm.sway._internal.scripts.setSwayThemeVars = set-sway-theme-vars;
  user.wm.sway._internal.scripts.setSwaySystemdSessionVars = set-sway-systemd-session-vars;
  user.wm.sway._internal.scripts.writeSwaySessionEnv = write-sway-session-env;
  user.wm.sway._internal.scripts.writeSwayPortalEnv = write-sway-portal-env;
  user.wm.sway._internal.scripts.swaySessionStart = sway-session-start;
  user.wm.sway._internal.scripts.swaySessionRefreshEnv = sway-session-refresh-env;
  user.wm.sway._internal.scripts.rebuildKsycoCa = rebuild-ksycoca;

  # Portal configuration is now handled at system level in system/wm/sway.nix
  # Removed duplicate Home Manager xdg.portal configuration to avoid conflicts

  # Sway-only portal reliability: add drop-ins (NOT full unit files) to avoid shadowing /etc/systemd/user units.
  #
  # We wrap ExecStart to avoid GTK choosing X11 via DISPLAY=:0 during fast relog.
  xdg.configFile."systemd/user/xdg-desktop-portal-gtk.service.d/10-sway-portal-env.conf" = {
    text = ''
      [Unit]
      # During fast relogs portal-gtk can fail before the compositor is fully ready.
      # Avoid hitting systemd's default start-rate limiting, otherwise the service becomes "dead"
      # and DBus activation for portals can block clients (Waybar timeouts).
      StartLimitIntervalSec=0

      [Service]
      # Critical for fast relog: portal-gtk can transiently fail (broken pipe / display attach issues).
      # If it doesn't auto-restart, xdg-desktop-portal + clients (Waybar) can block on DBus activation timeouts.
      Restart=on-failure
      RestartSec=1s

      # Force Wayland behavior for portal-gtk in Sway, and prevent DISPLAY=:0 from selecting X11.
      # This is scoped to this service only (no global env mutation).
      EnvironmentFile=-%t/sway-portal.env
      UnsetEnvironment=DISPLAY

      # Override ExecStart via wrapper (drop-in, not unit shadowing).
      ExecStart=
      ExecStart=${xdg-desktop-portal-gtk-wrapper}/bin/xdg-desktop-portal-gtk-wrapper
    '';
  };

  # Cleanup: remove stale broken user-level portal unit files from a previous iteration.
  # Evidence: systemd reports "Service has no ExecStart= ... Refusing." for these units,
  # which prevents Waybar from starting (it tries to activate org.freedesktop.portal.Desktop).
  home.activation.cleanupBrokenPortalUnits = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    portal_units="xdg-desktop-portal.service xdg-desktop-portal-gtk.service"
    for unit in $portal_units; do
      unit_path="$HOME/.config/systemd/user/$unit"

      # If a user unit exists but has no ExecStart, it shadows the real system unit and breaks activation.
      if [ -e "$unit_path" ] && ! ${pkgs.gnugrep}/bin/grep -q '^ExecStart=' "$unit_path" 2>/dev/null; then
        # Only delete if it matches our previous minimal override shape (avoid deleting legit custom units).
        if ${pkgs.gnugrep}/bin/grep -q '^EnvironmentFile=-%t/sway-session\\.env' "$unit_path" 2>/dev/null; then
          ${pkgs.coreutils}/bin/rm -f "$unit_path" || true
        fi
      fi

      # Remove any lingering enable symlinks under *.wants/ (dangling symlinks keep the unit "enabled").
      for link in "$HOME/.config/systemd/user/"*.wants/"$unit"; do
        if [ -L "$link" ]; then
          ${pkgs.coreutils}/bin/rm -f "$link" || true
        fi
      done
    done

    # Reload user systemd if available.
    ${pkgs.systemd}/bin/systemctl --user daemon-reload >/dev/null 2>&1 || true
  '';
}
