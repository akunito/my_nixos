# Prevent AUTOMATIC (idle) system suspend on always-on desktops.
#
# Context: Plasma 6 machines hand power management to KDE PowerDevil (see the
# powerManagement_ENABLE handoff used by LAPTOP_A / DESK_A). PowerDevil's default
# profile auto-suspends after idle by calling logind's Suspend(). On a laptop
# that's wanted; on a DESKTOP that runs scheduled restic backups and is managed
# remotely over SSH/Tailscale, idle-suspend is harmful — it drops the machine off
# the network and can pause a running rebuild or miss the backup window.
#
# Fix: hold a systemd "block" inhibitor on `sleep`. logind then refuses any
# suspend request (including PowerDevil's idle one), so the machine stays up.
# PowerDevil's Energy page stays fully visible/usable — this only stops the
# suspend from actually taking effect. Trade-off: MANUAL suspend is blocked too,
# which is fine for an always-on desktop.
#
# Enable with systemSettings.autoSuspendInhibit = true.

{ config, lib, pkgs, systemSettings, ... }:

lib.mkIf (systemSettings.autoSuspendInhibit or false) {
  systemd.services.inhibit-auto-suspend = {
    description = "Block automatic system suspend (always-on desktop: backups + remote mgmt)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=sleep --who=nixos --why=\"always-on desktop (scheduled backups + remote management)\" --mode=block ${pkgs.coreutils}/bin/sleep infinity";
      Restart = "always";
      RestartSec = "5s";
    };
  };
}
