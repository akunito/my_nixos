# KOMI_LXC_proxy Profile Configuration
# Cloudflare Tunnel (native) + Nginx Proxy Manager (Docker) + ACME Certs
#
# Container specs:
# - IP: 192.168.8.13
# - RAM: 1024 MB
# - vCPU: 1
# - Disk: 10 GB
#
# Services:
#   - cloudflared: Native NixOS service for Cloudflare Tunnel
#   - NPM: Docker container for local reverse proxy
#   - ACME: Let's Encrypt wildcard cert

let
  base = import ./KOMI_LXC-base-config.nix;
  secrets = import ../secrets/komi/secrets.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "komi-proxy";
    envProfile = "KOMI_LXC_proxy"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles KOMI_LXC_proxy -s -u";
    systemStateVersion = "25.11";
    serverEnv = "PROD"; # Production environment

    # Domain settings (passed to acme.nix)
    wildcardLocal = secrets.wildcardLocal;

    # Network
    ipAddress = "192.168.8.13";
    nameServers = [ "192.168.8.1" ];

    # Firewall ports
    allowedTCPPorts = [
      22    # SSH
      80    # HTTP (NPM)
      443   # HTTPS (NPM)
      81    # NPM Admin UI
      9100  # Prometheus Node Exporter
      9092  # cAdvisor (Docker metrics)
    ];
    allowedUDPPorts = [ ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Cloudflare Tunnel (Native Service) ===
    cloudflaredEnable = true;

    # === ACME Certificates (Let's Encrypt via Cloudflare DNS) ===
    acmeEnable = true;
    acmeEmail = secrets.acmeEmail;

    # === Prometheus Exporters (enabled from base) ===
    # prometheusExporterEnable = true (from base)
    # prometheusExporterCadvisorEnable = true (from base)

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:05)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:05:00";
    autoUpgradeRestartDocker = true;  # Restart NPM after upgrades
    autoUserUpdateBranch = "release-25.11";

    # ============================================================================
    # EMAIL NOTIFICATIONS (Auto-update failure alerts)
    # ============================================================================
    notificationOnFailureEnable = true;
    notificationSmtpHost = "192.168.8.11"; # Komi's mailer
    notificationSmtpPort = 25;
    notificationSmtpAuth = false;
    notificationSmtpTls = false;
    notificationFromEmail = secrets.notificationFromEmail;
    notificationToEmail = secrets.alertEmail;
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";

    # Shell color: Cyan for proxy/network services
    starshipHostStyle = "bold #00BFFF";
  };
}
