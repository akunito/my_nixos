"""Spacing: gaps between tiles / to the monitor edge, space around each bar."""
from __future__ import annotations

import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402

from .. import log, spacing  # noqa: E402
from ..state import State  # noqa: E402

_log = log.get("gui.spacing")

ROWS = (("inner", "Between tiles", "px between adjacent tiles (sway gaps inner)", spacing.GAP_MAX),
        ("edge", "Tiles to monitor edge", "px from the tiles to the screen border (sway inner + outer)", spacing.GAP_MAX),
        ("bar_top", "Above the bar", "px between the screen top and the bar", 40),
        ("bar_sides", "Bar sides", "px left and right of the bar", 40),
        ("bar_bottom", "Under the bar", "px under the bar; the bar-to-tiles space is this + the edge gap", 40))


class SpacingPanel(Gtk.Box):
    def __init__(self, win) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win = win
        self.ctl = win.ctl
        header = Adw.HeaderBar()
        self.title = Adw.WindowTitle(title="Spacing", subtitle="")
        header.set_title_widget(self.title)
        self.append(header)
        page = Adw.PreferencesPage(vexpand=True)
        self.append(page)
        self.spins: dict[str, Adw.SpinRow] = {}
        tiles = Adw.PreferencesGroup(title="Tiles", description="Applied live to every workspace and kept for new ones.")
        bars = Adw.PreferencesGroup(title="Waybar", description="Changing these restarts Waybar (tray icons are kept).")
        for key, title, sub, hi in ROWS:
            row = Adw.SpinRow.new_with_range(0, hi, 1)
            row.set_title(title)
            row.set_subtitle(sub)
            row.connect("notify::value", lambda *_: self._preview())
            self.spins[key] = row
            (tiles if key in ("inner", "edge") else bars).add(row)
        page.add(tiles)
        page.add(bars)
        res = Adw.PreferencesGroup(title="Result")
        self.result = Adw.ActionRow(title="Bar to tiles", subtitle="")
        res.add(self.result)
        actions = Gtk.Box(spacing=8, halign=Gtk.Align.END, margin_top=8)
        self.reset_btn = Gtk.Button(label="Reset to Nix defaults")
        self.reset_btn.connect("clicked", lambda *_: self._run(reset=True))
        self.apply_btn = Gtk.Button(label="Apply")
        self.apply_btn.add_css_class("suggested-action")
        self.apply_btn.connect("clicked", lambda *_: self._run())
        actions.append(self.reset_btn)
        actions.append(self.apply_btn)
        res.add(actions)
        page.add(res)
        self._loading = False
        self.refresh()

    def on_show(self) -> None:
        self.refresh()

    def refresh(self) -> None:
        self.ctl.reload_state()
        v = spacing.values(self.ctl.state)
        self._loading = True
        for key, row in self.spins.items():
            row.set_value(v[key])
        self._loading = False
        self.title.set_subtitle(f"tiles {v['inner']}/{v['edge']} px · bar margins {v['bar_top']}/{v['bar_sides']}/{v['bar_bottom']} px")
        self._preview()

    def _vals(self) -> dict[str, int]:
        return {k: int(r.get_value()) for k, r in self.spins.items()}

    def _preview(self) -> None:
        v = self._vals()
        self.result.set_subtitle(f"{v['bar_bottom'] + v['edge']} px  (under the bar {v['bar_bottom']} + edge {v['edge']})")

    def _run(self, reset: bool = False) -> None:
        v = self._vals()
        self.apply_btn.set_sensitive(False)
        self.reset_btn.set_sensitive(False)

        def worker() -> None:
            try:
                st = State()
                ch = spacing.update(st, reset=reset, inner=None if reset else v["inner"], edge=None if reset else v["edge"],
                                    bar_top=None if reset else v["bar_top"], bar_sides=None if reset else v["bar_sides"],
                                    bar_bottom=None if reset else v["bar_bottom"])
                spacing.apply(st, ch, "spacing: reset to Nix defaults" if reset else
                              "spacing: " + ", ".join(f"{k}={x}" for k, x in ch["values"].items()))
                msg, err = ("Spacing reset" if reset else "Spacing applied"), False
            except Exception as exc:
                _log.exception("spacing apply failed")
                msg, err = f"Spacing failed: {exc}", True
            GLib.idle_add(self._done, msg, err)

        threading.Thread(target=worker, daemon=True).start()

    def _done(self, msg: str, err: bool) -> bool:
        self.apply_btn.set_sensitive(True)
        self.reset_btn.set_sensitive(True)
        self.win.toast(msg, error=err)
        self.refresh()
        return False
