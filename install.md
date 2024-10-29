---
author: Akunito
title: Install script
---

## Interactive Install Script

Read the comments in `./install.sh` for more info Basically to use the script, you have to create a copy of `flake.nix` to ie: `flake.PERSONAL.nix` or `flake.HOMELAB.nix`, and adjust the variables there. You can use as example any of `my flake.{PROFILES}.nix` 
Then you can run the script like this:

```sh
# In case you want interactive mode:
./install.sh ~/.dotfiles "HOME"
# In case you want to run silently:
./install.sh ~/.dotfiles "HOME" -s

# where $1 is the path to your ~/.dotfiles and $2 is PROFILE on flake.PROFILE.nix
```

## Note that the rest of the document is partially deprecated but some of the notes from Emmet might be still valid, use it with caution.

These are just some simple install notes for myself (in-case I have to reinstall unexpectedly). You could also use these to try out my config in a VM.

---
## Automated Install Script (Experimental)

### Install Directly From Git

I wrote a quick automated install script at [install.sh](./install.sh).
It essentially just runs [*the manual install steps*]{.spurious-link target="Manual Install Procedure"} and additionally hardens the security of the system-level (root configuration) files using [harden.sh](./harden.sh).

I\'ll eventually™ add the ability to supply arguments to this script as well.

The quickest way to install is running the install script directly from the remote git repo using `nix run`{.verbatim}, which is essentially just one of the following:

```sh
# Install from gitlab
nix run gitlab:librephoenix/nixos-config

# Or install from github
nix run github:librephoenix/nixos-config

# Or install from codeberg
nix run git+https://codeberg.org/librephoenix/nixos-config
```

This will install the dotfiles to `~/.dotfiles`{.verbatim}, but if you\'d like to install to a custom directory, just supply it as a positional argument, i.e:

```sh
# Install from gitlab
nix run gitlab:librephoenix/nixos-config -- /your/custom/directory
```

The script will ask for sudo permissions at certain points, *but you should not run the script as root*.

If the above `nix run`{.verbatim} command gives you an error, odds are you either don\'t have `git`{.verbatim} installed, or you haven\'t enabled the experimental features in your Nix config (`nix-command`{.verbatim} and `flakes`{.verbatim}). To get the command to install properly, you can first enter a shell with `git`{.verbatim} available using:

```sh
nix-shell -p git
```

and then running:

```sh
nix run --experimental-features 'nix-command flakes' gitlab:librephoenix/nixos-config
```

And if you want a single copy-paste solution:

```sh
nix-shell -p git --command "nix run --experimental-features 'nix-command flakes' gitlab:librephoenix/nixos-config"
```

This *should* still work with a custom dotfiles directory too, i.e:

```sh
nix-shell -p git --command "nix run --experimental-features 'nix-command flakes' gitlab:librephoenix/nixos-config -- /your/custom/directory"
```

At a certain point in the install script it will open `nano`{.verbatim} (or whatever your \$EDITOR is set to) and ask you to edit the `flake.nix`{.verbatim}. You can edit as much or as little of the config variables as you like, and it will continue the install after you exit the editor.

Potential Errors: I\'ve only tested it working on UEFI with the default EFI mount point of `/boot`{.verbatim}. I\'ve added experimental legacy (BIOS) boot support, but it does rely on a quick and dirty script to find the grub device. If you are testing it using some weird boot configuration for whatever reason, try modifying `bootMountPath`{.verbatim} (UEFI) or `grubDevice`{.verbatim} (legacy BIOS) in `flake.nix`{.verbatim} before install, or else it will complain about not being able to install the bootloader.

Note: If you\'re installing this to a VM, Hyprland won\'t work unless 3D acceleration is enabled.

Disclaimer: If you install my `homelab`{.verbatim} or `worklab`{.verbatim} profiles *CHANGE THE PUBLIC SSH KEYS UNLESS YOU WANT ME TO BE ABLE TO SSH INTO YOUR SERVER. YOU CAN CHANGE OR REMOVE THE SSH KEY IN THE RELEVANT CONFIGURATION.NIX*:

-   [configuration.nix](./profiles/homelab/configuration.nix) for homelab profile
-   [configuration.nix](./profiles/worklab/configuration.nix) for worklab profile

### Install From Local Git Clone

The dotfiles can be installed after cloning the repo into `~/.dotfiles`{.verbatim} using:

