{ pkgs, lib, systemSettings, ... }:

let
  secrets = import ../../secrets/control-panel.nix;

  # Build the control panel from source
  controlPanel = pkgs.rustPlatform.buildRustPackage {
    pname = "control-panel";
    version = "0.1.0";
    src = ../../apps/control-panel;

    cargoLock = {
      lockFile = ../../apps/control-panel/Cargo.lock;
      # Allow fetching from network for dependencies
      allowBuiltinFetchGit = true;
    };

    nativeBuildInputs = with pkgs; [
      pkg-config
    ];

    buildInputs = with pkgs; [
      openssl
    ];

    # Set OPENSSL env vars for building
    OPENSSL_NO_VENDOR = 1;
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
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

in
{
  config = lib.mkIf (systemSettings.controlPanelEnable or false) {
    # Create systemd service
    systemd.services.control-panel = {
      description = "NixOS Infrastructure Control Panel";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${controlPanel}/bin/control-panel";
        Environment = [
          "CONFIG_PATH=${configFile}"
          "RUST_LOG=info"
        ];
        Restart = "always";
        RestartSec = 5;
        User = systemSettings.username or "akunito";
        Group = "users";
        WorkingDirectory = systemSettings.dotfilesPath or "/home/akunito/.dotfiles";

        # Hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        NoNewPrivileges = true;
        ReadWritePaths = [
          # Allow SSH agent socket access
          "/run/user"
        ];
      };
    };

    # Open firewall port (local network only)
    networking.firewall.allowedTCPPorts = [
      (systemSettings.controlPanelPort or 3100)
    ];
  };
}
