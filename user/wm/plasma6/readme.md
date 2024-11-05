
1. if you have been using Plasma already and you want to save your configuration files,
you can run the script ./_export_homeDotfiles.sh

- This will copy all the Plasma's dotfiles from your $HOME to the given directory (I use "~/.dotfiles-plasma-config/source")

- You might need to overwrite or remove them first from the "~/.dotfiles-plasma-config/source" directory if you have already exported them before.

- NOTE that you will be asked to do this during the install.sh script execution as well, when the Home-manager will be applied. In this way will be easier to manage.


2. If you want to use the any directory to setup your Plasma settings, then you need to run the script "./run _remove_homeDotfiles.sh" that you will find in the current directory. After that you should be able to run the main install.sh or build home-manager.
I use for this purpose "~/.dotfiles-plasma-config/userDotfiles" or adjust the variable on plasma6.nix file.

- NOTE: plasma6.nix creates symlinks from $HOME plasma dotfiles to the current directory.

- NOTE: additional variable was added to the path that is using the username from flake.nix so you can have different profiles for different users or computers. For example, you can find on my dotfiles, that under plasma6 there are files for akunito user and for aga user. If you have imported your plasma dotfiles to /source, now you must rename or copy the directory to be called as your user: /username to match with plasma6.nix expected path to be sourced


# NixOS - home-manager source (unmutable files) into
Important ! Remember that install.sh runs on Git, so you have to commit first to get last changes on home-manager


We can source under /home directory any directory or file that we have in our GIT repo, or in any other location.

> NOTE these files will be overwritten if you reinstall home-manager as they are under /nix/store/result/.....
> If you want to keep theirs changes, you need another approach >> [[NixOS - home-manager link dotfiles to my project]]

## Source a directory
The directory might **need to contain a file at least** to don't fail when executing home-manager
### sample
```sh
  home.file.".local/share/kded6/" = { 
    source = ./. + builtins.toPath ("/" + userSettings.username + "/kded6");
    recursive = true;
  };
```
- Where `home.file.".local/share/kded6/"` represents the user directory `$HOME/.local/share/kded6/` where the file will be sourced
	- the recursive option will generate symlinks for each of the files inside the directery	![[NixOS - home-manager source (unmutable files) into-1725020129480.jpeg]]
- And `source = ./. + builtins.toPath ("/" + userSettings.username + "/kded6");`
  contains the path to our directory on our GIT repo or another location, that will be copied to `/nix/store/result/.....` and be linked
	  - these files as everything under `/nix/store/result` are **unmutable** 
	  - Note also that I use a variable `userSettings.username` that comes from my flake.nix with all the system variable that I use.
	  - Additionally we have `builtins.toPath ("text to path")` that is a nix built function to convert the type `"text"` to `path` 
	    https://nix.dev/manual/nix/2.18/language/builtins#builtins-toPath
	    This is only needed if you want to use a variable as mentioned on previous point.
		- Otherwise you can just do `source = ./username/kded6` literally / hardcoded
  
## Source a file
### sample with variable from flake.nix
```sh
home.file.".config/kwinrc".source = ./. + builtins.toPath ("/" + userSettings.username + "/kwinrc"); 
```
#### sample
```sh
home.file.".config/kwinrc".source = ./username/kwinrc;
```

# NixOS - home-manager link dotfiles to my project
## Use case
I want to link the Plasma dotfiles that contain all the settings into my project https://github.com/akunito/my_nixos
But I want these files to be mutable and if the user makes a change, I want to be able to keep these changes and uploaded to the repo when needed.

I first tried with home.file / source the files. but this make them unmutable and as soon I rebuild home-manager, the changes are lost.
Then I decided just to create symlinks

