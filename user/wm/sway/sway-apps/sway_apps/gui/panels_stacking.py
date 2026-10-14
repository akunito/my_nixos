"""Placeholder; the owning workstream replaces it."""
from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402


class StackingPanel(Gtk.Box):
    def __init__(self, win) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win = win
        self.ctl = win.ctl
        self.append(Adw.HeaderBar())
        self.append(Adw.StatusPage(title="stacking", description="Not implemented yet"))

    def on_show(self) -> None:
        pass

    def refresh(self) -> None:
        pass
