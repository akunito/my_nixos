# Doom Emacs

## What is Doom Emacs?

[Doom Emacs](https://github.com/doomemacs/doomemacs) is a distribution of the [Emacs Text Editor](https://www.gnu.org/software/emacs/) designed for [Vim](https://www.vim.org/) users. Emacs is valued for its extensibility and extra features beyond text editing:

- [Org Mode](https://orgmode.org/) - Hierarchical text-based document format
- [Org Roam](https://www.orgroam.com/) - A second brain / personal wiki
- [Org Agenda](https://orgmode.org/) - Calendar and todo list
- [magit](https://magit.vc/) - Git Client

![Doom Emacs Screenshot](https://raw.githubusercontent.com/librephoenix/nixos-config-screenshots/main/app/doom.png)

Emacs has proven to be incredibly efficient, and transferring workflow to fit inside Emacs has allowed for much more productivity. It's primarily used for writing, note-taking, task/project management and organizing information.

## Configuration

This directory includes the Doom Emacs configuration, which consists of:

- `config.el` - Main configuration
- `init.el` - Doom modules (easy sets of packages curated by Doom)
- `packages.el` - Additional packages from Melpa (Emacs package manager)
- `themes/doom-stylix-theme.el.mustache` - Mustache Doom Emacs template to be used with stylix, requires the [stylix.nix module](../../user/style/stylix.nix) as well
- `doom.nix` - Loads Nix Doom Emacs and configuration into the flake when imported
- A few other [random scripts](./scripts)

The full config is a [literate org document (doom.org)](./doom.org).

## Integration

The Doom Emacs module is integrated into the user configuration and can be enabled in profiles. See [User Modules Guide](../user-modules.md) for details.

## Related Documentation

- [User Modules Guide](../user-modules.md) - User-level modules overview
- [Themes Guide](../themes.md) - Stylix theme integration

**Original Documentation**: The original [user/app/doom-emacs/README.org](../../../user/app/doom-emacs/README.org) file is preserved for historical reference. All content has been integrated into this documentation.

