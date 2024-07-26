
1. if you have been using Plasma already and you want to save your configuration files,
you can run the script ./_import_homeDotfiles.sh

- This will copy all the Plasma's dotfiles from your $HOME to the current directory.

- NOTE that you might need to overwrite or remove them first.


2. If you want to use the current directory's dotfiles to setup your Plasma settings, then you need to run _remove_homeDotfiles.sh script from the current directory. After that you should be able to run the main install.sh or build home-manager.

- NOTE: plasma5.nix creates symlinks from $HOME plasma dotfiles to the current directory.