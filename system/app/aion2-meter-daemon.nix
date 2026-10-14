# AION 2 DPS meter, headless Linux daemon (aionmeter-daemon, Plane A2M-48 phase 2b).
#
# Runs whatever framework-dependent publish sits in the install dir:
#   ${installDir}/aionmeter-daemon.dll (+ deps, data/)
# The meter repo (~/Projects/aion2-dps-meter) produces it with its docker build
# (build/out/<sha>/aionmeter-daemon-linux-x64/) and its tools/linux/deploy.sh
# (to be written there) copies it into the install dir and restarts this unit.
# Not a derivation yet: the build happens in that repo's docker image (on DESK_W11
# through rbuild), exactly like the Windows deploy folder, and the release
# cadence is per commit of the meter, not per dotfiles deploy. A nix package comes
# with the Linux release (port doc step 3). Missing dll -> the unit is skipped
# (ConditionPathExists), not failed.
#
# SYSTEM service with User=, because a user service cannot be granted ambient
# capabilities and pcap needs CAP_NET_RAW + CAP_NET_ADMIN. Same uid as the game,
# so /proc/<pid>/fd of AION 2 is readable without CAP_SYS_PTRACE.
# When the game is not running it just waits ("AION 2 is not running").
# SIGTERM makes it close and save the fight in progress and flush state.
{ pkgs, lib, systemSettings, userSettings, ... }:
let
  cfg = systemSettings;
  orDefault = v: d: if v == null then d else v;
  user = orDefault (cfg.aion2MeterDaemonUser or null) userSettings.username;
  home = "/home/${user}";
  installDir = orDefault (cfg.aion2MeterDaemonInstallDir or null) "${home}/.local/opt/aionmeter-daemon";
  dataDir = orDefault (cfg.aion2MeterDaemonDataDir or null) "${home}/.local/share/AionMeter";
  extraArgs = cfg.aion2MeterDaemonExtraArgs or [ ];
  uiDir = orDefault (cfg.aion2MeterUiInstallDir or null) "${home}/.local/opt/aionmeter-ui";
  # Daemon <-> UI socket. Not the meter's default $XDG_RUNTIME_DIR/aionmeter.sock: the unit has no
  # XDG_RUNTIME_DIR and PrivateTmp, so its fallback /tmp/aionmeter-<uid>.sock lands in a private /tmp the UI
  # never sees, and /run/user/<uid> does not exist before login. RuntimeDirectory= gives a /run dir owned by User=.
  socketPath = "/run/aionmeter/aionmeter.sock";
  # Overlay UI (AionMeter.Linux, Avalonia on XWayland, window class "aionmeter"; DESK sway-apps: Hyper+g launches,
  # Hyper+Shift+g sends SIGUSR1 to $XDG_RUNTIME_DIR/aionmeter-ui.pid (written by the UI) to turn click-through off).
  # Reconnects while the daemon is away (restart wipes /run/aionmeter).
  # Avalonia dlopens the X11/fontconfig/GL libs by soname; NixOS has no /usr/lib, so they go on LD_LIBRARY_PATH.
  aionmeterUi = pkgs.writeShellScriptBin "aionmeter-ui" ''
    dll=''${AIONMETER_UI_DIR:-${uiDir}}/AionMeter.Linux.dll
    if [ ! -f "$dll" ]; then
      ${pkgs.libnotify}/bin/notify-send -a "AION 2 meter" "aionmeter-ui" "Not installed: $dll"
      exit 1
    fi
    export LD_LIBRARY_PATH=${lib.makeLibraryPath (with pkgs; [
      xorg.libX11 xorg.libICE xorg.libSM xorg.libXi xorg.libXcursor xorg.libXrandr xorg.libXext xorg.libXrender
      fontconfig freetype libGL
    ])}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
    exec ${pkgs.dotnet-runtime_10}/bin/dotnet "$dll" --socket ${socketPath} "$@"
  '';
  # Native overlay card (AionMeter.Overlay: GTK4 + wlr-layer-shell, layer OVERLAY, so it paints above gamescope's
  # fullscreen view, at the output's own scale). Pid in $XDG_RUNTIME_DIR/aionmeter-overlay.pid; SIGUSR1 = click-through,
  # SIGUSR2 = hide/show. GirCore opens every lib by soname -> LD_LIBRARY_PATH (getLib: glib/pango/fontconfig are split).
  # No LD_PRELOAD: the program dlopens libgtk4-layer-shell RTLD_GLOBAL itself before GTK loads libwayland-client.
  # No steam-run / GDK_BACKEND=x11: it must be a Wayland client.
  overlayDir = orDefault (cfg.aion2MeterOverlayInstallDir or null) "${home}/.local/opt/aionmeter-overlay";
  overlayMonitor = cfg.aion2MeterOverlayMonitor or "DP-1";
  # A2M-50: GTK's own file chooser (Craft "Load market file…" when the portal is down) aborts the whole process without the
  # org.gtk.gtk4.Settings.FileChooser schema on XDG_DATA_DIRS ("GLib-GIO-ERROR: No GSettings schemas are installed", measured
  # 2026-10-13 in a nested sway). questlog's skill icons are WebP: gdk-pixbuf has png/jpeg built in but WebP needs the loader, and
  # GDK_PIXBUF_MODULE_FILE replaces the whole cache, so one file lists the stock loaders plus webp.
  pixbufLoaders = pkgs.runCommand "aionmeter-pixbuf-loaders" { } ''
    { cat ${pkgs.gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache
      ${pkgs.gdk-pixbuf.dev}/bin/gdk-pixbuf-query-loaders ${pkgs.webp-pixbuf-loader}/lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader-webp.so | grep -v '^#'; } > $out
  '';
  aionmeterOverlay = pkgs.writeShellScriptBin "aionmeter-overlay" ''
    dll=''${AIONMETER_OVERLAY_DIR:-${overlayDir}}/AionMeter.Overlay.dll
    if [ ! -f "$dll" ]; then
      ${pkgs.libnotify}/bin/notify-send -a "AION 2 meter" "aionmeter-overlay" "Not installed: $dll"
      exit 1
    fi
    export LD_LIBRARY_PATH=${lib.makeLibraryPath (map lib.getLib (with pkgs; [
      gtk4 gtk4-layer-shell glib cairo pango gdk-pixbuf graphene harfbuzz fontconfig freetype wayland
    ]))}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export XDG_DATA_DIRS=${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}:${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}
    export GDK_PIXBUF_MODULE_FILE=${pixbufLoaders}
    export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
    # A2M-50 window mode (meter e4db091): the card is a plain Wayland toplevel placed through Sway IPC, so SWAYSOCK must point at the
    # live compositor — a shell started before a sway restart carries a stale path (measured 2026-10-13), take the newest socket then.
    # --monitor only matters for the old layer-shell card (`aionmeter-overlay --layer`), window mode ignores it.
    if [ -z "''${SWAYSOCK:-}" ] || [ ! -S "$SWAYSOCK" ]; then
      s=$(ls -t /run/user/"$(id -u)"/sway-ipc.*.sock 2>/dev/null | head -n 1); [ -n "$s" ] && export SWAYSOCK="$s"
    fi
    exec ${pkgs.dotnet-runtime_10}/bin/dotnet "$dll" --socket ${socketPath} --monitor ${overlayMonitor} "$@"
  '';
  # pid of a live front-end: from its own pid file, checked against /proc cmdline (stale file, reused pid).
  # Never pkill -f: it matches the launcher shells as well.
  livePid = ''
    live_pid() {
      [ -f "$1" ] || return 1
      p=$(cat "$1" 2>/dev/null) || return 1
      case $p in ""|*[!0-9]*) return 1;; esac
      [ -r "/proc/$p/cmdline" ] && tr '\0' ' ' < "/proc/$p/cmdline" | grep -q "$2" || return 1
      echo "$p"
    }
    run=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  '';
  # Hyper+g: hide/show the card if it runs, else start it detached.
  aionmeterOverlayToggle = pkgs.writeShellScriptBin "aionmeter-overlay-toggle" ''
    ${livePid}
    if p=$(live_pid "$run/aionmeter-overlay.pid" AionMeter.Overlay.dll); then
      exec kill -USR2 "$p"
    fi
    exec setsid -f ${aionmeterOverlay}/bin/aionmeter-overlay </dev/null >/dev/null 2>&1
  '';
  # Hyper+Shift+g: click-through toggle of the card; the Avalonia UI when the card is not running.
  aionmeterClicks = pkgs.writeShellScriptBin "aionmeter-clicks" ''
    ${livePid}
    if p=$(live_pid "$run/aionmeter-overlay.pid" AionMeter.Overlay.dll) || p=$(live_pid "$run/aionmeter-ui.pid" AionMeter.Linux.dll); then
      exec kill -USR1 "$p"
    fi
    exec ${pkgs.libnotify}/bin/notify-send -a "AION 2 meter" "aionmeter" "No overlay running"
  '';
