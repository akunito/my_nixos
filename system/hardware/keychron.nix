{ config, pkgs, lib, systemSettings, ... }:

{
  # Grant access to Keychron keyboards for the Keychron Launcher / VIA
  # This udev rule allows the browser to access Keychron keyboards via WebHID API
  # Vendor ID 3434 is the standard Keychron vendor ID
  # After applying this configuration, unplug and replug your keyboard for the rule to take effect
  services.udev.extraRules = ''
    # Grant access to Keychron keyboards for the Keychron Launcher / VIA
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
  '';
}

