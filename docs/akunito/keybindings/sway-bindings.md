---
id: keybindings.sway-bindings
summary: Generated table of every binding on DESK grouped by category — sway-apps shortcuts (editable), nix-owned sway keys, tmux binds and kitty maps. Regenerate with `sway-apps shortcuts doc --write docs/akunito/keybindings/sway-bindings.md`.
tags: [sway, tmux, kitty, keybindings, sway-apps, generated]
---

# Bindings (generated 2026-09-07 on DESK)

Owner `sway-apps` = editable in the GUI (Hyper+Shift+n → Shortcuts) or `sway-apps shortcuts`; `nix` / `tmux (nix)` / `kitty (nix)` = read-only, defined in nix (take a key over with a shortcut marked *override*).

## Apps

| Keys | Name | Command | Owner |
|---|---|---|---|
| `Hyper+a` | Bluetooth manager | `exec ~/.config/sway/scripts/app-toggle.sh .blueman-manager-wrapped blueman-manager` | sway-apps |
| `Hyper+b` | Bottles | `exec ~/.config/sway/scripts/app-toggle.sh com.usebottles.bottles bottles` | sway-apps |
| `Hyper+c` | VS Code | `exec ~/.config/sway/scripts/app-toggle.sh code code --enable-features=UseOzonePlatform,Way` | sway-apps |
| `Hyper+d` | Obsidian | `exec ~/.config/sway/scripts/app-toggle.sh md.Obsidian obsidian --no-sandbox --ozone-platfo` | sway-apps |
| `Hyper+e` | Dolphin | `exec ~/.config/sway/scripts/app-toggle.sh org.kde.dolphin dolphin` | sway-apps |
| `Hyper+g` | Chromium | `exec ~/.config/sway/scripts/app-toggle.sh chromium-browser chromium` | sway-apps |
| `Hyper+l` | Telegram | `exec ~/.config/sway/scripts/app-toggle.sh org.telegram.desktop Telegram` | sway-apps |
| `Hyper+m` | Mission Center | `exec ~/.config/sway/scripts/app-toggle.sh io.missioncenter.MissionCenter missioncenter` | sway-apps |
| `Hyper+n` | nwg-look | `exec ~/.config/sway/scripts/app-toggle.sh nwg-look nwg-look` | sway-apps |
| `Hyper+o` | Element | `exec ~/.config/sway/scripts/app-toggle.sh 'title:^Element' element-desktop --password-stor` | sway-apps |
| `Hyper+p` | Bitwarden | `exec ~/.config/sway/scripts/app-toggle.sh Bitwarden bitwarden` | sway-apps |
| `Hyper+r` | Alacritty | `exec ~/.config/sway/scripts/app-toggle.sh Alacritty alacritty` | sway-apps |
| `Hyper+s` | Control Panel | `exec ~/.config/sway/scripts/app-toggle.sh control-panel control-panel` | sway-apps |
| `Hyper+Shift+a` | Pavucontrol | `exec ~/.config/sway/scripts/app-toggle.sh org.pulseaudio.pavucontrol pavucontrol` | sway-apps |
| `Hyper+Shift+e` | Ranger (kitty) | `exec ~/.config/sway/scripts/app-toggle.sh kitty-ranger kitty --class kitty-ranger ranger` | sway-apps |
| `Hyper+Shift+t` | Trayscale | `exec ~/.config/sway/scripts/app-toggle.sh dev.deedles.Trayscale trayscale` | sway-apps |
| `Hyper+t` | Kitty | `exec ~/.config/sway/scripts/app-toggle.sh kitty kitty` | sway-apps |
| `Hyper+u` | DBeaver | `exec ~/.config/sway/scripts/app-toggle.sh io.dbeaver.DBeaverCommunity dbeaver` | sway-apps |
| `Hyper+v` | Vivaldi | `exec ~/.config/sway/scripts/app-toggle.sh vivaldi-stable vivaldi` | sway-apps |
| `Hyper+x` | Calculator | `exec ~/.config/sway/scripts/app-toggle.sh org.gnome.Calculator gnome-calculator` | sway-apps |
| `Hyper+y` | Spotify | `exec ~/.config/sway/scripts/app-toggle.sh spotify spotify --enable-features=UseOzonePlatfo` | sway-apps |
| `Hyper+z` | Zen Browser | `exec ~/.config/sway/scripts/app-toggle.sh zen-beta zen-beta` | sway-apps |

