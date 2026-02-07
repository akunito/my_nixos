# Tailscale/Headscale Mesh VPN Service
#
# Provides secure mesh networking with optional subnet routing and exit node capabilities.
# Supports self-hosted Headscale as coordination server.
#
# Configuration:
#   systemSettings.tailscaleEnable = true;           # Enable Tailscale client
#   systemSettings.tailscaleLoginServer = "https://headscale.example.com";  # Headscale URL
#   systemSettings.tailscaleAdvertiseRoutes = ["192.168.8.0/24"];  # Subnets to advertise
#   systemSettings.tailscaleExitNode = false;        # Act as exit node
#   systemSettings.tailscaleAcceptRoutes = false;    # Accept advertised routes
#
# After deployment, authenticate with:
#   tailscale up --login-server=https://headscale.example.com --advertise-routes=192.168.8.0/24
#
# For subnet router, approve routes on Headscale:
#   docker exec headscale headscale routes list
#   docker exec headscale headscale routes enable -r <route-id>

{ config, lib, pkgs, systemSettings, ... }:

let
  isSubnetRouter = (systemSettings.tailscaleAdvertiseRoutes or []) != [];
  isExitNode = systemSettings.tailscaleExitNode or false;
  hasLoginServer = (systemSettings.tailscaleLoginServer or "") != "";
  acceptRoutes = systemSettings.tailscaleAcceptRoutes or false;

  # Build the tailscale up command for the helper script
  tailscaleUpCmd = lib.concatStringsSep " " (
    [ "${pkgs.tailscale}/bin/tailscale up" ]
    ++ lib.optional hasLoginServer "--login-server=${systemSettings.tailscaleLoginServer}"
    ++ lib.optional isSubnetRouter "--advertise-routes=${lib.concatStringsSep "," systemSettings.tailscaleAdvertiseRoutes}"
    ++ lib.optional isExitNode "--advertise-exit-node"
    ++ lib.optional acceptRoutes "--accept-routes"
  );
in
lib.mkIf (systemSettings.tailscaleEnable or false) {
  # Enable Tailscale service
  services.tailscale = {
    enable = true;
    # Enable routing features for subnet router or exit node
    useRoutingFeatures = lib.mkIf (isSubnetRouter || isExitNode) "server";
  };

  # IP forwarding required for subnet router or exit node
  boot.kernel.sysctl = lib.mkIf (isSubnetRouter || isExitNode) {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Firewall configuration
  networking.firewall = {
    # Trust the Tailscale interface
    trustedInterfaces = [ "tailscale0" ];
    # Tailscale direct connection port (UDP)
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # Environment packages for CLI access
  environment.systemPackages = [ pkgs.tailscale ];

  # Helper script for connecting with the configured settings
  environment.etc."tailscale/connect.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      # Auto-generated Tailscale connect script
      # Run this after deployment to authenticate and configure Tailscale

      echo "Connecting to Tailscale..."
      ${if hasLoginServer then ''
      echo "Login server: ${systemSettings.tailscaleLoginServer}"
      '' else ''
      echo "Using default Tailscale coordination server"
      ''}
      ${if isSubnetRouter then ''
      echo "Advertising routes: ${lib.concatStringsSep ", " systemSettings.tailscaleAdvertiseRoutes}"
      '' else ""}
      ${if isExitNode then ''
      echo "Advertising as exit node"
      '' else ""}

      ${tailscaleUpCmd}
    '';
  };

  # Prometheus metrics export for Tailscale status (optional, when node_exporter is enabled)
  systemd.services.tailscale-metrics = lib.mkIf (config.services.prometheus.exporters.node.enable or false) {
    description = "Export Tailscale metrics for Prometheus";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "tailscale-metrics" ''
        mkdir -p /var/lib/node_exporter/textfile_collector

        # Get Tailscale status
        STATUS=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$STATUS" ]; then
          # Tailscale is running and responding
          echo "tailscale_up 1" > /var/lib/node_exporter/textfile_collector/tailscale.prom.tmp

          # Count connected peers
          PEERS=$(echo "$STATUS" | ${pkgs.jq}/bin/jq '.Peer | length // 0')
          echo "tailscale_peers $PEERS" >> /var/lib/node_exporter/textfile_collector/tailscale.prom.tmp

          # Check if we're connected to coordination server
          BACKEND_STATE=$(echo "$STATUS" | ${pkgs.jq}/bin/jq -r '.BackendState // "Unknown"')
          if [ "$BACKEND_STATE" = "Running" ]; then
            echo "tailscale_backend_running 1" >> /var/lib/node_exporter/textfile_collector/tailscale.prom.tmp
          else
            echo "tailscale_backend_running 0" >> /var/lib/node_exporter/textfile_collector/tailscale.prom.tmp
          fi

          # Check direct vs relay connections (from peer data)
          DIRECT=0
          RELAY=0
          for peer in $(echo "$STATUS" | ${pkgs.jq}/bin/jq -r '.Peer | keys[]' 2>/dev/null); do
            DIRECT_CONN=$(echo "$STATUS" | ${pkgs.jq}/bin/jq -r ".Peer[\"$peer\"].CurAddr" 2>/dev/null)
            if [ -n "$DIRECT_CONN" ] && [ "$DIRECT_CONN" != "null" ]; then
              DIRECT=$((DIRECT + 1))
            else
              RELAY=$((RELAY + 1))
            fi
          done
          echo "tailscale_peers_direct $DIRECT" >> /var/lib/node_exporter/textfile_collector/tailscale.prom.tmp
          echo "tailscale_peers_relay $RELAY" >> /var/lib/node_exporter/textfile_collector/tailscale.prom.tmp

          # Atomic move
          mv /var/lib/node_exporter/textfile_collector/tailscale.prom.tmp /var/lib/node_exporter/textfile_collector/tailscale.prom
        else
          # Tailscale is not running or not responding
          echo "tailscale_up 0" > /var/lib/node_exporter/textfile_collector/tailscale.prom.tmp
          echo "tailscale_peers 0" >> /var/lib/node_exporter/textfile_collector/tailscale.prom.tmp
          echo "tailscale_backend_running 0" >> /var/lib/node_exporter/textfile_collector/tailscale.prom.tmp
          mv /var/lib/node_exporter/textfile_collector/tailscale.prom.tmp /var/lib/node_exporter/textfile_collector/tailscale.prom
        fi
      '';
    };
  };

  # Timer to update metrics every minute
  systemd.timers.tailscale-metrics = lib.mkIf (config.services.prometheus.exporters.node.enable or false) {
    description = "Timer for Tailscale metrics export";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "60s";
    };
  };
}
