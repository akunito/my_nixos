# sway-apps: window rules + manual startup apps manager (CLI now, GTK4 GUI next).
#
# State lives in the repo (user/wm/sway/apps/*.json) and is edited at runtime by
# the tool, which auto-commits. Nix only (1) installs the tool, (2) points it at
# the right files, and (3) regenerates the Sway include on every activation so
# a fresh deploy never boots with a stale or missing ~/.config/sway/sway-apps.conf.
# The include line itself and the removal of the legacy hardcoded rules are in
# swayfx-config.nix, keyed on the same flag.
{ config, lib, pkgs, systemSettings, ... }:

let
  enabled = systemSettings.swayAppsEnable or false;
  useFx = systemSettings.swayUseSwayfx or true;
  swayPkg = if useFx then pkgs.swayfx else pkgs.sway;
  dotfiles = systemSettings.dotfilesPath or "${config.home.homeDirectory}/.dotfiles";
  profile = systemSettings.envProfile or "default";
  # paths.SWAY_FEATURES: which patch-only commands this machine's sway accepts.
  swayFeatures = lib.concatStringsSep "," (
    lib.optional (systemSettings.swayWindowStacking or false) "stacking"
    ++ lib.optional (systemSettings.swayAboveFullscreen or false) "above_fullscreen"
    ++ lib.optional (systemSettings.swayXwaylandZeroScaling or false) "xwayland_zero_scaling"
    ++ lib.optional (systemSettings.swayAppsOwnsOutputs or false) "owns_outputs");

  # Stylix -> GTK CSS tokens. Written only when stylix is on; the GUI falls
  # back to its built-in dark palette otherwise. Same guard as extras.nix.
  stylixAvailable =
    (systemSettings.stylixEnable or false)
    && (config ? lib) && (config.lib ? stylix) && (config.lib.stylix ? colors);
  stylixCss =
    let c = config.lib.stylix.colors; in ''
      /* generated from stylix (base16 scheme: ${c.scheme or "unknown"}) */
      @define-color sa_base00 #${c.base00};
      @define-color sa_base01 #${c.base01};
      @define-color sa_base02 #${c.base02};
      @define-color sa_base03 #${c.base03};
      @define-color sa_base04 #${c.base04};
      @define-color sa_base05 #${c.base05};
      @define-color sa_base06 #${c.base06};
      @define-color sa_base07 #${c.base07};
      @define-color sa_base08 #${c.base08};
      @define-color sa_base09 #${c.base09};
      @define-color sa_base0A #${c.base0A};
      @define-color sa_base0B #${c.base0B};
      @define-color sa_base0C #${c.base0C};
      @define-color sa_base0D #${c.base0D};
      @define-color sa_base0E #${c.base0E};
      @define-color sa_base0F #${c.base0F};
    '';

  sway-apps = pkgs.python3Packages.buildPythonApplication {
    pname = "sway-apps";
    version = "0.1.0";
    pyproject = true;
    src = lib.cleanSource ./.;
    build-system = [ pkgs.python3Packages.setuptools ];
    dependencies = [ pkgs.python3Packages.pygobject3 ];
    nativeBuildInputs = [ pkgs.wrapGAppsHook4 pkgs.gobject-introspection ];
    buildInputs = [ pkgs.gtk4 pkgs.libadwaita ];
    # The GTK4 wrapper hook must not double-wrap the python entry point.
    dontWrapGApps = true;
    preFixup = ''
      makeWrapperArgs+=(
        "''${gappsWrapperArgs[@]}"
        --set-default SWAY_APPS_DOTFILES "${dotfiles}"
        --set-default SWAY_APPS_STATE_DIR "${dotfiles}/user/wm/sway/apps"
        --set-default SWAY_APPS_PROFILE "${profile}"
        --set-default SWAY_APPS_SWAY_BIN "${swayPkg}/bin/sway"
        --set-default SWAY_APPS_SWAYMSG_BIN "${swayPkg}/bin/swaymsg"
        --set-default SWAY_APPS_SWAY_FEATURES "${swayFeatures}"
        --prefix PATH : "${lib.makeBinPath [ pkgs.git pkgs.libnotify pkgs.coreutils ]}"
      )
    '';
    doCheck = false;
    meta.description = "Window rules and startup apps manager for Sway";
    meta.mainProgram = "sway-apps";
  };
  # On-demand driven suite (tests/e2e): nested headless sway, private D-Bus,
  # virtual pointer. Runs the repo checkout (not the installed package), so a
  # worktree can be tested before it is deployed:
  #   sway-apps-e2e [-k SUBSTR] [--list] [--keep]   (SWAY_APPS_E2E_REPO=<dir> to point elsewhere)
  e2ePython = pkgs.python3.withPackages (p: [ p.pygobject3 ]);
  sway-apps-e2e = pkgs.writeShellApplication {
    name = "sway-apps-e2e";
    runtimeInputs = [ pkgs.dbus pkgs.coreutils ];
    text = ''
      repo="''${SWAY_APPS_E2E_REPO:-${dotfiles}}"
      export E2E_SWAY="''${E2E_SWAY:-${swayPkg}/bin/sway}"
      export E2E_WAYBAR="''${E2E_WAYBAR:-${config.programs.waybar.package}/bin/waybar}"
      export E2E_GRIM="${pkgs.grim}/bin/grim"
      export E2E_PYTHON="${e2ePython}/bin/python3"
      export GI_TYPELIB_PATH="${lib.makeSearchPathOutput "lib" "lib/girepository-1.0" (with pkgs; [ gtk4 glib gdk-pixbuf pango harfbuzz graphene gobject-introspection ])}"
      export E2E_TMP="''${E2E_TMP:-''${XDG_RUNTIME_DIR:-/tmp}/sway-apps-e2e}"
      export E2E_RUNTIME_ROOT="''${E2E_RUNTIME_ROOT:-''${XDG_RUNTIME_DIR:-/tmp}}"
      mkdir -p "$E2E_TMP"
      unset LD_LIBRARY_PATH
      cd "$repo/user/wm/sway/sway-apps/tests/e2e"
      exec "$E2E_PYTHON" run.py "$@"
    '';
  };
