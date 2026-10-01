{ config, pkgs, lib, systemSettings, ... }:

# Headless NVIDIA compute (CUDA in containers), no X, no display on the card.
# Imported from a NixOS profile base only when systemSettings.gpuType == "nvidia";
# never import from a darwin profile — hardware.nvidia does not exist there and
# an mkIf cannot hide an undeclared option.
#
# Option facts verified against nixos-25.11 (nixos/modules/hardware/video/nvidia.nix):
# - hardware.nvidia does NOTHING unless "nvidia" is in services.xserver.videoDrivers
#   (or datacenter.enable). That is the only switch, even with xserver disabled:
#   the kmod, GSP firmware, persistenced and powerManagement units all live in the
#   block gated on it. services.xserver.enable stays false.
# - hardware.nvidia.open has NO default for driver >= 560 (assertion). 25.11 ships
#   580.142 for stable == production == latest == beta on linuxPackages 6.12.
# - modesetting defaults to TRUE for >= 535, which adds nvidia-drm.modeset=1 and
#   nvidia-drm.fbdev=1. Forced off here: headless needs no DRM node on the card,
#   and without nvidia_drm loaded there is no second /dev/dri node to race the
#   iGPU for renderD128 (Jellyfin maps the whole /dev/dri on the NAS).
# - nvidiaSettings defaults TRUE (GTK app, not in cache.nixos.org) — off.
# - videoAcceleration defaults TRUE (nvidia-vaapi-driver into hardware.graphics) — off.
let
  s = systemSettings;
  nv = config.hardware.nvidia.package;
  smi = "${nv.bin}/bin/nvidia-smi";
  powerLimit = s.nvidiaPowerLimitWatts or null;
  persistenced = s.nvidiaPersistencedEnable or false;
  pm = s.nvidiaPowerManagementEnable or false;
  ctk = s.nvidiaContainerToolkitEnable or false;
  rootless = config.virtualisation.docker.rootless.enable;
