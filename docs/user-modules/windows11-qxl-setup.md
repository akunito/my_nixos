---
id: user-modules.windows11-qxl-setup
summary: Complete guide for setting up QXL display drivers in Windows 11 VMs with SPICE for bidirectional clipboard and dynamic resolution support. Includes troubleshooting for resolution issues and driver installation.
tags: [virtualization, windows11, qxl, spice, vm, qemu, kvm, virt-manager, display, resolution, clipboard]
related_files: [system/app/virtualization.nix, docs/system-modules/app-modules.md]
---

# Windows 11 VM QXL Display Setup Guide

Complete guide for setting up QXL display drivers in Windows 11 VMs with SPICE for bidirectional clipboard and dynamic resolution support.

## Overview

This guide covers configuring QXL video drivers for Windows 11 guests running under QEMU/KVM with SPICE. QXL provides excellent SPICE integration for dynamic resolution changes and clipboard sharing, though it requires using Windows 10-compatible drivers since Windows 11-specific QXL drivers are not available in the virtio-win ISO.

## Prerequisites

- NixOS host with virtualization enabled (`userSettings.virtualizationEnable = true`)
- virt-manager installed and configured
- Latest virtio-win ISO downloaded
- Windows 11 VM created (or existing VM)

## Step 1: Download Latest virtio-win ISO

The virtio-win package in NixOS may have an older version. Download the latest ISO:

```bash
# Download latest stable virtio-win ISO
wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso \
  -O ~/Downloads/virtio-win-latest.iso

# Or check for specific version numbers at:
# https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/
```

**Note**: The latest virtio-win ISO does not include Windows 11-specific QXL drivers. You'll need to use the Windows 10-compatible QXL driver.

## Step 2: Configure VM XML for QXL

Edit your VM's XML configuration (via `virsh edit <vm-name>` or virt-manager → View → Details → XML):

### Video Configuration

```xml
<video>
  <model type='qxl' heads='1' primary='yes'
         ram='262144' vram='262144' vgamem='131072'/>
  <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x0'/>
</video>
```

**Parameters explained**:
- `ram='262144'` - Video RAM (256MB, supports high resolutions)
- `vram='262144'` - Video RAM buffer (256MB)
- `vgamem='131072'` - VGA memory (128MB, supports 4K+)
- `heads='1'` - Single display (increase for multi-monitor)
- `primary='yes'` - Primary display

### Graphics Configuration

Ensure SPICE graphics are configured:

```xml
<graphics type="spice" autoport="yes">
  <listen type="address"/>
  <image compression="off"/>
</graphics>
```

### SPICE Channel Configuration

Add SPICE channel for clipboard and resolution sync:

```xml
<channel type="spicevmc">
  <target type="virtio" name="com.redhat.spice.0"/>
  <address type="virtio-serial" controller="0" bus="0" port="1"/>
</channel>
```

## Step 3: Mount virtio-win ISO in VM

1. Shut down the Windows 11 VM
2. In virt-manager: VM → View → Details → CD/DVD
3. Select the virtio-win ISO (or browse to your downloaded ISO)
4. Ensure "Connect" is checked
5. Boot the VM

## Step 4: Install QXL Driver in Windows 11

Since Windows 11-specific QXL drivers don't exist, use the Windows 10-compatible driver:

1. **Boot Windows 11** and open **Device Manager** (Win + X → Device Manager)

2. **Locate Display Adapter** - You should see "Microsoft Basic Display Adapter" or similar

