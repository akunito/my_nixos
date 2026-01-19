# Ranger File Manager - Complete Guide

## Introduction

Ranger is a minimalistic TUI (Terminal User Interface) file manager controlled with vim keybindings, making it extremely efficient for file management tasks.

## Basic Navigation

### Movement
- `j` / `k` - Move down/up one file
- `h` / `l` - Move left (parent directory) / right (enter directory or open file)
- `gg` - Jump to top of file list
- `G` - Jump to bottom of file list
- `J` / `K` - Move down/up half a page
- `<C-F>` / `<C-B>` - Move down/up one full page
- `H` / `L` - Go back/forward in directory history
- `]` / `[` - Move to next/previous parent directory
- `}` / `{` - Traverse forward/backward through directory history

### Quick Directory Navigation
- `gh` - Go to home directory (`~`)
- `ga` - Go to `~/Archive`
- `gd` - Go to `~/Downloads`
- `gm` - Go to `~/Media`
- `go` - Go to `~/Org`
- `gp` - Go to `~/Projects`
- `gD` - Go to `~/.dotfiles`
- `ge` - Go to `/etc`
- `gv` - Go to `/var`
- `gi` - Go to `~/External`
- `gM` - Go to `/mnt`
- `gs` - Go to `/srv`
- `gP` - Go to `/tmp`
- `g/` - Go to root (`/`)

### Opening Files
- `l` or `<Enter>` - Open file or enter directory
- `i` - Display file in pager
- `E` or `F4` - Edit file
- `r` - Open with... (select application)
- `o` - Change sort order
- `z` - Toggle various settings (see Settings section)

## File Selection and Marking

### Single File Selection
- `<Space>` - Toggle mark on current file
- `t` - Toggle tag on current file
- `ut` - Remove tag from current file

### Multiple File Selection
- `v` - Mark all files in current directory (toggle)
- `uv` - Unmark all files
- `V` - Toggle visual mode (select range)
- `uV` - Toggle visual mode (reverse)

### Visual Selection Example
1. Navigate to a file
2. Press `V` to enter visual mode
3. Use `j`/`k` to extend selection
4. Press `V` again to exit visual mode
5. All files in the range are now marked

## Bulk Operations - Copy and Move

### Copying Files

**Basic Copy:**
- `yy` - Copy (yank) selected/marked files
- `ya` - Add files to copy buffer (mode=add)
- `yr` - Remove files from copy buffer (mode=remove)
- `yt` - Toggle files in copy buffer (mode=toggle)
- `uy` - Clear copy buffer (uncut)

**Copy with Range Selection:**
- `ygg` - Copy from current position to top
- `yG` - Copy from current position to bottom
- `yj` - Copy current file and next file
- `yk` - Copy current file and previous file

**Paste Operations:**
- `pp` - Paste files
- `po` - Paste with overwrite
- `pP` - Paste and append to existing files
- `pO` - Paste with overwrite and append
- `pl` - Paste as symlink (absolute)
- `pL` - Paste as symlink (relative)
- `phl` - Paste as hardlink
- `pht` - Paste hardlinked subtree

**Example: Copy Multiple Files**
```
1. Navigate to source directory
2. Press <Space> on first file to mark it
3. Use j/k to move to next file
4. Press <Space> again to mark it
5. Repeat for all files you want to copy
6. Press yy to copy all marked files
7. Navigate to destination directory
8. Press pp to paste
```

**Example: Copy All Files in Directory**
```
1. Navigate to directory
2. Press v to mark all files
3. Press yy to copy
4. Navigate to destination
5. Press pp to paste
```

**Example: Copy Range of Files**
```
1. Navigate to first file
2. Press V to enter visual mode
3. Use j to extend selection to last file
4. Press V again to exit visual mode
5. Press yy to copy
6. Navigate to destination
7. Press pp to paste
```

### Moving/Cutting Files

