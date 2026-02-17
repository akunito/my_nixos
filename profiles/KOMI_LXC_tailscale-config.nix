# KOMI_LXC_tailscale Profile Configuration
# Tailscale Subnet Router for Komi's home network mesh access
#
# Container specs:
# - IP: 192.168.8.14
# - RAM: 1024 MB
# - vCPU: 1
# - Disk: 8 GB
#
# Purpose:
#   - Subnet router advertising 192.168.8.0/24 (temporary, will change to 192.168.1.0/24)
#   - Enables direct mesh connectivity to home services from remote locations
#
# After deployment:
#   1. Authenticate: tailscale up --login-server=https://<headscale-domain>
#   2. Approve routes on Headscale
#   3. Verify: tailscale status

let
  base = import ./KOMI_LXC-base-config.nix;
  secrets = import ../secrets/komi/secrets.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "komi-tailscale";
    envProfile = "KOMI_LXC_tailscale"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles KOMI_LXC_tailscale -s -u";
    systemStateVersion = "25.11";
    serverEnv = "PROD"; # Production infrastructure

    # Network
    ipAddress = "192.168.8.14";
    nameServers = [ "192.168.8.1" ];

    # Firewall ports
    allowedTCPPorts = [
      22    # SSH
      9100  # Prometheus Node Exporter
    ];
    allowedUDPPorts = [
      41641 # Tailscale direct connections
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Tailscale Subnet Router ===
    tailscaleEnable = true;
    tailscaleLoginServer = "https://${secrets.headscaleDomain}";
    tailscaleAdvertiseRoutes = [
      "192.168.8.0/24"   # Current LAN (will change to 192.168.1.0/24 after network migration)
    ];
    tailscaleExitNode = false;
    tailscaleAcceptRoutes = false;

    # === Prometheus Exporters ===
    prometheusExporterCadvisorEnable = false; # No Docker, no cAdvisor

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:10)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:10:00";
    autoUpgradeRestartDocker = false;
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

    # Disable Docker for this lightweight container
    dockerEnable = false;

    # Shell color: Green for networking/routing services
    starshipHostStyle = "bold #00FF7F";

    # Minimal packages - routing container
    homePackages = pkgs: pkgs-unstable: [
      pkgs.zsh
      pkgs.git
    ];
  };
}
