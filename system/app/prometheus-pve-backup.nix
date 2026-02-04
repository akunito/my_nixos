# Proxmox Backup Monitoring
#
# Monitors Proxmox VE backup (vzdump) tasks and exposes metrics via textfile collector.
# This runs on the monitoring server and queries the Proxmox API for recent backup status.
#
# Metrics exposed:
#   pve_backup_last_success{vmid, name} - Unix timestamp of last successful backup
#   pve_backup_status{vmid, name} - 1 = success, 0 = failed
#   pve_backup_age_seconds{vmid, name} - Seconds since last successful backup
#
# Feature flag: prometheusPveBackupEnable

{ config, pkgs, lib, systemSettings, ... }:

let
  pveHost = systemSettings.prometheusPveHost or "192.168.8.82";
  pveTokenFile = systemSettings.prometheusPveTokenFile or "/etc/secrets/pve-token";
  pveUser = systemSettings.prometheusPveUser or "prometheus@pve";
  pveTokenName = systemSettings.prometheusPveTokenName or "prometheus";
  textfileDir = "/var/lib/prometheus-node-exporter/textfile";

  # Script to query Proxmox API and write backup metrics
  pveBackupScript = pkgs.writeShellScript "pve-backup-metrics" ''
    #!/bin/bash
    set -euo pipefail

    PVE_HOST="${pveHost}"
    PVE_TOKEN_FILE="${pveTokenFile}"
    PVE_USER="${pveUser}"
    PVE_TOKEN_NAME="${pveTokenName}"
    TEXTFILE="${textfileDir}/pve_backup.prom"
    TEMP_FILE=$(mktemp)

    # Read the API token
    if [ ! -f "$PVE_TOKEN_FILE" ]; then
      echo "Error: PVE token file not found: $PVE_TOKEN_FILE" >&2
      exit 1
    fi
    PVE_TOKEN=$(cat "$PVE_TOKEN_FILE")

    # Get the node name (usually 'pve')
    NODE=$(${pkgs.curl}/bin/curl -sk \
      -H "Authorization: PVEAPIToken=$PVE_USER!$PVE_TOKEN_NAME=$PVE_TOKEN" \
      "https://$PVE_HOST:8006/api2/json/nodes" | \
      ${pkgs.jq}/bin/jq -r '.data[0].node // "pve"')

    # Get VM/LXC info for name lookup
    declare -A VM_NAMES

    # Get VMs
    VMS=$(${pkgs.curl}/bin/curl -sk \
      -H "Authorization: PVEAPIToken=$PVE_USER!$PVE_TOKEN_NAME=$PVE_TOKEN" \
      "https://$PVE_HOST:8006/api2/json/nodes/$NODE/qemu" 2>/dev/null || echo '{"data":[]}')

    while IFS= read -r line; do
      vmid=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.vmid')
      name=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.name')
      if [ "$vmid" != "null" ] && [ "$name" != "null" ]; then
        VM_NAMES[$vmid]="$name"
      fi
    done < <(echo "$VMS" | ${pkgs.jq}/bin/jq -c '.data[]')

    # Get LXCs
    LXCS=$(${pkgs.curl}/bin/curl -sk \
      -H "Authorization: PVEAPIToken=$PVE_USER!$PVE_TOKEN_NAME=$PVE_TOKEN" \
      "https://$PVE_HOST:8006/api2/json/nodes/$NODE/lxc" 2>/dev/null || echo '{"data":[]}')

    while IFS= read -r line; do
      vmid=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.vmid')
      name=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.name')
      if [ "$vmid" != "null" ] && [ "$name" != "null" ]; then
        VM_NAMES[$vmid]="$name"
      fi
    done < <(echo "$LXCS" | ${pkgs.jq}/bin/jq -c '.data[]')

    # Query Proxmox API for recent vzdump tasks (last 7 days)
    SINCE=$(($(date +%s) - 604800))
    TASKS=$(${pkgs.curl}/bin/curl -sk \
      -H "Authorization: PVEAPIToken=$PVE_USER!$PVE_TOKEN_NAME=$PVE_TOKEN" \
      "https://$PVE_HOST:8006/api2/json/nodes/$NODE/tasks?typefilter=vzdump&since=$SINCE&limit=500" 2>/dev/null || echo '{"data":[]}')

    # Process tasks and find latest backup per VMID
    declare -A LATEST_SUCCESS
    declare -A LATEST_STATUS
    declare -A LATEST_TIME

    while IFS= read -r line; do
      upid=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.upid')
      status=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.status')
      starttime=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.starttime')

      # Extract VMID from task ID (format: UPID:node:pid:starttime:vzdump:vmid:user:)
      vmid=$(echo "$upid" | sed -n 's/.*:vzdump:\([0-9]*\):.*/\1/p')

      if [ -n "$vmid" ] && [ "$starttime" != "null" ]; then
        # Check if this is the latest task for this VMID
        if [ -z "''${LATEST_TIME[$vmid]:-}" ] || [ "$starttime" -gt "''${LATEST_TIME[$vmid]}" ]; then
          LATEST_TIME[$vmid]="$starttime"
          if [ "$status" = "OK" ]; then
            LATEST_STATUS[$vmid]=1
            LATEST_SUCCESS[$vmid]="$starttime"
          else
            LATEST_STATUS[$vmid]=0
          fi
        fi

        # Also track latest success separately (even if not the most recent task)
        if [ "$status" = "OK" ]; then
          if [ -z "''${LATEST_SUCCESS[$vmid]:-}" ] || [ "$starttime" -gt "''${LATEST_SUCCESS[$vmid]}" ]; then
            LATEST_SUCCESS[$vmid]="$starttime"
          fi
        fi
      fi
    done < <(echo "$TASKS" | ${pkgs.jq}/bin/jq -c '.data[]')

    # Write metrics
    NOW=$(date +%s)

    cat > "$TEMP_FILE" << 'HEADER'
