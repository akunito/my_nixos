# AION 2 DPS meter, headless Linux daemon (aionmeter-daemon, Plane A2M-48 phase 2b).
#
# Runs whatever framework-dependent publish sits in the install dir:
#   ${installDir}/aionmeter-daemon.dll (+ deps, data/)
# The meter repo (~/Projects/aion2-dps-meter) produces it with its docker build
# (build/out/<sha>/aionmeter-daemon-linux-x64/) and its tools/linux/deploy.sh
# (to be written there) copies it into the install dir and restarts this unit.
# Not a derivation yet: the build happens in that repo's docker image (on DESK_W11
# through rbuild), exactly like the Windows deploy folder, and the release
# cadence is per commit of the meter, not per dotfiles deploy. A nix package comes
# with the Linux release (port doc step 3). Missing dll -> the unit is skipped
# (ConditionPathExists), not failed.
#
# SYSTEM service with User=, because a user service cannot be granted ambient
# capabilities and pcap needs CAP_NET_RAW + CAP_NET_ADMIN. Same uid as the game,
# so /proc/<pid>/fd of AION 2 is readable without CAP_SYS_PTRACE.
# When the game is not running it just waits ("AION 2 is not running").
# SIGTERM makes it close and save the fight in progress and flush state.
{ pkgs, lib, systemSettings, userSettings, ... }:
let
  cfg = systemSettings;
  orDefault = v: d: if v == null then d else v;
  user = orDefault (cfg.aion2MeterDaemonUser or null) userSettings.username;
  home = "/home/${user}";
  installDir = orDefault (cfg.aion2MeterDaemonInstallDir or null) "${home}/.local/opt/aionmeter-daemon";
  dataDir = orDefault (cfg.aion2MeterDaemonDataDir or null) "${home}/.local/share/AionMeter";
  extraArgs = cfg.aion2MeterDaemonExtraArgs or [ ];
in
{
  config = lib.mkIf (cfg.aion2MeterDaemonEnable or false) {
    # Must exist before the unit starts: ReadWritePaths of a missing dir fails the namespace setup.
    systemd.tmpfiles.rules = [ "d ${dataDir} 0755 ${user} users -" ];

    systemd.services.aion2-meter-daemon = {
      description = "AION 2 DPS meter daemon (headless capture)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "${installDir}/aionmeter-daemon.dll";
      # SharpPcap dlopens libpcap.so.
      environment = {
        LD_LIBRARY_PATH = "${pkgs.libpcap}/lib";
        DOTNET_CLI_TELEMETRY_OPTOUT = "1";
        DOTNET_NOLOGO = "1";
        HOME = home;
      };
      serviceConfig = {
        Type = "simple";
        User = user;
        Group = "users";
        WorkingDirectory = installDir;
        ExecStart = lib.escapeShellArgs ([
          "${pkgs.dotnet-runtime_10}/bin/dotnet"
          "${installDir}/aionmeter-daemon.dll"
          "--data-dir"
          dataDir
        ] ++ extraArgs);
        AmbientCapabilities = [ "CAP_NET_RAW" "CAP_NET_ADMIN" ];
        CapabilityBoundingSet = [ "CAP_NET_RAW" "CAP_NET_ADMIN" ];
        KillSignal = "SIGTERM";
        TimeoutStopSec = 20;
        Restart = "on-failure";
        RestartSec = 10;
        Nice = 5;
        # Modest hardening. Not ProtectHome/ProtectProc: it reads the game's
        # /proc/<pid>/fd and writes into the user's home.
        ProtectSystem = "strict";
        ReadWritePaths = [ dataDir ];
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
      };
    };
  };
}
