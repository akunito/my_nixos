# GPU Monitoring Guide

Complete guide to GPU monitoring tools and their configuration for different GPU types.

## Table of Contents

- [Overview](#overview)
- [Available Tools](#available-tools)
- [Profile-Specific Configuration](#profile-specific-configuration)
- [Usage Instructions](#usage-instructions)
- [Troubleshooting](#troubleshooting)
- [Related Documentation](#related-documentation)

## Overview

This configuration provides comprehensive GPU monitoring capabilities for AMD, Intel, and NVIDIA GPUs. Different tools are available depending on your GPU type and profile configuration.

### GPU Types by Profile

- **DESK**: AMD dedicated GPU
- **AGADESK**: AMD dedicated GPU
- **VMDESK**: AMD (likely integrated)
- **VMHOME**: AMD (likely integrated)
- **HOME**: AMD (likely integrated)
- **AGA**: Intel integrated GPU
- **LAPTOP**: Intel integrated GPU
- **YOGAAKU**: Intel integrated GPU
- **WSL**: Intel integrated GPU

## Available Tools

### btop-rocm

**Purpose**: System monitor with AMD GPU statistics integration

**Availability**: DESK and AGADESK profiles only

**Requirements**:
- `btop-rocm` package (already installed)
- `rocmPackages.rocm-smi` package (provides ROCm SMI library)

**Features**:
- CPU, memory, and process monitoring
- AMD GPU utilization, temperature, and memory usage
- Real-time statistics display
- Terminal-based interface

**Usage**:
```bash
btop-rocm
```

**Configuration**:
- Configuration file: `~/.config/btop/btop.conf`
- GPU monitoring is enabled automatically when ROCm SMI library is available
- Press `5`, `6`, `7` keys to toggle GPU monitoring boxes

### nvitop

**Purpose**: Universal GPU monitor supporting AMD, NVIDIA, and Intel GPUs

**Availability**: All profiles (recommended for all GPU types)

**Features**:
- Works with AMD GPUs via amdgpu driver (no ROCm required)
- Works with NVIDIA GPUs via nvidia-smi
- Works with Intel integrated GPUs
- Real-time GPU utilization, temperature, memory usage
- Process-level GPU usage information
- Terminal-based interface similar to htop
- Python-based implementation

**Usage**:
```bash
nvitop
```

**Benefits**:
- Universal support for all GPU types
- No additional dependencies for AMD GPUs (uses amdgpu driver directly)
- Works on all profiles regardless of GPU type
- Can coexist with btop

### rocm-smi

**Purpose**: Command-line tool for AMD GPU statistics

**Availability**: DESK and AGADESK profiles only

**Requirements**:
- `rocmPackages.rocm-smi` package
- AMD GPU with ROCm support

**Features**:
- GPU temperature, utilization, clock speeds
- Memory usage and bandwidth
- Power consumption
- Command-line interface suitable for scripts

**Usage**:
```bash
# Display all GPU information
rocm-smi

# Monitor continuously
watch -n 1 rocm-smi

# Get specific metrics
rocm-smi --showtemp
rocm-smi --showuse
rocm-smi --showmemuse
```

**Note**: This tool is also required for `btop-rocm` to work, as it provides the `librocm_smi64.so` library.

### btop

**Purpose**: System monitor with optional GPU support

**Availability**: All profiles

**Features**:
- CPU, memory, and process monitoring
- Intel GPU stats via sysfs/hwmon (if available)
- Terminal-based interface

**Usage**:
```bash
btop
```

**Note**: For AMD dedicated GPUs, use `btop-rocm` instead. Regular `btop` may show Intel GPU stats on systems with Intel integrated graphics.

### LACT (Linux AMDGPU Controller)

**Purpose**: GUI tool for AMD GPU monitoring and overclocking

**Availability**: DESK and AGADESK profiles (when `amdLACTdriverEnable = true`)

**Features**:
- Real-time GPU monitoring
- Overclocking and undervolting
- Fan curve configuration
- Power limit adjustment
- Temperature monitoring
- GUI interface

**Usage**:
```bash
lact
```

**Configuration**:
- Service: `lactd` (systemd service)
- Automatically started on boot when enabled
- Configuration via GUI interface

## Profile-Specific Configuration

### DESK and AGADESK Profiles (AMD Dedicated GPU)

**Installed Packages**:
```nix
systemPackages = pkgs: pkgs-unstable: [
  pkgs.btop              # System monitor
  pkgs.btop-rocm         # System monitor with GPU stats
  pkgs.rocmPackages.rocm-smi  # ROCm SMI library and CLI tool
  pkgs.nvitop            # Universal GPU monitor
];
```

**Available Tools**:
- `btop-rocm` - System monitor with AMD GPU stats
- `nvitop` - Universal GPU monitor
- `rocm-smi` - Command-line GPU stats
- `lact` - GUI monitoring and overclocking (if enabled)

**Configuration**:
```nix
systemSettings = {
  gpuType = "amd";
  amdLACTdriverEnable = true;  # Enable LACT GUI tool
};
```

### Other Profiles (Intel, AMD Integrated)

**Recommended Package**:
```nix
systemPackages = pkgs: pkgs-unstable: [
  pkgs.btop              # System monitor (may show Intel GPU stats)
  pkgs.nvitop            # Universal GPU monitor (optional but recommended)
];
```

**Available Tools**:
- `btop` - System monitor (may show Intel GPU stats)
- `nvitop` - Universal GPU monitor (works with Intel and AMD integrated GPUs)

## Usage Instructions

### For AMD Dedicated GPU (DESK, AGADESK)

**Quick GPU Stats**:
```bash
rocm-smi
```

**System Monitor with GPU**:
```bash
btop-rocm
```

**Dedicated GPU Monitor**:
```bash
nvitop
```

**GUI Monitoring**:
```bash
lact
```

### For Intel or AMD Integrated GPUs

**System Monitor**:
```bash
btop
```

**GPU Monitor**:
```bash
nvitop
```

### Keyboard Shortcuts

**btop/btop-rocm**:
- `5`, `6`, `7` - Toggle GPU monitoring boxes
- `h` - Help menu
- `q` - Quit

**nvitop**:
- `h` - Help menu
- `q` - Quit
- Arrow keys - Navigate
- `F5` - Toggle processes view

## Troubleshooting

### btop-rocm Not Showing GPU Stats

**Problem**: `btop-rocm` runs but doesn't display GPU information.

**Solutions**:
1. Verify `rocmPackages.rocm-smi` is installed:
   ```bash
   nix-env -q | grep rocm-smi
   ```

2. Check if ROCm SMI library is available:
   ```bash
   rocm-smi
   ```
   If this command works, the library is available.

3. Verify GPU is detected:
   ```bash
   rocm-smi --list
   ```

4. Check btop configuration:
   - Ensure GPU monitoring is enabled in `~/.config/btop/btop.conf`
   - Try pressing `5`, `6`, `7` keys to toggle GPU boxes

### rocm-smi Command Not Found

**Problem**: `rocm-smi` command is not available.

**Solutions**:
1. Verify package is in system packages:
   ```nix
   pkgs.rocmPackages.rocm-smi
   ```

2. Rebuild system:
   ```bash
   sudo nixos-rebuild switch
   ```

3. Check if package is in PATH:
   ```bash
   which rocm-smi
   ```

### nvitop Not Detecting GPU

**Problem**: `nvitop` doesn't show any GPU information.

**Solutions**:
1. Verify GPU driver is loaded:
   ```bash
   lsmod | grep amdgpu  # For AMD
   lsmod | grep i915     # For Intel
   lsmod | grep nvidia   # For NVIDIA
   ```

2. Check GPU permissions:
   ```bash
   ls -l /dev/dri/
   ```
   User should be in `video` or `render` group.

3. Verify GPU is accessible:
   ```bash
   # For AMD
   cat /sys/class/drm/card*/device/uevent
   
   # For Intel
   intel_gpu_top  # If available
   ```

### LACT Not Starting

**Problem**: LACT GUI doesn't start or service fails.

**Solutions**:
1. Check if LACT is enabled:
   ```nix
   systemSettings = {
     amdLACTdriverEnable = true;
   };
   ```

2. Check service status:
   ```bash
   systemctl status lactd
   ```

3. Check service logs:
   ```bash
   journalctl -u lactd -n 50
   ```

4. Verify AMD GPU is present:
   ```bash
   lspci | grep -i amd
   ```

### GPU Stats Not Updating

**Problem**: GPU statistics are static or not updating.

**Solutions**:
1. Verify GPU is being used:
   - Run a GPU-intensive application
   - Check if stats change

2. Restart monitoring tool:
   - Close and reopen the monitoring application

3. Check for driver issues:
   ```bash
   dmesg | grep -i gpu
   dmesg | grep -i amd
   ```

4. Verify permissions:
   ```bash
   groups  # Should include video or render group
   ```

## Related Documentation

- [Hardware Guide](../hardware.md) - General hardware configuration
- [GPU Configuration](../hardware.md#gpu-configuration) - GPU type configuration
- [System Modules](../system-modules.md) - System module documentation

