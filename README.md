---
author: Akunito
title: NixOS Config (forked from Librephoenix)
---

## Table of Contents
- [Background](#background)
- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Maintenance](#maintenance)
- [Usage](#usage)
- [Original Document from Librephoenix](#original-document-from-librephoenix)

# Background
This configuration started as a fork of Librephoenix's NixOS setup, enhanced with additional features for different use cases including homelab servers, family laptops, and development machines.

# Features
I have implemented my own features, however most of the original code is still there, but some features are partially commented. NOTE: All original documentation from Librephoenix is below on this document, after my list of changes.
- Plasma 6 desktop environment
- SSH server for opening LUKS remotely
- Automated system maintenance
- Docker container management
- QEMU virtualization support
- Network bridge configuration
- Printer support
- And more...

# Installation
[Install document](./install.md)

# Configuration
### Flake.nix management for different computers/profiles
I added more variables into flake.nix files to allow a more dynamic flake.nix management.
I have added more variables that allows for example:
-   Enable or Disable Docker or Virtualization by setting true or false.
-   Set your SSH authorizedKeys only on flake.nix, and will be inherited on the rest of .nix modules or files.
-   Enable or Disable SSH on BOOT by setting true or false.
This allows you to set faster many of the features for a different computer, without modifying any other file, but only flake.nix, making much easier to manage different computers and keeping updated each of theirs local repositories. You can find different backups as examples of `flake.nix` like `flake.HOMELAB.nix` or `flake.WORK.nix`

# Maintenance
To automate and make easier the maintenance of System, User and Home-Manager generations
[[https://github.com/akunito/my_nixos/blob/main/maintenance.sh]]
The script will be called automatically by install.sh or upgrade.sh as well.
If you run it directly, it will show a menu with all the options.
In case it runs silently -s, it will perform all the actions as the 1st option in the menu.

# Usage
## AutoUpgrade system
I could not find the way to use the official AutoUpgrade with my NixOS config. If you know how to do it, please let me know. As work around, I run a script by SSH to update my NixOS computers. You can find the function `update_nixos()` in [myScripts repo](https://github.com/akunito/myScripts/blob/main/MACOS/menu_functions.sh) repository. I call the function from [menuUpdateSystem.sh](https://github.com/akunito/myScripts/blob/main/MACOS/menu_Update_System.sh) script. Which is an interactive menu and you can implement as well, using the repo as example. The main menu is called menu.sh

## Docker containers
In case you have some services running by Docker, and you switch your system to a new version, you will have issues to boot the system, as NixOS pick up the Overlay filesystems to boot with the system, and this is breaking it. The install.sh and upgrade.sh scripts will prevent this now by stoping the docker containers and informing you about. More about the issue [here](https://discourse.nixos.org/t/docker-switch-overlay-overlay2-fs-lead-to-emergency-console/29217/4)

## SSH Server to send the passphrase and Open your LUKS encrypted disks.
Librephoenix has a homeLab repository where he explains the different options we have for encrypting our data. However he avoided the full encryption of the system because the inconvinience of implementing it on a server where if you restart the computer you cannot set the passphrase when you are out of home. However I have implemented this by setting a SSH server on boot, where it is possible to connect and set the passphrase to open all your LUKS devices. Additionally you can combine this method with the method from Librephoenix, what will increase even more the security, I think. Check more about on his repository.

## Additional/secondary LUKS devices
On [drives.nix](./system/hardware/drives.md) you can find instructions how to add additional LUKS devices to be opened automatically on boot.

## Plasma 6 implemented
Currently I\'m not using Hyprland as I\'m using MacOS, by the moment, at least until Asahi Linux releases on M3 CPUs. Then maybe I will try to use NixOS on my MacBook. That\'s why I switched to Plasma, mostly to reduce the maintenance time. Plasma just works out of the box with simple and advances features. Everyday I have to deal with different computers on my work or studies or projects, etc. This includes Windows, Linux and MacOS. That got me very annoyed by shortcuts and keys, when switching between them I was constantly mixing them. So I developed a kind of framework that allows me to use the same shotcuts on all my computers. (Additionally I can use Caps Lock as a Hyper key for all global shortcuts like navigate desks) Plasma allows to do this quite easily, if you combine it with a QMK or VIA keyboard. You can find that project on [Keyboard Framework respository](https://github.com/akunito/SpinachKeyboardFramework) in case you are interested. More info on [Plasma 6 Readme](./user/wm/plasma6/readme.md)
## Plasma configuration files are integrated on this project as well. There are few scripts
to integrate them, you can check more on the [Plasma 6 Readme](./user/wm/plasma6/readme.md), where it\'s explained deeper.

## Virtualization QEMU server & remote.
I managed to use this and connect remotely from MacOS to use virt-manager on the Mac, but with the VM running totally on the NixOS server.

-   Note: virt-manager has permission issues if you set your machines or ISOs on a directory under /home
-   Note: if you want to do this from your MacBook, instructions on the next:

## Virt-manager from MacOS to Linux
-   [Virt-manager for MacOS Repository](https://github.com/jeffreywildman/homebrew-virt-manager)
-   [How to install it](https://gist.github.com/anamorph/3af11f2bd54af54a45c8b3bdafcc9939)
-   Find my summary here as well:
```zsh
# Install required packages
brew tap jeffreywildman/homebrew-virt-manager
brew install py2cairo virt-viewer virt-manager

# Install X11 server
brew install --cask xquartz

# Launch virt-manager
virt-manager --no-fork
```

## Firewall, iptables rules
I\'m currently not using iptables rules, but in case you do, the `install.sh` script will ask you to clean the rules when you are installing the system. I think if you don\'t clean them before installing, they will duplicate or make some mess.

## To set network bridges for Virsh/VMs
You can find a tutorial on [NixOS wiki Libvirt](https://nixos.wiki/wiki/Libvirt) And a example here:
```sh
# go to the directory where you want to store these files
cd /mnt/DATA_4TB/Syncthing/git_repos/myProjects/homeLab      

# create a file 
touch networking_nm-bridge.xml

# with this content
<network>
  <name>nm-bridge</name>
  <forward mode='bridge'/>
  <bridge name='nm-bridge'/>
</network>

# Add and enable the bridge interface
# you might need to use sudo for some of the next commands
virsh net-define network_nm-bridge.xml
virsh net-start nm-bridge
sudo ip link add nm-bridge type bridge
sudo ip address ad dev nm-bridge 192.168.0.0/24
sudo ip link set dev nm-bridge up

# if you need to remove a wrong ip address use this
ip address del 10.25.0.1/24 dev nm-bridge
```

## Printer Brother Laser
Added driver for Brother Laser printers. Added some comments how to setup. 
TODO: Implement sharing printer by CAPS on network. I started but didn\'t finish it.

## Kernel modules
Additional information about kernel modules is in [kernelModules Document](./kernelModules.md) that explains the kernel modules for CPU Power Management



---



# original-document-from-librephoenix
## The notes before are keeped as they might be still valid.

## What is this repository?
These are my dotfiles (configuration files) for my NixOS setup(s).

## My Themes
[Stylix](https://github.com/danth/stylix#readme) (and [base16.nix](https://github.com/SenchoPens/base16.nix#readme), of course) is amazing, allowing you to theme your entire system with base16-themes.

Using this I have [55+ themes](./themes) (I add more sometimes) I can switch between on-the-fly. Visit the [themes directory](./themes) for more info and screenshots!

## Install
I wrote some reinstall notes for myself [here (install.md)](./install.md).

TLDR: You should be able to install my dotfiles to a fresh NixOS system with the following experimental script:

```nix
nix-shell -p git --command "nix run --experimental-features 'nix-command flakes' gitlab:librephoenix/nixos-config"
```

Disclaimer: Ultimately, I can\'t gaurantee this will work for anyone other than myself, so *use this at your own discretion*. Also my dotfiles are *highly* opinionated, which you will discover immediately if you try them out.

Potential Errors: I\'ve only tested it working on UEFI with the default EFI mount point of `/boot`{.verbatim}. I\'ve added experimental legacy (BIOS) boot support, but it does rely on a quick and dirty script to find the grub device. If you are testing it using some weird boot configuration for whatever reason, try modifying `bootMountPath`{.verbatim} (UEFI) or `grubDevice`{.verbatim} (legacy BIOS) in `flake.nix`{.verbatim} before install, or else it will complain about not being able to install the bootloader.

Note: If you\'re installing this to a VM, Hyprland won\'t work unless 3D acceleration is enabled.

Security Disclaimer: If you install or copy my `homelab`{.verbatim} or `worklab`{.verbatim} profiles, *CHANGE THE PUBLIC SSH KEYS UNLESS YOU WANT ME TO BE ABLE TO SSH INTO YOUR SERVER. YOU CAN CHANGE OR REMOVE THE SSH KEY IN THE RELEVANT CONFIGURATION.NIX*:

-   [configuration.nix](./profiles/homelab/configuration.nix) for homelab profile
-   [configuration.nix](./profiles/worklab/configuration.nix) for worklab profile

## Modules
Separate Nix files can be imported as modules using an import block:

```nix
imports = [ ./import1.nix
            ./import2.nix
            ...
          ];
```

This conveniently allows configurations to be (\*cough cough) *modular* (ba dum, tssss).

I have my modules separated into two groups:

-   System-level - stored in the [system directory](./system)
    -   System-level modules are imported into configuration.nix, which is what is sourced into [my flake (flake.nix)](./flake.nix)
-   User-level - stored in the [user directory](./user) (managed by home-manager)
    -   User-level modules are imported into home.nix, which is also sourced into [my flake (flake.nix)](./flake.nix)

More detailed information on these specific modules are in the [system directory](./system) and [user directory](./user) respectively.

## Patches
In some cases, since I use `nixpgs-unstable`{.verbatim}, I must patch nixpkgs. This can be done inside of a flake via:

```nix
nixpkgs-patched = (import nixpkgs { inherit system; }).applyPatches {
  name = "nixpkgs-patched";
  src = nixpkgs;
  patches = [ ./example-patch.nix ];
};

# configure pkgs
pkgs = import nixpkgs-patched { inherit system; };

# configure lib
lib = nixpkgs.lib;
```

Patches can either be local or remote, so you can even import unmerged pull requests by using `fetchpatch`{.verbatim} and the raw patch url, i.e: <https://github.com/NixOS/nixpkgs/pull/example.patch>.

I currently curate patches local to this repo in the [patches](./patches) directory.

## Profiles
I separate my configurations into [profiles](./profiles) (essentially system templates), i.e:

-   [Personal](./profiles/personal) - What I would run on a personal laptop/desktop
-   [Work](./profiles/work) - What I would run on a work laptop/desktop (if they let me bring my own OS :P)
-   [Homelab](./profiles/homelab) - What I would run on a server or homelab
-   [WSL](./profiles/wsl) - What I would run underneath Windows Subystem for Linux

My profile can be conveniently selected in [my flake.nix](./flake.nix) by setting the `profile`{.verbatim} variable.

More detailed information on these profiles is in the [profiles directory](./profiles).

## Nix Wrapper Script
Some Nix commands are confusing, really long to type out, or require me to be in the directory with my dotfiles. To solve this, I wrote a [wrapper script called phoenix](./system/bin/phoenix.nix), which calls various scripts in the root of this directory.

TLDR:

-   `phoenix sync`{.verbatim} - Synchronize system and home-manager state with config files (essentially `nixos-rebuild switch`{.verbatim} + `home-manager switch`{.verbatim})
    -   `phoenix sync system`{.verbatim} - Only synchronize system state (essentially `nixos-rebuild switch`{.verbatim})
    -   `phoenix sync user`{.verbatim} - Only synchronize home-manager state (essentially `home-manager switch`{.verbatim})
-   `phoenix update`{.verbatim} - Update all flake inputs without synchronizing system and home-manager states
-   `phoenix upgrade`{.verbatim} - Update flake.lock and synchronize system and home-manager states (`phoenix update`{.verbatim} +     `phoenix sync`{.verbatim})
-   `phoenix refresh`{.verbatim} - Call synchronization posthooks (mainly to refresh stylix and some dependent daemons)
-   `phoenix pull`{.verbatim} - Pull changes from upstream git and attempt to merge local changes (I use this to update systems other than my main system)
-   `phoenix harden`{.verbatim} - Ensure that all \"system-level\" files cannot be edited by an unprivileged user
-   `phoenix soften`{.verbatim} - Relax permissions so all dotfiles can be edited by a normal user (use temporarily for git or other operations)
-   `phoenix gc`{.verbatim} - Garbage collect the system and user nix stores
    -   `phoenix gc full`{.verbatim} - Delete everything not currently in use
    -   `phoenix gc 15d`{.verbatim} - Delete everything older than 15 days
    -   `phoenix gc 30d`{.verbatim} - Delete everything older than 30 days
    -   `phoenix gc Xd`{.verbatim} - Delete everything older than X days

