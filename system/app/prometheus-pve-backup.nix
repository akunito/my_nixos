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

    # Read the API token (supports both raw token and KEY=VALUE format)
    if [ ! -f "$PVE_TOKEN_FILE" ]; then
      echo "Error: PVE token file not found: $PVE_TOKEN_FILE" >&2
      exit 1
    fi
    # Source the file to get environment variables
    set -a
    source "$PVE_TOKEN_FILE"
    set +a
    # Use PVE_TOKEN_VALUE if set, otherwise use file content directly
    PVE_TOKEN="''${PVE_TOKEN_VALUE:-$(cat "$PVE_TOKEN_FILE")}"

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

    # Function to process a single VM backup result
    process_vm_backup() {
      local vmid="$1"
      local starttime="$2"
      local success="$3"  # 1 or 0
      local vm_name="$4"  # optional, from log parsing

      if [ -n "$vmid" ] && [ "$starttime" != "null" ]; then
        # Update VM name if provided from log (more reliable than API for some cases)
        if [ -n "$vm_name" ] && [ "$vm_name" != "unknown" ]; then
          VM_NAMES[$vmid]="$vm_name"
        fi

        # Check if this is the latest task for this VMID
        if [ -z "''${LATEST_TIME[$vmid]:-}" ] || [ "$starttime" -gt "''${LATEST_TIME[$vmid]}" ]; then
          LATEST_TIME[$vmid]="$starttime"
          LATEST_STATUS[$vmid]="$success"
          if [ "$success" -eq 1 ]; then
            LATEST_SUCCESS[$vmid]="$starttime"
          fi
        fi

        # Also track latest success separately (even if not the most recent task)
        if [ "$success" -eq 1 ]; then
          if [ -z "''${LATEST_SUCCESS[$vmid]:-}" ] || [ "$starttime" -gt "''${LATEST_SUCCESS[$vmid]}" ]; then
            LATEST_SUCCESS[$vmid]="$starttime"
          fi
        fi
      fi
    }

    # Function to parse batch backup task log and extract per-VM results
    parse_batch_task_log() {
      local upid="$1"
      local starttime="$2"
      local task_status="$3"

      # URL-encode the UPID (replace : with %3A)
      local encoded_upid=$(echo "$upid" | sed 's/:/%3A/g')

      # Fetch task log
      local log_response=$(${pkgs.curl}/bin/curl -sk \
        -H "Authorization: PVEAPIToken=$PVE_USER!$PVE_TOKEN_NAME=$PVE_TOKEN" \
        "https://$PVE_HOST:8006/api2/json/nodes/$NODE/tasks/$encoded_upid/log?limit=1000" 2>/dev/null || echo '{"data":[]}')

      # Extract log text (combine all log entries)
      local log_text=$(echo "$log_response" | ${pkgs.jq}/bin/jq -r '.data[].t // empty' 2>/dev/null)

      if [ -z "$log_text" ]; then
        return
      fi

      # Track which VMs we've seen in this log and their names
      declare -A log_vm_names
      declare -A log_vm_success

      # Parse log for VM backup info
      # Format: "INFO: Starting Backup of VM 201 (lxc)"
      #         "INFO: CT Name: planePROD-nixos" or "INFO: VM Name: ..."
      #         "INFO: Finished Backup of VM 201 (00:03:01)"
      #         "ERROR: ..." indicates failure

      local current_vmid=""

      while IFS= read -r log_line; do
        # Check for "Starting Backup of VM XXX"
        if [[ "$log_line" =~ INFO:\ Starting\ Backup\ of\ VM\ ([0-9]+) ]]; then
          current_vmid="''${BASH_REMATCH[1]}"
          log_vm_success[$current_vmid]=0  # Assume failure until we see "Finished"
        fi

        # Check for "CT Name: xxx" or "VM Name: xxx"
        if [[ "$log_line" =~ INFO:\ (CT|VM)\ Name:\ (.+) ]] && [ -n "$current_vmid" ]; then
          local parsed_name="''${BASH_REMATCH[2]}"
          # Trim whitespace
          parsed_name=$(echo "$parsed_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          log_vm_names[$current_vmid]="$parsed_name"
        fi

        # Check for "Finished Backup of VM XXX" - indicates success
        if [[ "$log_line" =~ INFO:\ Finished\ Backup\ of\ VM\ ([0-9]+) ]]; then
          local finished_vmid="''${BASH_REMATCH[1]}"
          log_vm_success[$finished_vmid]=1
        fi

        # Check for errors related to a VM
        if [[ "$log_line" =~ ERROR:.*VM\ ([0-9]+) ]]; then
          local error_vmid="''${BASH_REMATCH[1]}"
          log_vm_success[$error_vmid]=0
        fi
      done <<< "$log_text"

      # Process all VMs found in this batch task
      for vmid in "''${!log_vm_success[@]}"; do
        local vm_name="''${log_vm_names[$vmid]:-}"
        local success="''${log_vm_success[$vmid]}"
        process_vm_backup "$vmid" "$starttime" "$success" "$vm_name"
      done
    }

    while IFS= read -r line; do
      upid=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.upid')
      status=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.status')
      starttime=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.starttime')

      # Extract VMID from task ID (format: UPID:node:pid:starttime:vzdump:vmid:user:)
      # Note: Batch backup jobs have empty VMID field in UPID
      vmid=$(echo "$upid" | sed -n 's/.*:vzdump:\([0-9]*\):.*/\1/p')

      if [ -n "$vmid" ] && [ "$starttime" != "null" ]; then
        # Single VM backup task - process directly
        if [ "$status" = "OK" ]; then
          process_vm_backup "$vmid" "$starttime" 1 ""
        else
          process_vm_backup "$vmid" "$starttime" 0 ""
        fi
      elif [ -z "$vmid" ] && [ "$starttime" != "null" ]; then
        # Batch backup task (empty VMID) - parse task log for per-VM results
        parse_batch_task_log "$upid" "$starttime" "$status"
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
