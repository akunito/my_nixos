# XMonad

## What is XMonad?

[XMonad](https://xmonad.org/) is a tiling window manager written and configured in Haskell. Since I have built up my own XMonad config over a few years, it is extremely efficient for me to operate (since it can be managed fully with the keyboard).

![XMonad Screenshot](./xmonad.png)

With my XMonad setup, there are several auxiliary utilities required to make it a "full desktop environment." A few of these packages include:

- [xmobar](https://codeberg.org/xmobar/xmobar) - Status bar
- [rofi](https://github.com/davatorium/rofi) - App launcher
- [alttab](https://github.com/sagb/alttab) - Window switcher
- [feh](https://feh.finalrewind.org/) - Wallpaper utility
- pavucontrol and pamixer - Sound and volume control
- [networkmanager_dmenu](https://github.com/firecat53/networkmanager-dmenu) - Internet connection control
- brightnessctl - Screen brightness control
- [sct](https://www.umaxx.net/) - Adjust screen color temperature
- xkill and killall - Better than hitting Ctrl+Alt+Delete and waiting a few minutes

## My Config

This directory includes my XMonad configuration, which consists of:

- [xmonad.hs](./xmonad.hs) - Main configuration
- [startup.sh](./startup.sh) - Startup script called by XMonad on startup
- [lib/Colors/Stylix.hs.mustache](./lib/Colors/Stylix.hs.mustache) - Mustache template used to generate color library to theme XMonad with Stylix
- [xmobarrc.mustache](./xmobarrc.mustache) - Mustache template used to generate my xmobar config themed with Stylix
- [xmonad.nix](./xmonad.nix) - Loads XMonad and my configuration (along with any necessary packages for my config) into my flake when imported

My full config is a [literate org document (xmonad.org)](./xmonad.org).

## Related Documentation

For comprehensive documentation, see [docs/user-modules/xmonad.md](../../../docs/user-modules/xmonad.md).

**Note**: The original [README.org](./README.org) file is preserved for historical reference.

