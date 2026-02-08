{ pkgs, lib, systemSettings, ... }:

let
  secrets = import ../../secrets/control-panel.nix;

  # Build the native control panel from workspace
  controlPanelNative = pkgs.rustPlatform.buildRustPackage {
    pname = "control-panel-native";
    version = "0.2.0";
    src = ../../apps/control-panel;

    cargoLock = {
      lockFile = ../../apps/control-panel/Cargo.lock;
      allowBuiltinFetchGit = true;
    };

    # Build only the native crate
    cargoBuildFlags = [ "-p" "control-panel-native" ];

    nativeBuildInputs = with pkgs; [
      pkg-config
      makeWrapper
    ];

    buildInputs = with pkgs; [
      openssl
      # GUI dependencies
      wayland
      wayland-protocols
      libxkbcommon
      # For Vulkan/GL rendering
      libGL
      vulkan-loader
    ];

    # Link against system libraries
    OPENSSL_NO_VENDOR = 1;
    PKG_CONFIG_PATH = lib.makeSearchPath "lib/pkgconfig" [
      pkgs.openssl.dev
      pkgs.wayland.dev
      pkgs.libxkbcommon.dev
    ];

    # Runtime library path for GUI
    postInstall = ''
      wrapProgram $out/bin/control-panel \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
          pkgs.wayland
          pkgs.libxkbcommon
          pkgs.libGL
          pkgs.vulkan-loader
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
    exec = "${controlPanelNative}/bin/control-panel";
    icon = "preferences-system";
    categories = [ "Settings" "System" ];
    terminal = false;
  };

in
{
  config = lib.mkIf (systemSettings.controlPanelNativeEnable or false) {
    # Install the native app and desktop entry
    environment.systemPackages = [
      controlPanelNative
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
