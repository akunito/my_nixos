# NAS-specific services module
# ZFS pool management, SMART monitoring, NFS tuning, S3 sleep schedule,
# and Docker Compose auto-start.
#
# Enabled via: nasServicesEnable = true (in profile systemSettings)

{ config, pkgs, lib, systemSettings, userSettings, ... }:

let
  nasEnabled = systemSettings.nasServicesEnable or false;
  username = userSettings.username;
  composeBase = "/mnt/ssdpool/docker/compose";
  # Docker compose projects to start on boot (in order)
  composeProjects = systemSettings.nasDockerProjects or [
    "npm"
    "cloudflared"
    "media"
    "vpn-media"
    "exporters"
    "monitoring"
  ];
in
{
  config = lib.mkIf nasEnabled {
    # ========================================================================
    # ZFS
    # ========================================================================
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.extraPools = systemSettings.nasZfsPools or [ "ssdpool" "extpool" ];
    # Don't auto-request credentials at boot — unlock manually via SSH
    boot.zfs.requestEncryptionCredentials = false;
    # REQUIRED for ZFS — generate with: head -c 8 /dev/urandom | od -A none -t x1 | tr -d ' ' | head -c 8
    networking.hostId = systemSettings.nasHostId or "deadbeef";

    # ZFS auto-scrub (monthly)
    services.zfs.autoScrub = {
      enable = true;
      interval = "monthly";
    };

    # ZFS auto-snapshot (daily for media, 7-day retention)
    services.zfs.autoSnapshot = {
      enable = systemSettings.nasAutoSnapshotEnable or false;
      daily = 7;
      weekly = 0;
      monthly = 0;
    };

    # ========================================================================
    # SMART monitoring
    # ========================================================================
    services.smartd = {
      enable = true;
      autodetect = true;
      notifications = {
        mail = {
          enable = systemSettings.nasSmartMailEnable or false;
          recipient = systemSettings.nasSmartMailRecipient or "";
        };
        wall.enable = true;
      };
    };

    # ========================================================================
    # NFS tuning — NFSv4 only, 16 threads
    # ========================================================================
    services.nfs.server = lib.mkIf (systemSettings.nfsServerEnable or false) {
      # nfsd thread count
      extraNfsdConfig = ''
        threads=16
        vers2=n
        vers3=n
        vers4=y
        vers4.0=y
        vers4.1=y
        vers4.2=y
      '';
    };

    # ========================================================================
    # S3 sleep schedule — suspend at 23:00, wake at 11:00 via RTC
    # ========================================================================

    # Set RTC alarm for next wake (runs before each suspend)
    systemd.services.nas-rtc-wake = {
      description = "Set RTC alarm to wake NAS at 11:00";
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        # Calculate next 11:00 timestamp
        TOMORROW_11=$(date -d "tomorrow 11:00" +%s)
        TODAY_11=$(date -d "today 11:00" +%s)
        NOW=$(date +%s)
        if [ "$NOW" -lt "$TODAY_11" ]; then
          WAKE_TIME=$TODAY_11
        else
          WAKE_TIME=$TOMORROW_11
        fi
        ${pkgs.util-linux}/bin/rtcwake -m no -t "$WAKE_TIME"
        echo "RTC alarm set for $(date -d @$WAKE_TIME)"
      '';
    };

    # Nightly suspend timer
    systemd.timers.nas-suspend = {
      description = "Suspend NAS at 23:00";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 23:00:00";
        Persistent = true;
      };
    };
    systemd.services.nas-suspend = {
      description = "Suspend NAS to RAM";
      serviceConfig.Type = "oneshot";
      script = ''
        echo "NAS suspending at $(date)"
        ${pkgs.systemd}/bin/systemctl suspend
      '';
    };

    # Docker pre-suspend: stop all containers gracefully
    systemd.services.nas-docker-pre-suspend = {
      description = "Stop Docker containers before suspend";
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutSec = 120;
        User = username;
      };
      environment = {
        XDG_RUNTIME_DIR = "/run/user/1000";
        DOCKER_HOST = "unix:///run/user/1000/docker.sock";
      };
      script = ''
        echo "Stopping Docker containers for suspend..."
        for project in ${lib.concatMapStringsSep " " (p: "'${p}'") (lib.reverseList composeProjects)}; do
          if [ -d "${composeBase}/$project" ]; then
            echo "  Stopping $project..."
            cd "${composeBase}/$project" && ${pkgs.docker-compose}/bin/docker-compose stop -t 30 || true
          fi
        done
        echo "All containers stopped."
      '';
    };

    # Docker post-resume: start all containers
    systemd.services.nas-docker-post-resume = {
      description = "Start Docker containers after resume";
      after = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
      wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutSec = 180;
        User = username;
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 10"; # Wait for networking
      };
      environment = {
        XDG_RUNTIME_DIR = "/run/user/1000";
        DOCKER_HOST = "unix:///run/user/1000/docker.sock";
      };
      script = ''
        echo "Starting Docker containers after resume..."
        for project in ${lib.concatMapStringsSep " " (p: "'${p}'") composeProjects}; do
          if [ -d "${composeBase}/$project" ]; then
            echo "  Starting $project..."
            cd "${composeBase}/$project" && ${pkgs.docker-compose}/bin/docker-compose up -d || true
          fi
        done
        echo "All containers started."
      '';
    };

    # ========================================================================
    # Docker Compose auto-start on boot
    # ========================================================================
    systemd.services.nas-docker-compose-up = {
      description = "Start all Docker Compose projects on boot";
      after = [ "docker.service" "zfs-mount.service" "network-online.target" ];
      requires = [ "docker.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutSec = 300;
        User = username;
      };
      environment = {
        XDG_RUNTIME_DIR = "/run/user/1000";
        DOCKER_HOST = "unix:///run/user/1000/docker.sock";
      };
      script = ''
        echo "Starting Docker Compose projects..."
        for project in ${lib.concatMapStringsSep " " (p: "'${p}'") composeProjects}; do
          if [ -d "${composeBase}/$project" ]; then
            echo "  Starting $project..."
            cd "${composeBase}/$project" && ${pkgs.docker-compose}/bin/docker-compose up -d || true
          fi
        done
        echo "All projects started."
      '';
    };
  };
}
