# GPU Monitoring Guide

Complete guide to GPU monitoring tools and their configuration for different GPU types.

## Table of Contents

- [Overview](#overview)
- [Available Tools](#available-tools)
- [Module-Based Configuration](#module-based-configuration)
- [Usage Instructions](#usage-instructions)
- [Troubleshooting](#troubleshooting)
- [Module Implementation](#module-implementation)
- [Related Documentation](#related-documentation)

## Overview

This configuration provides comprehensive GPU monitoring capabilities for AMD, Intel, and NVIDIA GPUs. GPU monitoring tools are automatically installed via the `system/hardware/gpu-monitoring.nix` module based on the `gpuType` setting in your profile configuration.

**Module-Based Configuration**: All GPU monitoring packages are managed by a single module (`system/hardware/gpu-monitoring.nix`), ensuring consistency and preventing conflicts. No manual package configuration is needed in profile files.

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

### btop (System Monitor)

**Purpose**: System monitor with optional GPU statistics integration

**Availability**: All profiles (automatically installed by module)

**For AMD GPUs (DESK, AGADESK):**
- Provided by `btop-rocm` package (compiled with ROCm support)
- Requires `rocmPackages.rocm-smi` for GPU detection (automatically installed)
- **IMPORTANT**: Use `btop` command, not `btop-rocm` (the package provides the `btop` binary)

**For Intel/Other GPUs:**
- Standard `btop` package
- May show Intel GPU stats via sysfs/hwmon

**Features**:
- CPU, memory, and process monitoring
- AMD GPU utilization, temperature, and memory usage (AMD profiles with ROCm)
- Real-time statistics display
- Terminal-based interface

**Usage**:
```bash
btop
```

**Configuration**:
- Configuration file: `~/.config/btop/btop.conf`
- GPU monitoring is enabled automatically when ROCm SMI library is available (AMD)
- Press `5`, `6`, `7` keys to toggle GPU monitoring boxes

### nvtop (GPU Monitor)

**Purpose**: Dedicated GPU monitor with GPU-specific variants

**Availability**: All profiles (automatically installed by module)

**GPU-Specific Variants**:
- **AMD**: `nvtopPackages.amd` - AMD-specific variant (prevents NVIDIA build errors)
- **Intel**: `nvtopPackages.intel` - Intel-specific variant
- **Other**: `nvtopPackages.modelling` - Generic fallback

**Features**:
- Works with AMD GPUs via amdgpu driver (no ROCm required)
- Works with NVIDIA GPUs via nvidia-smi
- Works with Intel integrated GPUs
- Real-time GPU utilization, temperature, memory usage
- Process-level GPU usage information
- Terminal-based interface similar to htop

**Usage**:
```bash
nvtop
```

**Benefits**:
- GPU-specific compilation avoids dependency issues
- Prevents build failures and runtime errors
- Works reliably for each GPU type
- No conflicts with other GPU drivers

**IMPORTANT**: Do NOT use generic `pkgs.nvtop` or `pkgs.nvitop` - they cause build/runtime errors. The module automatically uses the correct variant.

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

### intel-gpu-tools

**Purpose**: Intel GPU monitoring and diagnostics

**Availability**: Intel profiles only (LAPTOP, AGA, YOGAAKU, WSL, automatically installed by module)

**Features**:
- Provides `intel_gpu_top` command for real-time Intel GPU usage
- Intel GPU diagnostics and monitoring
- Terminal-based interface

**Usage**:
```bash
intel_gpu_top
```

**Benefits**:
- Intel-specific GPU monitoring
- Real-time usage statistics
- Highly recommended for Intel systems

### LACT (Linux AMDGPU Controller)

**Purpose**: GUI tool for AMD GPU monitoring and overclocking

**Availability**: DESK and AGADESK profiles (when `amdLACTdriverEnable = true`, configured in `opengl.nix`)

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

## Module-Based Configuration

GPU monitoring is handled automatically by the `system/hardware/gpu-monitoring.nix` module. No manual package configuration is needed in profile files.

### Module Location

The module is located at `system/hardware/gpu-monitoring.nix` and is automatically imported in all profile `configuration.nix` files.

### Automatic Package Installation

Packages are automatically installed based on `gpuType` setting:

**AMD Profiles (DESK, AGADESK):**
- `btop-rocm` - System monitor (provides `btop` command)
- `rocmPackages.rocm-smi` - ROCm SMI library and CLI tool
- `nvtopPackages.amd` - AMD-specific GPU monitor
- `radeontop` - Low-level AMD GPU monitor

**Intel Profiles (LAPTOP, AGA, YOGAAKU, WSL):**
- `btop` - Standard system monitor
- `nvtopPackages.intel` - Intel-specific GPU monitor
- `intel-gpu-tools` - Provides `intel_gpu_top` command

**Other GPU Types:**
- `btop` - Standard system monitor
- `nvtopPackages.modelling` - Generic GPU monitor

### Profile Configuration

**Required Setting**:
```nix
systemSettings = {
  gpuType = "amd";  # or "intel" or "nvidia"
  amdLACTdriverEnable = true;  # Optional: Enable LACT GUI tool for AMD
};
```

**No Manual Package Configuration Needed**: The module handles all GPU monitoring packages automatically. Do NOT add GPU monitoring packages to `systemPackages` in profile configs.

## Usage Instructions

### For AMD Dedicated GPU (DESK, AGADESK)

**Quick GPU Stats**:
```bash
rocm-smi
```

**System Monitor with GPU**:
```bash
btop
```
Note: On AMD profiles, this is provided by `btop-rocm` package. Press `5`, `6`, `7` to toggle GPU boxes.

**Dedicated GPU Monitor**:
```bash
nvtop
```
Note: Uses GPU-specific variant automatically (AMD: `nvtopPackages.amd`, Intel: `nvtopPackages.intel`)

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
nvtop
```
Note: Uses Intel-specific variant (`nvtopPackages.intel`)

**Intel GPU Top**:
```bash
intel_gpu_top
```
Note: Real-time Intel GPU usage statistics (highly recommended)

### Keyboard Shortcuts

**btop**:
- `5`, `6`, `7` - Toggle GPU monitoring boxes (AMD profiles with ROCm)
- `h` - Help menu
- `q` - Quit

**nvtop**:
- `h` - Help menu
- `q` - Quit
- Arrow keys - Navigate
- `F5` - Toggle processes view

**intel_gpu_top**:
- `q` - Quit
- Real-time display updates automatically

## Troubleshooting

### btop Not Showing GPU Stats (AMD Profiles)

**Problem**: `btop` runs but doesn't display GPU information on AMD profiles.

**Solutions**:
1. Verify `rocmPackages.rocm-smi` is installed (should be automatic via module):
   ```bash
   which rocm-smi
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

5. Verify module is imported:
   - Check that `system/hardware/gpu-monitoring.nix` is imported in your profile's `configuration.nix`
   - Verify `gpuType = "amd"` is set in your profile config

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

### nvtop Not Detecting GPU

**Problem**: `nvtop` doesn't show any GPU information.

**Solutions**:
1. Verify correct variant is installed:
   - AMD profiles: Should use `nvtopPackages.amd`
   - Intel profiles: Should use `nvtopPackages.intel`
   - Module automatically selects the correct variant

2. Verify GPU driver is loaded:
   ```bash
   lsmod | grep amdgpu  # For AMD
   lsmod | grep i915     # For Intel
   lsmod | grep nvidia   # For NVIDIA
   ```

3. Check GPU permissions:
   ```bash
   ls -l /dev/dri/
   ```
   User should be in `video` or `render` group.

4. Verify GPU is accessible:
   ```bash
   # For AMD
   cat /sys/class/drm/card*/device/uevent
   
   # For Intel
   intel_gpu_top  # Should be available on Intel profiles
   ```

5. Verify module is imported and `gpuType` is set correctly

### Module Not Installing Packages

**Problem**: GPU monitoring packages are not installed.

**Solutions**:
1. Verify `gpuType` is set in profile config:
   ```nix
   systemSettings = {
     gpuType = "amd";  # or "intel"
   };
   ```

2. Verify module is imported in profile `configuration.nix`:
   ```nix
   imports = [
     # ... other imports ...
     ../../system/hardware/gpu-monitoring.nix
   ];
   ```

3. Check that `systemSettings` is passed via `specialArgs` (should be automatic in flake-base.nix)

4. Rebuild system:
   ```bash
   sudo nixos-rebuild switch
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

### User Permissions

**Problem**: GPU monitoring tools require elevated permissions.

**Solutions**:
1. Verify user is in `video` and `render` groups:
   ```bash
   groups
   ```

2. Add user to groups if needed:
   ```nix
   users.users.${username}.extraGroups = [ "video" "render" ];
   ```

3. Log out and log back in after adding groups

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

## Module Implementation

### Module Location

`system/hardware/gpu-monitoring.nix`

### How It Works

The module uses `lib.mkIf` to conditionally install packages based on `systemSettings.gpuType`:

- **AMD**: Installs `btop-rocm`, `rocmPackages.rocm-smi`, `nvtopPackages.amd`, `radeontop`
- **Intel**: Installs `btop`, `nvtopPackages.intel`, `intel-gpu-tools`
- **Other**: Installs `btop`, `nvtopPackages.modelling` (fallback)

### Importing the Module

The module is automatically imported in all profile `configuration.nix` files:
- `profiles/work/configuration.nix` (used by personal, DESK, AGADESK, LAPTOP, etc.)
- `profiles/homelab/base.nix` (used by homelab, HOME, VMHOME)
- `profiles/wsl/configuration.nix` (used by WSL)

No manual import needed in individual profile configs.

### Benefits

- **DRY Principle**: Single source of truth for GPU monitoring
- **No Conflicts**: Prevents binary collisions (btop vs btop-rocm)
- **Automatic**: Packages selected based on GPU type
- **Consistent**: Same tools across all profiles with same GPU type

## Related Documentation

- [Hardware Guide](../hardware.md) - General hardware configuration
- [GPU Configuration](../hardware.md#gpu-configuration) - GPU type configuration
- [System Modules](../../system-modules.md) - System module documentation

