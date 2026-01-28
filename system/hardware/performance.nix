{ systemSettings, lib, pkgs, ... }:

# Consolidated performance optimizations for all profile types
# Uses lib.mkMerge to combine global defaults with profile-specific settings
lib.mkMerge [
  # Global defaults - benefits all profiles without negative side effects
  {
    boot.kernel.sysctl = {
      # TCP BBR congestion control - benefits all profiles (gaming/development/server)
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";

      # NFS optimizations - benefits all profiles that use NFS
      "sunrpc.tcp_max_slot_table_entries" = 128;
      "sunrpc.udp_slot_table_entries" = 128;
    };
  }

  # Desktop optimizations (enabled via enableDesktopPerformance flag)
  # Aggressive settings for maximum performance on desktop systems
  (lib.mkIf systemSettings.enableDesktopPerformance {
    boot.kernel.sysctl = {
      # VM settings (desktop-optimized)
      "vm.swappiness" = 10;  # Reduce swap usage (desktop system)
      "vm.dirty_ratio" = 15;  # Reduce dirty page ratio
      "vm.dirty_background_ratio" = 5;

      # Network optimizations (aggressive - maximum performance)
      "net.core.rmem_max" = 16777216;  # 16MB
      "net.core.wmem_max" = 16777216;  # 16MB
      "net.ipv4.tcp_rmem" = "4096 87380 16777216";
      "net.ipv4.tcp_wmem" = "4096 65536 16777216";
      "net.core.netdev_max_backlog" = 5000;
      "net.ipv4.tcp_fastopen" = 3;  # Enable TCP Fast Open
    };

    # Ananicy - Auto Nice Daemon for desktop
    # System-wide automatic process priority management
    # Prevents lag without reducing performance for ALL applications
    services.ananicy.enable = true;

    # Ananicy automatically detects and adjusts priority for:
    # - Indexers (cursor-agent, rg, ripgrep, etc.)
    # - Compilers (gcc, clang, rustc, etc.)
    # - Language servers (node, typescript-server, etc.)
    # - Build tools (make, ninja, cargo, etc.)
    # - Background tasks (backups, sync, etc.)
    # - Any CPU-intensive background process
    #
    # How it works:
    # - Sets background processes to low priority (Nice=19) automatically
    # - Allows 100% CPU usage when system is idle (fast operations)
    # - Instantly yields CPU when user interacts (mouse, keyboard, GUI)
    # - Zero lag, maximum performance for all applications
    #
    # Benefits:
    # - Cursor IDE: No lag during indexing
    # - Development: Compilers don't freeze the system
    # - Gaming: Background tasks don't affect frame rates
    # - General: System remains responsive during any background work
  })

  # Laptop optimizations (enabled via enableLaptopPerformance flag)
  # Conservative settings for battery life while maintaining responsiveness
  (lib.mkIf systemSettings.enableLaptopPerformance {
    boot.kernel.sysctl = {
      # VM settings (battery-focused)
      "vm.swappiness" = 20;  # Moderate swap usage (balance between performance and battery)
      "vm.dirty_ratio" = 20;  # Balanced dirty page ratio
      "vm.dirty_background_ratio" = 10;

      # Network optimizations (conservative - save power)
      "net.core.rmem_max" = 8388608;  # 8MB (smaller than desktop to save power)
      "net.core.wmem_max" = 8388608;  # 8MB
      "net.ipv4.tcp_rmem" = "4096 65536 8388608";
      "net.ipv4.tcp_wmem" = "4096 32768 8388608";
      "net.core.netdev_max_backlog" = 3000;
      "net.ipv4.tcp_fastopen" = 3;  # Enable TCP Fast Open
    };

    # Ananicy for laptop (prevents lag, doesn't hurt battery)
    # Same benefits as desktop, but with power-conscious settings above
    services.ananicy.enable = true;
  })

  # Server optimizations (homelab profile)
  # Throughput-focused settings for 24/7 server operation
  (lib.mkIf (systemSettings.profile == "homelab") {
    boot.kernel.sysctl = {
      # VM settings (throughput-focused, 24/7 operation)
      "vm.swappiness" = 60;  # Higher swap usage (servers can benefit from swap for caching)
      "vm.dirty_ratio" = 30;  # Higher dirty page ratio (better for server workloads)
      "vm.dirty_background_ratio" = 15;

      # Network optimizations (large buffers for server workloads)
      "net.core.rmem_max" = 33554432;  # 32MB (large buffers for NFS/server operations)
      "net.core.wmem_max" = 33554432;  # 32MB
      "net.ipv4.tcp_rmem" = "4096 131072 33554432";
      "net.ipv4.tcp_wmem" = "4096 131072 33554432";
      "net.core.netdev_max_backlog" = 10000;
      "net.ipv4.tcp_fastopen" = 3;  # Enable TCP Fast Open
    };

    # NO Ananicy for servers (not needed for non-interactive systems)
    # Servers don't have interactive users, so process priority management is unnecessary
  })
]
