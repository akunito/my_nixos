# SNMP Exporter for pfSense and network devices
#
# Feature flags (from profile config):
#   - prometheusSnmpExporterEnable: Enable SNMP Exporter
#   - prometheusSnmpCommunity: SNMP community string
#   - prometheusSnmpTargets: List of targets [{name, host, module}]
#
# Prerequisites:
#   1. Enable SNMP on pfSense: Services > SNMP
#   2. Set community string (use long random string)
#   3. Bind to LAN interface only
#   4. Add firewall rule: LAN pass UDP 161 from monitoring server to Self
#
# Metrics collected:
#   - pfStatusRunning, pfStatusRuntime: Firewall state
#   - pfCounterMatch, pfCounterMemDrop: Packet processing
#   - pfStateTableCount: Connection tracking
#   - Interface traffic and descriptions

{ pkgs, lib, systemSettings, config, ... }:

let
  snmpTargets = systemSettings.prometheusSnmpTargets or [];
  snmpCommunity = systemSettings.prometheusSnmpCommunity or "public";

  # Generate snmp.yml with actual community string
  # IMPORTANT: snmp_exporter requires NUMERIC OIDs, not MIB names
  # MIB names like "ifDescr" don't work at runtime - use generator or numeric OIDs
  snmpConfig = pkgs.writeText "snmp.yml" ''
    auths:
      pfsense_v2:
        community: ${snmpCommunity}
        version: 2

    modules:
      # Standard interface MIB - works on most network devices
      # Using numeric OIDs (IF-MIB and IF-MIB extensions)
      if_mib:
        walk:
          - 1.3.6.1.2.1.2.2.1.2      # ifDescr
          - 1.3.6.1.2.1.2.2.1.3      # ifType
          - 1.3.6.1.2.1.2.2.1.5      # ifSpeed
          - 1.3.6.1.2.1.2.2.1.7      # ifAdminStatus
          - 1.3.6.1.2.1.2.2.1.8      # ifOperStatus
          - 1.3.6.1.2.1.2.2.1.10     # ifInOctets
          - 1.3.6.1.2.1.2.2.1.11     # ifInUcastPkts
          - 1.3.6.1.2.1.2.2.1.13     # ifInDiscards
          - 1.3.6.1.2.1.2.2.1.14     # ifInErrors
          - 1.3.6.1.2.1.2.2.1.16     # ifOutOctets
          - 1.3.6.1.2.1.2.2.1.17     # ifOutUcastPkts
          - 1.3.6.1.2.1.2.2.1.19     # ifOutDiscards
          - 1.3.6.1.2.1.2.2.1.20     # ifOutErrors
          - 1.3.6.1.2.1.31.1.1.1.6   # ifHCInOctets (64-bit)
          - 1.3.6.1.2.1.31.1.1.1.10  # ifHCOutOctets (64-bit)

      # pfSense specific - PF firewall stats + interface metrics
      pfsense:
        walk:
          # Interface metrics (IF-MIB)
          - 1.3.6.1.2.1.2.2.1.2      # ifDescr
          - 1.3.6.1.2.1.2.2.1.3      # ifType
          - 1.3.6.1.2.1.2.2.1.5      # ifSpeed
          - 1.3.6.1.2.1.2.2.1.7      # ifAdminStatus
          - 1.3.6.1.2.1.2.2.1.8      # ifOperStatus
          - 1.3.6.1.2.1.2.2.1.10     # ifInOctets
          - 1.3.6.1.2.1.2.2.1.14     # ifInErrors
          - 1.3.6.1.2.1.2.2.1.16     # ifOutOctets
          - 1.3.6.1.2.1.2.2.1.20     # ifOutErrors
          - 1.3.6.1.2.1.31.1.1.1.6   # ifHCInOctets (64-bit)
          - 1.3.6.1.2.1.31.1.1.1.10  # ifHCOutOctets (64-bit)
          # pfSense/PF specific OIDs (BEGEMOT-PF-MIB)
          - 1.3.6.1.4.1.12325.1.200.1.1    # pfStatus
          - 1.3.6.1.4.1.12325.1.200.1.2    # pfCounters
          - 1.3.6.1.4.1.12325.1.200.1.3    # pfStateTable
  '';
in
lib.mkIf (systemSettings.prometheusSnmpExporterEnable or false) {
  services.prometheus.exporters.snmp = {
    enable = true;
    port = 9116;
    configurationPath = snmpConfig;
  };

  services.prometheus.scrapeConfigs = map (target: {
    job_name = "snmp_${target.name}";
    metrics_path = "/snmp";
    params = {
      auth = [ "pfsense_v2" ];
      module = [ (target.module or "pfsense") ];
      target = [ target.host ];
    };
    static_configs = [{
      targets = [ "127.0.0.1:9116" ];
      labels = { instance = target.name; };
    }];
  }) snmpTargets;
}
