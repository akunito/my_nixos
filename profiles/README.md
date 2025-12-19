# System Profiles

This directory contains various system profiles which can easily be set in [flake.nix](../flake.nix) by setting the `profile` variable. Each profile directory contains a `configuration.nix` for system-level configuration and a `home.nix` for user-level configuration. Setting the `profile` variable in [my flake](../flake.nix) will automatically source the correct `configuration.nix` and `home.nix`.

Current profiles I have available are:

- [Personal](./personal) - What I would run on a personal laptop/desktop*
- [Work](./work) - What I would run on my work laptop/desktop*
- [Homelab](./homelab) - What I would run on a server or homelab*
- [Worklab](./worklab) - My homelab config with my work SSH keys preinstalled*
- [WSL](./wsl) - Windows Subsystem for Linux (uses [NixOS-WSL](https://github.com/nix-community/NixOS-WSL))
- [Nix on Droid](./nix-on-droid) - So that I can run Emacs on my phone (uses [nix-on-droid](https://github.com/nix-community/nix-on-droid))

*My [personal](./personal) and [work](./work) profiles are actually functionally identical (the [work](./work) profile is actually imported into the [personal](./personal) profile)! The only difference between them is that my [personal](./personal) profile has a few extra things like gaming and social apps.

*My [homelab](./homelab) and [worklab](./worklab) profiles are similarly functionally identical (they both utilize the [base.nix](./homelab/base.nix) file)! The only difference is that they have different preinstalled SSH keys.

## Related Documentation

For comprehensive documentation, see [docs/profiles.md](../docs/profiles.md).

**Note**: The original [README.org](./README.org) file is preserved for historical reference.

