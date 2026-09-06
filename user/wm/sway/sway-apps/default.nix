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
        --prefix PATH : "${lib.makeBinPath [ pkgs.git pkgs.libnotify pkgs.coreutils ]}"
      )
    '';
    doCheck = false;
    meta.description = "Window rules and startup apps manager for Sway";
    meta.mainProgram = "sway-apps";
  };
in
{
  config = lib.mkIf enabled {
    home.packages = [ sway-apps ];

    # Published so swayfx-config.nix / startup-apps.nix can call it by store path.
    user.wm.sway._internal.scripts.swayApps = sway-apps;

    xdg.configFile."sway-apps/theme-stylix.css" = lib.mkIf stylixAvailable { text = stylixCss; };

    # Regenerate the include from the repo state on every activation. No
    # reload here: the session picks it up on the next reload/login, and the
    # tool reloads itself after every edit. No git: activation must never
    # create commits.
    home.activation.swayAppsGenerate = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -d "${dotfiles}/user/wm/sway/apps" ]; then
        SWAY_APPS_GIT=0 ${sway-apps}/bin/sway-apps --json apply --no-reload --no-validate >/dev/null 2>&1 \
          || echo "sway-apps: include generation failed (run 'sway-apps doctor')" >&2
      fi
    '';
  };
}
