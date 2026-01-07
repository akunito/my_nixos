# Themes Guide

Complete guide to the theming system and available themes.

## Table of Contents

- [Overview](#overview)
- [Available Themes](#available-themes)
- [Theme Structure](#theme-structure)
- [Switching Themes](#switching-themes)
- [Custom Themes](#custom-themes)
- [Stylix Integration](#stylix-integration)
- [Troubleshooting](#troubleshooting)

## Overview

This configuration uses [Stylix](https://github.com/danth/stylix) for system-wide theming with [base16](https://github.com/chriskempson/base16) color schemes. Stylix applies themes consistently across all applications, providing a unified look and feel.

### Features

- **55+ Themes**: Pre-configured base16 themes
- **System-Wide**: Themes apply to all applications
- **Dynamic Switching**: Change themes without restarting applications
- **Consistent Styling**: Unified colors across GTK, Qt, terminal, and more
- **Automatic Integration**: Works with many applications automatically

## Available Themes

### Popular Themes

- **catppuccin-mocha** - Popular modern dark theme
- **nord** - Clean, arctic theme
- **dracula** - Dark theme with vibrant colors
- **gruvbox-dark-medium** - Retro groove theme
- **solarized-dark** - Carefully designed dark theme
- **everforest** - Comfortable, pleasant theme

### Complete Theme List

All themes are located in the `themes/` directory:

- alph
- ashes
- atelier-cave
- atelier-dune
- atelier-estuary
- atelier-forest
- atelier-heath
- atelier-lakeside
- atelier-plateau
- atelier-savanna
- atelier-seaside
- atelier-sulphurpool
- ayu-dark
- bespin
- caret
- catppuccin-frappe
- catppuccin-mocha
- darkmoss
- doom-one
- dracula
- ember
- emil
- eris
- eva
- everforest
- fairy-floss
- gigavolt
- gruvbox-dark-hard
- gruvbox-dark-medium
- gruvbox-light-hard
- gruvbox-light-medium
- helios
- henna
- horizon-dark
- io
- isotope
- manegarm
- material-vivid
- miramare
- monokai
- nord
- oceanic-next
- old-hope
- outrun-dark
- selenized-dark
- selenized-light
- solarized-dark
- solarized-light
- spaceduck
- stella
- summerfruit-dark
- tomorrow-night
- twilight
- ubuntu
- uwunicorn
- windows-95
- woodland
- xcode-dusk

Each theme directory contains:
- `README.org` - Theme documentation and preview (original format, preserved)
- `${theme-name}.yaml` - Base16 color definitions
- `backgroundurl.txt` - Wallpaper URL
- `backgroundsha256.txt` - Wallpaper checksum
- `polarity.txt` - Light or dark theme
- Preview images

**Related Documentation**: See [themes/README.md](../../themes/README.md) for directory-level documentation.

**Note**: Theme-specific README.org files are preserved in their original location for historical reference.

## Theme Structure

Each theme directory stores a few relevant files:

- `${theme-name}.yaml` - Stores all 16 colors for the theme
- `backgroundurl.txt` - Direct link to the wallpaper associated with the theme
- `backgroundsha256.txt` - SHA256 sum of the wallpaper
- `polarity.txt` - Whether the background is `light` or `dark`
- `${theme-name}.png` - Screenshot of the theme for previewing purposes

Look at any of the theme directories for more info!

### Theme Directory

```
themes/THEME_NAME/
├── THEME_NAME.yaml      # Base16 color definitions
├── backgroundurl.txt     # Wallpaper URL
├── backgroundsha256.txt # Wallpaper checksum
├── polarity.txt         # "light" or "dark"
├── README.org           # Theme documentation
└── preview images       # Screenshots
```

### Color Definition

Themes use base16 YAML format:

```yaml
scheme: "Theme Name"
author: "Author"
base00: "#000000"  # Background
base01: "#111111"  # Lighter background
base02: "#222222"  # Selection background
base03: "#333333"  # Comments
base04: "#444444"  # Dark foreground
base05: "#555555"  # Default foreground
base06: "#666666"  # Light foreground
base07: "#777777"  # Lighter foreground
base08: "#880000"  # Red
base09: "#884400"  # Orange
base0A: "#888800"  # Yellow
base0B: "#008800"  # Green
base0C: "#008888"  # Cyan
base0D: "#000088"  # Blue
base0E: "#880088"  # Magenta
base0F: "#888888"  # Brown
```

## Switching Themes

### Configuration

Set theme in your flake file:

```nix
userSettings = {
  theme = "catppuccin-mocha";  # Theme name
};
```

### Apply Theme

After changing theme:

```sh
# Rebuild home-manager
phoenix sync user

# Or refresh posthooks
phoenix refresh
```

### Dynamic Switching

Some applications support theme switching without restart:
- GTK applications (after refresh)
- Qt applications (after refresh)
- Terminal emulators (may require restart)

## Custom Themes

### Creating a Custom Theme

1. **Create theme directory**:
   ```sh
   mkdir -p themes/my-theme
   ```

2. **Create color definition**:
   ```sh
   cp themes/nord/nord.yaml themes/my-theme/my-theme.yaml
   # Edit colors
   ```

3. **Add wallpaper**:
   ```sh
   echo "https://example.com/wallpaper.jpg" > themes/my-theme/backgroundurl.txt
   ```

4. **Set polarity**:
   ```sh
   echo "dark" > themes/my-theme/polarity.txt
   ```

5. **Update Stylix configuration**:
   ```nix
   stylix = {
     base16Scheme = "${./themes/my-theme/my-theme.yaml}";
     image = "https://example.com/wallpaper.jpg";
   };
   ```

### Testing Theme Backgrounds

Test if theme backgrounds are accessible:

```sh
./themes/background-test.sh
```

This script checks all theme background URLs and reports which are broken.

## Stylix Integration

### Supported Applications

Stylix automatically themes:

- **GTK Applications**: All GTK apps (GTK2, GTK3, GTK4/LibAdwaita)
- **Qt Applications**: All Qt apps (QT5 and QT6)
- **Terminal Emulators**: Alacritty, Kitty, etc.
- **Window Managers**: Hyprland, XMonad (with templates)
- **Text Editors**: Emacs (with doom-stylix-theme)
- **File Managers**: Ranger, etc.
- **System Components**: SDDM, system themes

### GTK Configuration

Stylix configures GTK applications through multiple mechanisms:

1. **Stylix GTK Target**: `stylix.targets.gtk.enable = true` generates CSS files with Stylix colors
2. **Home Manager GTK Module**: Sets `gtk-theme-name` and `gtk-application-prefer-dark-theme` in config files
3. **DConf Settings**: Required for GTK4/LibAdwaita apps (Chromium, Blueman, etc.) to respect dark mode

**GTK4/LibAdwaita Apps** (Chromium, Blueman, Vivaldi extensions):
- These apps require `dconf.settings` to set `org.gnome.desktop.interface.color-scheme = "prefer-dark"`
- Home Manager's `gtk` module sets config files but doesn't set gsettings via dconf
- The configuration uses `dconf.settings` in `user/style/stylix.nix` to properly set gsettings

**Configuration Example**:
```nix
stylix.targets.gtk.enable = true;
gtk = {
  enable = true;
  gtk3.extraConfig = {
    gtk-theme-name = "Adwaita-dark";
    gtk-application-prefer-dark-theme = 1;
  };
  gtk4.extraConfig = {
    gtk-theme-name = "Adwaita-dark";
    gtk-application-prefer-dark-theme = 1;
  };
};
dconf.settings = {
  "org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "Adwaita-dark";
  };
};
```

### Qt Configuration

Stylix configures Qt applications through the Qt target:

1. **Stylix Qt Target**: `stylix.targets.qt.enable = true` generates qt5ct configuration files automatically
2. **Platform Theme**: Choose between `qtct` (custom Stylix colors) or `gtk3` (native Adwaita matching)
3. **Environment Variables**: `QT_QPA_PLATFORMTHEME` is set automatically by Stylix

**Platform Theme Options**:
- **`qtct` (Recommended)**: Uses custom Stylix colors via qt5ct. Stylix generates `.config/qt5ct/colors/oomox-current.conf` and `.config/qt5ct/qt5ct.conf` automatically. Works for both QT5 and QT6 applications.
- **`gtk3`**: QT apps match GTK Adwaita theme. Simpler but doesn't use custom Stylix colors.

**Configuration Example**:
```nix
stylix.targets.qt.enable = true;
stylix.targets.qt.platform = "qtct";  # For custom Stylix colors
# OR
qt.platformTheme.name = "gtk3";  # For Adwaita matching
```

**Important**: Do NOT manually create qt5ct config files. Stylix generates them declaratively. Manual file creation conflicts with Stylix's declarative approach.

### Wayland Environment Variable Injection

On Wayland (Sway, Hyprland), environment variables from Home Manager need to be synced with the D-Bus activation environment. This is necessary because:

- Home Manager defines variables in `~/.nix-profile/etc/profile.d/hm-session-vars.sh`
- Window managers don't automatically import these into D-Bus activation environment
- GUI applications launched via D-Bus need these variables

**Sway Configuration**:
```nix
startup = [
  {
    command = "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP QT_QPA_PLATFORMTHEME GTK_THEME GTK_APPLICATION_PREFER_DARK_THEME";
    always = true;
  }
];
```

This command syncs declarative config with the running session so GUI apps inherit the correct GTK/QT theme variables.

### Application-Specific Configuration

Some applications require additional configuration:

#### Doom Emacs

Uses `doom-stylix-theme.el.mustache` template for theme integration.

#### XMonad

Uses `Stylix.hs.mustache` template for color integration.

#### Hyprland

Can use Stylix colors directly or use `hyprland_noStylix.nix` for manual theming.

## Troubleshooting

### Theme Not Applying

**Problem**: Theme changes don't appear.

**Solutions**:
1. Rebuild home-manager: `phoenix sync user`
2. Refresh posthooks: `phoenix refresh`
3. Restart applications
4. Check theme name spelling
5. Verify theme file exists

### Background Not Downloading

**Problem**: Installation fails with background download error.

**Solutions**:
1. Test backgrounds: `./themes/background-test.sh`
2. Select theme with working background
3. Or use local background image
4. Check network connectivity

### Colors Look Wrong

**Problem**: Colors don't match theme.

**Solutions**:
1. Verify theme YAML format
2. Check base16 color definitions
3. Rebuild: `phoenix sync user`
4. Clear application caches
5. Restart applications

### Application Not Themed

**Problem**: Specific application not using theme.

**Solutions**:
1. Check if application supports GTK/Qt theming
2. Verify Stylix integration for that app
3. Check application-specific theme settings
4. May require manual configuration

### GTK4/LibAdwaita Apps Showing Light Mode

**Problem**: Chromium, Blueman, or other GTK4/LibAdwaita apps show light mode despite dark theme.

**Solutions**:
1. Verify `dconf.settings` is configured in `user/style/stylix.nix`:
   ```nix
   dconf.settings = {
     "org/gnome/desktop/interface" = {
       color-scheme = "prefer-dark";
       gtk-theme = "Adwaita-dark";
     };
   };
   ```
2. Check gsettings: `gsettings get org.gnome.desktop.interface color-scheme` (should be "prefer-dark")
3. Rebuild: `phoenix sync user`
4. Restart the application

### Qt Applications Not Themed

**Problem**: Qt applications (QT5/QT6) not using Stylix theme.

**Solutions**:
1. Verify `stylix.targets.qt.enable = true` is set
2. Check `QT_QPA_PLATFORMTHEME` environment variable: `env | grep QT_QPA_PLATFORMTHEME` (should be "qt5ct" for qtct platform)
3. Verify qt5ct config exists: `ls ~/.config/qt5ct/colors/` (Stylix generates this automatically)
4. On Wayland: Ensure `dbus-update-activation-environment` includes `QT_QPA_PLATFORMTHEME` in Sway startup
5. Rebuild: `phoenix sync user`
6. Restart the application

### Environment Variables Not Set

**Problem**: GTK/QT environment variables not available in GUI applications.

**Solutions**:
1. On Wayland: Verify `dbus-update-activation-environment` command in Sway/Hyprland config
2. Check environment variables: `env | grep -E "GTK_|QT_"`
3. Verify Home Manager session variables: `cat ~/.nix-profile/etc/profile.d/hm-session-vars.sh`
4. Restart window manager session (log out and back in)

## Best Practices

### 1. Use Declarative Configuration

**CRITICAL**: Always use Stylix and Home Manager's declarative configuration. Do NOT use imperative tools.

- **DO NOT use `lxappearance`** - It modifies files that Home Manager/Stylix regenerate
- **DO NOT manually create** qt5ct/qt6ct config files - Stylix generates them declaratively
- **DO use** `stylix.targets.qt.enable = true` for Qt theming
- **DO use** `dconf.settings` for GTK4/LibAdwaita gsettings

**Why**: Imperative tools create conflicts where manual changes are overwritten on rebuild, causing the exact inconsistencies you're trying to solve.

### 2. Platform Theme Choice

Choose between Qt platform themes based on your preference:

- **`qtct` (Recommended)**: Custom Stylix colors via qt5ct. Gives full control over Qt theming with your Stylix color scheme.
- **`gtk3`**: Native Adwaita matching. Simpler but doesn't use custom Stylix colors.

Set via:
```nix
stylix.targets.qt.platform = "qtct";  # Custom colors
# OR
qt.platformTheme.name = "gtk3";  # Adwaita matching
```

### 3. System vs User Level Configuration

- **System-level** (`system/style/stylix.nix`): Should only set base variables, not application-specific theming
- **User-level** (`user/style/stylix.nix`): Controls application-specific theming (GTK, Qt, etc.)

**Example**: `QT_QPA_PLATFORMTHEME` should be set at user-level, not system-level, to avoid conflicts.

### 4. Wayland Environment Variables

On Wayland (Sway, Hyprland), always include `dbus-update-activation-environment` in window manager startup:

- This syncs Home Manager variables with D-Bus activation environment
- Required for GUI applications to inherit theme variables
- Not a workaround - it's necessary for Wayland

### 5. Theme Selection

- Choose themes that match your workflow
- Consider light/dark based on environment
- Test themes before committing
- Keep backup of preferred theme

### 6. Custom Themes

- Follow base16 color scheme format
- Test with multiple applications
- Document custom theme purpose
- Share themes with community

### 7. Theme Updates

- Test theme changes incrementally
- Keep theme files in version control
- Document theme-specific customizations
- Backup theme configurations

### 8. Performance

- Themes don't impact performance significantly
- Wallpaper downloads are cached
- Theme switching is fast
- No need to optimize themes

## Related Documentation

- [Stylix Documentation](https://github.com/danth/stylix#readme)
- [Base16 Documentation](https://github.com/chriskempson/base16)
- [User Modules Guide](user-modules.md) - Application theming
- [Configuration Guide](configuration.md) - Configuration management