**Basic Cut:**
- `dd` - Cut selected/marked files
- `da` - Add files to cut buffer (mode=add)
- `dr` - Remove files from cut buffer (mode=remove)
- `dt` - Toggle files in cut buffer (mode=toggle)
- `ud` - Clear cut buffer (uncut)

**Cut with Range Selection:**
- `dgg` - Cut from current position to top
- `dG` - Cut from current position to bottom
- `dj` - Cut current file and next file
- `dk` - Cut current file and previous file

**Example: Move Multiple Files**
```
1. Mark files using <Space> or visual mode (V)
2. Press dd to cut
3. Navigate to destination
4. Press pp to paste (files are moved)
```

**Example: Move All Files Matching Pattern**
```
1. Use / to search for pattern (e.g., /\.txt$)
2. Press n to jump to next match
3. Press <Space> to mark each match
4. Or use :mark command with pattern
5. Press dd to cut
6. Navigate to destination
7. Press pp to paste
```

## Bulk Operations - Delete and Trash

### Deleting Files

- `dD` - Delete selected/marked files (permanent, no undo!)
- `dT` - Move to trash (safer, can recover)
- `F8` - Delete (console command)

**Example: Delete Multiple Files**
```
1. Mark files with <Space> or visual mode
2. Press dD to delete permanently
   OR
   Press dT to move to trash
```

**Example: Delete All Files in Directory**
```
1. Press v to mark all files
2. Press dT to move to trash (safer)
   OR
   Press dD to delete permanently
```

### Using Console Commands for Bulk Delete
- `:delete` - Delete with confirmation
- `:trash` - Move to trash with confirmation

**Example: Delete Files Matching Pattern**
```
1. Search for pattern: /\.tmp$
2. Mark all matches
3. Press dT to trash them
```

## Bulk Operations - Rename

### Renaming Files

- `cw` - Rename current file (console)
- `a` or `F2` - Rename (append mode)
- `A` - Rename with cursor at end
- `I` - Rename with cursor at beginning

**Example: Rename Multiple Files (Bulk Rename)**
```
1. Mark files you want to rename
2. Type :bulkrename
3. This opens an editor with all filenames
4. Edit the names in the editor
5. Save and close
6. Review the generated script
7. Close to execute
```

**Example: Rename with Pattern**
```
1. Mark files
2. Use :rename command in console
3. Or use :bulkrename for multiple files
```

## Bulk Operations - Permissions

### Changing Permissions

**Quick Permission Changes:**
- `=` - Open chmod console
- `+r` / `+w` / `+x` - Add read/write/execute permission
- `-r` / `-w` / `-x` - Remove read/write/execute permission
- `+u[rwx]` - Add permission for user
- `+g[rwx]` - Add permission for group
- `+o[rwx]` - Add permission for others
- `+a[rwx]` - Add permission for all

**Example: Make Multiple Files Executable**
```
1. Mark files
2. Press = to open chmod console
3. Type 755 or +x
4. Press Enter
```

**Example: Remove Write Permission from Multiple Files**
```
1. Mark files
2. Press = to open chmod console
3. Type -w
4. Press Enter
```

## Bulk Operations - Search and Filter

### Searching Files

- `/` - Search for pattern in filenames
- `n` - Jump to next match
- `N` - Jump to previous match
- `f` - Find files (console)
- `:filter` - Filter files by pattern

**Example: Mark All Files Matching Pattern**
```
1. Type /pattern to search
2. Press n to jump through matches
3. Press <Space> on each match to mark
4. Or use :mark command
```

**Example: Filter and Operate on Results**
```
1. Type :filter pattern
2. Only matching files are shown
3. Mark files you want
4. Perform operations (copy, move, delete)
5. Type :filter to clear filter
```

### Advanced Filtering

- `.d` - Filter: show only directories
- `.f` - Filter: show only files
- `.l` - Filter: show only symlinks
- `.m` - Filter: show only files matching MIME type
- `.n` - Filter: show only files matching name pattern
- `.c` - Clear all filters
- `.p` - Pop last filter from stack