3. **Update Driver**:
   - Right-click the display adapter → **Update driver**
   - Select **Browse my computer for drivers**
   - Click **Let me pick from a list of available drivers on my computer**
   - Click **Have Disk...**
   - Browse to the virtio-win CD drive (usually `E:\`)
   - Navigate to: `E:\qxldod\w10\amd64\` or `E:\qxl\w10\amd64\`
     - If `qxldod` folder exists, use that (QXL-DOD for Windows 8+)
     - Otherwise use `qxl\w10\amd64\`
   - Select the `.inf` file
   - Click **Next** and install

4. **If Windows warns about compatibility**:
   - Click **Install anyway** (the Win10 driver works on Win11)
   - If Secure Boot is enabled, you may need to disable it temporarily or disable driver signature enforcement

5. **Reboot Windows** after installation

## Step 5: Install SPICE Guest Tools

For clipboard sharing and better integration:

1. On the virtio-win CD, run `virtio-win-gt-x64.msi` (or `virtio-win-gt-x86.msi` for 32-bit)
2. This installs:
   - SPICE guest tools
   - VirtIO Serial driver (needed for SPICE channel)
   - Other VirtIO drivers
3. Reboot after installation

## Step 6: Verify Installation

### Check Device Manager
- Display adapter should show "QXL" or "Red Hat QXL"
- No yellow warning icons

### Check SPICE Channel
- In virt-manager: VM → View → Details → Channel
- `com.redhat.spice.0` should show **"Connected"**

### Check Services (Windows)
- Win + R → `services.msc`
- Look for:
  - **Spice Agent** (should be Running, Automatic)
  - **Spice Guest Service** (should be Running, Automatic)

### Test Dynamic Resolution
1. Resize the virt-manager window
2. Windows 11 should automatically adjust resolution
3. If not working, check SPICE channel connection

### Test Clipboard
1. Copy text from host → paste in Windows 11 guest
2. Copy text from Windows 11 guest → paste on host
3. Both directions should work

## Troubleshooting

### Resolution Issues

**Problem**: QXL sets very high resolution (beyond 4K) and won't change

**Solution**: Limit maximum resolution in XML:

```xml
<video>
  <model type='qxl' heads='1' primary='yes'
         ram='131072' vram='131072' vgamem='65536'>
    <resolution x='2560' y='1440'/>
  </model>
  <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x0'/>
</video>
```

Adjust `x` and `y` values to your desired maximum resolution.

### Driver Won't Install

**Problem**: Windows rejects the driver

**Solutions**:
1. Disable Secure Boot temporarily in VM firmware settings
2. Or disable driver signature enforcement:
   - Settings → Update & Security → Recovery → Advanced startup → Restart now
   - Troubleshoot → Advanced options → Startup Settings → Restart
   - Press F7 to disable driver signature enforcement
   - Install driver, then re-enable Secure Boot

### SPICE Channel Not Connected

**Problem**: Channel shows "Disconnected" in virt-manager

**Solutions**:
1. Verify SPICE guest tools are installed
2. Check Spice Agent service is running in Windows
3. Restart the service: `net stop spiceagent && net start spiceagent`
4. Reboot Windows

### Clipboard Not Working

**Problem**: Copy/paste doesn't work between host and guest

**Solutions**:
1. Verify SPICE channel is connected
2. Ensure Spice Agent service is running
3. Try with XWayland apps if using Wayland on host
4. Restart Spice Agent service in Windows

### Alternative: Use VirtIO-GPU Instead

If QXL causes issues, switch to VirtIO-GPU:

```xml
<video>
  <model type='virtio' heads='1' primary='yes'/>
  <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x0'/>
</video>
```

**Important**: Do NOT include `<acceleration accel3d='yes'/>` with SPICE.

Then install VirtIO display driver from `E:\Display\w11\amd64\` or `E:\Display\w10\amd64\` in the virtio-win ISO.

## Complete Example XML

Here's a complete video/graphics section for reference:

```xml
<graphics type="spice" autoport="yes">
  <listen type="address"/>
  <image compression="off"/>
</graphics>
<video>
  <model type='qxl' heads='1' primary='yes'
         ram='262144' vram='262144' vgamem='131072'/>
  <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x0'/>
</video>
<channel type="spicevmc">
  <target type="virtio" name="com.redhat.spice.0"/>
  <address type="virtio-serial" controller="0" bus="0" port="1"/>
</channel>
```

## Related Documentation

- [System Modules - Virtualization](../system-modules/app-modules.md#virtualization-systemappvirtualizationnix)
- [Virtualization Configuration](../system-modules/app-modules.md)

## Notes

- QXL drivers for Windows 11 are not available - use Windows 10-compatible drivers
- QXL provides better SPICE integration than VirtIO-GPU for dynamic resolution
- For maximum resolution support, increase `vgamem` values (e.g., `131072` for 4K+)
- SPICE auto-resize can be disabled in virt-manager if manual control is preferred

