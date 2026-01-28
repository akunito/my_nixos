{ systemSettings, lib, ... }:

# Consolidated I/O scheduler optimization for all profile types
# Uses lib.mkMerge to apply profile-specific I/O scheduler rules
# VMs are automatically excluded - hypervisor handles I/O scheduling
lib.mkMerge [
  # Desktop I/O scheduler (enabled via enableDesktopPerformance flag)
  (lib.mkIf systemSettings.enableDesktopPerformance {
    services.udev.extraRules = ''
      # NVMe drives: use mq-deadline (better than none for modern NVMe)
      ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="mq-deadline"

      # SATA drives: use bfq (better for desktop workloads)
      ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="bfq"
    '';
  })

  # Laptop I/O scheduler (enabled via enableLaptopPerformance flag)
  (lib.mkIf systemSettings.enableLaptopPerformance {
    services.udev.extraRules = ''
      # NVMe drives: use mq-deadline
      ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="mq-deadline"

      # SATA drives: use bfq (same as desktop - good for interactive workloads)
      ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="bfq"
    '';
  })

  # Server I/O scheduler (homelab profile)
  # All drives use mq-deadline for better server workload performance
  (lib.mkIf (systemSettings.profile == "homelab") {
    services.udev.extraRules = ''
      # NVMe drives: use mq-deadline (better for server workloads)
      ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="mq-deadline"

      # SATA drives: use mq-deadline (better for server workloads than bfq)
      ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="mq-deadline"
    '';
  })

  # VMs are automatically excluded
  # Hypervisors handle I/O scheduling for virtual machines, so we don't set schedulers
  # This is intentional - profiles without enableDesktopPerformance/enableLaptopPerformance/homelab
  # get no I/O scheduler changes
]