```sh
git clone https://gitlab.com/librephoenix/nixos-config.git ~/.dotfiles ~/.dotfiles/install.sh
```

or with a custom directory:

```sh
git clone https://gitlab.com/librephoenix/nixos-config.git /your/custom/directory /your/custom/directory/install.sh
```

If you install to a custom directory, make sure to edit the `userSettings.dotfilesDir`{.verbatim} in the [flake.nix](./flake.nix), or else my [phoenix wrapper script](./system/bin/phoenix.nix) won\'t work.

At a certain point in the install script it will open `nano`{.verbatim} (or whatever your `$EDITOR`{.verbatim} is set to) and ask you to edit the `flake.nix`{.verbatim}. You can edit as much or as little of the config variables as you like, and it will continue the install after you exit the editor.

Potential Errors: I mainly only test this on UEFI, but I\'ve added experimental legacy (BIOS) boot support. Keep in mind, it does rely on a quick and dirty script to find the grub device. If you are testing it using some weird boot configuration for whatever reason, try modifying `bootMountPath`{.verbatim} (UEFI) or `grubDevice`{.verbatim} (legacy BIOS) in `flake.nix`{.verbatim} before install, or else it will complain about not being able to install the bootloader.

Note: If you\'re installing this to a VM, Hyprland won\'t work unless 3D acceleration is enabled.

Disclaimer: If you install my `homelab`{.verbatim} or `worklab`{.verbatim} profiles *CHANGE THE PUBLIC SSH KEYS UNLESS YOU WANT ME TO BE ABLE TO SSH INTO YOUR SERVER. YOU CAN CHANGE OR REMOVE THE SSH KEY IN THE RELEVANT CONFIGURATION.NIX*:

-   [configuration.nix](./profiles/homelab/configuration.nix) for homelab profile
-   [configuration.nix](./profiles/worklab/configuration.nix) for worklab profile

### Automatic Install Script Limitations

