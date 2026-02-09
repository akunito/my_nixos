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
in
{
  config = lib.mkIf (bondingEnabled && interfaces != []) {
    # Load bonding kernel module
    boot.kernelModules = [ "bonding" ];

    # Configure the bond interface
    networking.bonds.bond0 = {
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

    # Configure interfaces: disable DHCP on slaves and set up bond0
    networking.interfaces = lib.listToAttrs (map (iface: {
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
    };

    # Set default gateway if using static IP
    networking.defaultGateway = lib.mkIf (staticIp != null && !useDhcp) {
      address = staticIp.gateway;
      interface = "bond0";
    };

    # Ensure NetworkManager doesn't interfere with bonded interfaces
    # NetworkManager will automatically detect and manage the bond
    networking.networkmanager.unmanaged = lib.mkIf (cfg.networkManager or true) interfaces;
  };
}
