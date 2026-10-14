"""Stacking: peek setting, open floating windows with pin / above-fullscreen, always-pin rules."""
from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402

from .. import log, stacking, swayipc  # noqa: E402
from .controller import Outcome  # noqa: E402
from .panels import Panel  # noqa: E402
from .widgets import button, list_row, switch_row  # noqa: E402

_log = log.get("gui.stacking")

KEYS = (("Hyper+middle click", "pin / unpin the floating window under the pointer"),
        ("Hyper+wheel up / down", "raise / lower the floating window under the pointer, one step within its band"),
        ("Hold left or right button on a tile", "peek: the tile is drawn above the floats until you let go"))


class StackingPanel(Panel):
    def __init__(self, win) -> None:
        super().__init__(win, "Stacking")
        self.header_button("Refresh", self.refresh, icon="view-refresh-symbolic", start=False)
        self.header_button("Overview", self.show_overview, icon="dialog-information-symbolic")
        self.wins: list[dict] = []
        self.show_overview()

    # ---- list --------------------------------------------------------------------------
    def refresh(self) -> None:
        self.ctl.reload_state()
        try:
            self.wins = stacking.floating_windows(swayipc.get("get_tree")) if swayipc.available() else []
        except Exception as exc:  # sway restarting: keep the panel usable
            _log.warning("get_tree failed: %s", exc)
            self.wins = []
        q = self.query()
        rows = []
        for w in self.wins:
            name = stacking.label(w)
            if q and q not in (name + w["title"]).lower():
                continue
            chips = [(f"ws {w['workspace']}", "")]
            chips += [(c, "common") for c in ("pinned", "above_fullscreen", "sticky") if w[c]]
            rows.append((str(w["id"]), list_row(name, w["title"], chips), w))
        self.fill_list(rows)
        pinned = sum(1 for w in self.wins if w["pinned"])
        self.toolbar.get_title_widget().set_subtitle(f"{len(self.wins)} floating · {pinned} pinned · peek "
                                                     f"{'on' if stacking.peek_enabled(self.ctl.state) else 'off'}")
        if self.selected_id is None:
            self.show_overview()

    # ---- overview (nothing selected) ---------------------------------------------------
    def show_overview(self) -> None:
        self.listbox.unselect_all()
        self.selected_id = None
        self.clear_detail()
        self.detail_header("Window stacking", "Floating windows sit above tiles. Pinned floats sit above every other float. "
                                              "Pick a floating window on the left to pin it or put it over fullscreen views.")
        ok = stacking.supported("stacking")
        g = Adw.PreferencesGroup(title="Peek")
        peek = switch_row("Lift a covered tile while a button is held",
                          stacking.peek_enabled(self.ctl.state),
                          "left or right button on the visible part of a tile that a float overlaps; Alt drags, "
                          "title bars and fullscreen views are left alone" if ok else
                          "needs the sway stacking patch (Nix flag swayWindowStacking)")
        peek.set_sensitive(ok)
        peek.connect("notify::active", lambda r, *_: self._set_peek(r.get_active()))
        g.add(peek)
        self.detail.append(g)
        gk = Adw.PreferencesGroup(title="Keys")
        for keys, what in KEYS:
            gk.add(Adw.ActionRow(title=keys, subtitle=what))
        self.detail.append(gk)
        gc = Adw.PreferencesGroup(title="Above fullscreen", description=stacking.FULLSCREEN_COST)
        self.detail.append(gc)

    def _set_peek(self, on: bool) -> None:
        if on == stacking.peek_enabled(self.ctl.state):
            return
        stacking.set_peek(self.ctl.state, on)
        self.win.run_outcome(lambda: self.ctl._finish(f"Peek {'on' if on else 'off'}", True, None))

    # ---- one window --------------------------------------------------------------------
    def show_detail(self, w: dict) -> None:
        self.clear_detail()
        self.detail_header(stacking.label(w), f"{w['title']} · workspace {w['workspace']} on {w['output']} · "
                                              f"z {w['z'] + 1} from the bottom" + (" (top)" if w["top"] else ""))
        g = Adw.PreferencesGroup(title="This window", description="Live only: gone when the window closes. "
                                 "Use “Always pin this app” to keep it.")
        pin = switch_row("Pinned", w["pinned"], "above every unpinned float of its workspace")
        pin.set_sensitive(stacking.supported("stacking"))
        pin.connect("notify::active", lambda r, *_: self._live(w, "pin", r.get_active()))
        g.add(pin)
        af = switch_row("Above fullscreen", w["above_fullscreen"], "drawn and clickable over a fullscreen view (costs frames, see Overview)")
        af.set_sensitive(stacking.supported("above_fullscreen"))
        af.connect("notify::active", lambda r, *_: self._live(w, "above_fullscreen", r.get_active()))
        g.add(af)
        self.detail.append(g)

        def z(step: str) -> None:
            self._run(f"[con_id={w['id']}] z {step}", f"{step} {stacking.label(w)}")

        def always(af_too: bool) -> None:
            try:
                crit = stacking.identity_criteria(w)
            except ValueError as exc:
                self.win.toast(str(exc), error=True)
                return
            rule = stacking.pin_rule(self.ctl.state, crit, af_too)
            self.win.run_outcome(lambda: self.ctl.save_rule(rule, rule.scope), refresh_all=True)

        btns = [button("Lower", lambda: z("lower"), icon="go-down-symbolic"),
                button("Raise", lambda: z("raise"), icon="go-up-symbolic"),
                button("Always pin this app", lambda: always(False), style="suggested-action")]
        if stacking.supported("above_fullscreen"):
            btns.append(button("Always pin, over fullscreen", lambda: always(True)))
        for b in btns[:2]:
            b.set_sensitive(stacking.supported("stacking"))
        self.action_bar(*btns)

    def _live(self, w: dict, verb: str, on: bool) -> None:
        if bool(w[verb]) == on:
            return
        self._run(stacking.window_command(w["id"], verb, "enable" if on else "disable"),
                  f"{verb.replace('_', ' ')} {'on' if on else 'off'} · {stacking.label(w)}")

    def _run(self, command: str, message: str) -> None:
        def go() -> Outcome:
            try:
                swayipc.command(command)
            except swayipc.SwayError as exc:
                return Outcome(False, str(exc))
            return Outcome(True, message)
        self.win.run_outcome(go)
        self.refresh()
