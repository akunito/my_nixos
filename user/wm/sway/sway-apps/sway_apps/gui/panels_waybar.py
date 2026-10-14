"""Waybar: per-monitor bars (live state vs saved default), widget templates."""
from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402

from .. import log, waybar  # noqa: E402
from .controller import Outcome  # noqa: E402
from .panels import Panel, _clear_box  # noqa: E402
from .widgets import button, combo_row, combo_value, list_row, switch_row  # noqa: E402

_log = log.get("gui.waybar")

TEMPLATES_ID = "templates"
WS_LABELS = {"output": "This monitor", "all": "All workspaces"}
TPL_LABELS = {"primary": "Primary template", "secondary": "Secondary template", "custom": "Custom (this bar only)"}


class LayoutEditor(Gtk.Box):
    """Left / center / right module lists with reorder, plus the catalog pool."""

    def __init__(self, layout: dict[str, list[str]], pool: list[str], on_change=None) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.layout = {s: list(layout.get(s, ())) for s in waybar.SECTIONS}
        self.pool = sorted(pool)
        self.on_change = on_change
        self.cols = Gtk.Box(spacing=8, homogeneous=True)
        self.append(self.cols)
        add = Gtk.Box(spacing=6)
        self.pick = Gtk.DropDown.new_from_strings([""])
        self.pick.set_hexpand(True)
        add.append(self.pick)
        for sec in waybar.SECTIONS:
            add.append(button(f"Add {sec}", lambda s=sec: self._add(s), icon="list-add-symbolic"))
        self.append(add)
        self._render()

    def get_layout(self) -> dict[str, list[str]]:
        return {s: list(v) for s, v in self.layout.items()}

    def _changed(self) -> None:
        self._render()
        if self.on_change:
            self.on_change()

    def _render(self) -> None:
        _clear_box(self.cols)
        for sec in waybar.SECTIONS:
            col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            title = Gtk.Label(label=sec.upper(), xalign=0)
            title.add_css_class("sa-section-title")
            col.append(title)
            lb = Gtk.ListBox()
            lb.add_css_class("boxed-list")
            lb.set_selection_mode(Gtk.SelectionMode.NONE)
            items = self.layout[sec]
            for i, name in enumerate(items):
                row = Adw.ActionRow(title=name)
                for icon, tip, fn, ok in (("go-up-symbolic", "Move up", lambda s=sec, k=i: self._move(s, k, -1), i > 0),
                                          ("go-down-symbolic", "Move down", lambda s=sec, k=i: self._move(s, k, 1), i < len(items) - 1),
                                          ("go-next-symbolic", "To the next section", lambda s=sec, k=i: self._hop(s, k), True),
                                          ("list-remove-symbolic", "Remove", lambda s=sec, k=i: self._remove(s, k), True)):
                    b = Gtk.Button(icon_name=icon, valign=Gtk.Align.CENTER, tooltip_text=tip, sensitive=ok)
                    b.add_css_class("flat")
                    b.connect("clicked", lambda *_a, f=fn: f())
                    row.add_suffix(b)
                lb.append(row)
            if not items:
                lb.append(Adw.ActionRow(title="(empty)"))
            col.append(lb)
            self.cols.append(col)
        used = {n for v in self.layout.values() for n in v}
        free = [n for n in self.pool if n not in used]
        self.pick.set_model(Gtk.StringList.new(free or ["(every module is placed)"]))
        self.pick.set_sensitive(bool(free))

    def _add(self, sec: str) -> None:
        item = self.pick.get_selected_item()
        name = item.get_string() if item is not None else ""
        if name and name in self.pool and all(name not in v for v in self.layout.values()):
            self.layout[sec].append(name)
            self._changed()

    def _move(self, sec: str, i: int, d: int) -> None:
        lst = self.layout[sec]
        j = i + d
        if 0 <= j < len(lst):
            lst[i], lst[j] = lst[j], lst[i]
            self._changed()

    def _hop(self, sec: str, i: int) -> None:
        secs = waybar.SECTIONS
        nxt = secs[(secs.index(sec) + 1) % len(secs)]
        self.layout[nxt].append(self.layout[sec].pop(i))
        self._changed()

    def _remove(self, sec: str, i: int) -> None:
        self.layout[sec].pop(i)
        self._changed()


