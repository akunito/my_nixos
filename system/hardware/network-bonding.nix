# Network bonding (LACP link aggregation) module
# Configures Linux bonding for increased bandwidth and failover
#
# Prerequisites:
#   1. Configure switch LAG/LACP before enabling this module
#   2. Both interfaces must be connected to the same LAG on the switch
#
# Usage in profile:
#   networkBondingEnable = true;
#   networkBondingMode = "802.3ad";  # LACP
#   networkBondingInterfaces = [ "enp11s0f0" "enp11s0f1" ];
#   networkBondingDhcp = true;
#
# To disable on profiles without bonding hardware:
#   networkBondingEnable = false;  # (default in lib/defaults.nix)
#
# Documentation: docs/system-modules/network-bonding.md
#
# Verification after applying:
#   cat /proc/net/bonding/bond0
#   ip addr show bond0

{ config, pkgs, lib, systemSettings, ... }:

let
  cfg = systemSettings;
  bondingEnabled = cfg.networkBondingEnable or false;
  interfaces = cfg.networkBondingInterfaces or [];
  mode = cfg.networkBondingMode or "802.3ad";
  useDhcp = cfg.networkBondingDhcp or true;
  staticIp = cfg.networkBondingStaticIp or null;
  lacpRate = cfg.networkBondingLacpRate or "fast";
  miimon = cfg.networkBondingMiimon or "100";
  xmitHashPolicy = cfg.networkBondingXmitHashPolicy or "layer3+4";
  vlans = cfg.networkBondingVlans or [];

  # Detect which network manager is active
  useNetworkManager = cfg.networkManager or false;
  useNetworkd = cfg.useNetworkd or false;

  # Generate NetworkManager connection file for bond0
  nmBondConnection = ''
    [connection]
    id=bond0
    uuid=5a73d159-bd8c-47a6-b89c-68ac9f718475
    type=bond
    interface-name=bond0
    autoconnect=true

    [bond]
    mode=${mode}
    miimon=${miimon}
    ${lib.optionalString (mode == "802.3ad") "lacp_rate=${lacpRate}"}
    ${lib.optionalString (mode == "802.3ad") "xmit_hash_policy=${xmitHashPolicy}"}

    [ipv4]
    ${if useDhcp then "method=auto" else if staticIp != null then "method=manual\naddress1=${staticIp.address}\ngateway=${staticIp.gateway}" else "method=auto"}

    [ipv6]
    method=auto
  '';

  # Generate NetworkManager slave connection files
  nmSlaveConnection = iface: ''
    [connection]
    id=bond0-slave-${iface}
    type=ethernet
    interface-name=${iface}
    master=bond0
    slave-type=bond
    autoconnect=true
  '';

  # Generate NetworkManager VLAN connection file for a bond VLAN overlay
  nmVlanConnection = vlan: let
    vlanId = toString vlan.id;
    # Extract address and prefix from CIDR notation (e.g., "192.168.20.96/24")
    address = vlan.address;
  in ''
    [connection]
    id=bond0-vlan${vlanId}
    type=vlan
    interface-name=bond0.${vlanId}
    autoconnect=true

    [vlan]
    parent=bond0
    id=${vlanId}

    [ipv4]
    method=manual
    address1=${address}

    [ipv6]
    method=disabled
  '';
in
{
  config = lib.mkIf (bondingEnabled && interfaces != []) {
    # Load bonding and 802.1Q VLAN kernel modules
    boot.kernelModules = [ "bonding" ] ++ lib.optional (vlans != []) "8021q";

    # Configure the bond interface (kernel-level bond creation)
    # Only use networking.bonds when systemd-networkd is managing networking
    # When NetworkManager is active, it will create the bond via connection profiles
    networking.bonds = lib.mkIf useNetworkd {
      bond0 = {
        interfaces = interfaces;
        driverOptions = {
          mode = mode;
          miimon = miimon;
        } // lib.optionalAttrs (mode == "802.3ad") {
          # LACP-specific options
          lacp_rate = lacpRate;
          xmit_hash_policy = xmitHashPolicy;
        };
      };
    };

    # ========================================================================
    # systemd-networkd configuration (when useNetworkd = true)
    # ========================================================================
    networking.interfaces = lib.mkIf useNetworkd (
      lib.listToAttrs (map (iface: {
        name = iface;
        value = {
          useDHCP = false;
        };
      }) interfaces) // {
        # Configure bond0 IP addressing
        bond0 = if useDhcp then {
          useDHCP = true;
        } else if staticIp != null then {
          useDHCP = false;
          ipv4.addresses = [{
            address = lib.head (lib.splitString "/" staticIp.address);
            prefixLength = lib.toInt (lib.last (lib.splitString "/" staticIp.address));
          }];
        } else {
          useDHCP = true; # Fallback to DHCP
        };
      }
    );

    # Set default gateway if using static IP (systemd-networkd path)
    networking.defaultGateway = lib.mkIf (useNetworkd && staticIp != null && !useDhcp) {
      address = staticIp.gateway;
      interface = "bond0";
    };

    # ========================================================================
    # NetworkManager configuration (when networkManager = true)
    # ========================================================================
    # NOTE: We do NOT mark slave interfaces as unmanaged because NetworkManager
    # needs to manage them in order to enslave them to the bond.
    # The slave connection profiles handle this properly.

    # Create NetworkManager connection files directly in /etc
    environment.etc = lib.mkIf useNetworkManager ({
      "NetworkManager/system-connections/bond0.nmconnection" = {
        text = nmBondConnection;
        mode = "0600";
      };
    } // lib.listToAttrs (map (iface: {
      name = "NetworkManager/system-connections/bond0-slave-${iface}.nmconnection";
      value = {
        text = nmSlaveConnection iface;
        mode = "0600";
      };
    }) interfaces) // lib.listToAttrs (map (vlan: {
      name = "NetworkManager/system-connections/bond0-vlan${toString vlan.id}.nmconnection";
      value = {
        text = nmVlanConnection vlan;
        mode = "0600";
      };
    }) vlans));

    # Reload NetworkManager after activation to pick up new connection files
    system.activationScripts.reloadNetworkManager = lib.mkIf useNetworkManager (
      lib.stringAfter [ "etc" ] ''
        if systemctl is-active --quiet NetworkManager; then
          ${pkgs.networkmanager}/bin/nmcli connection reload || true
        fi
      ''
    );
  };
}
