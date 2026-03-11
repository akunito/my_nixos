# Egress Monitoring — Daily Outbound Connection Audit (SEC-AUDIT-04)
#
# Logs all non-loopback ESTABLISHED outbound connections to a file
# and exports as Prometheus textfile metrics for alerting on unexpected destinations.
#
# Configuration:
#   systemSettings.egressAuditEnable = true;
#
# Log output: /var/log/egress-audit.log
# Prometheus metrics: /var/lib/prometheus-node-exporter/textfile/egress_audit.prom

{ config, lib, pkgs, systemSettings, ... }:

lib.mkIf (systemSettings.egressAuditEnable or false) {
  systemd.services.egress-audit = {
    description = "Audit outbound network connections";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "egress-audit" ''
        LOG="/var/log/egress-audit.log"
        PROM_DIR="/var/lib/prometheus-node-exporter/textfile"

        # Log header with timestamp
        echo "=== Egress audit $(date -Iseconds) ===" >> "$LOG"

        # Capture all non-loopback ESTABLISHED TCP connections
        ${pkgs.iproute2}/bin/ss -tnp state established \
          | grep -v '127.0.0.1' \
          | grep -v '::1' \
          >> "$LOG" 2>&1

        echo "" >> "$LOG"

        # Count unique remote IPs for Prometheus
        REMOTE_COUNT=$(${pkgs.iproute2}/bin/ss -tn state established \
          | grep -v '127.0.0.1' | grep -v '::1' | grep -v 'Recv-Q' \
          | awk '{print $4}' | cut -d: -f1 | sort -u | wc -l)

        # Export as Prometheus metric (if node-exporter textfile dir exists)
        if [ -d "$PROM_DIR" ]; then
          {
            echo "# HELP egress_unique_remote_ips Number of unique remote IPs with established connections"
            echo "# TYPE egress_unique_remote_ips gauge"
            echo "egress_unique_remote_ips $REMOTE_COUNT"
          } > "$PROM_DIR/egress_audit.prom.tmp"
          mv "$PROM_DIR/egress_audit.prom.tmp" "$PROM_DIR/egress_audit.prom"
        fi
      '';
    };
  };

  systemd.timers.egress-audit = {
    description = "Timer for daily egress audit";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # Rotate the log file
  services.logrotate.settings.egress-audit = {
    files = "/var/log/egress-audit.log";
    frequency = "weekly";
    rotate = 4;
    compress = true;
    missingok = true;
    notifempty = true;
  };
}
