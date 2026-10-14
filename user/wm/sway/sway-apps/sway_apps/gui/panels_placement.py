"""Placement: window memory (journal), never-remember list, monitor power-off
policy (default + per monitor), the two bring shortcuts, current loans."""
from __future__ import annotations

import time

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402

from .. import log, placement  # noqa: E402
from .widgets import scrolled  # noqa: E402

_log = log.get("gui.placement")

POLICY_HELP = ("ignore: sway-apps adds nothing. With 'always connected' (Monitors) a panel that sleeps never disappears; "
               "if an output IS removed, sway moves its workspaces away and sway-apps sends them home when it returns.\n"
               "move windows: after the grace, its windows join the visible workspace of the focused screen; when it "
               "returns, each one still there goes back where it was (anything you moved meanwhile stays).")


def _trash_button(cb) -> Gtk.Button:
    b = Gtk.Button(icon_name="user-trash-symbolic", valign=Gtk.Align.CENTER, tooltip_text="Forget")
    b.add_css_class("flat")
    b.connect("clicked", lambda *_: cb())
    return b


class PlacementPanel(Gtk.Box):
    def __init__(self, win) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win = win
        self.ctl = win.ctl
        self._loading = False
        self._grace_timer = 0
        self.toolbar = Adw.HeaderBar()
        self.title = Adw.WindowTitle(title="Placement", subtitle="remember · bring · power-off")
        self.toolbar.set_title_widget(self.title)
        refresh = Gtk.Button(icon_name="view-refresh-symbolic", tooltip_text="Refresh")
        refresh.connect("clicked", lambda *_: self.refresh())
        self.toolbar.pack_end(refresh)
        self.append(self.toolbar)
        self.page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin_top=12, margin_bottom=24,
                            margin_start=18, margin_end=18)
        clamp = Adw.Clamp(maximum_size=900)
        clamp.set_child(self.page)
        self.append(scrolled(clamp))

    def on_show(self, *_a) -> None:
        self.refresh()

    # ---- helpers ------------------------------------------------------------------
    def _state(self):
        self.ctl.reload_state()
        return self.ctl.state

    def _save(self, message: str, mutate) -> None:
        if self._loading:
            return
        try:
            st = self._state()
            mutate(st)
            extra = placement.persist(st, message)
            self.win.toast(message + extra)
        except Exception as exc:  # never let a click crash the window
            _log.exception("placement save failed")
            self.win.toast(f"Error: {exc}", error=True)
        GLib.idle_add(lambda: (self.refresh(), False)[1])  # not from inside the handler of a row being replaced

    # ---- build --------------------------------------------------------------------
    def refresh(self) -> None:
        self._loading = True
        try:
            child = self.page.get_first_child()
            while child is not None:
                nxt = child.get_next_sibling()
                self.page.remove(child)
                child = nxt
            st = self._state()
            cfg = st.feature(placement.SETTINGS_KEY)
            rows = placement.journal_rows()
            self.page.append(self._memory_group(cfg, rows))
            self.page.append(self._exclusions_group(cfg))
            self.page.append(self._poweroff_group(st))
            self.page.append(self._bring_group(st))
            self.title.set_subtitle(f"{len(rows)} remembered · default power-off: {placement.policy_view(st)['default']}")
        finally:
            self._loading = False

    def _memory_group(self, cfg: dict, rows: list[dict]) -> Adw.PreferencesGroup:
        g = Adw.PreferencesGroup(
            title="Window memory",
            description="Each app opens where its last window was: workspace, floating, size and position on its monitor "
                        "(clamped to that monitor). Rules always win; games, dialogs, sticky/pinned and fullscreen-born "
                        "windows are skipped; a second window of a running app only gets the size.")
        on = Adw.SwitchRow(title="Remember where windows go", active=bool((cfg.get("journal") or {}).get("enabled", True)))
        on.connect("notify::active", lambda r, _p: self._save(f"placement journal {'on' if r.get_active() else 'off'}",
                                                              lambda st: placement.set_journal(st, r.get_active())))
        g.add(on)
        if not rows:
            g.add(Adw.ActionRow(title="Nothing remembered yet", subtitle="Move or resize a window; it is written within a second."))
        for r in rows:
            rect = r.get("rect") or []
            what = f"floating {rect[2]}×{rect[3]} at +{rect[0]},+{rect[1]}" if r.get("floating") and len(rect) == 4 else "tiled"
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(r.get("updated", 0))) if r.get("updated") else ""
            row = Adw.ActionRow(title=r["app"] + ("  (X11)" if r.get("x11") else ""),
                                subtitle=f"ws {r.get('workspace', '?')} · {what} · {r.get('output', '')}" + (f" · {when}" if when else ""))
            row.add_suffix(_trash_button(lambda key=r["app"]: self._forget(key)))
            g.add(row)
        return g

    def _forget(self, key: str) -> None:
        try:
            found = placement.forget(key)
            self.win.toast(f"{key}: {'forgotten' if found else 'was not remembered'}")
        except OSError as exc:
            self.win.toast(f"Error: {exc}", error=True)
        GLib.idle_add(lambda: (self.refresh(), False)[1])

    def _exclusions_group(self, cfg: dict) -> Adw.PreferencesGroup:
        g = Adw.PreferencesGroup(title="Never remember",
                                 description="Apps that place themselves (some Electron/GTK apps restore their own geometry and "
                                             "would fight once on open). Identity = app_id, or the X11 class. Shared by every machine.")
        add = Adw.EntryRow(title="Add app_id or X11 class")
        add.set_show_apply_button(True)

        def on_apply(row) -> None:
            app = row.get_text().strip()
            if app:
                self._save(f"placement exclude +{app}", lambda st: placement.set_exclusion(st, app, True))
        add.connect("apply", on_apply)
        g.add(add)
        for app in (cfg.get("journal") or {}).get("exclude") or []:
            row = Adw.ActionRow(title=app)
            row.add_suffix(_trash_button(lambda a=app: self._save(f"placement exclude -{a}", lambda st: placement.set_exclusion(st, a, False))))
            g.add(row)
        return g

    def _poweroff_group(self, st) -> Adw.PreferencesGroup:
        view = placement.policy_view(st)
        g = Adw.PreferencesGroup(title="When a monitor goes away", description=POLICY_HELP)
        opts = ["ignore", "move windows"]
        default = Adw.ComboRow(title="Default", subtitle="for every monitor without its own choice")
        default.set_model(Gtk.StringList.new(opts))
        default.set_selected(1 if view["default"] == "move" else 0)
        default.connect("notify::selected", lambda r, _p: self._save(
            f"power-off policy default={'move' if r.get_selected() == 1 else 'ignore'}",
            lambda s: placement.set_policy(s, None, "move" if r.get_selected() == 1 else "ignore")))
        g.add(default)
        for m in view["monitors"]:
            row = Adw.ComboRow(title=f"{m['role']}  ·  {m['name'] or ''}".strip(" ·"),
                               subtitle=f"now: {'move windows' if m['effective'] == 'move' else 'ignore'}")
            row.set_model(Gtk.StringList.new([f"default ({'move windows' if view['default'] == 'move' else 'ignore'})"] + opts))
            row.set_selected({None: 0, "ignore": 1, "move": 2}.get(m["override"], 0))

            def changed(r, _p, role=m["role"]) -> None:
                pol = ("default", "ignore", "move")[r.get_selected()]
                self._save(f"power-off policy {role}={pol}", lambda s: placement.set_policy(s, role, pol))
            row.connect("notify::selected", changed)
            g.add(row)
        grace = Adw.SpinRow.new_with_range(1, 60, 1)
        grace.set_title("Grace before moving (s)")
        grace.set_subtitle("a monitor back within this time moves nothing")
        grace.set_value(float(view["grace_seconds"]))

        def grace_changed(r, _p) -> None:
            # one commit per settled value, not one per spin step
            if self._grace_timer:
                GLib.source_remove(self._grace_timer)

            def fire() -> bool:
                self._grace_timer = 0
                v = float(r.get_value())
                self._save(f"power-off grace {v:g}s", lambda s: placement.set_policy(s, None, placement.policy_view(s)["default"], v))
                return False
            self._grace_timer = GLib.timeout_add(800, fire)
        grace.connect("notify::value", grace_changed)
        g.add(grace)
        return g

    def _bring_group(self, st) -> Adw.PreferencesGroup:
        keys = placement.bring_shortcuts(st)
        g = Adw.PreferencesGroup(title="Bring windows",
                                 description="Hotkeys run inside the sway-apps watch daemon (no process start). Edit the keys under Shortcuts.")
        for what, title, sub in (
            ("offscreen", "Bring off-screen windows here",
             "floating windows with less than 24 px on every screen (either axis) move into the focused screen; size kept, trimmed only if larger"),
            ("all", "Bring all windows here / send them back",
             "first press: every window of the other screens joins this screen's workspace; second press: each one still there goes home"),
        ):
            row = Adw.ActionRow(title=title, subtitle=sub)
            key = Gtk.Label(label=keys.get(what) or "no shortcut", valign=Gtk.Align.CENTER)
            key.add_css_class("sa-chip")
            row.add_suffix(key)
            run = Gtk.Button(label="Run", valign=Gtk.Align.CENTER)
            run.connect("clicked", lambda *_a, w=what: self._bring(w))
            row.add_suffix(run)
            g.add(row)
        try:
            loans = placement.loans()
        except Exception as exc:  # no sway socket (GUI over ssh)
            loans = []
            _log.debug("loans unavailable: %s", exc)
        for l in loans:
            g.add(Adw.ActionRow(title=f"On loan: {l.get('source')} → ws {l.get('host_ws')}",
                                subtitle=f"{len(l.get('windows') or [])} window(s) · {'bring all' if l.get('reason') == 'bring' else 'monitor power-off'}"))
        if loans:
            clear = Adw.ActionRow(title="Forget the loans", subtitle="the windows stay where they are; nothing goes back later")
            b = Gtk.Button(label="Forget", valign=Gtk.Align.CENTER)
            b.add_css_class("destructive-action")
            b.connect("clicked", lambda *_: (placement.loans(clear=True), GLib.idle_add(lambda: (self.refresh(), False)[1])))
            clear.add_suffix(b)
            g.add(clear)
        return g

    def _bring(self, what: str) -> None:
        try:
            res = placement.bring(what)
        except Exception as exc:
            self.win.toast(f"Error: {exc}", error=True)
            return
        if what == "offscreen":
            self.win.toast(f"{res.get('moved', 0)} off-screen window(s) brought here")
        else:
            n = sum(int(l.get("windows", 0)) if isinstance(l.get("windows"), int) else int(l.get("returned", 0)) for l in res.get("loans", []))
            self.win.toast(f"{'lent' if res.get('action') == 'lent' else res.get('action')}: {n} window(s)")
        GLib.idle_add(lambda: (self.refresh(), False)[1])