## Gaming

| Keys | Name | Command | Owner |
|---|---|---|---|
| `Hyper+F9` | Gamescope: force fullscreen | `exec swaymsg '[app_id=gamescope] fullscreen enable' 2>/dev/null; swaymsg '[class=gamescope` | sway-apps |

## Windows

| Keys | Name | Command | Owner |
|---|---|---|---|
| `Down` |  | `resize grow height 10 px` | nix |
| `h` |  | `resize shrink width 10 px` | nix |
| `Hyper+Down` |  | `focus output down` | nix |
| `Hyper+Escape` |  | `kill` | nix |
| `Hyper+f` |  | `fullscreen toggle` | nix |
| `Hyper+greater` |  | `focus up` | nix |
| `Hyper+h` |  | `focus left` | nix |
| `Hyper+j` |  | `focus down` | nix |
| `Hyper+k` |  | `focus up` | nix |
| `Hyper+Left` |  | `focus output left` | nix |
| `Hyper+less` |  | `focus down` | nix |
| `Hyper+minus` |  | `scratchpad show` | nix |
| `Hyper+question` |  | `focus right` | nix |
| `Hyper+Right` |  | `focus output right` | nix |
| `Hyper+Shift+comma` |  | `focus left` | nix |
| `Hyper+Shift+f` |  | `floating toggle` | nix |
| `Hyper+Shift+g` |  | `fullscreen toggle` | nix |
| `Hyper+Shift+i` |  | `resize grow height 5 ppt` | nix |
| `Hyper+Shift+Left` |  | `move container to output left` | nix |
| `Hyper+Shift+minus` |  | `move scratchpad` | nix |
| `Hyper+Shift+o` |  | `resize shrink height 5 ppt` | nix |
| `Hyper+Shift+p` |  | `resize grow width 5 ppt` | nix |
| `Hyper+Shift+Right` |  | `move container to output right` | nix |
| `Hyper+Shift+s` |  | `sticky toggle` | nix |
| `Hyper+Shift+space` |  | `floating toggle` | nix |
| `Hyper+Shift+u` |  | `resize shrink width 5 ppt` | nix |
| `Hyper+Up` |  | `focus output up` | nix |
| `j` |  | `resize grow height 10 px` | nix |
| `k` |  | `resize shrink height 10 px` | nix |
| `l` |  | `resize grow width 10 px` | nix |
| `Left` |  | `resize shrink width 10 px` | nix |
| `Right` |  | `resize grow width 10 px` | nix |
| `Up` |  | `resize shrink height 10 px` | nix |

## Workspaces

