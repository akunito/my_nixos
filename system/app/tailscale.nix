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
  acceptDns = systemSettings.tailscaleAcceptDns or true;  # Default true (Tailscale default)

  # Build the tailscale up command for the helper script
  tailscaleUpCmd = lib.concatStringsSep " " (
    [ "${pkgs.tailscale}/bin/tailscale up" ]
    ++ lib.optional hasLoginServer "--login-server=${systemSettings.tailscaleLoginServer}"
    ++ lib.optional isSubnetRouter "--advertise-routes=${lib.concatStringsSep "," systemSettings.tailscaleAdvertiseRoutes}"
    ++ lib.optional isExitNode "--advertise-exit-node"
    ++ lib.optional acceptRoutes "--accept-routes"
    ++ lib.optional (!acceptDns) "--accept-dns=false"
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

  # Environment packages for CLI and GUI access
  environment.systemPackages = [
    pkgs.tailscale
    pkgs.trayscale  # GTK systray GUI for Tailscale
  ];

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
        mkdir -p /var/lib/prometheus-node-exporter/textfile
        PROM_FILE="/var/lib/prometheus-node-exporter/textfile/tailscale.prom"

        # Get Tailscale status
        STATUS=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$STATUS" ]; then
          {
            # Global metrics
            echo "# HELP tailscale_up Tailscale daemon status (1=up, 0=down)"
            echo "# TYPE tailscale_up gauge"
            echo "tailscale_up 1"

            echo "# HELP tailscale_backend_running Headscale connection status (1=connected, 0=disconnected)"
            echo "# TYPE tailscale_backend_running gauge"
            BACKEND_STATE=$(echo "$STATUS" | ${pkgs.jq}/bin/jq -r '.BackendState // "Unknown"')
            if [ "$BACKEND_STATE" = "Running" ]; then
              echo "tailscale_backend_running 1"
            else
              echo "tailscale_backend_running 0"
            fi

            # Count peers and connection types
            PEERS=$(echo "$STATUS" | ${pkgs.jq}/bin/jq '.Peer | length // 0')
            echo "# HELP tailscale_peers Total number of peers"
            echo "# TYPE tailscale_peers gauge"
            echo "tailscale_peers $PEERS"

            # Per-peer metrics
            echo "# HELP tailscale_peer_online Peer online status (1=online, 0=offline)"
            echo "# TYPE tailscale_peer_online gauge"
            echo "# HELP tailscale_peer_direct Peer using direct connection (1=direct, 0=relay)"
            echo "# TYPE tailscale_peer_direct gauge"
            echo "# HELP tailscale_peer_rx_bytes Bytes received from peer"
            echo "# TYPE tailscale_peer_rx_bytes counter"
            echo "# HELP tailscale_peer_tx_bytes Bytes transmitted to peer"
            echo "# TYPE tailscale_peer_tx_bytes counter"
            echo "# HELP tailscale_peer_last_seen_seconds Seconds since peer was last seen"
            echo "# TYPE tailscale_peer_last_seen_seconds gauge"

            DIRECT_COUNT=0
            RELAY_COUNT=0

            # Process each peer
            echo "$STATUS" | ${pkgs.jq}/bin/jq -r '.Peer | to_entries[] | @base64' | while read -r peer_b64; do
              PEER=$(echo "$peer_b64" | base64 -d)

              # Use DNSName (Headscale-assigned name) instead of HostName (device-reported)
              # DNSName is like "android-aga.tailnet.akunito.com." - extract the first part
              DNSNAME=$(echo "$PEER" | ${pkgs.jq}/bin/jq -r '.value.DNSName // ""')
              if [ -n "$DNSNAME" ] && [ "$DNSNAME" != "null" ]; then
                # Extract first part of DNS name (before first dot)
                HOSTNAME=$(echo "$DNSNAME" | cut -d'.' -f1)
              else
                # Fallback to HostName if DNSName not available
                HOSTNAME=$(echo "$PEER" | ${pkgs.jq}/bin/jq -r '.value.HostName // "unknown"' | tr -d '"' | tr ' ' '_')
              fi

              # Get Tailscale IP as additional label
              TAILSCALE_IP=$(echo "$PEER" | ${pkgs.jq}/bin/jq -r '.value.TailscaleIPs[0] // ""')

              # Get user info (from UserID)
              USER_ID=$(echo "$PEER" | ${pkgs.jq}/bin/jq -r '.value.UserID // 0')

              OS=$(echo "$PEER" | ${pkgs.jq}/bin/jq -r '.value.OS // "unknown"')
              ONLINE=$(echo "$PEER" | ${pkgs.jq}/bin/jq -r '.value.Online // false')
              RX_BYTES=$(echo "$PEER" | ${pkgs.jq}/bin/jq -r '.value.RxBytes // 0')
              TX_BYTES=$(echo "$PEER" | ${pkgs.jq}/bin/jq -r '.value.TxBytes // 0')
              CUR_ADDR=$(echo "$PEER" | ${pkgs.jq}/bin/jq -r '.value.CurAddr // ""')
              LAST_SEEN=$(echo "$PEER" | ${pkgs.jq}/bin/jq -r '.value.LastSeen // "0001-01-01T00:00:00Z"')

              # Sanitize hostname for Prometheus label
              HOSTNAME=$(echo "$HOSTNAME" | sed 's/[^a-zA-Z0-9_-]/_/g')
              [ -z "$HOSTNAME" ] && HOSTNAME="unknown"

              # Build labels string with optional tailscale_ip
              if [ -n "$TAILSCALE_IP" ] && [ "$TAILSCALE_IP" != "null" ]; then
                LABELS="hostname=\"$HOSTNAME\",os=\"$OS\",tailscale_ip=\"$TAILSCALE_IP\""
              else
                LABELS="hostname=\"$HOSTNAME\",os=\"$OS\""
              fi

              # Online status
              if [ "$ONLINE" = "true" ]; then
                echo "tailscale_peer_online{$LABELS} 1"
              else
                echo "tailscale_peer_online{$LABELS} 0"
              fi

              # Direct connection status
              if [ -n "$CUR_ADDR" ] && [ "$CUR_ADDR" != "" ] && [ "$CUR_ADDR" != "null" ]; then
                echo "tailscale_peer_direct{$LABELS} 1"
              else
                echo "tailscale_peer_direct{$LABELS} 0"
              fi

              # Traffic stats
              echo "tailscale_peer_rx_bytes{$LABELS} $RX_BYTES"
              echo "tailscale_peer_tx_bytes{$LABELS} $TX_BYTES"

              # Last seen (convert to seconds since epoch if not zero date)
              if [ "$LAST_SEEN" != "0001-01-01T00:00:00Z" ] && [ -n "$LAST_SEEN" ]; then
                LAST_SEEN_EPOCH=$(${pkgs.coreutils}/bin/date -d "$LAST_SEEN" +%s 2>/dev/null || echo "0")
                NOW=$(${pkgs.coreutils}/bin/date +%s)
                if [ "$LAST_SEEN_EPOCH" -gt 0 ]; then
                  SECONDS_AGO=$((NOW - LAST_SEEN_EPOCH))
                  echo "tailscale_peer_last_seen_seconds{$LABELS} $SECONDS_AGO"
                fi
              fi
            done

            # Summary counts
            DIRECT_COUNT=$(echo "$STATUS" | ${pkgs.jq}/bin/jq '[.Peer | to_entries[] | select(.value.CurAddr != "" and .value.CurAddr != null)] | length')
            RELAY_COUNT=$(echo "$STATUS" | ${pkgs.jq}/bin/jq '[.Peer | to_entries[] | select(.value.CurAddr == "" or .value.CurAddr == null)] | length')

            echo "# HELP tailscale_peers_direct Number of peers with direct connections"
            echo "# TYPE tailscale_peers_direct gauge"
            echo "tailscale_peers_direct $DIRECT_COUNT"
            echo "# HELP tailscale_peers_relay Number of peers using relay"
            echo "# TYPE tailscale_peers_relay gauge"
            echo "tailscale_peers_relay $RELAY_COUNT"

          } > "$PROM_FILE.tmp"

          mv "$PROM_FILE.tmp" "$PROM_FILE"
        else
          # Tailscale is not running
          {
            echo "# HELP tailscale_up Tailscale daemon status (1=up, 0=down)"
            echo "# TYPE tailscale_up gauge"
            echo "tailscale_up 0"
            echo "# HELP tailscale_peers Total number of peers"
            echo "# TYPE tailscale_peers gauge"
            echo "tailscale_peers 0"
            echo "# HELP tailscale_backend_running Headscale connection status"
            echo "# TYPE tailscale_backend_running gauge"
            echo "tailscale_backend_running 0"
          } > "$PROM_FILE.tmp"
          mv "$PROM_FILE.tmp" "$PROM_FILE"
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