class WaybarPanel(Panel):
    def __init__(self, win) -> None:
        super().__init__(win, "Waybar")
        self.header_button("Show all", lambda: self._live([b.key for b in self.model.bars], visible=True),
                           icon="view-reveal-symbolic")
        self.header_button("Hide all", lambda: self._live([b.key for b in self.model.bars], visible=False),
                           icon="view-conceal-symbolic")
        self.header_button("Refresh", self.refresh, icon="view-refresh-symbolic", start=False)
        self.header_button("Reset to default", self.reset_default, icon="edit-undo-symbolic", start=False)
        self.header_button("Save as default", self.save_default, icon="document-save-symbolic", style="suggested-action",
                           start=False)
        self.model: waybar.Model | None = None

    # ---- data ----------------------------------------------------------------
    def _load(self) -> waybar.Model:
        self.ctl.reload_state()
        self.model = waybar.Model(self.ctl.state)
        return self.model

    def _status(self) -> dict:
        sway = waybar.SwayLink.connect()
        try:
            return waybar.status(self.model, sway)
        finally:
            if sway:
                sway.close()

    def _apply(self, fn, message: str, sync: bool = False) -> Outcome:
        sway = waybar.SwayLink.connect()
        try:
            res = fn(sway)
            if sync:
                waybar.Runtime().sync(sway, reload=True)
            return Outcome(True, message, res if isinstance(res, dict) else {})
        finally:
            if sway:
                sway.close()

    def _live(self, keys: list[str], **values) -> None:
        what = ", ".join(f"{k}={v}" for k, v in values.items())
        self.win.run_outcome(lambda: self._apply(lambda sway: waybar.Runtime().set_live(keys, sway, **values),
                                                 f"Live: {what} ({len(keys)} bar(s)); Save as default to keep it in the profile"))
        self.refresh()

    def _persist(self, message: str) -> Outcome:
        # ctl._finish writes the profile JSON and commits like every other panel.
        out = self.ctl._finish(message, False, None)
        sway = waybar.SwayLink.connect()
        try:
            out.details["waybar"] = waybar.Runtime().sync(sway, reload=True)
        finally:
            if sway:
                sway.close()
        return out

    # ---- list ----------------------------------------------------------------
    def refresh(self) -> None:
        m = self._load()
        st = {b["key"]: b for b in self._status()["bars"]}
        rows = []
        q = self.query()
        for b in m.bars:
            if q and q not in b.key.lower() and q not in b.name.lower():
                continue
            s = st.get(b.key, {})
            chips = [("shown" if b.visible else "hidden", "ok" if b.visible else ""),
                     ("all ws" if s.get("shows_all") else "this ws", ""), (f"{b.size}%", "")]
            if s.get("fullscreen"):
                chips.append(("fullscreen", "warn"))
            if b.local:
                chips.append(("live", "warn"))
            outs = ", ".join(s.get("outputs") or ()) or "not connected"
            sub = f"{b.bar_id} · {outs} · {TPL_LABELS[b.template].lower()}"
            rows.append((b.key, list_row(f"{b.key}  ·  {b.name}", sub, chips, disabled=not b.visible), b))
        rows.append((TEMPLATES_ID, list_row("Widget templates", "primary · secondary (shared by every secondary bar)",
                                            [("edit", "")]), TEMPLATES_ID))
        self.fill_list(rows)
        live = sum(1 for b in m.bars if b.local)
        self.toolbar.get_title_widget().set_subtitle(
            f"{len(m.bars)} bars · {live} with live changes" + (" — Save as default keeps them" if live else ""))

    def on_show(self) -> None:
        self.refresh()

    # ---- detail --------------------------------------------------------------
    def show_detail(self, item) -> None:
        if item == TEMPLATES_ID:
            self._show_templates()
            return
        b: waybar.Bar = self.model.by_key.get(item.key) if self.model else item
        if b is None:
            return
        self.clear_detail()
        self.detail_header(f"{b.bar_id} — {b.name}", b.criteria or "every output without a registered monitor")
        saved = b.saved

        g = Adw.PreferencesGroup(title="This machine (live)",
                                 description="Applies at once and survives a reboot; Hyper+Shift+H toggles the focused "
                                             "monitor's bar. Save as default writes it to the profile.")
        vis = switch_row("Visible", b.visible, f"default: {'shown' if saved['visible'] else 'hidden'}")
        vis.connect("notify::active", lambda r, _p: r.get_active() != b.visible and self._live([b.key], visible=r.get_active()))
        g.add(vis)
        ws = combo_row("Workspaces", list(WS_LABELS.values()), WS_LABELS[b.ws],
                       f"default: {WS_LABELS[saved['ws']].lower()} · one visible bar always shows all")
        ws.connect("notify::selected", lambda r, _p: self._on_ws(b, r))
        g.add(ws)
        size = Adw.SpinRow.new_with_range(waybar.SIZE_MIN, waybar.SIZE_MAX, 5)
        size.set_title("Size %")
        size.set_subtitle(f"font, height, paddings, tray icons · default {saved['size']}% · restarts Waybar")
        size.set_value(b.size)
        g.add(size)
        self.detail.append(g)

        tg = Adw.PreferencesGroup(title="Widgets", description="Primary and secondary templates are shared; custom is this bar's own.")
        tpl = combo_row("Template", list(TPL_LABELS.values()), TPL_LABELS[b.template])
        tg.add(tpl)
        self.detail.append(tg)
        holder = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.detail.append(holder)
        editor: dict[str, LayoutEditor | None] = {"e": None}

        def show_editor() -> None:
            _clear_box(holder)
            editor["e"] = None
            if combo_value(tpl) == TPL_LABELS["custom"]:
                editor["e"] = LayoutEditor(b.layout, list(self.model.modules), on_change=lambda: self.mark_dirty(save_tpl))
                holder.append(editor["e"])
        tpl.connect("notify::selected", lambda *_: (show_editor(), self.mark_dirty(save_tpl)))
        show_editor()

        def save_tpl() -> None:
            choice = next(k for k, v in TPL_LABELS.items() if v == combo_value(tpl))
            lay = editor["e"].get_layout() if editor["e"] else None

            def do() -> Outcome:
                waybar.set_bar_template(self.ctl.state, b.key, choice, lay)
                return self._persist(f"Waybar {b.bar_id}: template {choice}")
            self.clear_dirty()
            self.win.run_outcome(do)
            self.refresh()
        self.attach_banner(save_tpl)

        def apply_size() -> None:
            v = int(size.get_value())
            if v != b.size:
                self._live([b.key], size=v)
        self.action_bar(button("Apply size", apply_size, icon="zoom-fit-best-symbolic"),
                        button("Save widgets", save_tpl, style="suggested-action", icon="document-save-symbolic"))

    def _on_ws(self, b: waybar.Bar, row: Adw.ComboRow) -> None:
        mode = next(k for k, v in WS_LABELS.items() if v == combo_value(row))
        if mode != b.ws:
            self._live([b.key], ws=mode)

    def _show_templates(self) -> None:
        self.clear_detail()
        self.detail_header("Widget templates", "Every bar uses primary (the primary monitor's) or secondary, unless it has a custom layout.")
        m = self.model
        editors: dict[str, LayoutEditor] = {}
        for t in waybar.TEMPLATES:
            cur = m.template_layout(t)
            changed = cur != m.default_template_layout(t)
            g = Adw.PreferencesGroup(title=f"{t.capitalize()} template",
                                     description="edited in the profile" if changed else "Nix default (user/wm/sway/waybar.nix)")
            self.detail.append(g)
            editors[t] = LayoutEditor(cur, list(m.modules), on_change=lambda: self.mark_dirty(save))
            self.detail.append(editors[t])
            self.detail.append(button(f"Reset {t} to the Nix default", lambda tt=t: self._reset_template(tt),
                                      icon="edit-undo-symbolic"))

        def save() -> None:
            def do() -> Outcome:
                for t, e in editors.items():
                    if e.get_layout() != m.template_layout(t):
                        waybar.set_template(self.ctl.state, t, e.get_layout())
                return self._persist("Waybar: widget templates")
            self.clear_dirty()
            self.win.run_outcome(do)
            self.refresh()
        self.attach_banner(save)
        self.action_bar(button("Save templates", save, style="suggested-action", icon="document-save-symbolic"))

    def _reset_template(self, t: str) -> None:
        def do() -> Outcome:
            waybar.set_template(self.ctl.state, t, None)
            return self._persist(f"Waybar: {t} template back to the Nix default")
        self.win.run_outcome(do)
        self.refresh()
        self._show_templates()

    # ---- defaults ------------------------------------------------------------
    def save_default(self) -> None:
        def do() -> Outcome:
            waybar.save_default(self.ctl.state)
            return self._persist("Waybar: live bar state saved as the profile default")
        self.win.run_outcome(do)
        self.refresh()

    def reset_default(self) -> None:
        def do() -> Outcome:
            waybar.reset_local()
            return self._apply(lambda sway: waybar.Runtime().sync(sway, reload=True),
                               "Waybar: live changes dropped, profile default applies")
        self.win.run_outcome(do)
        self.refresh()
