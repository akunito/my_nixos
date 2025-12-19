# Picom

## Overview

This is the picom configuration. It uses [pijulius' picom](https://github.com/pijulius/picom) which has awesome animations!

![Picom Animation](./picom.gif)

## Configuration Files

There are 2 main files in this directory:

- `picom.conf` - Picom configuration
- `picom.nix` - A Nix module to import the pijulius fork of picom into the setup via the import block of home.nix

## Integration

The Picom module is integrated into the user configuration. See [User Modules Guide](../user-modules.md) for details.

## Related Documentation

- [User Modules Guide](../user-modules.md) - User-level modules overview

**Related Documentation**: See [user/wm/picom/README.md](../../../user/wm/picom/README.md) for directory-level documentation.

**Note**: The original [user/wm/picom/README.org](../../../user/wm/picom/README.org) file is preserved for historical reference.

