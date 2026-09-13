# claude-sync — Home Manager side: package, `claude` wrapper, 15-minute timer.
# Hooks + cleanupPeriodDays live in claude-code.nix (same settings.json).
# Flag: claudeSyncEnable. Hub side: system/app/claude-sync-hub.nix (VPS).
# Design + runbook: docs/akunito/infrastructure/services/claude-sync.md
{ pkgs, pkgs-unstable, lib, systemSettings, userSettings, ... }:

let
  cs = import ./claude-sync-pkg.nix { inherit pkgs pkgs-unstable lib systemSettings userSettings; };
in
lib.mkIf cs.enable {
  home.packages = [ cs.package cs.wrapper ];

  # Safety net for anything the hooks miss (Claude killed, hand-edited skill,
  # machine rebooted mid-session): full two-way sync every 15 minutes.
  systemd.user.services.claude-sync = {
    Unit.Description = "claude-sync: two-way sync of ~/.claude with the VPS hub";
    Service = {
      Type = "oneshot";
      ExecStart = "${cs.package}/bin/claude-sync sync";
      # the dedicated key needs no agent; keep gpg-agent out of it
      Environment = [ "SSH_AUTH_SOCK=" "CLAUDE_SYNC_AUTO=1" ];
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.user.timers.claude-sync = {
    Unit.Description = "claude-sync every 15 minutes";
    Timer = {
      OnBootSec = "3m";
      OnUnitActiveSec = "15m";
      RandomizedDelaySec = "2m";
      AccuracySec = "1m";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
