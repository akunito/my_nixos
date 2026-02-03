# LXC_proxy Profile Configuration
# Cloudflare Tunnel (native) + Nginx Proxy Manager (Docker) + ACME Certs
#
# Extends LXC-base-config.nix
#
# Services:
#   - cloudflared: Native NixOS service for Cloudflare Tunnel (*.akunito.com)
#   - NPM: Docker container for local reverse proxy (*.local.akunito.com)
#   - ACME: Let's Encrypt wildcard cert for *.local.akunito.com
#
# Migration from Debian cloudflared container (192.168.8.102)

let
  base = import ./LXC-base-config.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "proxy";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_proxy -s -u";
    systemStateVersion = "25.11";

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
    acmeEmail = "diego88aku@gmail.com";
    # Certs stored at /var/lib/acme/local.akunito.com/ and copied to /srv/certs/
    # Setup: echo 'CF_DNS_API_TOKEN=xxx' | sudo tee /etc/secrets/cloudflare-acme

    # === NPM runs in Docker (enabled via base) ===
    # Docker is enabled by default in LXC-base-config.nix (userSettings.dockerEnable = true)
    # Mount /srv/certs in NPM docker-compose for SSL certificates

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
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";

    # Shell color: Cyan for proxy/network services
    starshipHostStyle = "bold #00BFFF";
  };
}
