# SNMP Exporter for pfSense and network devices
#
# Feature flags (from profile config):
#   - prometheusSnmpExporterEnable: Enable SNMP Exporter
#   - prometheusSnmpCommunity: SNMP community string (v2c fallback)
#   - prometheusSnmpv3User: SNMPv3 username (preferred)
#   - prometheusSnmpv3AuthPass: SNMPv3 auth password (SHA)
#   - prometheusSnmpv3PrivPass: SNMPv3 privacy password (AES)
#   - prometheusSnmpTargets: List of targets [{name, host, module}]
#
# Prerequisites:
#   For SNMPv3 (recommended):
#   1. Install NET-SNMP package on pfSense: System > Package Manager
#   2. Disable built-in SNMP: Services > SNMP (uncheck enable)
#   3. Configure NET-SNMP: Services > SNMP (NET-SNMP)
#   4. Create SNMPv3 user with SHA auth and AES privacy
#   5. Add firewall rule: LAN pass UDP 161 from monitoring server to Self
#
#   For SNMPv2c (fallback):
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

  # SNMPv3 credentials (preferred)
  snmpv3User = systemSettings.prometheusSnmpv3User or null;
  snmpv3AuthPass = systemSettings.prometheusSnmpv3AuthPass or null;
  snmpv3PrivPass = systemSettings.prometheusSnmpv3PrivPass or null;

  # SNMPv2c credentials (fallback)
  snmpCommunity = systemSettings.prometheusSnmpCommunity or "public";

  # Use SNMPv3 if all credentials are provided
  useSnmpv3 = snmpv3User != null && snmpv3AuthPass != null && snmpv3PrivPass != null;
  authName = if useSnmpv3 then "pfsense_v3" else "pfsense_v2";

  # Generate snmp.yml with auth config and metric definitions
  # snmp_exporter requires explicit metric definitions to convert OIDs to Prometheus metrics
  snmpConfig = pkgs.writeText "snmp.yml" (''
    auths:
  '' + (if useSnmpv3 then ''
      pfsense_v3:
        version: 3
        security_level: authPriv
        username: ${snmpv3User}
        auth_protocol: SHA
        auth_passphrase: ${snmpv3AuthPass}
        priv_protocol: AES
        priv_passphrase: ${snmpv3PrivPass}
  '' else ''
      pfsense_v2:
        community: ${snmpCommunity}
        version: 2
  '') + ''
    modules:
      # pfSense specific - PF firewall stats + interface metrics
      pfsense:
        timeout: 20s
        walk:
          # Interface metrics (IF-MIB) - only the columns we need
          - 1.3.6.1.2.1.2.2.1.2     # ifDescr
          - 1.3.6.1.2.1.2.2.1.5     # ifSpeed
          - 1.3.6.1.2.1.2.2.1.7     # ifAdminStatus
          - 1.3.6.1.2.1.2.2.1.8     # ifOperStatus
          - 1.3.6.1.2.1.2.2.1.14    # ifInErrors
          - 1.3.6.1.2.1.2.2.1.20    # ifOutErrors
          - 1.3.6.1.2.1.31.1.1.1.6  # ifHCInOctets
          - 1.3.6.1.2.1.31.1.1.1.10 # ifHCOutOctets
        get:
          # PF Status scalars (with .0 suffix for scalars)
          - 1.3.6.1.4.1.12325.1.200.1.1.1.0  # pfStatusRunning
          - 1.3.6.1.4.1.12325.1.200.1.1.2.0  # pfStatusRuntime
          - 1.3.6.1.4.1.12325.1.200.1.1.3.0  # pfStatusDebug
          - 1.3.6.1.4.1.12325.1.200.1.2.1.0  # pfCounterMatch
          - 1.3.6.1.4.1.12325.1.200.1.2.2.0  # pfCounterBadOffset
          - 1.3.6.1.4.1.12325.1.200.1.2.3.0  # pfCounterFragment
          - 1.3.6.1.4.1.12325.1.200.1.2.4.0  # pfCounterShort
          - 1.3.6.1.4.1.12325.1.200.1.2.5.0  # pfCounterNormalize
          - 1.3.6.1.4.1.12325.1.200.1.2.6.0  # pfCounterMemDrop
          - 1.3.6.1.4.1.12325.1.200.1.3.1.0  # pfStateTableCount
          - 1.3.6.1.4.1.12325.1.200.1.3.2.0  # pfStateTableSearches
          - 1.3.6.1.4.1.12325.1.200.1.3.3.0  # pfStateTableInserts
          - 1.3.6.1.4.1.12325.1.200.1.3.4.0  # pfStateTableRemovals
        metrics:
          # Interface description (used as label)
          - name: ifDescr
            oid: 1.3.6.1.2.1.2.2.1.2
            type: DisplayString
            indexes:
              - labelname: ifIndex
                type: Integer
          # Interface operational status (1=up, 2=down)
          - name: ifOperStatus
            oid: 1.3.6.1.2.1.2.2.1.8
            type: gauge
            indexes:
              - labelname: ifIndex
                type: Integer
            lookups:
              - labels: [ifIndex]
                labelname: ifDescr
                oid: 1.3.6.1.2.1.2.2.1.2
                type: DisplayString
          # Interface admin status (1=up, 2=down)
          - name: ifAdminStatus
            oid: 1.3.6.1.2.1.2.2.1.7
            type: gauge
            indexes:
              - labelname: ifIndex
                type: Integer
            lookups:
              - labels: [ifIndex]
                labelname: ifDescr
                oid: 1.3.6.1.2.1.2.2.1.2
                type: DisplayString
          # Interface speed (bits per second)
          - name: ifSpeed
            oid: 1.3.6.1.2.1.2.2.1.5
            type: gauge
            indexes:
              - labelname: ifIndex
                type: Integer
            lookups:
              - labels: [ifIndex]
                labelname: ifDescr
                oid: 1.3.6.1.2.1.2.2.1.2
                type: DisplayString
          # 64-bit input octets
          - name: ifHCInOctets
            oid: 1.3.6.1.2.1.31.1.1.1.6
            type: counter
            indexes:
              - labelname: ifIndex
                type: Integer
            lookups:
              - labels: [ifIndex]
                labelname: ifDescr
                oid: 1.3.6.1.2.1.2.2.1.2
                type: DisplayString
          # 64-bit output octets
          - name: ifHCOutOctets
            oid: 1.3.6.1.2.1.31.1.1.1.10
            type: counter
            indexes:
              - labelname: ifIndex
                type: Integer
            lookups:
              - labels: [ifIndex]
                labelname: ifDescr
                oid: 1.3.6.1.2.1.2.2.1.2
                type: DisplayString
          # Input errors
          - name: ifInErrors
            oid: 1.3.6.1.2.1.2.2.1.14
            type: counter
            indexes:
              - labelname: ifIndex
                type: Integer
            lookups:
              - labels: [ifIndex]
                labelname: ifDescr
                oid: 1.3.6.1.2.1.2.2.1.2
                type: DisplayString
          # Output errors
          - name: ifOutErrors
            oid: 1.3.6.1.2.1.2.2.1.20
            type: counter
            indexes:
              - labelname: ifIndex
                type: Integer
            lookups:
              - labels: [ifIndex]
                labelname: ifDescr
                oid: 1.3.6.1.2.1.2.2.1.2
                type: DisplayString
          # PF Status - Running (1=running, 0=not running)
          - name: pfStatusRunning
            oid: 1.3.6.1.4.1.12325.1.200.1.1.1
            type: gauge
          # PF Status - Runtime (seconds since started)
          - name: pfStatusRuntime
            oid: 1.3.6.1.4.1.12325.1.200.1.1.2
            type: counter
          # PF Status - Debug level
          - name: pfStatusDebug
            oid: 1.3.6.1.4.1.12325.1.200.1.1.3
            type: gauge
          # PF Status - Host ID
          - name: pfStatusHostId
            oid: 1.3.6.1.4.1.12325.1.200.1.1.4
            type: DisplayString
          # PF Counter - Match (packets matched by rules)
          - name: pfCounterMatch
            oid: 1.3.6.1.4.1.12325.1.200.1.2.1
            type: counter
          # PF Counter - Bad offset
          - name: pfCounterBadOffset
            oid: 1.3.6.1.4.1.12325.1.200.1.2.2
            type: counter
          # PF Counter - Fragment
          - name: pfCounterFragment
            oid: 1.3.6.1.4.1.12325.1.200.1.2.3
            type: counter
          # PF Counter - Short packets
          - name: pfCounterShort
            oid: 1.3.6.1.4.1.12325.1.200.1.2.4
            type: counter
          # PF Counter - Normalized packets
          - name: pfCounterNormalize
            oid: 1.3.6.1.4.1.12325.1.200.1.2.5
            type: counter
          # PF Counter - Memory dropped
          - name: pfCounterMemDrop
            oid: 1.3.6.1.4.1.12325.1.200.1.2.6
            type: counter
          # PF State Table - Count (current active connections)
          - name: pfStateTableCount
            oid: 1.3.6.1.4.1.12325.1.200.1.3.1
            type: gauge
          # PF State Table - Searches
          - name: pfStateTableSearches
            oid: 1.3.6.1.4.1.12325.1.200.1.3.2
            type: counter
          # PF State Table - Inserts
          - name: pfStateTableInserts
            oid: 1.3.6.1.4.1.12325.1.200.1.3.3
            type: counter
          # PF State Table - Removals
          - name: pfStateTableRemovals
            oid: 1.3.6.1.4.1.12325.1.200.1.3.4
            type: counter
  '');
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
    scrape_interval = "30s";
    scrape_timeout = "25s";
    params = {
      auth = [ authName ];  # Uses pfsense_v3 if SNMPv3 configured, otherwise pfsense_v2
      module = [ (target.module or "pfsense") ];
      target = [ target.host ];
    };
    static_configs = [{
      targets = [ "127.0.0.1:9116" ];
      labels = { instance = target.name; };
    }];
  }) snmpTargets;
}
