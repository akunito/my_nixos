# VPS_PROD Profile Configuration
# Production VPS on Netcup RS 4000 G12 (Nuremberg)
#
# Extends VPS-base-config.nix
#
# Phase 1: Minimal — just Tailscale for connectivity
# Later phases will enable: PostgreSQL, Redis, Docker services, monitoring, etc.

let
  base = import ./VPS-base-config.nix;
  secrets = import ../secrets/domains.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "vps-prod";
    envProfile = "VPS_PROD";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles VPS_PROD -s -u -d";

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Tailscale (Phase 1 — first thing needed) ===
    tailscaleEnable = true;
    tailscaleLoginServer = "https://${secrets.headscaleDomain}";
    tailscaleAcceptRoutes = true; # Accept routes from home subnet router
    tailscaleAcceptDns = true;

    # === Package Modules ===
    systemBasicToolsEnable = true;
    systemNetworkToolsEnable = false;

    # === System Services (ALL DISABLED — Phase 1 minimal) ===
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = false;
    xboxControllerEnable = false;
    appImageEnable = false;

    # === Homelab Services (enabled incrementally per migration phases) ===
    # postgresqlServerEnable = false;  # Phase 2
    # mariadbServerEnable = false;     # Phase 2
    # redisServerEnable = false;       # Phase 2
    # pgBouncerEnable = false;         # Phase 2
    # cloudflaredEnable = false;       # Phase 2
    # acmeEnable = false;              # Phase 2
    # grafanaEnable = false;           # Phase 2
    # homelabDockerEnable = false;     # Phase 3
    # headscaleEnable = false;         # Phase 2
    # wireguardServerEnable = false;   # Phase 2

    # ============================================================================
    # EMAIL NOTIFICATIONS (for future auto-update failures)
    # ============================================================================
    notificationOnFailureEnable = false; # Enable after SMTP relay is set up
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";
  };
}
