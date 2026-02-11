{ pkgs, lib, systemSettings, ... }:

let
  secrets = import ../../secrets/control-panel.nix;

  # Build the web control panel (standalone server binary)
  controlPanelWeb = pkgs.rustPlatform.buildRustPackage {
    pname = "control-panel-web";
    version = "0.2.0";
    src = ../../apps/control-panel;

    cargoLock = {
      lockFile = ../../apps/control-panel/Cargo.lock;
      allowBuiltinFetchGit = true;
    };

    # Build only the web crate
    cargoBuildFlags = [ "-p" "control-panel-web" ];

    nativeBuildInputs = with pkgs; [
      pkg-config
      makeWrapper
    ];

    buildInputs = with pkgs; [
      openssl
      # Workspace includes tauri-app which pulls in GTK/WebKit deps at resolution time
      webkitgtk_4_1
      gtk3
      glib
      cairo
      pango
      gdk-pixbuf
      libsoup_3
    ];

    OPENSSL_NO_VENDOR = 1;
    PKG_CONFIG_PATH = lib.makeSearchPath "lib/pkgconfig" [
      pkgs.openssl.dev
      pkgs.webkitgtk_4_1.dev
      pkgs.gtk3.dev
      pkgs.glib.dev
      pkgs.cairo.dev
      pkgs.pango.dev
      pkgs.gdk-pixbuf.dev
      pkgs.libsoup_3.dev
    ];
  };

  # Build the Tauri desktop app (wraps the web server in a native window)
  controlPanelDesktop = pkgs.rustPlatform.buildRustPackage {
    pname = "control-panel-desktop";
    version = "0.2.0";
    src = ../../apps/control-panel;

    cargoLock = {
      lockFile = ../../apps/control-panel/Cargo.lock;
      allowBuiltinFetchGit = true;
    };

    # Build the Tauri crate
    cargoBuildFlags = [ "-p" "control-panel-desktop" ];

    nativeBuildInputs = with pkgs; [
      pkg-config
      makeWrapper
    ];

    buildInputs = with pkgs; [
      openssl
      # Tauri/WebKitGTK dependencies
      webkitgtk_4_1
      gtk3
      glib
      cairo
      pango
      gdk-pixbuf
      libsoup_3
      # Wayland support
      wayland
      libxkbcommon
    ];

    OPENSSL_NO_VENDOR = 1;
    PKG_CONFIG_PATH = lib.makeSearchPath "lib/pkgconfig" [
      pkgs.openssl.dev
      pkgs.webkitgtk_4_1.dev
      pkgs.gtk3.dev
      pkgs.glib.dev
      pkgs.cairo.dev
      pkgs.pango.dev
      pkgs.gdk-pixbuf.dev
      pkgs.libsoup_3.dev
    ];

    # Runtime library path for WebKitGTK
    postInstall = ''
      wrapProgram $out/bin/control-panel-desktop \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
          pkgs.webkitgtk_4_1
          pkgs.gtk3
          pkgs.wayland
          pkgs.libxkbcommon
        ]}
    '';
  };

  # Generate TOML config from secrets
  configFile = pkgs.writeText "control-panel-config.toml" ''
    [server]
    host = "0.0.0.0"
    port = ${toString (systemSettings.controlPanelPort or 3100)}

    [auth]
    username = "${secrets.httpAuthUser}"
    password = "${secrets.httpAuthPassword}"

    [ssh]
    private_key_path = "${secrets.sshPrivateKeyPath}"
    default_user = "${secrets.sshUser}"

    [proxmox]
    host = "${secrets.proxmox.host}"
    user = "${secrets.proxmox.user}"

    [dotfiles]
    path = "${systemSettings.dotfilesPath or "/home/akunito/.dotfiles"}"

    ${lib.concatMapStringsSep "\n" (node: ''
    [[docker_nodes]]
    name = "${node.name}"
    host = "${node.host}"
    ctid = ${toString node.ctid}
    '') secrets.dockerNodes}

    ${lib.concatMapStringsSep "\n" (profile: ''
    [[profiles]]
    name = "${profile.name}"
    type = "${profile.type}"
    hostname = "${profile.hostname}"
    ${lib.optionalString (profile ? ip) ''ip = "${profile.ip}"''}
    ${lib.optionalString (profile ? ctid) ''ctid = ${toString profile.ctid}''}
    ${lib.optionalString (profile ? baseProfile) ''base_profile = "${profile.baseProfile}"''}
    '') secrets.profiles}

    ${lib.optionalString (secrets ? grafana) ''
    [grafana]
    base_url = "${secrets.grafana.baseUrl}"

    ${lib.concatMapStringsSep "\n" (dashboard: ''
    [[grafana.dashboards]]
    name = "${dashboard.name}"
    uid = "${dashboard.uid}"
    slug = "${dashboard.slug}"
    '') secrets.grafana.dashboards}
    ''}
  '';

  # Desktop entry for application menu
  desktopItem = pkgs.makeDesktopItem {
    name = "control-panel";
    desktopName = "NixOS Control Panel";
    genericName = "Infrastructure Management";
    comment = "Manage NixOS infrastructure, Docker containers, and deployments";
    exec = "${controlPanelDesktop}/bin/control-panel-desktop";
    icon = "preferences-system";
    categories = [ "Settings" "System" ];
    terminal = false;
  };

in
{
  config = lib.mkIf (systemSettings.controlPanelNativeEnable or false) {
    # Install the desktop app and web server
    environment.systemPackages = [
      controlPanelDesktop
      controlPanelWeb
      desktopItem
    ];

    # Environment variable for config path
    environment.sessionVariables = {
      CONTROL_PANEL_CONFIG = "${configFile}";
    };

    # Also set it in /etc/profile for non-session access
    environment.etc."control-panel/config.toml".source = configFile;
  };
}
