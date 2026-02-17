# KOMI_LXC_mailer Profile Configuration
# Mail relay service and uptime monitoring (Kuma)
# Hosts docker containers for mail services and kuma monitoring
#
# Container specs:
# - IP: 192.168.1.11
# - RAM: 1024 MB
# - vCPU: 1
# - Disk: 10 GB

let
  base = import ./KOMI_LXC-base-config.nix;
  secrets = import ../secrets/komi/secrets.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "komi-mailer";
    envProfile = "KOMI_LXC_mailer"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles KOMI_LXC_mailer -s -u";
    systemStateVersion = "25.11";
    serverEnv = "PROD"; # Production environment

    # Network
    ipAddress = "192.168.1.11";
    nameServers = [ "192.168.1.1" ];

    # Firewall - Add SMTP port for mail service
    allowedTCPPorts = [
      22    # SSH
      25    # SMTP (mail service)
      80    # HTTP
      443   # HTTPS
      3000  # Web apps
      3001  # Kuma monitoring
      9100  # Prometheus Node Exporter
      9092  # cAdvisor (Docker metrics)
    ];

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:35)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:35:00";
    autoUpgradeRestartDocker = false;
    autoUserUpdateBranch = "release-25.11";

    # ============================================================================
    # EMAIL NOTIFICATIONS (Auto-update failure alerts)
    # ============================================================================
    notificationOnFailureEnable = true;
    notificationSmtpHost = "192.168.1.11"; # Self (this IS the mailer)
    notificationSmtpPort = 25;
    notificationSmtpAuth = false;
    notificationSmtpTls = false;
    notificationFromEmail = secrets.notificationFromEmail;
    notificationToEmail = secrets.alertEmail;
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";
  };
}