**Example: Copy All Directories**
```
1. Type .d to show only directories
2. Press v to mark all
3. Press yy to copy
4. Navigate to destination
5. Press pp to paste
6. Type .c to clear filter
```

## Bulk Operations - Sorting

### Sorting Files

- `or` - Reverse current sort order
- `oz` - Sort randomly
- `os` - Sort by size (ascending)
- `oS` - Sort by size (descending)
- `ob` - Sort by basename (ascending)
- `oB` - Sort by basename (descending)
- `on` - Sort naturally (ascending)
- `oN` - Sort naturally (descending)
- `om` - Sort by modification time (ascending)
- `oM` - Sort by modification time (descending)
- `oc` - Sort by creation time (ascending)
- `oC` - Sort by creation time (descending)
- `oa` - Sort by access time (ascending)
- `oA` - Sort by access time (descending)
- `ot` - Sort by type (ascending)
- `oT` - Sort by type (descending)
- `oe` - Sort by extension (ascending)
- `oE` - Sort by extension (descending)

**Example: Find Largest Files**
```
1. Press oS to sort by size (descending)
2. Largest files are at top
3. Mark them for deletion or moving
```

## File Operations

### Creating Files and Directories

- `<Insert>` or `:touch` - Create new file
- `F7` or `:mkdir` - Create new directory

**Example: Create Multiple Directories**
```
1. Type :mkdir dir1
2. Press Enter
3. Type :mkdir dir2
4. Repeat as needed
```

### Viewing File Information

- `i` - Display file in pager
- `du` - Show disk usage of current directory
- `dU` - Show disk usage sorted by size
- `dc` - Get cumulative size of directories
- `w` - Open task view

### Yanking Paths (Copy to Clipboard)

- `yp` - Yank path of selected file(s)
- `yd` - Yank directory of selected file(s)
- `yn` - Yank name of selected file(s)
- `y.` - Yank name without extension

**Example: Copy File Paths to Clipboard**
```
1. Mark multiple files
2. Press yp to copy all paths to clipboard
3. Paste in another application
```

## Tabs

### Tab Management

- `<C-n>` or `gn` - New tab
- `<C-w>` or `gc` - Close current tab
- `<TAB>` or `gt` - Next tab
- `<S-TAB>` or `gT` - Previous tab
- `<A-Left>` / `<A-Right>` - Move tab left/right
- `<a-1>` through `<a-9>` - Jump to tab 1-9
- `uq` - Restore closed tab

**Example: Copy Files Between Tabs**
```
1. Open source directory in tab 1
2. Press <C-n> to create new tab
3. Navigate to destination in tab 2
4. Press <TAB> to switch back to tab 1
5. Mark files and press yy
6. Press <TAB> to switch to tab 2
7. Press pp to paste
```

## Settings Toggles

### Quick Settings

- `zh` or `<C-h>` - Toggle hidden files
- `zi` - Toggle image previews
- `zm` - Toggle mouse support
- `zp` - Toggle file previews
- `zP` - Toggle directory previews
- `zs` - Toggle case-insensitive sorting
- `zv` - Toggle preview script
- `zc` - Toggle collapse preview
- `zd` - Toggle directories first
- `zf` - Filter files
- `F` - Freeze file list (toggle)

## Console Commands

### Opening Console

- `:` or `;` - Open console
- `!` - Open shell in current directory
- `@` - Run shell command on selected files
- `#` - Run shell command with prompt
- `s` - Open shell console
- `cd` - Change directory (console)

### Useful Console Commands

- `:cd <path>` - Change directory
- `:find <pattern>` - Find files
- `:filter <pattern>` - Filter files
- `:mark <pattern>` - Mark files matching pattern
- `:unmark <pattern>` - Unmark files matching pattern
- `:search <pattern>` - Search for pattern
- `:shell <command>` - Run shell command
- `:rename <newname>` - Rename file
- `:delete` - Delete files
- `:trash` - Move to trash
- `:mkdir <name>` - Create directory
- `:touch <name>` - Create file
- `:chmod <mode>` - Change permissions
- `:bulkrename` - Bulk rename files
- `:help` - Show help