| Keys | Name | Command | Owner |
|---|---|---|---|
| `Hyper+0` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome focus 10` | nix |
| `Hyper+1` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome focus 1` | nix |
| `Hyper+2` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome focus 2` | nix |
| `Hyper+3` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome focus 3` | nix |
| `Hyper+4` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome focus 4` | nix |
| `Hyper+5` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome focus 5` | nix |
| `Hyper+6` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome focus 6` | nix |
| `Hyper+7` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome focus 7` | nix |
| `Hyper+8` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome focus 8` | nix |
| `Hyper+9` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome focus 9` | nix |
| `Hyper+q` |  | `exec /home/akunito/.config/sway/scripts/workspace-nav-prev.sh` | nix |
| `Hyper+Shift+0` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome move 10` | nix |
| `Hyper+Shift+1` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome move 1` | nix |
| `Hyper+Shift+2` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome move 2` | nix |
| `Hyper+Shift+3` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome move 3` | nix |
| `Hyper+Shift+4` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome move 4` | nix |
| `Hyper+Shift+5` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome move 5` | nix |
| `Hyper+Shift+6` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome move 6` | nix |
| `Hyper+Shift+7` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome move 7` | nix |
| `Hyper+Shift+8` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome move 8` | nix |
| `Hyper+Shift+9` |  | `exec /nix/store/bw3ja4v062hplyf0a4mwp5j7y6mmwnxg-swaysome-2.3.2/bin/swaysome move 9` | nix |
| `Hyper+Shift+q` |  | `exec /home/akunito/.config/sway/scripts/workspace-move-prev.sh` | nix |
| `Hyper+Shift+w` |  | `exec /home/akunito/.config/sway/scripts/workspace-move-next.sh` | nix |
| `Hyper+w` |  | `exec /home/akunito/.config/sway/scripts/workspace-nav-next.sh` | nix |
| `Super+Tab` |  | `workspace back_and_forth` | nix |

## Media

| Keys | Name | Command | Owner |
|---|---|---|---|
| `XF86AudioLowerVolume` |  | `exec /nix/store/ppkdph2v0fj2iry188qbzgrkhksg7zmx-swayosd-0.2.1/bin/swayosd-client --output` | nix |
| `XF86AudioMicMute` |  | `exec /nix/store/ppkdph2v0fj2iry188qbzgrkhksg7zmx-swayosd-0.2.1/bin/swayosd-client --input-` | nix |
| `XF86AudioMute` |  | `exec /nix/store/ppkdph2v0fj2iry188qbzgrkhksg7zmx-swayosd-0.2.1/bin/swayosd-client --output` | nix |
| `XF86AudioNext` |  | `exec /nix/store/hilkim3q8xdnk82g3598vy90v65hg8cm-playerctl-2.4.1/bin/playerctl next` | nix |
| `XF86AudioPlay` |  | `exec /nix/store/hilkim3q8xdnk82g3598vy90v65hg8cm-playerctl-2.4.1/bin/playerctl play-pause` | nix |
| `XF86AudioPrev` |  | `exec /nix/store/hilkim3q8xdnk82g3598vy90v65hg8cm-playerctl-2.4.1/bin/playerctl previous` | nix |
| `XF86AudioRaiseVolume` |  | `exec /nix/store/ppkdph2v0fj2iry188qbzgrkhksg7zmx-swayosd-0.2.1/bin/swayosd-client --output` | nix |
| `XF86AudioStop` |  | `exec /nix/store/hilkim3q8xdnk82g3598vy90v65hg8cm-playerctl-2.4.1/bin/playerctl stop` | nix |
| `XF86MonBrightnessDown` |  | `exec /nix/store/ppkdph2v0fj2iry188qbzgrkhksg7zmx-swayosd-0.2.1/bin/swayosd-client --bright` | nix |
| `XF86MonBrightnessUp` |  | `exec /nix/store/ppkdph2v0fj2iry188qbzgrkhksg7zmx-swayosd-0.2.1/bin/swayosd-client --bright` | nix |

## Screenshots

| Keys | Name | Command | Owner |
|---|---|---|---|
| `Ctrl+Alt+c` |  | `exec sh -c 'cat /tmp/last-screenshot-path 2>/dev/null \| /nix/store/awajqzf42jn3wfvbdlsv9p` | nix |
| `Hyper+Shift+c` |  | `exec /home/akunito/.config/sway/scripts/screenshot.sh area` | nix |
| `Hyper+Shift+x` |  | `exec /home/akunito/.config/sway/scripts/screenshot.sh full` | nix |
| `Print` |  | `exec /home/akunito/.config/sway/scripts/screenshot.sh area` | nix |
| `Shift+Print` |  | `exec /home/akunito/.config/sway/scripts/screenshot.sh clipboard` | nix |

## System

