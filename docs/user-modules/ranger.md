# Ranger File Manager

## What is Ranger?

[Ranger](https://ranger.github.io/) is a minimalistic TUI file manager controlled with vim keybindings (making it extremely efficient).

![Ranger Screenshot](https://raw.githubusercontent.com/librephoenix/nixos-config-screenshots/main/app/ranger.png)

If you've never tried a terminal file manager, it's worth trying. Here's a quick overview of how to work with it:

## Keybindings

- `j` and `k` - Move up and down
- `l` - Move into a directory or open file at point
- `h` - Move up a directory
- `g g` - Move to top
- `G` - Move to bottom
- `SPC` - Mark a file
- `y y` - Copy (yank) file(s)
- `d d` - Cut file(s)
- `p p` - Paste file(s)
- `d T` - Trash file(s)
- `d D` - Delete a file (no undo!)
- `!` - Run a shell command in current directory
- `@` - Run a shell command on file(s)
- `Ctrl-r` - Refresh view

Just like in vim, commands can be given by typing a colon `:` (semicolons `;` also work in ranger!) and typing the command, i.e `:rename newfilename`.

## Configuration

Ranger configuration is located in `user/app/ranger/` and includes:

- Custom color schemes
- File operation commands
- Preview support
- Custom keybindings

## Integration

The Ranger module is integrated into the user configuration. See [User Modules Guide](../user-modules.md) for details.

## Related Documentation

- [User Modules Guide](../user-modules.md) - User-level modules overview