in
{
  config = lib.mkIf (cfg.aion2MeterDaemonEnable or false) {
    # Must exist before the unit starts: ReadWritePaths of a missing dir fails the namespace setup.
    systemd.tmpfiles.rules = [ "d ${dataDir} 0755 ${user} users -" ];
    environment.systemPackages = [ aionmeterUi aionmeterOverlay aionmeterOverlayToggle aionmeterClicks ];
    # The card's CSS asks for Inter, then Noto Sans / DejaVu Sans.
    fonts.packages = [ pkgs.inter ];

    systemd.services.aion2-meter-daemon = {
      description = "AION 2 DPS meter daemon (headless capture)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "${installDir}/aionmeter-daemon.dll";
      # SharpPcap dlopens libpcap.so. getLib: libpcap is split and ${pkgs.libpcap}/lib holds only pkgconfig
      # (measured 2026-10-13: the daemon then reports "No capture (Npcap missing)").
      environment = {
        LD_LIBRARY_PATH = "${lib.getLib pkgs.libpcap}/lib";
        DOTNET_CLI_TELEMETRY_OPTOUT = "1";
        DOTNET_NOLOGO = "1";
        HOME = home;
      };
      serviceConfig = {
        Type = "simple";
        User = user;
        Group = "users";
        WorkingDirectory = installDir;
        ExecStart = lib.escapeShellArgs ([
          "${pkgs.dotnet-runtime_10}/bin/dotnet"
          "${installDir}/aionmeter-daemon.dll"
          "--data-dir"
          dataDir
          "--socket"
          socketPath
        ] ++ extraArgs);
        RuntimeDirectory = "aionmeter";
        RuntimeDirectoryMode = "0750";
        AmbientCapabilities = [ "CAP_NET_RAW" "CAP_NET_ADMIN" ];
        CapabilityBoundingSet = [ "CAP_NET_RAW" "CAP_NET_ADMIN" ];
        KillSignal = "SIGTERM";
        TimeoutStopSec = 20;
        Restart = "on-failure";
        RestartSec = 10;
        Nice = 5;
        # Modest hardening. Not ProtectHome/ProtectProc: it reads the game's
        # /proc/<pid>/fd and writes into the user's home.
        ProtectSystem = "strict";
        ReadWritePaths = [ dataDir ];
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
      };
    };
  };
}