in
{
  config = lib.mkIf ((s.gpuType or "none") == "nvidia") (lib.mkMerge [
    {
      # Replaces the stock ["modesetting" "fbdev"]: with xserver disabled those two
      # are inert, and the iGPU (amdgpu) binds by modalias regardless of this list.
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        package = config.boot.kernelPackages.nvidiaPackages.${s.nvidiaDriverChannel or "production"};
        # Open kmod: NVIDIA's recommendation for Turing+ (3090 = GA102, Ampere).
        # Also the only variant cache.nixos.org has (MIT/GPL); the closed kmod is unfree.
        open = s.nvidiaOpenKernelModule or true;
        modesetting.enable = false;
        nvidiaSettings = false;
        videoAcceleration = false;
        nvidiaPersistenced = persistenced;
        # NVreg_PreserveVideoMemoryAllocations=1 + nvidia-{suspend,resume,hibernate}.service.
        powerManagement.enable = pm;
      };

      # modesetting.enable = false is NOT enough: udev autoloads nvidia_drm (and with it
      # nvidia_modeset) by PCI alias right after nvidia binds, the 3090 takes renderD128
      # and the iGPU drops to renderD129 (measured on the NAS, 2026-10-01). blacklist does
      # not stop alias loads; `install … false` stops every load. CUDA never needs it.
      boot.extraModprobeConfig = ''
        install nvidia_drm ${pkgs.coreutils}/bin/false
      '';
    }

    (lib.mkIf pm {
      # Stock nvidia-suspend is only "Before=systemd-suspend.service" — NOT after
      # sleep.target, so it races every pre-sleep hook (the NAS's docker-stop units
      # included) and can freeze the GPU while a CUDA container still holds VRAM,
      # making the driver dump that VRAM to disk. After sleep.target = after every
      # unit ordered Before=sleep.target has finished.
      systemd.services.nvidia-suspend.after = [ "sleep.target" ];
      systemd.services.nvidia-hibernate.after = [ "sleep.target" ];
      # Where PreserveVideoMemoryAllocations dumps VRAM (default /tmp). Must be a
      # disk fs with O_TMPFILE and room for the allocated VRAM (up to 24 GB on a
      # 3090); /var/tmp is not a tmpfs on any profile here. Empty if the GPU
      # containers were stopped first, which is the plan.
      boot.extraModprobeConfig = ''
        options nvidia NVreg_TemporaryFilePath=/var/tmp
      '';
    })

    (lib.mkIf (powerLimit != null) {
      # Board power cap. Not persistent: the driver forgets it on module reload and
      # it is not guaranteed across S3, so re-apply at boot AND after every resume.
      systemd.services.nvidia-power-limit = {
        description = "Cap NVIDIA board power at ${toString powerLimit} W";
        wantedBy = [ "multi-user.target" "suspend.target" ];
        after = [ "systemd-modules-load.service" "suspend.target" ]
          ++ lib.optional persistenced "nvidia-persistenced.service"
          ++ lib.optional pm "nvidia-resume.service";
        wants = lib.optional persistenced "nvidia-persistenced.service";
        serviceConfig = {
          Type = "oneshot";
          # false on purpose: suspend.target re-starts it after every resume, which
          # only runs it again if it went inactive after the last run.
          RemainAfterExit = false;
          # nvidia binds by udev modalias, not systemd-modules-load; without
          # persistenced nothing else orders this after the device exists.
          ExecStartPre = pkgs.writeShellScript "nvidia-wait-dev" ''
            for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
              [ -e /dev/nvidia0 ] && exit 0
              ${pkgs.coreutils}/bin/sleep 1
            done
            echo "no /dev/nvidia0 after 60s" >&2
            exit 1
          '';
          # -pm 1 only when persistenced is off: with the daemon running, legacy
          # persistence mode is redundant (NVIDIA deprecates -pm in its favour).
          ExecStart =
            lib.optional (!persistenced) "${smi} -pm 1"
            ++ [ "${smi} -pl ${toString powerLimit}" ];
        };
      };
    })

    (lib.mkIf ctk {
      # CDI only (docker 25+): `--device nvidia.com/gpu=all`. No nvidia runtime and
      # no virtualisation.docker.enableNvidia (deprecated in 25.11; it also asserts
      # enable32Bit). The toolkit module sets features.cdi=true on BOTH the root
      # and the rootless daemon, adds nvidia-ctk to the rootless daemon PATH, and
      # forces hardware.graphics.enable (the spec bind-mounts /run/opengl-driver).
      hardware.nvidia-container-toolkit.enable = true;
    })

    (lib.mkIf (ctk && rootless) {
      # Rootless dockerd runs under rootlesskit --copy-up=/run: every /run entry
      # that exists when the daemon STARTS becomes a symlink into a live bind of
      # the real /run; anything created later is invisible to it. The CDI
      # generator (RuntimeDirectory=cdi) is ordered only before the ROOT
      # docker.service, so on boot it can lose the race against the lingering
      # user manager. Pre-creating the dir makes the copy-up'd /run/cdi a path
      # symlink that survives the generator recreating the directory.
      systemd.tmpfiles.rules = [ "d /run/cdi 0755 root root -" ];
      # Spell the dirs out: the rootless default set has changed between docker
      # releases; these are the dirs the NixOS generator writes to.
      virtualisation.docker.rootless.daemon.settings."cdi-spec-dirs" = [ "/etc/cdi" "/var/run/cdi" ];
    })

    (lib.mkIf (s.nvidiaGpuExporterEnable or false) {
      # utkuozdemir/nvidia_gpu_exporter (cache.nixos.org has it); shells out to
      # nvidia-smi per scrape. DCGM rejected: not in the cache, and GeForce cards
      # get only a subset of DCGM fields. Port 9835 is NOT added to
      # allowedTCPPorts: tailscale0 is a trusted interface, the VPS Prometheus
      # scrapes over the tailnet, nothing on the LAN needs it.
      services.prometheus.exporters.nvidia-gpu = {
        enable = true;
        port = s.nvidiaGpuExporterPort or 9835;
      };
    })
  ]);
}