# HELP pve_backup_last_success Unix timestamp of last successful backup
# TYPE pve_backup_last_success gauge
# HELP pve_backup_status Status of most recent backup task (1=success, 0=failed)
# TYPE pve_backup_status gauge
# HELP pve_backup_age_seconds Seconds since last successful backup
# TYPE pve_backup_age_seconds gauge
HEADER

    for vmid in "''${!LATEST_TIME[@]}"; do
      name="''${VM_NAMES[$vmid]:-unknown}"
      status="''${LATEST_STATUS[$vmid]:-0}"
      success_time="''${LATEST_SUCCESS[$vmid]:-0}"

      echo "pve_backup_status{vmid=\"$vmid\", name=\"$name\"} $status" >> "$TEMP_FILE"

      if [ "$success_time" -gt 0 ]; then
        age=$((NOW - success_time))
        echo "pve_backup_last_success{vmid=\"$vmid\", name=\"$name\"} $success_time" >> "$TEMP_FILE"
        echo "pve_backup_age_seconds{vmid=\"$vmid\", name=\"$name\"} $age" >> "$TEMP_FILE"
      fi
    done

    # Atomically move to final location
    mv "$TEMP_FILE" "$TEXTFILE"
    chmod 644 "$TEXTFILE"

    echo "PVE backup metrics written to $TEXTFILE"
  '';

in
{
  config = lib.mkIf (systemSettings.prometheusPveBackupEnable or false) {
    # Systemd service to collect backup metrics
    systemd.services.prometheus-pve-backup = {
      description = "Proxmox VE Backup Metrics Collector";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pveBackupScript}";
        User = "root";
        # Restart on failure but don't spam
        Restart = "on-failure";
        RestartSec = "60s";
      };

      # Ensure textfile directory exists
      preStart = ''
        mkdir -p ${textfileDir}
      '';
    };

    # Timer to run hourly (backups are typically daily/weekly)
    systemd.timers.prometheus-pve-backup = {
      description = "Proxmox VE Backup Metrics Collection Timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "1h";
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };
  };
}