in
{
  config = lib.mkIf enabled {
    home.packages = [ sway-apps sway-apps-e2e ];

    # Published so swayfx-config.nix / startup-apps.nix can call it by store path.
    user.wm.sway._internal.scripts.swayApps = sway-apps;

    # Output-hotplug reconciler: adopts unknown outputs (settings.auto_adopt),
    # registers the pins with the running compositor and re-applies the
    # "always connected" connector forces. Never moves windows.
    systemd.user.services.sway-apps-watch = {
      Unit = {
        Description = "sway-apps: react to monitor hotplug (adopt, pin, force)";
        PartOf = [ "sway-session.target" ];
        After = [ "sway-session.target" ];
      };
      Service = {
        Type = "simple";
        EnvironmentFile = "-%t/sway-session.env";
        ExecStart = "${sway-apps}/bin/sway-apps watch";
        # Every feature hotkey is a `nop` binding this daemon reacts to: down = dead keys.
        Restart = "always";
        RestartSec = "1";
      };
      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };

    # Owns org.kde.StatusNotifierWatcher so Waybar restarts/reloads never lose
    # tray items (sway_apps/tray.py says why; Type=dbus orders on the name).
    systemd.user.services.sway-apps-tray = {
      Unit = {
        Description = "sway-apps: StatusNotifierWatcher (tray items survive Waybar restarts)";
        PartOf = [ "sway-session.target" ];
        After = [ "sway-session.target" ];
        Before = [ "waybar.service" ];
      };
      Service = {
        Type = "dbus";
        BusName = "org.kde.StatusNotifierWatcher";
        ExecStart = "${sway-apps}/bin/sway-apps tray-watcher";
        Restart = "always";
        RestartSec = "1";
      };
      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };

    xdg.configFile."sway-apps/theme-stylix.css" = lib.mkIf stylixAvailable { text = stylixCss; };

    # Regenerate the include from the repo state on every activation. No
    # reload here: the session picks it up on the next reload/login, and the
    # tool reloads itself after every edit. No git: activation must never
    # create commits. The apply also writes the Waybar config/CSS and the sway
    # bar blocks (sway_apps/waybar.py), after linkGeneration so HM's old
    # waybar/config symlink is gone; `waybar apply` then reloads Waybar (and
    # sway, only when a bar id is new to it) if the generated config changed,
    # as HM's own onChange did. Without a session it is left for the watch
    # daemon at login.
    home.activation.swayAppsGenerate = lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "writeBoundary" "linkGeneration" ] ''
      if [ -d "${dotfiles}/user/wm/sway/apps" ]; then
        SWAY_APPS_GIT=0 ${sway-apps}/bin/sway-apps --json apply --no-reload --no-validate >/dev/null 2>&1 \
          || echo "sway-apps: include generation failed (run 'sway-apps doctor')" >&2
        SWAY_APPS_GIT=0 ${sway-apps}/bin/sway-apps --json waybar apply >/dev/null 2>&1 \
          || echo "sway-apps: waybar generation failed (run 'sway-apps waybar apply')" >&2
      fi
    '';
  };
}
