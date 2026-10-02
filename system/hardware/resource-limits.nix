{ lib, systemSettings, ... }:

# Resource guards for a machine where one runaway process must not take the host or the
# distro down with it (DESK_W11: a WSL VM with swap=0 inside a 32 GB Windows desktop).
#
# Measured 2026-10-02 (WSL 2.7.14, systemd 258, NixOS 25.11): a dotnet build inside WSL
# peaked at 22.8 GB of the VM's 24 GB (init.scope memory.peak), Windows crawled, the build
# was OOM-killed -- and the distro then restarted every 34 s for an hour. The cgroup tree
# lives in the VM kernel and survives a distro restart, so every new systemd read
# oom_kill=1 from the old init.scope and, with DefaultOOMPolicy=stop, stopped init.scope,
# which holds WSL's own /init (PID 2): "init.scope: Stopping timed out. Killing process 2
# (init-systemd)". Only `wsl --shutdown` (new VM, fresh cgroups) broke the loop. The plain
# build and the test suite reproduce nothing (9 s / 2.9 GB, 6 s / 1.4 GB), so the peak was
# a one-off runaway; what has to change is that a runaway dies alone.
let
  s = systemSettings;
in
{
  config = lib.mkIf (s.resourceLimitsEnable or false) {
    # A process OOM-killed inside a unit no longer stops the unit: for init.scope the unit
    # is the whole distro, for session-N.scope it is the terminal the build ran in.
    systemd.extraConfig = "DefaultOOMPolicy=continue";

    # Everything started from a login shell (builds, tests, Claude Code) sits in
    # user-<uid>.slice; sudo does not move cgroups, so a `sudo nixos-rebuild` evaluation
    # stays here too. MemoryHigh throttles, MemoryMax lets the kernel kill the largest
    # process in the slice. .NET reads the cgroup limit and sizes its GC heap from it, so
    # dotnet backs off before the kill. A drop-in, not a unit: systemd's own user-.slice
    # keeps its StopWhenUnneeded/TasksMax.
    systemd.units."user-.slice" = {
      overrideStrategy = "asDropin";
      text = ''
        [Slice]
        MemoryHigh=${s.limitsUserMemoryHigh}
        MemoryMax=${s.limitsUserMemoryMax}
        CPUQuota=${s.limitsUserCpuQuota}
      '';
    };

    # `wsl.exe -e <cmd>` (VS Code Remote, Windows-side scripts, a Claude session started that
    # way) skips login and runs straight under WSL's /init, i.e. in init.scope, outside every
    # user slice: the 21 GB node test of 2026-10-02 14:36 was exactly that (task_memcg=/init.scope,
    # uid 1000). Same caps there; /init itself is a few MB, so the kill lands on the runaway.
    systemd.units."init.scope" = {
      overrideStrategy = "asDropin";
      text = ''
        [Scope]
        MemoryHigh=${s.limitsUserMemoryHigh}
        MemoryMax=${s.limitsUserMemoryMax}
        CPUQuota=${s.limitsUserCpuQuota}
      '';
    };

    # Deploys: nix-daemon runs every build (install.sh, nix build, home-manager). Upstream
    # already ships OOMPolicy=continue on it; the caps are ours.
    systemd.services.nix-daemon.serviceConfig = {
      MemoryHigh = s.limitsNixMemoryHigh;
      MemoryMax = s.limitsNixMemoryMax;
      CPUQuota = s.limitsNixCpuQuota;
    };
    nix.settings = {
      max-jobs = lib.mkIf ((s.nixMaxJobs or null) != null) s.nixMaxJobs;
      cores = lib.mkIf ((s.nixBuildCores or null) != null) s.nixBuildCores;
    };
  };
}
