---
id: user-modules.picom
summary: Picom compositor module overview and where its config and Nix module live.
tags: [picom, compositor, x11, animations, user-modules]
related_files:
  - user/wm/picom/**
  - docs/user-modules/picom.md
key_files:
  - user/wm/picom/picom.nix
  - docs/user-modules/picom.md
activation_hints:
  - If changing compositor settings, picom fork selection, or picom config files
---

# Picom

## Overview

This is the picom configuration. It uses [pijulius' picom](https://github.com/pijulius/picom) which has awesome animations!

![Picom Animation](./picom.gif)

## Configuration Files

There are 2 main files in this directory:

- `picom.conf` - Picom configuration
- `picom.nix` - A Nix module to import the pijulius fork of picom into the setup via the import block of home.nix

## Integration

The Picom module is integrated into the user configuration. See [User Modules Guide](README.md) for details.

## Related Documentation

- [User Modules Guide](README.md) - User-level modules overview

**Related Documentation**: See [user/wm/picom/README.md](../../../user/wm/picom/README.md) for directory-level documentation.

**Note**: The original [user/wm/picom/README.org](../../../user/wm/picom/README.org) file is preserved for historical reference.

