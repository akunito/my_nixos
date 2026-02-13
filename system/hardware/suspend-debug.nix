# Suspend/resume debug instrumentation
# Logs timestamps, battery level, and network state around sleep events.
# Enable via suspendDebugEnable = true in profile config.

{ systemSettings, pkgs, lib, ... }:

let
  suspendScript = pkgs.writeShellScript "suspend-debug-pre" ''
    echo "$(date -Iseconds) SUSPENDING battery=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo N/A)%" \
      >> /var/log/suspend-debug.log
    logger -t suspend-debug "SUSPENDING"
  '';
  resumeScript = pkgs.writeShellScript "suspend-debug-post" ''
    echo "$(date -Iseconds) RESUMED battery=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo N/A)%" \
      >> /var/log/suspend-debug.log
    logger -t suspend-debug "RESUMED"
    # Network beacon: send UDP to DESK to confirm wake
    echo "RESUMED $(hostname) $(date -Iseconds)" | ${pkgs.netcat-gnu}/bin/nc -u -w1 192.168.8.96 9999 2>/dev/null || true
    # Log network status
    ${pkgs.iproute2}/bin/ip link show | logger -t suspend-debug
  '';
in
lib.mkIf (systemSettings.suspendDebugEnable or false) {
  systemd.services."suspend-debug" = {
    description = "Suspend/resume debug logging";
    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = suspendScript;
      ExecStop = resumeScript;
    };
  };
}
