"""Window rules, shortcuts and startup for DESK_W11.

The twin of user/wm/sway/sway-apps, for the Windows desk: the same shape of
state (one JSON in the repo), the same split (a CLI that does everything and a
GUI on top), and the same rule -- the state is the source of truth and the
files the window manager reads are GENERATED from it.

What gets generated here:

    glazewm/config.yaml       from glazewm/config.template.yaml + the state
                              (window rules and the workspace table)
    generated-apps.ahk        the Hyper+<letter> table and the startup list,
                              included by hyper-desktops.ahk

Everything else in hyper-desktops.ahk stays hand-written: the gestures, the
journal, the repair. This tool owns the data, not the behaviour.
"""
