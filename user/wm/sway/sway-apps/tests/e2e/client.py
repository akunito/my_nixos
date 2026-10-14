"""Test window for the e2e suite: chosen app_id/title/size, logs pointer presses.

python3 client.py --app-id e2e.a [--title T] [--size 400x300] [--log FILE] [--fullscreen] [--color RRGGBB]
--color: undecorated window painted one solid colour (pixel checks on grim crops).
Each press/release appends "press|release <button> <x> <y>" (surface coords) to --log, and
text committed through GTK's input method (dead keys composed) appends "text <repr>".
Prints "mapped" on stdout once the window is shown.
"""
from __future__ import annotations

import argparse
import os
import sys

os.environ.setdefault("GSK_RENDERER", "cairo")   # pixman headless sway has no GL
os.environ.setdefault("GTK_A11Y", "none")
os.environ.setdefault("GDK_BACKEND", "wayland")
os.environ.setdefault("GDK_DEBUG", "no-portals")  # portals get D-Bus-activated and outlive the suite

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--app-id", required=True)
    ap.add_argument("--title", default=None)
    ap.add_argument("--size", default="400x300")
    ap.add_argument("--log")
    ap.add_argument("--fullscreen", action="store_true")
    ap.add_argument("--color")
    a = ap.parse_args()
    GLib.set_prgname(a.app_id)
    w, h = (int(v) for v in a.size.split("x"))
    loop = GLib.MainLoop()
    win = Gtk.Window(title=a.title or a.app_id)
    win.set_default_size(w, h)
    if a.color:
        css = Gtk.CssProvider()
        css.load_from_string(f"window {{ background: #{a.color}; }}")
        Gtk.StyleContext.add_provider_for_display(win.get_display(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        win.set_decorated(False)
        win.set_child(Gtk.Box())
    else:
        win.set_child(Gtk.Label(label=a.title or a.app_id))
    log = open(a.log, "a", buffering=1) if a.log else None

    if log:
        click = Gtk.GestureClick(button=0)
        click.connect("pressed", lambda g, n, x, y: log.write(f"press {g.get_current_button()} {int(x)} {int(y)}\n"))
        click.connect("released", lambda g, n, x, y: log.write(f"release {g.get_current_button()} {int(x)} {int(y)}\n"))
        win.add_controller(click)
        im = Gtk.IMMulticontext()
        keys = Gtk.EventControllerKey()
        keys.set_im_context(im)
        im.connect("commit", lambda _im, text: log.write(f"text {text!r}\n"))
        win.add_controller(keys)
        win.connect("notify::is-active", lambda w, _p: im.focus_in() if w.is_active() else im.focus_out())
    win.connect("close-request", lambda *_: (loop.quit(), False)[1])
    win.connect("map", lambda *_: print("mapped", flush=True))
    if a.fullscreen:
        win.fullscreen()
    win.present()
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
