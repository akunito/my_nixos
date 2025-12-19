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

**Note**: Theme README.org files are preserved in their original location for historical reference. All content has been integrated into this documentation.

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

- **GTK Applications**: All GTK apps
- **Qt Applications**: All Qt apps
- **Terminal Emulators**: Alacritty, Kitty, etc.
- **Window Managers**: Hyprland, XMonad (with templates)
- **Text Editors**: Emacs (with doom-stylix-theme)
- **File Managers**: Ranger, etc.
- **System Components**: SDDM, system themes

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

## Best Practices

### 1. Theme Selection

- Choose themes that match your workflow
- Consider light/dark based on environment
- Test themes before committing
- Keep backup of preferred theme

### 2. Custom Themes

- Follow base16 color scheme format
- Test with multiple applications
- Document custom theme purpose
- Share themes with community

### 3. Theme Updates

- Test theme changes incrementally
- Keep theme files in version control
- Document theme-specific customizations
- Backup theme configurations

### 4. Performance

- Themes don't impact performance significantly
- Wallpaper downloads are cached
- Theme switching is fast
- No need to optimize themes

## Related Documentation

- [Stylix Documentation](https://github.com/danth/stylix#readme)
- [Base16 Documentation](https://github.com/chriskempson/base16)
- [User Modules Guide](user-modules.md) - Application theming
- [Configuration Guide](configuration.md) - Configuration management

