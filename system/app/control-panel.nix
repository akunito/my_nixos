{ pkgs, lib, systemSettings, ... }:

let
  secrets = import ../../secrets/control-panel.nix;

  # Build the control panel web server from workspace
  controlPanel = pkgs.rustPlatform.buildRustPackage {
    pname = "control-panel-web";
    version = "0.2.0";
    src = ../../apps/control-panel;

    cargoLock = {
      lockFile = ../../apps/control-panel/Cargo.lock;
      # Allow fetching from network for dependencies
      allowBuiltinFetchGit = true;
    };

    # Build only the web crate
    cargoBuildFlags = [ "-p" "control-panel-web" ];

    nativeBuildInputs = with pkgs; [
      pkg-config
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

    # Set OPENSSL env vars for building
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

      # Set SSH_AUTH_SOCK dynamically based on user ID
      # This enables SSH agent authentication when using encrypted keys
      script = ''
        # Try to find SSH agent socket for the configured user
        USER_ID=$(id -u ${systemSettings.username or "akunito"})
        AGENT_SOCK="/run/user/$USER_ID/ssh-agent"
        GNOME_SOCK="/run/user/$USER_ID/keyring/ssh"
        GPG_SOCK="/run/user/$USER_ID/gnupg/S.gpg-agent.ssh"

        if [ -S "$AGENT_SOCK" ]; then
          export SSH_AUTH_SOCK="$AGENT_SOCK"
          echo "Using SSH agent at $AGENT_SOCK"
        elif [ -S "$GNOME_SOCK" ]; then
          export SSH_AUTH_SOCK="$GNOME_SOCK"
          echo "Using GNOME keyring SSH agent at $GNOME_SOCK"
        elif [ -S "$GPG_SOCK" ]; then
          export SSH_AUTH_SOCK="$GPG_SOCK"
          echo "Using GPG agent SSH at $GPG_SOCK"
        else
          echo "Warning: No SSH agent socket found. SSH operations may fail for encrypted keys."
        fi

        exec ${controlPanel}/bin/control-panel-web
      '';

      serviceConfig = {
        Type = "simple";
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
