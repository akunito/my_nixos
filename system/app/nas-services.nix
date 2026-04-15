# NAS-specific services module
# ZFS pool management, SMART monitoring, NFS tuning, S3 sleep schedule,
# and Docker Compose auto-start.
#
# Enabled via: nasServicesEnable = true (in profile systemSettings)

{ config, pkgs, lib, systemSettings, userSettings, ... }:

let
  nasEnabled = systemSettings.nasServicesEnable or false;
  username = userSettings.username;
  isRootless = userSettings.dockerRootlessEnable or false;
  composeBase = "/mnt/ssdpool/docker/compose";
  # Root Docker projects (need NET_ADMIN / privileged)
  rootDockerProjects = systemSettings.nasRootDockerProjects or [ "vpn-media" ];
  # Rootless Docker projects (everything else)
  rootlessDockerProjects = systemSettings.nasRootlessDockerProjects or [
    "npm"
    "cloudflared"
    "media"
    "exporters"
    "monitoring"
  ];
  # Combined for backward compat (used by suspend/resume)
  composeProjects = rootDockerProjects ++ rootlessDockerProjects;
  # Rootless environment
  rootlessEnv = {
    XDG_RUNTIME_DIR = "/run/user/1000";
    DOCKER_HOST = "unix:///run/user/1000/docker.sock";
  };
