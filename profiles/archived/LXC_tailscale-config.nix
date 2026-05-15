# LXC_tailscale Profile Configuration
# Tailscale Subnet Router for home network mesh access
#
# Extends LXC-base-config.nix
#
# Purpose:
#   - Subnet router advertising 192.168.8.0/24 and 192.168.20.0/24
#   - Enables direct mesh connectivity to home services from remote locations
#   - Replaces VPS relay bottleneck with direct peer-to-peer connections
#
# After deployment:
#   1. Authenticate: tailscale up --login-server=https://headscale.akunito.com
#   2. Approve routes on Headscale: docker exec headscale headscale routes enable -r <id>
#   3. Verify: tailscale status

let
  base = import ./LXC-base-config.nix;
  secrets = import ../secrets/domains.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "tailscale";
    envProfile = "LXC_tailscale"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_tailscale -s -u";
    systemStateVersion = "25.11";
    serverEnv = "PROD"; # Production infrastructure

    # Firewall ports
    allowedTCPPorts = [
      22    # SSH
      9100  # Prometheus Node Exporter
    ];
    allowedUDPPorts = [
      41641 # Tailscale direct connections
    ];

    # Disable Docker - this is a lightweight routing container
    # Docker is inherited from base but we don't need it
    # Note: dockerEnable is in userSettings, handled there

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Tailscale Subnet Router ===
    tailscaleEnable = true;
    tailscaleLoginServer = "https://${secrets.headscaleDomain}";
    tailscaleAdvertiseRoutes = [
      "192.168.8.0/24"   # Main LAN (LXC containers, desktops)
      "192.168.20.0/24"  # TrueNAS/Storage network
    ];
    tailscaleExitNode = false;   # Not an exit node (just subnet router)
    tailscaleAcceptRoutes = false; # Don't accept routes from other nodes

    # === Prometheus Exporters (enabled from base) ===
    # prometheusExporterEnable = true (from base)
    prometheusExporterCadvisorEnable = false; # No Docker, no cAdvisor

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:10)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:10:00";
    autoUpgradeRestartDocker = false; # No Docker to restart
    autoUserUpdateBranch = "release-25.11";
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
