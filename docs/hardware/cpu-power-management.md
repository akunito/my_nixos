# CPU Power Management

Complete guide to CPU frequency governors and power management.

## Table of Contents

- [Overview](#overview)
- [CPU Frequency Governors](#cpu-frequency-governors)
- [Governor Comparison](#governor-comparison)
- [Configuration](#configuration)
- [Kernel Modules](#kernel-modules)
- [TLP Configuration](#tlp-configuration)
- [Recommendations](#recommendations)

## Overview

CPU power management controls how the CPU scales its frequency based on workload. Different governors provide different balances between performance and power consumption.

## CPU Frequency Governors

### cpufreq_powersave

**Description**: Forces the CPU to always run at its lowest possible frequency, regardless of system load.

**Energy Consumption**: Very Low

**Performance**: Low

**Use Case**: Ideal for systems with constant low-load tasks, where power consumption is more critical than performance (e.g., file servers, low-traffic web servers, basic home automation tasks).

**Kernel Module**: `cpufreq_powersave`

### ondemand

**Description**: Dynamically adjusts CPU frequency based on current load. Scales up when load increases, scales down when load decreases.

**Energy Consumption**: Moderate

**Performance**: Moderate to High

**Use Case**: Suitable for most home lab environments where workloads vary. Good for servers that handle a mix of tasks, including some that are CPU-intensive but don't require maximum performance all the time.

**Kernel Module**: `cpufreq_ondemand`

### schedutil

**Description**: Modern governor that integrates directly with the Linux kernel's task scheduler. Adjusts CPU frequencies based on actual CPU utilization observed by the scheduler.

**Energy Consumption**: Moderate to Low

**Performance**: Moderate to High

**Use Case**: Ideal for modern systems with dynamic workloads, where both energy efficiency and responsive performance are important. Strong candidate for home labs that need to balance power savings with the ability to handle occasional high-performance tasks.

**Kernel Module**: Built into kernel (no separate module needed)

**Recommendation**: ⭐ **Recommended default** for most systems

### performance

**Description**: Forces the CPU to always run at its maximum frequency, regardless of load.

**Energy Consumption**: High

**Performance**: Very High

**Use Case**: Suitable for systems where maximum performance is a priority, such as when running virtual machines, compiling software, or hosting high-traffic services. Generally not recommended for energy-conscious home labs unless performance is the sole concern.

**Kernel Module**: `cpufreq_performance`

### conservative

**Description**: Similar to ondemand, but increases and decreases CPU frequency more gradually. Ramps up less aggressively, aiming to save more power at the cost of some performance.

**Energy Consumption**: Low to Moderate

**Performance**: Moderate

**Use Case**: Best for environments where power saving is more important than immediate responsiveness, such as systems that mostly idle with occasional, less-critical bursts of activity.

**Kernel Module**: `cpufreq_conservative`

### userspace

**Description**: Allows users or programs to set the CPU frequency manually. Doesn't automatically adjust frequencies based on load.

**Energy Consumption**: Variable

**Performance**: Variable

**Use Case**: Useful in specialized environments where specific frequency control is needed, often for testing, benchmarking, or in tightly controlled scenarios where manual tuning is preferred.

**Kernel Module**: `cpufreq_userspace`

## Governor Comparison

| Governor | Energy Consumption | Performance | Best Use Case |
|----------|-------------------|-------------|--------------|
| `cpufreq_powersave` | Very Low | Low | Systems with constant low load, power saving crucial |
| `ondemand` | Moderate | Moderate to High | General-purpose servers with variable workloads |
| `schedutil` | Moderate to Low | Moderate to High | Modern systems needing balance of efficiency and responsiveness |
| `performance` | High | Very High | Latency-sensitive or CPU-bound tasks requiring maximum performance |
| `conservative` | Low to Moderate | Moderate | Systems where power saving prioritized over immediate performance |
| `userspace` | Variable | Variable | Environments requiring manual frequency control |

## Configuration

### Using TLP

TLP provides advanced power management:

```nix
systemSettings = {
  TLP_ENABLE = false;  # Disable for granular control with profiles
  PROFILE_ON_BAT = "performance";
  PROFILE_ON_AC = "performance";
  WIFI_PWR_ON_AC = "off";  # off = disabled, on = enabled
  WIFI_PWR_ON_BAT = "off";
  INTEL_GPU_MIN_FREQ_ON_AC = 300;
  INTEL_GPU_MIN_FREQ_ON_BAT = 300;
};
```

### Using Power Profiles Daemon

For desktop systems:

```nix
systemSettings = {
  powerManagement_ENABLE = true;
  power-profiles-daemon_ENABLE = true;
};
```

This provides:
- Balanced profile (default)
- Performance profile
- Power saver profile

### Using logind

For laptop systems:

```nix
systemSettings = {
  LOGIND_ENABLE = false;  # Disable for granular control
  lidSwitch = "ignore";  # What to do when lid closes
  lidSwitchExternalPower = "ignore";
  lidSwitchDocked = "ignore";
  powerKey = "ignore";
};
```

**Lid Switch Options**:
- `ignore` - Do nothing
- `suspend` - Suspend system
- `hibernate` - Hibernate system
- `poweroff` - Power off
- `reboot` - Reboot
- `lock` - Lock screen

## Kernel Modules

### Loading Power Management Modules

```nix
systemSettings = {
  kernelModules = [
    "cpufreq_powersave"  # For powersave governor
    # "cpufreq_ondemand"  # For ondemand governor
    # "cpufreq_conservative"  # For conservative governor
    # "cpufreq_performance"  # For performance governor
  ];
};
```

**Note**: `schedutil` is built into the kernel and doesn't require a separate module.

### Module Configuration

Some modules may require additional configuration:

```nix
boot.extraModprobeConfig = ''
  # Module-specific options if needed
'';
```

## TLP Configuration

### Power Profiles

```nix
PROFILE_ON_BAT = "performance";   # Profile when on battery
PROFILE_ON_AC = "performance";   # Profile when on AC power
```

**Available Profiles**:
- `powersave` - Minimum power consumption
- `balanced` - Balance between power and performance
- `performance` - Maximum performance

### WiFi Power Management

```nix
WIFI_PWR_ON_AC = "off";   # off = disabled, on = enabled
WIFI_PWR_ON_BAT = "off";
```

### GPU Frequency

```nix
INTEL_GPU_MIN_FREQ_ON_AC = 300;   # Minimum GPU frequency on AC
INTEL_GPU_MIN_FREQ_ON_BAT = 300;  # Minimum GPU frequency on battery
```

Check current frequencies:
```sh
sudo tlp-stat -g
```

## Recommendations

### For Home Lab Servers

**Recommended**: `schedutil` or `ondemand`

- Good balance of power efficiency and performance
- Handles variable workloads well
- Modern and well-maintained

### For 24/7 Servers

**Recommended**: `cpufreq_powersave` or `conservative`

- Minimize power consumption
- Lower electricity costs
- Acceptable for low-load tasks

### For Development Workstations

**Recommended**: `schedutil` or `performance`

- Responsive performance
- Good for compiling and development
- Can handle CPU-intensive tasks

### For Laptops

**Recommended**: `schedutil` with power-profiles-daemon

- Automatic profile switching
- Battery optimization
- Performance when needed

### For Gaming Systems

**Recommended**: `performance`

- Maximum performance
- Consistent frame rates
- Low latency

## Best Practices

### 1. Choose Based on Workload

- Analyze your typical workload
- Consider power vs. performance trade-offs
- Test different governors

### 2. Monitor Power Consumption

```sh
# Check CPU frequencies
watch -n 1 "cat /proc/cpuinfo | grep MHz"

# Monitor power (if supported)
sudo powertop

# Check governor
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

### 3. Test Before Committing

- Test governor with your workload
- Monitor performance impact
- Check power consumption
- Verify stability

### 4. Use Power Profiles for Flexibility

For systems that need different profiles:
- Use power-profiles-daemon for automatic switching
- Use TLP for advanced control
- Configure logind for laptop-specific behavior

### 5. Document Configuration

Add comments explaining governor choice:

```nix
# Use schedutil for balanced power/performance
# Suitable for home lab with variable workloads
PROFILE_ON_AC = "balanced";
```

## Troubleshooting

### Governor Not Applying

**Problem**: Selected governor doesn't work.

**Solutions**:
1. Check if module is loaded: `lsmod | grep cpufreq`
2. Verify module is in kernelModules
3. Check CPU support: `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_available_governors`
4. Rebuild system: `aku sync system`

### High Power Consumption

**Problem**: System uses too much power.

**Solutions**:
1. Switch to powersave or conservative governor
2. Enable TLP power management
3. Check for CPU-intensive processes
4. Monitor with powertop

### Poor Performance

**Problem**: System feels slow.

**Solutions**:
1. Switch to performance or schedutil governor
2. Disable power saving features
3. Check CPU frequency scaling
4. Monitor CPU usage

## Related Documentation

- [Hardware Guide](../hardware.md) - General hardware configuration
- [Kernel Modules Documentation](../../kernelModules.md) - Kernel module details
- [Configuration Guide](../configuration.md) - Configuration management