in
{
  config = lib.mkIf nasEnabled {
    # ========================================================================
    # LAN fallback interface (2.5GbE for management when bond is down)
    # ========================================================================
    systemd.network.networks."20-lan-fallback" = {
      matchConfig.Name = systemSettings.nasLanInterface or "enp10s0";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      dhcpV4Config = {
        RouteMetric = 1024; # Higher metric than bond (lower priority)
        UseDNS = false; # Don't override bond DNS
      };
    };

    # ========================================================================
    # ZFS
    # ========================================================================
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.extraPools = systemSettings.nasZfsPools or [ "ssdpool" "extpool" ];
    # Don't prompt at boot — we auto-unlock from passphrase file on encrypted root
    boot.zfs.requestEncryptionCredentials = false;
    # REQUIRED for ZFS — generate with: head -c 8 /dev/urandom | od -A none -t x1 | tr -d ' ' | head -c 8
    networking.hostId = systemSettings.nasHostId or "deadbeef";

    # ========================================================================
    # ZFS pool auto-unlock after boot
    # ========================================================================
    # The NixOS boot drive is LUKS-encrypted (passphrase at boot).
    # Pool passphrases are stored on the encrypted root at /etc/zfs/keys/.
    # This is safe because the root filesystem is only accessible after
    # the user enters the LUKS passphrase at boot.
    #
    # Setup (one-time, during migration):
    #   sudo mkdir -p /etc/zfs/keys
    #   echo -n "your-ssdpool-passphrase" | sudo tee /etc/zfs/keys/ssdpool > /dev/null
    #   sudo chmod 000 /etc/zfs/keys && sudo chmod 400 /etc/zfs/keys/*
    #
    systemd.services.nas-zfs-unlock = {
      description = "Load ZFS encryption keys from file";
      after = [ "zfs-import.target" ];
      before = [ "zfs-mount.service" "local-fs.target" ];
      wantedBy = [ "zfs-mount.service" ];
      requiredBy = [ "zfs-mount.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        KEY_DIR="/etc/zfs/keys"
        for pool in ${lib.concatStringsSep " " (systemSettings.nasZfsPools or [ "ssdpool" ])}; do
          KEY_FILE="$KEY_DIR/$pool"
          if [ -f "$KEY_FILE" ]; then
            KEYSTATUS=$(${pkgs.zfs}/bin/zfs get -H -o value keystatus "$pool" 2>/dev/null || echo "unknown")
            if [ "$KEYSTATUS" = "unavailable" ]; then
              echo "Unlocking $pool from $KEY_FILE..."
              ${pkgs.zfs}/bin/zfs load-key -L "file://$KEY_FILE" "$pool" && echo "  $pool unlocked" || echo "  $pool unlock FAILED"
            else
              echo "$pool keystatus=$KEYSTATUS (no unlock needed)"
            fi
          else
            echo "WARNING: No key file for $pool at $KEY_FILE"
          fi
        done
      '';
    };

    # ZFS auto-scrub (monthly)
    services.zfs.autoScrub = {
      enable = true;
      interval = "monthly";
    };

    # ZFS auto-snapshot (daily for media, 7-day retention)
    # NOTE: Datasets must have com.sun:auto-snapshot=true set for snapshots to be taken.
    # The nas-zfs-properties service below ensures this property is set on relevant datasets.
    services.zfs.autoSnapshot = {
      enable = systemSettings.nasAutoSnapshotEnable or false;
      daily = 7;
      weekly = 0;
      monthly = 0;
    };

    # ========================================================================
    # ZFS dataset property normalization (idempotent one-shot)
    # ========================================================================
    # Ensures post-migration datasets use optimal properties:
    #   - com.sun:auto-snapshot=true (required for zfs-auto-snapshot to work)
    #   - dnodesize=auto (better metadata handling)
    #   - recordsize=1M on large-file datasets (media, backups)
    # Runs after pool mount, idempotent (setting same value is a no-op).
    systemd.services.nas-zfs-properties = {
      description = "Normalize ZFS dataset properties";
      after = [ "zfs-mount.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = let
        pools = systemSettings.nasZfsPools or [ "ssdpool" "extpool" ];
        zfs = "${pkgs.zfs}/bin/zfs";
      in ''
        set -u
        apply() {
          local dataset="$1" prop="$2" want="$3"
          if ! ${zfs} list "$dataset" >/dev/null 2>&1; then return; fi
          local have
          have=$(${zfs} get -H -o value "$prop" "$dataset" 2>/dev/null || echo "?")
          if [ "$have" != "$want" ]; then
            echo "  [set] $dataset $prop: $have -> $want"
            ${zfs} set "$prop=$want" "$dataset" || echo "  [err] failed: $prop=$want on $dataset"
          fi
        }

        echo "Normalizing ZFS properties..."

        # Enable auto-snapshots on key datasets
        for ds in ${lib.concatStringsSep " " pools}; do
          apply "$ds" com.sun:auto-snapshot true
          apply "$ds" dnodesize auto
        done

        # Child datasets that need auto-snapshot
        for ds in ssdpool/media ssdpool/docker ssdpool/workstation_backups extpool/vps-backups; do
          apply "$ds" com.sun:auto-snapshot true
        done

        # Large-file datasets: recordsize=1M for sequential throughput
        for ds in ssdpool/media extpool/vps-backups; do
          apply "$ds" recordsize 1M
        done

        echo "ZFS property normalization complete."
      '';
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
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 10"; # Wait for networking
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
    # Docker Compose auto-start on boot — Root Docker (vpn-media)
    # ========================================================================
    systemd.services.nas-docker-root-compose-up = {
      description = "Start root Docker Compose projects on boot (vpn-media)";
      after = [ "docker.service" "zfs-mount.service" "network-online.target" ];
      requires = [ "docker.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutSec = 120;
      };
      script = ''
        echo "Starting root Docker Compose projects..."
        for project in ${lib.concatMapStringsSep " " (p: "'${p}'") rootDockerProjects}; do
          if [ -d "${composeBase}/$project" ]; then
            echo "  Starting $project (root)..."
            cd "${composeBase}/$project" && ${pkgs.docker-compose}/bin/docker-compose up -d || true
          fi
        done
        echo "Root Docker projects started."
      '';
    };

    # ========================================================================
    # Docker Compose auto-start on boot — Rootless Docker (media, npm, etc.)
    # ========================================================================
    systemd.services.nas-docker-rootless-compose-up = lib.mkIf isRootless {
      description = "Start rootless Docker Compose projects on boot";
      after = [ "user@1000.service" "zfs-mount.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutSec = 300;
        User = username;
      };
      environment = rootlessEnv;
      script = ''
        echo "Starting rootless Docker Compose projects..."
        # Wait for rootless Docker socket
        for i in $(seq 1 30); do
          [ -S "/run/user/1000/docker.sock" ] && break
          echo "  Waiting for rootless Docker socket ($i/30)..."
          sleep 2
        done
        for project in ${lib.concatMapStringsSep " " (p: "'${p}'") rootlessDockerProjects}; do
          if [ -d "${composeBase}/$project" ]; then
            echo "  Starting $project (rootless)..."
            cd "${composeBase}/$project" && ${pkgs.docker-compose}/bin/docker-compose up -d || true
          fi
        done
        echo "Rootless Docker projects started."
      '';
    };

    # Fallback: single compose-up for non-rootless setups
    systemd.services.nas-docker-compose-up = lib.mkIf (!isRootless) {
      description = "Start all Docker Compose projects on boot";
      after = [ "docker.service" "zfs-mount.service" "network-online.target" ];
      requires = [ "docker.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutSec = 300;
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
