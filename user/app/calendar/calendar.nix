{ config, pkgs, lib, systemSettings, ... }:

let
  # Typelibs needed by gi.require_version() inside eds-refresh.py.
  # EDataServer.typelib transitively imports libxml2 (from gobject-introspection
  # itself), GLib/Gio (glib), libsoup, json-glib, libnotify, libical. Missing
  # any one -> the gi import fails at runtime.
  edsTypelibPath = lib.makeSearchPath "lib/girepository-1.0" [
    pkgs.evolution-data-server
    pkgs.gobject-introspection
    pkgs.glib
    pkgs.libsoup_3
    pkgs.json-glib
    pkgs.libnotify
    pkgs.libical
  ];
  edsRefreshWrapper = pkgs.writeShellApplication {
    name = "eds-refresh";
    runtimeInputs = [
      pkgs.evolution-data-server
      (pkgs.python3.withPackages (ps: [ ps.pygobject3 ]))
    ];
    text = ''
      export GI_TYPELIB_PATH="${edsTypelibPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
      exec python3 "${config.home.homeDirectory}/.config/sway/scripts/eds-refresh.py" "$@"
    '';
  };
in
{
  config = lib.mkIf systemSettings.goaCalendarEnable {
    home.packages = with pkgs; [
      gnome-calendar
      gnome-control-center
      edsRefreshWrapper
    ];

    home.file.".config/sway/scripts/waybar-gcal.sh" = {
      source = ../../wm/sway/scripts/waybar-gcal.sh;
      executable = true;
    };

    home.file.".config/sway/scripts/online-accounts-launch.sh" = {
      source = ../../wm/sway/scripts/online-accounts-launch.sh;
      executable = true;
    };

    home.file.".config/sway/scripts/eds-refresh.py" = {
      source = ../../wm/sway/scripts/eds-refresh.py;
      executable = true;
    };

    # Desktop entry: surfaces "Online Accounts" in rofi/wofi/app launchers
    # so the GOA sign-in is one click away instead of a memorized env-trick command.
    xdg.desktopEntries."online-accounts" = {
      name = "Online Accounts (sign in)";
      genericName = "Add Google / Nextcloud / Microsoft accounts for Calendar & Contacts";
      comment = "Sign in via GNOME Online Accounts (wraps gnome-control-center with XDG_CURRENT_DESKTOP=GNOME)";
      exec = "${config.home.homeDirectory}/.config/sway/scripts/online-accounts-launch.sh";
      icon = "preferences-system-online-accounts";
      terminal = false;
      categories = [ "Settings" "Network" ];
    };

    # EDS calendar refresh: ECal client connect+refresh+disconnect for every
    # enabled calendar source. Triggers CalDAV PROPFIND against Google and
    # updates the SQLite cache that the Waybar widget reads.
    systemd.user.services."eds-refresh" = {
      Unit = {
        Description = "Refresh evolution-data-server calendar caches";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${edsRefreshWrapper}/bin/eds-refresh";
      };
    };

    # Run once at sway-session start, then every 30 min while the session is up.
    systemd.user.timers."eds-refresh" = {
      Unit = {
        Description = "Periodic EDS calendar refresh (every 30 min)";
        PartOf = [ "graphical-session.target" ];
      };
      Timer = {
        OnStartupSec = "30s";    # first run shortly after session start
        OnUnitActiveSec = "30m"; # then every 30 minutes
        Unit = "eds-refresh.service";
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
