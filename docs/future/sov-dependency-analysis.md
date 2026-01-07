# Sov Dependency and Compatibility Analysis

**Date**: 2026-01-07  
**Issue**: Sov v0.94 crashes with segmentation fault during Wayland initialization  
**Status**: All dependencies present, crash appears to be a compatibility issue with SwayFX

---

## Dependency Verification

### ✅ All Required Dependencies Present

**Wayland Libraries** (verified via `ldd`):
- `libwayland-client.so.0` ✅
- `libwayland-cursor.so.0` ✅
- `libwayland-egl.so.1` ✅

**Graphics Libraries**:
- `libGLESv2.so.2` ✅
- `libEGL.so.1` ✅
- `libGLdispatch.so.0` ✅

**Other Dependencies**:
- `libxkbcommon.so.0` ✅
- `libpng16.so.16` ✅
- `libfreetype.so.6` ✅
- `libm.so.6` ✅
- `libc.so.6` ✅

**Wayland Protocols** (verified via WAYLAND_DEBUG):
- `wl_compositor` ✅
- `zxdg_output_manager_v1` ✅
- `zwlr_layer_shell_v1` ✅ (critical for overlays)
- `xdg_wm_base` ✅
- `zwlr_foreign_toplevel_manager_v1` ✅ (critical for window information)
- `wl_shm` ✅
- All other standard protocols ✅

### Environment Variables

**Verified**:
- `WAYLAND_DISPLAY=wayland-1` ✅
- `XDG_RUNTIME_DIR=/run/user/1000` ✅
- `SWAYSOCK=/run/user/1000/sway-ipc.1000.226529.sock` ✅
- `XDG_SESSION_TYPE=wayland` ✅
- `XDG_CURRENT_DESKTOP=sway` ✅

### Configuration

**Config File**: `~/.config/sov/config` ✅
- Format: Valid
- Content: Stylix colors (8-digit hex codes)
- Location: Correct

---

## Wayland Connection Analysis

### Successful Protocol Bindings

From `WAYLAND_DEBUG=1 sov` output, Sov successfully:
1. Connects to Wayland display ✅
2. Gets registry ✅
3. Binds to `wl_compositor` ✅
4. Binds to `zxdg_output_manager_v1` ✅
5. Binds to `zwlr_layer_shell_v1` ✅
6. Binds to `xdg_wm_base` ✅
7. Binds to `zwlr_foreign_toplevel_manager_v1` ✅
8. Creates shared memory pools ✅

**Conclusion**: All Wayland protocols are available and Sov successfully binds to them.

---

## Crash Analysis

### Stack Trace (from journalctl)
```
#0  0x000055a47d44fd11 ku_view_get_subview (/nix/store/.../sov-0.94/bin/sov + 0x14d11)
#1  0x000055a47d44454f gen_init (/nix/store/.../sov-0.94/bin/sov + 0x954f)
#2  0x000055a47d45745f ku_wayland_init (/nix/store/.../sov-0.94/bin/sov + 0x1c45f)
#3  0x000055a47d4430c2 main (/nix/store/.../sov-0.94/bin/sov + 0x80c2)
```

### Crash Location

**Function**: `ku_view_get_subview`  
**Called from**: `gen_init` → `ku_wayland_init`  
**Timing**: After successful Wayland protocol bindings, during view initialization

### Hypothesis

The crash occurs when Sov tries to access a view/subview that:
1. **Doesn't exist yet**: Sov may be trying to access views before they're created
2. **Is null/uninitialized**: The view structure may not be properly initialized
3. **Is incompatible with SwayFX**: SwayFX's wlroots fork may have different view structures

---

## SwayFX Compatibility

### System Information

- **SwayFX Version**: 0.5.3 (based on Sway 1.11.0)
- **wlroots Version**: 0.19.2 (from dependency tree)
- **Sov Version**: 0.94

### Known Compatibility Issues

1. **SwayFX is a fork**: SwayFX adds visual effects (blur, shadows, rounded corners) which may affect how views are managed
2. **wlroots version**: Sov may have been tested with standard Sway's wlroots, not SwayFX's fork
3. **View structure changes**: SwayFX may have modified view structures that Sov expects

### Testing Recommendations

1. **Test with standard Sway**: Temporarily switch to `pkgs.sway` (not `pkgs.swayfx`) to see if Sov works
2. **Check Sov version**: See if a newer version of Sov exists that fixes SwayFX compatibility
3. **Check SwayFX issues**: Look for known compatibility issues with applications

---

## Missing Dependencies Check

### Build Dependencies (Not Required at Runtime)

These are only needed to build Sov, not run it:
- `clang` ❌ (not needed at runtime)
- `meson` ❌ (not needed at runtime)
- `ninja` ❌ (not needed at runtime)
- `cmake` ❌ (not needed at runtime)
- `pkg-config` ❌ (not needed at runtime)

**Conclusion**: All runtime dependencies are present. Build dependencies are not needed.

---

## Proper Implementation

### Current Implementation (Correct)

```nix
# Keybinding
"${hyper}+Tab" = "exec ${pkgs.sov}/bin/sov";

# Config file
home.file.".config/sov/config" = lib.mkIf (...) {
  text = ''
    background-color = "#${config.lib.stylix.colors.base00}CC"
    border-color = "#${config.lib.stylix.colors.base02}FF"
    text-color = "#${config.lib.stylix.colors.base07}FF"
    active-workspace-color = "#${config.lib.stylix.colors.base0D}FF"
  '';
};
```

**This is the correct NixOS way to configure Sov**. No wrapper is needed.

---

## Solutions

### Option 1: Wait for Sov Fix (Recommended)

The crash appears to be a bug in Sov v0.94 when running on SwayFX. Options:
- Check for newer Sov version
- Report bug to Sov maintainer (Milan Toth)
- Check Sov GitHub issues for SwayFX compatibility

### Option 2: Test with Standard Sway

Temporarily test if Sov works with standard Sway:
```nix
package = pkgs.sway;  # Instead of pkgs.swayfx
```

If Sov works with standard Sway, this confirms a SwayFX compatibility issue.

### Option 3: Use Alternative

If Sov cannot be fixed, use alternatives:
- **Rofi window mode**: `rofi -show window` (already installed)
- **SwayFX native**: Check if SwayFX has built-in workspace overview
- **Other tools**: Research SwayFX-compatible workspace overview tools

---

## Conclusion

**All dependencies are present**. The crash is not due to missing dependencies, but appears to be a **compatibility issue between Sov v0.94 and SwayFX**. The crash occurs during view initialization after successful Wayland protocol binding, suggesting a bug in how Sov handles views in SwayFX's modified wlroots.

**Recommendation**: Test with standard Sway to confirm compatibility issue, then either wait for a Sov fix or use an alternative workspace overview tool.

