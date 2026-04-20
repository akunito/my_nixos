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
    # Kernel modules — drivetemp for SATA disk temperature via hwmon
    # ========================================================================
    boot.kernelModules = [ "drivetemp" ];

    # ========================================================================
    # Textfile collector directory for Docker node-exporter
    # ========================================================================
    # The NAS runs node-exporter as a Docker container (not NixOS-native).
    # This directory is bind-mounted into the container so NixOS systemd
    # services can write .prom files that node-exporter exposes.
    systemd.tmpfiles.rules = [
      "d /var/lib/prometheus-node-exporter/textfile 0775 root wheel -"
    ];

    # ========================================================================
    # ZFS pool metrics textfile collector
    # ========================================================================
    # Writes pool-level metrics (size, allocated, free, fragmentation, health)
    # to a .prom file for node-exporter's textfile collector.
    # Replaces the old SSH-based truenas-zfs-exporter that pushed to Graphite.
    systemd.services.nas-zfs-pool-metrics = {
      description = "ZFS pool metrics for Prometheus textfile collector";
      after = [ "zfs-mount.service" ];
      path = [ pkgs.zfs pkgs.coreutils pkgs.gawk ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "nas-zfs-pool-metrics" ''
          set -euo pipefail
          OUTFILE="/var/lib/prometheus-node-exporter/textfile/zfs_pools.prom"
          TMPFILE="$OUTFILE.tmp"

          cat > "$TMPFILE" << 'HEADER'
# HELP nas_zfs_pool_size_bytes Total size of ZFS pool in bytes
# TYPE nas_zfs_pool_size_bytes gauge
# HELP nas_zfs_pool_allocated_bytes Allocated space in ZFS pool in bytes
# TYPE nas_zfs_pool_allocated_bytes gauge
# HELP nas_zfs_pool_free_bytes Free space in ZFS pool in bytes
# TYPE nas_zfs_pool_free_bytes gauge
# HELP nas_zfs_pool_fragmentation ZFS pool fragmentation percentage
# TYPE nas_zfs_pool_fragmentation gauge
# HELP nas_zfs_pool_healthy ZFS pool health (1=ONLINE, 0=degraded/faulted)
# TYPE nas_zfs_pool_healthy gauge
HEADER

          # zpool list -Hp columns: name, size, alloc, free, ckpoint, expandsz, frag%, cap%, dedup, health, altroot
          zpool list -Hp | while IFS=$'\t' read -r name size alloc free _ _ frag _ _ health _; do
            [ -z "$name" ] && continue
            # Handle OFFLINE pools with null values
            [ "$size" = "-" ] || [ -z "$size" ] && size=0
            [ "$alloc" = "-" ] || [ -z "$alloc" ] && alloc=0
            [ "$free" = "-" ] || [ -z "$free" ] && free=0
            [ "$frag" = "-" ] || [ -z "$frag" ] && frag=0
            healthy=0
            [ "$health" = "ONLINE" ] && healthy=1
            echo "nas_zfs_pool_size_bytes{pool=\"$name\"} $size" >> "$TMPFILE"
            echo "nas_zfs_pool_allocated_bytes{pool=\"$name\"} $alloc" >> "$TMPFILE"
            echo "nas_zfs_pool_free_bytes{pool=\"$name\"} $free" >> "$TMPFILE"
            echo "nas_zfs_pool_fragmentation{pool=\"$name\"} $frag" >> "$TMPFILE"
            echo "nas_zfs_pool_healthy{pool=\"$name\"} $healthy" >> "$TMPFILE"
          done

          mv "$TMPFILE" "$OUTFILE"
          chmod 644 "$OUTFILE"
        '';
      };
    };

    systemd.timers.nas-zfs-pool-metrics = {
      description = "ZFS pool metrics timer (every 5 minutes)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
        RandomizedDelaySec = "30s";
      };
    };

    # ========================================================================
    # NixOS update timestamp metrics (textfile collector)
    # ========================================================================
    # Writes last system/user rebuild timestamps to a .prom file.
    # Same logic as prometheus-exporters.nix but decoupled from the
    # NixOS-native node-exporter (NAS uses Docker node-exporter).
    systemd.services.nas-update-metrics = {
      description = "Export NixOS last update timestamps for Prometheus";
      after = [ "network.target" ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "nas-update-metrics" ''
          set -euo pipefail
          TEXTFILE_DIR="/var/lib/prometheus-node-exporter/textfile"
          HOSTNAME=$(cat /proc/sys/kernel/hostname)
          OUTFILE="$TEXTFILE_DIR/nixos_updates.prom"

          # System rebuild timestamp (current NixOS generation)
          SYSTEM_TS=$(stat -c %Y /nix/var/nix/profiles/system 2>/dev/null || echo 0)

          # Home Manager rebuild timestamp
          USER_TS=0
          for hm_profile in /nix/var/nix/profiles/per-user/*/home-manager /home/*/.local/state/nix/profiles/home-manager; do
            if [ -e "$hm_profile" ]; then
              ts=$(stat -c %Y "$hm_profile" 2>/dev/null || echo 0)
              [ "$ts" -gt "$USER_TS" ] && USER_TS=$ts
            fi
          done

          cat > "$OUTFILE.tmp" <<METRICS
# HELP nixos_last_update_system_timestamp Unix timestamp of last NixOS system rebuild
# TYPE nixos_last_update_system_timestamp gauge
nixos_last_update_system_timestamp{hostname="$HOSTNAME"} $SYSTEM_TS
# HELP nixos_last_update_user_timestamp Unix timestamp of last Home Manager rebuild
# TYPE nixos_last_update_user_timestamp gauge
nixos_last_update_user_timestamp{hostname="$HOSTNAME"} $USER_TS
METRICS
          mv "$OUTFILE.tmp" "$OUTFILE"
        '';
      };
    };

    systemd.timers.nas-update-metrics = {
      description = "Export NixOS update timestamps periodically";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "15min";
      };
    };

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