At this time, this only works on an existing NixOS install. It also only works if the dotfiles are cloned into `~/.dotfiles`{.verbatim}. It also only works on UEFI, not on BIOS :(

Future upgrade plans:

-   [ ] Be able to install directly from NixOS iso
-   [ ] Be able to install just home-manager config to a non-NixOS Linux distro
-   [ ] Be able to detect EFI mount point for systemd-boot?
-   [x] ~~Be able to detect UEFI or BIOS and switch config as needed~~
-   [ ] ??? (open up an issue if you think there is anything else I should try to figure out)

## Manual Install Procedure

If you instead want to install this manually to see all the steps (kind of like an Arch install before the archinstall script existed), you can follow this following procedure:

### Clone Repo and Modify Configuration

Start by cloning the repo:

```sh
git clone https://gitlab.com/librephoenix/nixos-config.git ~/.dotfiles
```

Any custom directory should also work:

```sh
git clone https://gitlab.com/librephoenix/nixos-config.git /your/custom/directory
```

If you install to a custom directory, make sure to edit the `userSettings.dotfilesDir`{.verbatim} in the beginning [flake.nix](./flake.nix), or else my [phoenix wrapper script](./system/bin/phoenix.nix) won\'t work.

```nix
...
let
  ...
  # ----- USER SETTINGS ----- #
  dotfilesDir = "/your/custom/directory"; # username
  ...
```

To get the hardware configuration on a new system, either copy from `/etc/nixos/hardware-configuration.nix`{.verbatim} or run:

```sh
sudo nixos-generate-config --show-hardware-config > ~/.dotfiles/system/hardware-configuration.nix
```

Also, if you have a differently named user account than my default (`emmet`{.verbatim}), you *must* update the following lines in the let binding near the top of the [flake.nix](./flake.nix):

```nix
...
let
  ...
  # ----- USER SETTINGS ----- #
  username = "YOURUSERNAME"; # username
  name = "YOURNAME"; # name/identifier
  ...
```

There are many more config options there that you may also want to change as well.

The build will fail if you are booting from BIOS instead of UEFI, unless change some of the system settings of the flake. Change `bootMode`{.verbatim} to \"bios\" and set the `grubDevice`{.verbatim} appropriately for your system (i.e. `/dev/vda`{.verbatim} or `/dev/sda`{.verbatim}).

```nix
...
let
  # ---- SYSTEM SETTINGS ---- #
  ...
    bootMode = "bios"; # uefi or bios
    grubDevice = "/dev/vda"; # device identifier for grub; find this by running lsblk
  ...
```

Note: If you\'re installing this to a VM, Hyprland won\'t work unless 3D acceleration is enabled.

Disclaimer: If you install my `homelab`{.verbatim} or `worklab`{.verbatim} profiles *CHANGE THE PUBLIC SSH KEYS UNLESS YOU WANT ME TO BE ABLE TO SSH INTO YOUR SERVER. YOU CAN CHANGE OR REMOVE THE SSH KEY IN THE RELEVANT CONFIGURATION.NIX*:

-   [configuration.nix](./profiles/homelab/configuration.nix) for homelab profile
-   [configuration.nix](./profiles/worklab/configuration.nix) for worklab profile

### Rebuild and Switch System Config

Once the variables are set, then switch into the system configuration by
running:

```sh
sudo nixos-rebuild switch --flake ~/.dotfiles#system
```

or for your own custom directory:

```sh
sudo nixos-rebuild switch --flake /your/custom/directory#system
```

### Intall and Switch Home Manager Config

Home manager can be installed and the configuration activated with:

```sh
nix run home-manager/master -- switch --flake ~/.dotfiles#user
```

or for your own custom directory:

```sh
nix run home-manager/master -- switch --flake /your/custom/directory#user
```

## FAQ

### `home-manager switch --flake .#user`{.verbatim} Command Fails

If it fails with something to the effect of \"could not download {some image file}\" then that just means that one of my themes is having trouble downloading the background image. To conserve on space in the repo, my themes download the relevant wallpapers directly from their source, but that also means that if the link is broken, `home-manager switch`{.verbatim} fails.

I have included a script in the [themes directory](./themes) named [background-test.sh](./themes/background-test.sh) which performs a rough test on every theme background url, reporting which are broken.

If you\'re having this error, navigate to the [flake.nix](./flake.nix) and select any theme with a good background wallpaper link. As long as it is able to download the new wallpaper, it should be able to build.

### Do I have to put the configuration files in `~/.dotfiles`{.verbatim}?

No. You can put them in literally any directory you want. I just prefer to use `~/.dotfiles`{.verbatim} as a convention. If you change the directory, do keep in mind that the above scripts must be modified, replacing `~/.dotfiles`{.verbatim} with whatever directory you want to install them to. Also, you may want to modify the `dotfilesDir`{.verbatim} variable in `flake.nix`{.verbatim}.

### So I cloned these dotfiles into \~/.dotfiles, and now there are system-level files owned by my user account.. HOW IS THIS SECURE?!

If you\'re worried about someone modifying your system-level (root configuration) files as your unpriveleged user, see [harden.sh](./harden.sh).

### I installed this to a VM and when I log in, it crashes and sends me back to the login manager (SDDM)?

Enable 3D acceleration for your virtual machine. Hyprland doesn\'t work without it.

### It fails installing with some weird errors about grub or a bootloader?

It will 100% fail if you test it with a non-default boot configuration.
It might even give this error otherwise! If this is the case, try modifying `bootMountPath`{.verbatim} (UEFI) or `grubDevice`{.verbatim} (legacy BIOS) in `flake.nix`{.verbatim} before installing again.

### The install seems to work, but when I login, I\'m missing a lot of stuff (partial install)

This can happen if you run the autoinstall script on a system that already has a desktop environment, or if any other (non-Nix-store-symlink) config files are in the way of the config files generated by home-manager. In these cases, home-manager refuses to build anything, even if there\'s just one file in the way. If you try running `nix run home-manager/master -- switch --flake ~/.dotfiles#user`{.verbatim}, it should throw an error at the end with something like:

```sh
Existing file '/home/user/.gtkrc-2.0' is in the way of '/nix/store/6p3hzdbzhad8ra5j1qf4b2b3hs6as6sf-home-manager-files/.gtkrc-2.0'
Existing file '/home/user/.config/Trolltech.conf' is in the way of '/nix/store/6p3hzdbzhad8ra5j1qf4b2b3hs6as6sf-home-manager-files/.config/Trolltech.conf'
Existing file '/home/user/.config/user-dirs.conf' is in the way of '/nix/store/6p3hzdbzhad8ra5j1qf4b2b3hs6as6sf-home-manager-files/.config/user-dirs.conf'
...
```

The current solution to this is to delete or move the files mentioned so
that home-manager can evaluate. Once the files are out of the way, just
run
`nix run home-manager/master -- switch --flake ~/.dotfiles#user`{.verbatim}
again and it should work!
