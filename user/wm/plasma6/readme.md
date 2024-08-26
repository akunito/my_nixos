
1. if you have been using Plasma already and you want to save your configuration files,
you can run the script ./_import_homeDotfiles.sh

- This will copy all the Plasma's dotfiles from your $HOME to the current directory + /source

- NOTE that you might need to overwrite or remove them first from the /source directory.


2. If you want to use the current directory's dotfiles to setup your Plasma settings, then you need to run _remove_homeDotfiles.sh script from the current directory. After that you should be able to run the main install.sh or build home-manager.

- NOTE: plasma6.nix creates symlinks from $HOME plasma dotfiles to the current directory.

- NOTE: additional variable was added to the path that is using the username from flake.nix so you can have different profiles for different users or computers. For example, you can find on my dotfiles, that under plasma6 there are files for akunito user and for aga user. If you have imported your plasma dotfiles to /source, now you must rename or copy the directory to be called as your user: /username to match with plasma6.nix expected path to be sourced


Important ! Remember that install.sh runs on Git, so you have to commit first to get last changes on home-manager