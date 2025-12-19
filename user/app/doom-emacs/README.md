# Doom Emacs

## What is Doom Emacs?

[Doom Emacs](https://github.com/doomemacs/doomemacs) is a distribution of the [Emacs Text Editor](https://www.gnu.org/software/emacs/) designed for [Vim](https://www.vim.org/) users. I like to use Emacs due to its extensibility and extra features it is capable of (besides text editing). Some of these extra features include:

- [Org Mode](https://orgmode.org/) (Hierarchical text-based document format)
- [Org Roam](https://www.orgroam.com/) (A second brain / personal wiki)
- [Org Agenda](https://orgmode.org/) (Calendar and todo list)
- [magit](https://magit.vc/) (Git Client)

![Doom Emacs Screenshot](https://raw.githubusercontent.com/librephoenix/nixos-config-screenshots/main/app/doom.png)

I have found Emacs to be incredibly efficient, and transferring my workflow to fit inside of Emacs has allowed me to get much more work done. I primarily use Emacs for writing, note-taking, task/project management and organizing information.

## My Config

This directory includes my Doom Emacs configuration, which consists of:

- [config.el](./config.el) - Main configuration
- [init.el](./init.el) - Doom modules (easy sets of packages curated by Doom)
- [packages.el](./packages.el) - Additional packages from Melpa (Emacs package manager)
- [themes/doom-stylix-theme.el.mustache](./themes/doom-stylix-theme.el.mustache) - Mustache Doom Emacs template to be used with stylix, requires my [stylix.nix module](../../style/stylix.nix) as well
- [doom.nix](./doom.nix) - Loads Nix Doom Emacs and my configuration into my flake when imported
- A few other [random scripts](./scripts)

My full config is a [literate org document (doom.org)](./doom.org).

## Related Documentation

For comprehensive documentation, see [docs/user-modules/doom-emacs.md](../../../docs/user-modules/doom-emacs.md).

**Note**: The original [README.org](./README.org) file is preserved for historical reference.