## Advanced Examples

### Example 1: Organize Downloads by Extension
```
1. Navigate to ~/Downloads (gd)
2. Press oE to sort by extension
3. Type .f to show only files
4. Navigate to first .pdf file
5. Press V to enter visual mode
6. Use j to select all .pdf files
7. Press yy to copy
8. Type :mkdir pdfs
9. Press Enter
10. Press l to enter pdfs directory
11. Press pp to paste
12. Press h to go back
13. Repeat for other file types
```

### Example 2: Clean Up Temporary Files
```
1. Navigate to directory
2. Type :filter \.tmp$
3. Press v to mark all
4. Press dT to move to trash
5. Type .c to clear filter
```

### Example 3: Copy Recent Files
```
1. Navigate to directory
2. Press oM to sort by modification time (newest first)
3. Use j to navigate to recent files
4. Press <Space> to mark files from last week
5. Press yy to copy
6. Navigate to backup location
7. Press pp to paste
```

### Example 4: Move Large Files to Archive
```
1. Navigate to directory
2. Press oS to sort by size (largest first)
3. Press du to see disk usage
4. Mark large files (>100MB)
5. Press dd to cut
6. Navigate to archive (ga)
7. Press pp to paste
```

### Example 5: Bulk Rename Photos
```
1. Navigate to photo directory
2. Press oM to sort by date
3. Mark all photos
4. Type :bulkrename
5. In editor, rename files systematically:
   vacation_001.jpg
   vacation_002.jpg
   etc.
6. Save and close
7. Review generated script
8. Close to execute
```

## Tips and Tricks

1. **Use Quantifiers**: Many commands support numbers, e.g., `5j` moves down 5 files, `10yy` copies 10 files from current position.

2. **Combine Operations**: You can chain operations, e.g., mark files, copy, navigate, paste, all without leaving ranger.

3. **Bookmarks**: Use `m<key>` to bookmark a directory, then `'<key>` or `` `<key>`` to jump back.

4. **History Navigation**: Use `H` and `L` to navigate directory history quickly.

5. **Visual Mode**: `V` is powerful for selecting ranges - much faster than marking individually.

6. **Filter Stack**: Use filter commands (`.d`, `.f`, etc.) to build complex filters.

7. **Tab Completion**: In console, use `<TAB>` for command and path completion.

8. **Undo Operations**: Some operations can be undone, but deletions (`dD`) are permanent!

## Key Reference Quick Sheet

### Navigation
- `j/k` - Down/Up
- `h/l` - Left/Right
- `gg/G` - Top/Bottom
- `H/L` - History back/forward

### Selection
- `<Space>` - Mark file
- `v` - Mark all
- `V` - Visual mode
- `t` - Tag file

### Operations
- `yy` - Copy
- `dd` - Cut
- `pp` - Paste
- `dD` - Delete
- `dT` - Trash
- `cw` - Rename

### Search/Filter
- `/` - Search
- `n/N` - Next/Previous match
- `:filter` - Filter files
- `.d/.f/.l` - Filter by type

### Tabs
- `<C-n>` - New tab
- `<C-w>` - Close tab
- `<TAB>` - Next tab
- `gt/gT` - Next/Previous tab

### Settings
- `zh` - Toggle hidden
- `zi` - Toggle images
- `zp` - Toggle preview

### Console
- `:` - Open console
- `!` - Shell in directory
- `@` - Shell on files

## Getting Help

- `?` - Show help
- `:help` - Detailed help
- `:dump_commands` - List all commands
- `:dump_keybindings` - List all keybindings
- `:dump_settings` - List all settings

---

**Note**: This guide covers the keybindings and commands configured in your ranger setup. For the most up-to-date information, use `:help` within ranger itself.
