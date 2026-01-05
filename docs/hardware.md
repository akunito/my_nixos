# Hardware Guide

Complete guide to hardware-specific configurations and optimizations.

## Table of Contents

- [Overview](#overview)
- [Drive Management](#drive-management)
- [CPU Power Management](#cpu-power-management)
- [GPU Configuration](#gpu-configuration)
- [Network Adapters](#network-adapters)
- [Peripherals](#peripherals)
- [Kernel Modules](#kernel-modules)
- [Best Practices](#best-practices)

## Overview

This configuration includes comprehensive hardware support including drive management, power optimization, GPU configuration, and peripheral support.

## Drive Management

### LUKS Encrypted Drives

Support for multiple encrypted drives with automatic unlocking.

**Configuration**:
```nix
systemSettings = {
  mount2ndDrives = true;
  
  # Primary encrypted drive
  disk1_enabled = true;
  disk1_name = "/mnt/DATA_4TB";
  disk1_device = "/dev/mapper/DATA_4TB";
  disk1_fsType = "ext4";
  disk1_options = [ "nofail" "x-systemd.device-timeout=3s" ];
};
```

### Boot Options

For drives that may not always be connected:

```nix
disk1_options = [ "nofail" "x-systemd.device-timeout=3s" ];
```

- **nofail**: Don't fail boot if drive is unavailable
- **x-systemd.device-timeout**: Timeout for device availability

### NFS Mounts

Network file system mounts:

```nix
systemSettings = {
  nfsClientEnable = true;
  nfsMounts = [
    {
      what = "192.168.20.200:/mnt/hddpool/media";
      where = "/mnt/NFS_media";
      type = "nfs";
      options = "noatime";
    }
  ];
  
  nfsAutoMounts = [
    {
      where = "/mnt/NFS_media";
      automountConfig = {
        TimeoutIdleSec = "600";  # Unmount after 10 minutes idle
      };
    }
  ];
};
```

**Documentation**: See [Drive Management](hardware/drive-management.md)

## CPU Power Management

### CPU Frequency Governors

Different CPU governors for different use cases:

- **powersave** - Always minimum frequency (lowest power)
- **ondemand** - Scales based on load (balanced)
- **schedutil** - Modern scheduler-integrated (recommended)
- **performance** - Always maximum frequency (highest performance)
- **conservative** - Gradual frequency changes (power-focused)

**Configuration**:
```nix
systemSettings = {
  TLP_ENABLE = false;  # Disable for granular control
  PROFILE_ON_BAT = "performance";
  PROFILE_ON_AC = "performance";
  
  powerManagement_ENABLE = true;
  power-profiles-daemon_ENABLE = true;
};
```

**Documentation**: See [CPU Power Management](hardware/cpu-power-management.md)

### Kernel Modules for Power Management

```nix
systemSettings = {
  kernelModules = [
    "cpufreq_powersave"  # For powersave governor
    # ... other modules
  ];
};
```

## GPU Configuration

### GPU Types

Support for AMD, Intel, and NVIDIA GPUs:

```nix
systemSettings = {
  gpuType = "amd";  # "amd", "intel", or "nvidia"
  amdLACTdriverEnable = true;  # AMD LACT driver
};
```

### OpenGL Configuration

OpenGL is automatically configured based on GPU type in `system/hardware/opengl.nix`.

### AMD Specific

- LACT driver support for monitoring
- ROCm support (if enabled)
- AMDGPU driver configuration

### GPU Monitoring

GPU monitoring is handled automatically by the `system/hardware/gpu-monitoring.nix` module based on GPU type.

**For AMD Dedicated GPUs (DESK, AGADESK profiles):**
- `btop` - System monitor with AMD GPU stats (provided by `btop-rocm` package, requires `rocmPackages.rocm-smi`)
- `nvtop` - AMD-specific GPU monitor (from `nvtopPackages.amd`)
- `radeontop` - Low-level AMD GPU pipe monitoring
- `rocm-smi` - Command-line tool for AMD GPU statistics
- `lact` - GUI tool for detailed AMD GPU monitoring and overclocking

**For Intel GPUs (LAPTOP, AGA, YOGAAKU, WSL profiles):**
- `btop` - Standard system monitor (may show Intel GPU stats via sysfs/hwmon)
- `nvtop` - Intel-specific GPU monitor (from `nvtopPackages.intel`)
- `intel_gpu_top` - Real-time Intel GPU usage statistics (from `intel-gpu-tools`)

**For Other GPU Types:**
- `btop` - Standard system monitor
- `nvtop` - Generic GPU monitor (from `nvtopPackages.modelling`)

**Configuration**: GPU monitoring packages are automatically installed based on `gpuType` setting. No manual package configuration needed.

**Documentation**: See [GPU Monitoring](hardware/gpu-monitoring.md)

## Network Adapters

### WiFi Power Management

For Intel WiFi adapters, power save can be disabled to prevent connection drops:

```nix
systemSettings = {
  iwlwifiDisablePowerSave = true;  # Disable power save
  wifiPowerSave = false;  # System-level WiFi power save
};
```

**Use Case**: Prevents WiFi disconnection when laptop lid is closed.

**Configuration**: See `system/hardware/kernel.nix` for `boot.extraModprobeConfig`.

**Documentation**: See [Kernel Modules Documentation](../kernelModules.md)

### Network Configuration

```nix
systemSettings = {
  networkManager = true;
  ipAddress = "192.168.8.96";
  wifiIpAddress = "192.168.8.98";
  defaultGateway = null;
  nameServers = [ "192.168.8.1" ];
};
```

## Peripherals

### Bluetooth

```nix
systemSettings = {
  bluetoothEnable = true;
};
```

Features:
- Bluetooth daemon
- Device pairing support
- Audio device support

### Xbox Controller

```nix
systemSettings = {
  xboxControllerEnable = true;
  kernelModules = [ "xpadneo" ];
};
```

Features:
- Wireless Xbox controller support
- xpadneo driver
- Gamepad input

### Printing

```nix
systemSettings = {
  servicePrinting = true;
  networkPrinters = true;
  sharePrinter = false;
};
```

Features:
- CUPS printing service
- Brother Laser printer drivers
- Network printer discovery
- Printer sharing (CAPS)

## Kernel Modules

### Loading Modules

```nix
systemSettings = {
  kernelPackages = pkgs.linuxPackages_latest;
  kernelModules = [
    "i2c-dev"      # I2C device interface
    "i2c-piix4"    # I2C PIIX4 adapter
    "xpadneo"      # Xbox controller
    # "cpufreq_powersave"  # CPU power management
  ];
};
```

### Module Configuration

Some modules require additional configuration:

```nix
boot.extraModprobeConfig = ''
  options iwlwifi power_save=0
'';
```

### Available Modules

Common modules used in this configuration:

- **i2c-dev** - I2C device interface
- **i2c-piix4** - I2C adapter for older systems
- **xpadneo** - Xbox controller driver
- **cpufreq_powersave** - CPU power management

**Documentation**: See [Kernel Modules Documentation](../kernelModules.md)

## SystemD Configuration

### Service Management

SystemD services can be configured for hardware-related tasks:

```nix
systemSettings = {
  # Service-specific settings
};
```

### Timer Configuration

Hardware-related timers (e.g., for drive health checks):

```nix
systemd.timers.drive-health = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
  };
};
```

## Best Practices

### 1. Drive Management

- Use UUIDs for drive identification
- Add `nofail` for external drives
- Set appropriate timeouts for network drives
- Test drive mounting after configuration changes

### 2. Power Management

- Use `schedutil` governor for balanced systems
- Use `powersave` for 24/7 servers
- Use `performance` only when needed
- Monitor power consumption

### 3. GPU Configuration

- Select correct GPU type
- Enable GPU-specific features (e.g., LACT for AMD)
- Test OpenGL applications after configuration

### 4. Network Configuration

- Use static IPs for servers
- Reserve IPs in router by MAC address
- Disable WiFi power save if experiencing disconnections
- Test network connectivity after changes

### 5. Kernel Modules

- Only load necessary modules
- Test module loading after kernel updates
- Keep kernel modules updated
- Document custom module configurations

### 6. Hardware Testing

After hardware configuration changes:

1. Test basic functionality
2. Check system logs: `journalctl -xe`
3. Verify modules loaded: `lsmod`
4. Test specific hardware features
5. Monitor system stability

## Troubleshooting

### Drive Not Mounting

**Problem**: Drive doesn't mount on boot.

**Solutions**:
1. Check UUID: `sudo blkid`
2. Verify LUKS device is unlocked
3. Check filesystem: `sudo fsck /dev/mapper/DEVICE`
4. Review system logs: `journalctl -u mnt-DATA.mount`

### WiFi Disconnecting

**Problem**: WiFi disconnects when laptop lid closes.

**Solution**:
```nix
systemSettings = {
  iwlwifiDisablePowerSave = true;
};
```

### GPU Not Working

**Problem**: GPU acceleration not working.

**Solutions**:
1. Verify GPU type in configuration
2. Check OpenGL: `glxinfo | grep OpenGL`
3. Review GPU-specific modules
4. Check system logs for GPU errors

### Kernel Module Not Loading

**Problem**: Custom kernel module not loading.

**Solutions**:
1. Verify module exists: `modinfo MODULE_NAME`
2. Check module dependencies
3. Review kernel logs: `dmesg | grep MODULE_NAME`
4. Test manual loading: `sudo modprobe MODULE_NAME`

## Related Documentation

- [Drive Management](hardware/drive-management.md) - Detailed drive setup
- [CPU Power Management](hardware/cpu-power-management.md) - Power optimization
- [GPU Monitoring](hardware/gpu-monitoring.md) - GPU monitoring tools and configuration
- [Kernel Modules](../kernelModules.md) - Kernel module documentation
- [Configuration Guide](configuration.md) - General configuration

