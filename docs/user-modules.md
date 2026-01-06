# User Modules Guide

Complete reference for user-level Home Manager modules in this configuration.

## Table of Contents

- [Overview](#overview)
- [Application Modules](#application-modules)
- [Language Modules](#language-modules)
- [Shell Modules](#shell-modules)
- [Window Manager Modules](#window-manager-modules)
- [Style Modules](#style-modules)
- [Package Modules](#package-modules)
- [Using Modules](#using-modules)

## Overview

User modules are located in the `user/` directory and provide user-level configuration managed by Home Manager. They are imported in profile `home.nix` files and receive variables via `extraSpecialArgs`.

### Module Import Syntax

Separate Nix files can be imported as modules using an import block:

```nix
imports = [ import1.nix
            import2.nix
            ...
          ];
```

### Module Structure

```nix
{ lib, userSettings, pkgs, systemSettings, ... }:

{
  # Module configuration
  programs.example.enable = true;
  
  # ... more configuration
}
```

## Application Modules

### Browser (`user/app/browser/`)

**Purpose**: Web browser configurations

**Available Browsers**:
- `brave.nix` - Brave browser
- `floorp.nix` - Floorp browser
- `librewolf.nix` - LibreWolf browser
- `qutebrowser.nix` - Qutebrowser (keyboard-driven)
- `qute-containers.nix` - Qutebrowser with containers
- `vivaldi.nix` - Vivaldi browser

**Settings**:
- `userSettings.browser` - Default browser selection

**Usage**:
```nix
userSettings = {
  browser = "firefox";  # or "qutebrowser", "brave", etc.
};
```

### Doom Emacs (`user/app/doom-emacs/`)

**Purpose**: Doom Emacs configuration

**Features**:
- Full Doom Emacs setup
- Org Mode configuration
- Org Roam (personal wiki)
- Magit (Git client)
- Custom themes with Stylix integration
- Literate configuration (doom.org)

**Files**:
- `config.el` - Main configuration
- `init.el` - Doom modules
- `packages.el` - Additional packages
- `doom.nix` - Nix module

**Documentation**: See [Doom Emacs Documentation](user-modules/doom-emacs.md) and [Original README](../../user/app/doom-emacs/README.org)

### Git (`user/app/git/`)

**Purpose**: Git configuration

**Features**:
- Git user configuration
- Git aliases
- Git credential helper
- GPG signing support

**Settings**:
- `userSettings.username` - Git username
- `userSettings.email` - Git email

### Ranger (`user/app/ranger/`)

**Purpose**: Terminal file manager

**Features**:
- Vim-like keybindings
- Custom color schemes
- File operations (copy, move, delete)
- Preview support
- Custom commands

**Keybindings**:
- `j`/`k` - Navigate up/down
- `h`/`l` - Navigate directories
- `SPC` - Mark files
- `yy` - Copy
- `dd` - Cut
- `pp` - Paste

**Documentation**: See [Ranger Documentation](user-modules/ranger.md) and [Original README](../../user/app/ranger/README.org)

### Terminal (`user/app/terminal/`)

**Purpose**: Terminal emulator configurations

**Available Terminals**:
- `alacritty.nix` - Alacritty terminal
- `kitty.nix` - Kitty terminal

**Settings**:
- `userSettings.terminal` - Terminal selection

**Features**:
- Stylix theme integration
- Font configuration
- Keybinding customization

### Keepass (`user/app/keepass/`)

**Purpose**: Password manager

**Features**:
- KeepassXC installation
- Auto-type configuration
- Browser integration

### Games (`user/app/games/`)

**Purpose**: Gaming applications

**Features**:
- Gaming tools
- Game launchers
- Gaming optimizations

**Note**: Only included in personal profile, not work profile.

### Flatpak (`user/app/flatpak/`)

**Purpose**: Flatpak utility installation

**Features**:
- Flatpak CLI tools
- Note: Flatpaks must be installed manually

### Virtualization (`user/app/virtualization/`)

**Purpose**: User-level virtualization tools

**Features**:
- virt-manager
- Virtualization utilities

### LM Studio (`user/app/lmstudio/`)

**Purpose**: LM Studio configuration with MCP server support

**Features**:
- Self-contained module (includes Node.js for MCP servers)
- MCP server template configuration for web search
- Brave Search integration support
- Documentation for plugins and browser extensions

**Settings**:
- No profile-level configuration needed (module is self-contained)

**Documentation**: See [LM Studio Documentation](user-modules/lmstudio.md)

### DMenu Scripts (`user/app/dmenu-scripts/`)

**Purpose**: DMenu-based scripts

**Available Scripts**:
- `networkmanager-dmenu.nix` - NetworkManager dmenu interface

**Features**:
- Network connection management via dmenu

## Language Modules

Located in `user/lang/`, these modules provide programming language environments:

### Available Languages

- Python
- Rust
- Go
- JavaScript/Node.js
- And more...

**Note**: The maintainer plans to move these to project-specific `shell.nix` files in the future.

**Usage**: Import the desired language module in `home.nix`:

```nix
imports = [
  ../../user/lang/python.nix
  ../../user/lang/rust.nix
];
```

## Shell Modules

### Shell Configuration (`user/shell/sh.nix`)

**Purpose**: Bash and Zsh configurations

**Features**:
- Zsh as default shell
- Oh My Zsh integration
- Custom aliases
- Environment variables
- Prompt configuration

**Settings**:
- `userSettings.shell` - Shell selection ("zsh" or "bash")

### CLI Collection (`user/shell/cli-collection.nix`)

**Purpose**: Curated CLI utilities

**Includes**:
- File operations: `fd`, `ripgrep`, `bat`, `exa`
- System monitoring: `htop`, `btop`, `neofetch`
- Text processing: `jq`, `yq`, `fzf`
- Network tools: `curl`, `wget`, `httpie`
- And many more...

**Features**:
- Essential command-line tools
- Productivity utilities
- Modern replacements for traditional tools

## Window Manager Modules

### Plasma 6 (`user/wm/plasma6/`)

**Purpose**: KDE Plasma 6 desktop configuration

**Features**:
- Plasma 6 configuration files
- KWin window manager settings
- Plasma widgets configuration
- Keyboard shortcuts
- Desktop layout
- Symlink management for mutable configs

**Settings**:
- `userSettings.wm` - Set to "plasma6"

**Documentation**: See [Plasma 6 README](user-modules/plasma6.md)

### Hyprland (`user/wm/hyprland/`)

**Purpose**: Hyprland Wayland compositor configuration

**Features**:
- Hyprland configuration
- Waybar status bar
- Hyprprofiles (multiple configurations)
- Custom patches

**Settings**:
- `userSettings.wm` - Set to "hyprland"

**Files**:
- `hyprland.nix` - Main configuration
- `hyprland_noStylix.nix` - Configuration without Stylix
- `hyprprofiles/` - Multiple profile configurations

### SwayFX (`user/wm/sway/`)

**Purpose**: SwayFX Wayland compositor configuration

**Features**:
- SwayFX configuration (blur, shadows, rounded corners)
- Unified daemon management system
- Waybar status bar (with explicit config path for compatibility)
- nwg-dock application launcher
- SwayNC notification center
- Libinput-gestures (touchpad gestures for workspace navigation)
- Swaybar (SwayFX internal bar) disabled by default, toggleable via `${hyper}+b`
- Multi-monitor support
- Workspace management with swaysome

**Settings**:
- `userSettings.wm` - Set to "sway"
- `systemSettings.enableSwayForDESK` - Enable SwayFX for DESK profile

**Important Notes**:
- **Waybar Compatibility**: Sway and Hyprland are mutually exclusive in the same profile due to waybar config file conflicts
- **Libinput-Gestures**: Configured for 3-finger swipe gestures matching Sway keybindings (`next_on_output`/`prev_on_output`)

**Documentation**: See [SwayFX Daemon Integration](user-modules/sway-daemon-integration.md) - Complete guide to the daemon management system

### XMonad (`user/wm/xmonad/`)

**Purpose**: XMonad tiling window manager

**Features**:
- Haskell-based configuration
- Tiling layouts
- Xmobar status bar
- Rofi app launcher
- Stylix theme integration
- Literate configuration (xmonad.org)

**Settings**:
- `userSettings.wm` - Set to "xmonad"

**Documentation**: See [XMonad Documentation](user-modules/xmonad.md) and [Original README](../../user/wm/xmonad/README.org)

### Picom (`user/wm/picom/`)

**Purpose**: X11 compositor with animations

**Features**:
- Window animations
- Transparency effects
- Shadows and blur
- pijulius fork (enhanced animations)

**Documentation**: See [Picom Documentation](user-modules/picom.md) and [Original README](../../user/wm/picom/README.org)

### Input (`user/wm/input/`)

**Purpose**: Input method configuration

**Available**:
- `nihongo.nix` - Japanese input method

**Features**:
- Input method editors
- Language-specific input

## Style Modules

### Stylix (`user/style/stylix.nix`)

**Purpose**: System-wide theming with base16

**Features**:
- Base16 theme system
- System-wide color application
- Application theme integration
- Dynamic theme switching

**Settings**:
- `userSettings.theme` - Theme selection

**Documentation**: See [Themes Guide](themes.md)

## Package Modules

Located in `user/pkgs/`, these are custom package builds for packages not in Nix repositories:

### Available Packages

- `pokemon-colorscripts.nix` - Pokemon terminal colorscripts
- `rogauracore.nix` - ROG keyboard control (not working yet)

**Usage**: Import in `home.nix`:

```nix
imports = [
  ../../user/pkgs/pokemon-colorscripts.nix
];
```

## Using Modules

### Importing Modules

In a profile's `home.nix`:

```nix
imports = [
  ../../user/app/git/git.nix
  ../../user/wm/plasma6/plasma6.nix
  ../../user/shell/sh.nix
];
```

### Conditional Enabling

Modules should use `lib.mkIf` for conditional enabling:

```nix
programs.example.enable = lib.mkIf (userSettings.wm == "plasma6") true;
```

### Accessing Variables

Modules receive variables via function arguments:

```nix
{ lib, userSettings, pkgs, systemSettings, ... }:
```

### Variables from flake.nix

Variables can be imported from `flake.nix` by setting the `extraSpecialArgs` block inside the flake. This allows variables to be managed in one place (`flake.nix`) rather than having to manage them in multiple locations.

Common attribute sets passed to user modules:

- `userSettings` - Settings for the normal user (see flake.nix for more details)
- `systemSettings` - Settings for the system (see flake.nix for more details)
- `inputs` - Flake inputs (see flake.nix for more details)
- `pkgs-stable` - Allows including stable versions of packages along with (default) unstable versions
- `pkgs-emacs` - Pinned version of nixpkgs used for Emacs and its dependencies
- `pkgs-kdenlive` - Pinned version of nixpkgs used for kdenlive

### User Settings

Common user settings used across modules:

```nix
userSettings = {
  username = "akunito";
  name = "Akunito";
  email = "user@example.com";
  dotfilesDir = "/home/akunito/.dotfiles";
  theme = "catppuccin-mocha";
  editor = "emacs";
  shell = "zsh";
  browser = "firefox";
  terminal = "alacritty";
  wm = "plasma6";
};
```

## Module Development

### Creating a New Module

1. **Create module file**:
   ```sh
   touch user/app/myapp/myapp.nix
   ```

2. **Write module**:
   ```nix
   { lib, userSettings, pkgs, ... }:
   
   {
     programs.myapp.enable = true;
     programs.myapp.config = {
       # Configuration
     };
   }
   ```

3. **Import in profile**:
   ```nix
   imports = [
     ../../user/app/myapp/myapp.nix
   ];
   ```

### Best Practices

1. **Use userSettings for configuration**
2. **Make modules conditional when appropriate**
3. **Document non-obvious configurations**
4. **Test modules individually**
5. **Keep modules focused and single-purpose**

## Related Documentation

- [Configuration Guide](configuration.md) - Understanding configuration structure
- [System Modules](system-modules.md) - System-level modules
- [Themes Guide](themes.md) - Theming system
- [Plasma 6 Guide](user-modules/plasma6.md) - Plasma 6 specific documentation
- [Doom Emacs Guide](user-modules/doom-emacs.md) - Doom Emacs documentation
- [Ranger Guide](user-modules/ranger.md) - Ranger file manager documentation
- [SwayFX Daemon Integration](user-modules/sway-daemon-integration.md) - SwayFX daemon management system
- [XMonad Guide](user-modules/xmonad.md) - XMonad window manager documentation
- [Picom Guide](user-modules/picom.md) - Picom compositor documentation

**Related Documentation**: See [user/README.md](../../user/README.md) for directory-level documentation.

**Note**: The original [user/README.org](../../user/README.org) file is preserved for historical reference.

