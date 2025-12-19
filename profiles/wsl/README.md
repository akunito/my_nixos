# WSL Profile

Trying to use a computer without Linux is hard

This is the WSL profile, which is a minimal installation used on Windows underneath WSL. This (obviously) requires [NixOS-WSL](https://github.com/nix-community/NixOS-WSL) to be installed.

## Features

Essentially just use this for:
- Emacs
- Some useful CLI apps that can't be lived without (namely ranger)
- LibreOffice, which runs strangely slow on Windows

## Technical Details

The [nixos-wsl](./nixos-wsl) directory is taken directly from [NixOS-WSL](https://github.com/nix-community/NixOS-WSL) and merely patched slightly to allow it to run with the unstable channel of nixpkgs.

## Related Documentation

- [Profiles Guide](../../docs/profiles.md) - Complete profiles documentation
- [NixOS-WSL Repository](https://github.com/nix-community/NixOS-WSL) - Original project

