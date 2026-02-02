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
  # Note: New snmp_exporter format - lookups/overrides are generator-only, not runtime config
  snmpConfig = pkgs.writeText "snmp.yml" ''
    auths:
      pfsense_v2:
        community: ${snmpCommunity}
        version: 2

    modules:
      # Standard interface MIB - works on most network devices
      if_mib:
        walk:
          - ifDescr
          - ifType
          - ifSpeed
          - ifAdminStatus
          - ifOperStatus
          - ifInOctets
          - ifInUcastPkts
          - ifInErrors
          - ifInDiscards
          - ifOutOctets
          - ifOutUcastPkts
          - ifOutErrors
          - ifOutDiscards
          - ifHCInOctets
          - ifHCOutOctets

      # pfSense specific - PF firewall stats + interface metrics
      pfsense:
        walk:
          - ifDescr
          - ifType
          - ifSpeed
          - ifAdminStatus
          - ifOperStatus
          - ifInOctets
          - ifOutOctets
          - ifHCInOctets
          - ifHCOutOctets
          - ifInErrors
          - ifOutErrors
          # pfSense/PF specific OIDs
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