| Keys | Name | Command | Owner |
|---|---|---|---|
| `Escape` |  | `mode default` | nix |
| `Hyper+colon` |  | `exec /home/akunito/.config/sway/scripts/window-move.sh right` | nix |
| `Hyper+F5` |  | `exec /nix/store/n8dhhs93wxlhpl7j32ja4yg7y3sd8g5f-sway-refresh-wallpaper` | nix |
| `Hyper+grave` |  | `exec /home/akunito/.nix-profile/bin/sway-apps gui --section monitors` | nix |
| `Hyper+period` |  | `exec rofi -show emoji` | nix |
| `Hyper+Return` |  | `exec /nix/store/cr4h8m35wzmg3j2v739axb6mwagdm68b-keyboard-layout-switch/bin/keyboard-layou` | nix |
| `Hyper+Shift+b` |  | `exec waypaper` | nix |
| `Hyper+Shift+BackSpace` |  | `exec rofi -show power -show-icons` | nix |
| `Hyper+Shift+d` |  | `exec nwg-displays` | nix |
| `Hyper+Shift+End` |  | `exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit Sway` | nix |
| `Hyper+Shift+h` |  | `exec /home/akunito/.config/sway/scripts/waybar-toggle.sh` | nix |
| `Hyper+Shift+j` |  | `exec /home/akunito/.config/sway/scripts/window-move.sh left` | nix |
| `Hyper+Shift+k` |  | `exec /home/akunito/.config/sway/scripts/window-move.sh down` | nix |
| `Hyper+Shift+l` |  | `exec /home/akunito/.config/sway/scripts/window-move.sh up` | nix |
| `Hyper+Shift+n` |  | `exec /home/akunito/.nix-profile/bin/sway-apps` | nix |
| `Hyper+Shift+r` |  | `reload` | nix |
| `Hyper+Shift+Return` |  | `exec /home/akunito/.nix-profile/bin/desk-startup-apps-launcher` | nix |
| `Hyper+Shift+v` |  | `exec sh -c '/nix/store/z7lir4nmf5iw8h21sxqjx85nsdj3vq2j-cliphist-0.7.0/bin/cliphist list \` | nix |
| `Hyper+slash` |  | `exec rofi -show filebrowser` | nix |
| `Hyper+space` |  | `exec rofi -show combi -show-icons` | nix |
| `Hyper+Tab` |  | `exec /home/akunito/.config/sway/scripts/window-overview-grouped.sh` | nix |
| `Hyper+XF86AudioMute` |  | `exec /home/akunito/.config/sway/scripts/idle-inhibit-toggle.sh` | nix |
| `Return` |  | `mode default` | nix |
| `Super+l` |  | `exec /nix/store/lk18ikzwg50822gq10szs31218w43f6y-swaylock-with-grace/bin/swaylock-with-gra` | nix |
| `Super+v` |  | `exec voxtype record start` | nix |
| `Super+v` |  | `exec voxtype record stop` | nix |

## Terminal

| Keys | Name | Command | Owner |
|---|---|---|---|
| `C-Down` | Scroll down | `copy-mode \; send-keys -X scroll-down` | sway-apps |
| `C-M-[` | Copy mode (fast) | `copy-mode` | sway-apps |
| `C-M-]` | Paste (fast) | `paste-buffer` | sway-apps |
| `C-M-d` | Scroll up (copy mode) | `copy-mode` | sway-apps |
| `C-M-e` | Split vertical (fast) | `split-window -h -c "#{pane_current_path}"` | sway-apps |
| `C-M-p` | Copycat search | `copy-mode \; send-keys /` | sway-apps |
| `C-M-q` | Previous window (fast) | `previous-window` | sway-apps |
| `C-M-r` | Split horizontal (fast) | `split-window -v -c "#{pane_current_path}"` | sway-apps |
| `C-M-s` | Scroll page up | `copy-mode -u` | sway-apps |
| `C-M-t` | New window (fast) | `new-window -c "#{pane_current_path}"` | sway-apps |
| `C-M-w` | Next window (fast) | `next-window` | sway-apps |
| `C-M-x` | Close pane (fast) | `kill-pane` | sway-apps |
| `C-M-y` | Rename window (fast) | `command-prompt -I "#W" "rename-window '%%'"` | sway-apps |
| `C-M-z` | Close window (fast) | `kill-window` | sway-apps |
| `C-Up` | Scroll up | `copy-mode \; send-keys -X scroll-up` | sway-apps |
| `Ctrl+O, 2` | Rename window | `command-prompt -I "#W" "rename-window '%%'"` | sway-apps |
| `Ctrl+O, [` | Copy mode | `copy-mode` | sway-apps |
| `Ctrl+O, \;` | Pane right | `select-pane -R` | sway-apps |
| `Ctrl+O, ]` | Paste | `paste-buffer` | sway-apps |
| `Ctrl+O, e` | Split vertical | `split-window -h -c "#{pane_current_path}"` | sway-apps |
| `Ctrl+O, j` | Pane left | `select-pane -L` | sway-apps |
| `Ctrl+O, k` | Pane down | `select-pane -D` | sway-apps |
| `Ctrl+O, l` | Pane up | `select-pane -U` | sway-apps |
| `Ctrl+O, q` | Previous window | `previous-window` | sway-apps |
| `Ctrl+O, r` | Split horizontal | `split-window -v -c "#{pane_current_path}"` | sway-apps |
| `Ctrl+O, t` | New window | `new-window -c "#{pane_current_path}"` | sway-apps |
| `Ctrl+O, w` | Next window | `next-window` | sway-apps |
| `Ctrl+O, x` | Close pane | `kill-pane` | sway-apps |
| `Ctrl+O, z` | Close window | `kill-window` | sway-apps |
| `[copy] C-Down` |  | `send-keys -X scroll-down` | tmux (nix) |
| `[copy] C-Up` |  | `send-keys -X scroll-up` | tmux (nix) |
| `[copy] MouseDragEnd1Pane` |  | `send-keys -X copy-pipe-and-cancel "/nix/store/awajqzf42jn3wfvbdlsv9pxfmz7fzd27-wl-clipboar` | tmux (nix) |
| `[copy] r` |  | `send-keys -X rectangle-toggle` | tmux (nix) |
| `[copy] v` |  | `send-keys -X begin-selection` | tmux (nix) |
| `[copy] y` |  | `send-keys -X copy-pipe-and-cancel "/nix/store/awajqzf42jn3wfvbdlsv9pxfmz7fzd27-wl-clipboar` | tmux (nix) |
| `C-M-\;` |  | `select-pane -R` | tmux (nix) |
| `C-M-a` |  | `run-shell "/nix/store/5zk9dkk31vjg4c27179asazs4wr9xpql-ssh-smart-tmux/bin/ssh-smart-tmux"` | tmux (nix) |
| `C-M-f` |  | `select-pane -L` | tmux (nix) |
| `C-M-g` |  | `select-pane -U` | tmux (nix) |
| `C-M-H` |  | `display-menu -T "#[align=centre fg=#ae95c7]Fast Navigation"    "Split Vertical" "C-M-e" "s` | tmux (nix) |
| `C-M-j` |  | `select-pane -L` | tmux (nix) |
| `C-M-k` |  | `select-pane -D` | tmux (nix) |
| `C-M-l` |  | `select-pane -U` | tmux (nix) |
| `C-o` |  | `send-prefix` | tmux (nix) |
| `ctrl+c` |  | `copy_or_interrupt` | kitty (nix) |
| `Ctrl+O, h` |  | `display-menu -T "#[align=centre fg=#ae95c7]Keybindings"    "Split Vertical" "e" "split-win` | tmux (nix) |
| `ctrl+shift+c` |  | `send_text all \x03` | kitty (nix) |
| `ctrl+shift+v` |  | `send_text all \x16` | kitty (nix) |
| `ctrl+shift+x` |  | `send_text all \x18` | kitty (nix) |
| `ctrl+v` |  | `paste_from_clipboard` | kitty (nix) |
| `S-Enter` |  | `send-keys Escape '[13;2u'` | tmux (nix) |
| `shift+enter` |  | `send_text all \x1b[13;2u` | kitty (nix) |

