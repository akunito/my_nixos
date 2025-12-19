# XMonad

## What is XMonad?

[XMonad](https://xmonad.org/) is a tiling window manager written and configured in Haskell. With a custom XMonad config built over years, it's extremely efficient to operate (since it can be managed fully with the keyboard).

![XMonad Screenshot](./xmonad.png)

## Auxiliary Utilities

With the XMonad setup, several auxiliary utilities are required to make it a "full desktop environment":

- [xmobar](https://codeberg.org/xmobar/xmobar) - Status bar
- [rofi](https://github.com/davatorium/rofi) - App launcher
- [alttab](https://github.com/sagb/alttab) - Window switcher
- [feh](https://feh.finalrewind.org/) - Wallpaper utility
- pavucontrol and pamixer - Sound and volume control
- [networkmanager_dmenu](https://github.com/firecat53/networkmanager-dmenu) - Internet connection control
- brightnessctl - Screen brightness control
- [sct](https://www.umaxx.net/) - Adjust screen color temperature
- xkill and killall - Better than hitting Ctrl+Alt+Delete and waiting a few minutes

## Configuration

This directory includes the XMonad configuration, which consists of:

- `xmonad.hs` - Main configuration
- `startup.sh` - Startup script called by XMonad on startup
- `lib/Colors/Stylix.hs.mustache` - Mustache template used to generate color library to theme XMonad with Stylix
- `xmobarrc.mustache` - Mustache template used to generate xmobar config themed with Stylix
- `xmonad.nix` - Loads XMonad and configuration (along with any necessary packages) into the flake when imported

The full config is a [literate org document (xmonad.org)](./xmonad.org).

## Integration

The XMonad module is integrated into both system and user configurations. See [User Modules Guide](../user-modules.md) and [System Modules Guide](../system-modules.md) for details.

## Related Documentation

- [User Modules Guide](../user-modules.md) - User-level modules overview
- [System Modules Guide](../system-modules.md) - System-level modules overview
- [Themes Guide](../themes.md) - Stylix theme integration

**Related Documentation**: See [user/wm/xmonad/README.md](../../../user/wm/xmonad/README.md) for directory-level documentation.

**Note**: The original [user/wm/xmonad/README.org](../../../user/wm/xmonad/README.org) file is preserved for historical reference.

