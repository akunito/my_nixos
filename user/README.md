# User-level Nix Modules

Separate Nix files can be imported as modules using an import block:

```nix
imports = [ import1.nix
            import2.nix
            ...
          ];
```

My user-level Nix modules are organized into this directory:

- [app](./app) - Apps or collections of apps bundled with my configs
  - [browser](./app/browser) - Used to set default browser
  - [dmenu-scripts](./app/dmenu-scripts)
  - [doom-emacs](./app/doom-emacs)
  - [flatpak](./app/flatpak) - Installs flatpak as a utility (flatpaks must be installed manually)
  - [games](./app/games) - Gaming setup
  - [git](./app/git)
  - [keepass](./app/keepass)
  - [ranger](./app/ranger)
  - [terminal](./app/terminal) - Configuration for terminal emulators
  - [virtualization](./app/virtualization) - Virtualization and compatibility layers
- [lang](./lang) - Various bundled programming languages
  - I will probably get rid of this in favor of a shell.nix for every project, once I learn how that works
- [pkgs](./pkgs) - "Package builds" for packages not in the Nix repositories
  - [pokemon-colorscripts](./pkgs/pokemon-colorscripts.nix)
  - [rogauracore](./pkgs/rogauracore.nix) - not working yet
- [shell](./shell) - My default bash and zsh configs
  - [sh](./shell/sh.nix) - bash and zsh configs
  - [cli-collection](./shell/cli-collection.nix) - Curated useful CLI utilities
- [style](./style) - Stylix setup (system-wide base16 theme generation)
- [wm](./wm) - Window manager, compositor, wayland compositor, and/or desktop environment setups
  - [hyprland](./wm/hyprland)
  - [xmonad](./wm/xmonad)
  - [picom](./wm/picom)

## Variables imported from flake.nix

Variables can be imported from [flake.nix](../flake.nix) by setting the `extraSpecialArgs` block inside the flake (see [my flake](../flake.nix) for more details). This allows variables to be managed in one place ([flake.nix](../flake.nix)) rather than having to manage them in multiple locations.

I use this to pass a few attribute sets:

- `userSettings` - Settings for the normal user (see [flake.nix](../flake.nix) for more details)
- `systemSettings` - Settings for the system (see [flake.nix](../flake.nix) for more details)
- `inputs` - Flake inputs (see [flake.nix](../flake.nix) for more details)
- `pkgs-stable` - Allows me to include stable versions of packages along with (my default) unstable versions of packages
- `pkgs-emacs` - Pinned version of nixpkgs I use for Emacs and its dependencies
- `pkgs-kdenlive` - Pinned version of nixpkgs I use for kdenlive

## Related Documentation

For comprehensive documentation, see [docs/user-modules/](../docs/user-modules/README.md).

**Note**: The original [README.org](./README.org) file is preserved for historical reference.

