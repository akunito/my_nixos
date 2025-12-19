# Patches

I never thought I'd have to do this, but here we are.

Since I use `nixpkgs-unstable` (I am an Arch user by heart), there are some cases where certain packages will break or fail to build (usually due to my extremely customized, non-standard system).

With Nix, I *could* just rollback everything and wait to update until an upstream patch fixes things, but if it's a quick fix, I'd rather just patch it in immediately so that everything else can stay up to date.

## List of Patches

Here is a list of patches in this directory, along with a more detailed description of why it's necessary:

| Patch | Reason |
|-------|--------|
| [emacs-no-version-check.patch](./emacs-no-version-check.patch) | [35ccb9d](https://github.com/NixOS/nixpkgs/commit/35ccb9db3f4f0872f05d175cf53d0e1f87ff09ea) breaks my nix-doom-emacs install by preventing home-manager from building. This patch undoes this commit. |

## Related Documentation

For comprehensive documentation, see [docs/patches.md](../docs/patches.md).

**Note**: The original [README.org](./README.org) file is preserved for historical reference.

