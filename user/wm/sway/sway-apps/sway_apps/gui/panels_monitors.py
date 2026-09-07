"""Monitors (roles, pins, geometry) and the Workspaces map."""
from __future__ import annotations

import subprocess

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402

from .. import log, monitors as mon, paths, swayipc  # noqa: E402
from ..rules import Rule  # noqa: E402
from ..state import SCOPES, Monitor  # noqa: E402
from .panels import Panel  # noqa: E402
from .widgets import button, chip, combo_row, combo_value, confirm, entry_row, list_row, scrolled, switch_row  # noqa: E402

_log = log.get("gui.monitors")


class MonitorsPanel(Panel):
    def __init__(self, win) -> None:
        super().__init__(win, "Monitors")
        self.header_button("Physical layout", self.open_nwg, icon="preferences-desktop-display-symbolic")
        self.header_button("Fix group 0", lambda: self.win.run_outcome(self.ctl.fix_orphans), icon="edit-clear-all-symbolic")
        self.geom = Gtk.ToggleButton(label="pin geometry")
        self.geom.set_tooltip_text("Re-emit nwg-displays' geometry keyed by hardware id (survives connector renames)")
        self._geom_handler = self.geom.connect("toggled", self._on_geom)
        self.toolbar.pack_end(self.geom)
        self.header_button("Refresh", self.refresh, icon="view-refresh-symbolic", start=False)

    def open_nwg(self) -> None:
        try:
            swayipc.exec_("nwg-displays")
            self.win.toast("nwg-displays opened. Save there, then Refresh here.")
        except Exception as exc:
            self.win.toast(f"Cannot open nwg-displays: {exc}", error=True)

    def _on_geom(self, btn) -> None:
        self.win.run_outcome(lambda: self.ctl.set_pin_geometry(btn.get_active()))

    def refresh(self) -> None:
        self.ctl.reload_state()
        st = self.ctl.state
        with self.geom.handler_block(self._geom_handler):
            self.geom.set_active(bool(st.settings().get("pin_geometry")))
        live = mon.live_outputs()
        by_hw = {o.hw_id: o for o in live}
        rows = []
        q = self.query()
        for m in st.monitors():
            o = by_hw.get(m.criteria)
            if q and q not in m.id.lower() and q not in m.name.lower() and q not in m.criteria.lower():
                continue
            chips = [(f"ws {m.group * 10 + 1}-{m.group * 10 + 10}" if m.group else "unpinned", "" if m.group else "warn")]
            chips.append(("connected " + o.name, "ok") if o and o.active else ("absent", ""))
            if m.primary:
                chips.append(("primary", "profile"))
            rows.append((m.id, list_row(f"{m.id}  ·  {m.name or m.criteria}", m.criteria, chips, disabled=not m.enabled), m))
        known = {m.criteria for m in st.monitors()}
        for o in live:
            if o.hw_id in known or not o.active:
                continue
            row = list_row(f"NEW  ·  {o.name}", o.hw_id, [("unknown output", "warn"), (f"{o.width}x{o.height}", "")])
            rows.append((f"new:{o.name}", row, o))
        self.fill_list(rows)
        self.toolbar.get_title_widget().set_subtitle(f"{len(st.monitors())} roles · {sum(1 for o in live if o.active)} outputs on · profile {paths.profile_name()}")

    def show_detail(self, item, is_new: bool = False) -> None:
        if isinstance(item, mon.LiveOutput):
            guess = "main" if not self.ctl.state.monitors() else "second" if not self.ctl.state.monitor("second") else f"mon{len(self.ctl.state.monitors()) + 1}"
            used = {m.group for m in self.ctl.state.monitors()}
            free = next((g for g in range(1, 10) if g not in used), 0)
            item = Monitor(id=guess, criteria=item.hw_id, group=free, name=f"{item.make} {item.model}".strip(), scope="profile")
            is_new = True
        m: Monitor = item
        self.clear_detail()
        self.attach_banner(lambda: do_save())
        o = next((x for x in mon.live_outputs() if x.hw_id == m.criteria), None)
        self.detail_header(("New monitor: " if is_new else "") + (m.name or m.id), m.criteria)

        g = Adw.PreferencesGroup(title="Role", description="Roles are shared vocabulary across machines (main, second, tv, left). Rules target 'main slot 2', each machine maps the role to its own hardware id.")
        role = entry_row("Role id", m.id)
        name = entry_row("Name", m.name)
        crit = entry_row("Hardware id (make model serial)", m.criteria)
        pick = Gtk.Button(icon_name="video-display-symbolic", valign=Gtk.Align.CENTER, tooltip_text="Take from a connected output")
        pick.add_css_class("flat")
        crit.add_suffix(pick)
        group = Adw.SpinRow.new_with_range(0, 9, 1); group.set_title("Workspace group (decade)"); group.set_subtitle("0 = not pinned"); group.set_value(m.group)
        primary = switch_row("Primary", m.primary)
        enabled = switch_row("Enabled", m.enabled)
        scope = combo_row("Scope", list(SCOPES), m.scope)
        notes = entry_row("Notes", m.notes)
        for r in (role, name, crit, group, primary, enabled, scope, notes):
            g.add(r)
        self.detail.append(g)

        def do_pick(*_a) -> None:
            pop = Gtk.Popover(); lb = Gtk.ListBox(); lb.add_css_class("sa-list")
            for lo in mon.live_outputs():
                row = list_row(f"{lo.name}  {lo.width}x{lo.height}", lo.hw_id, [("on" if lo.active else "off", "ok" if lo.active else "")]); row.out = lo; lb.append(row)  # type: ignore[attr-defined]

            def chosen(_lb, row):
                pop.popdown(); crit.set_text(row.out.hw_id)
                if not name.get_text():
                    name.set_text(f"{row.out.make} {row.out.model}".strip())
            lb.connect("row-activated", chosen)
            sw = scrolled(lb); sw.set_size_request(480, 200); pop.set_child(sw); pop.set_parent(crit); pop.popup()
        pick.connect("clicked", do_pick)

        if o is not None:
            g2 = Adw.PreferencesGroup(title=f"Live output {o.name}")
            for t, v in (("Mode", f"{o.width}x{o.height} @ {o.refresh:.0f} Hz"), ("Position", f"{o.x},{o.y}"), ("Scale", o.scale),
                         ("Transform", o.transform), ("Current workspace", o.current_workspace or "-"), ("Active", o.active)):
                r = Adw.ActionRow(title=t, subtitle=str(v)); g2.add(r)
            self.detail.append(g2)

        if not is_new:
            users = [r for r in self.ctl.state.rules() if r.target and r.target.get("monitor") == m.id]
            g3 = Adw.PreferencesGroup(title=f"Rules targeting this role ({len(users)})")
            for r in users[:20]:
                g3.add(Adw.ActionRow(title=r.name, subtitle=f"slot {r.target['slot']} · {r.render_criteria()}"))
            if not users:
                g3.add(Adw.ActionRow(title="No rule targets this role yet"))
            self.detail.append(g3)

        def collect() -> Monitor:
            return Monitor(id=role.get_text().strip(), criteria=crit.get_text().strip(), group=int(group.get_value()),
                           name=name.get_text().strip(), primary=primary.get_active(), enabled=enabled.get_active(),
                           notes=notes.get_text(), scope=combo_value(scope))

        def do_save() -> None:
            n = collect()
            if not is_new and n.id != m.id:
                out = self.win.run_outcome(lambda: self.ctl.rename_monitor(n, n.id))
            else:
                out = self.win.run_outcome(lambda: self.ctl.save_monitor(n, n.scope))
            if out is not None and out.ok:
                self.clear_dirty()
                self.selected_id = n.id
                self.refresh()
                self.win.panels["workspaces"].refresh()

        def _dirty(*_a) -> None:
            self.mark_dirty(do_save)
        for r in (role, name, crit, notes):
            r.connect("changed", _dirty)
        group.connect("notify::value", _dirty)
        for r in (primary, enabled):
            r.connect("notify::active", _dirty)
        scope.connect("notify::selected", _dirty)
        if is_new:
            self.mark_dirty(do_save)

        def do_delete() -> None:
            users = [r for r in self.ctl.state.rules() if r.target and r.target.get("monitor") == m.id]
            body = m.criteria + (f"\n{len(users)} rule(s) target it; they keep their numeric workspace." if users else "")
            confirm(self.win, f"Remove monitor role {m.id}?", body, "Remove", lambda: (
                self.win.run_outcome(lambda: self.ctl.delete_monitor(m)), self.show_placeholder(), self.refresh()))

        btns = [button("Save", do_save, style="suggested-action", icon="document-save-symbolic")]
        if not is_new:
            btns.insert(0, button("Delete", do_delete, style="destructive-action"))
        self.action_bar(*btns)


class WorkspacesPanel(Gtk.Box):
    """Monitors as columns, slots 1-10 as rows: assigned apps + open windows."""

    def __init__(self, win) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win = win
        self.ctl = win.ctl
        self.toolbar = Adw.HeaderBar()
        self.toolbar.set_title_widget(Adw.WindowTitle(title="Workspaces", subtitle="assigned apps · open windows"))
        self.append(self.toolbar)
        self.toolbar.pack_end(button("Refresh", self.refresh, icon="view-refresh-symbolic"))
        self.toolbar.pack_start(button("Apply pins now", lambda: self.win.run_outcome(self._apply), icon="emblem-ok-symbolic"))
        self.grid_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self.grid_box.set_margin_start(16); self.grid_box.set_margin_end(16); self.grid_box.set_margin_top(12); self.grid_box.set_margin_bottom(12)
        sw = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
        sw.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        sw.set_child(self.grid_box)
        self.append(sw)
        GLib.timeout_add_seconds(5, self._tick)

    def _apply(self):
        from .controller import Outcome
        out = self.ctl.apply_all()
        moved = mon.apply_live(self.ctl.state) if swayipc.available() else []
        n = sum(1 for h in moved if h.get("ok"))
        return Outcome(out.ok, out.message + (f" · moved {n} workspace(s)" if n else ""))

    def on_show(self) -> None:
        self.refresh()

    def _tick(self) -> bool:
        if self.get_mapped():
            self.refresh()
        return True

    def refresh(self) -> None:
        self.ctl.reload_state()
        child = self.grid_box.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling(); self.grid_box.remove(child); child = nxt
        data = mon.workspace_map(self.ctl.state)
        if not data:
            lbl = Gtk.Label(label="No monitors defined yet. Add roles in Monitors (Hyper+`).")
            lbl.add_css_class("sa-empty"); self.grid_box.append(lbl)
            return
        for block in data:
            m = block["monitor"]
            col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            col.set_size_request(260, -1)
            head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            t = Gtk.Label(label=(f"{m['id']}" if m else "unpinned"), xalign=0); t.add_css_class("sa-detail-title")
            sub_txt = (f"{m['name'] or m['criteria']}\n" + ("connected " + block["connector"] if block["connected"] else "absent")) if m else "workspaces outside every pinned decade"
            sub = Gtk.Label(label=sub_txt, xalign=0, wrap=True); sub.add_css_class("sa-detail-sub")
            head.append(t); head.append(sub)
            col.append(head)
            lb = Gtk.ListBox(); lb.add_css_class("sa-list"); lb.add_css_class("boxed-list")
            for sl in block["slots"]:
                ws = sl["workspace"]
                title = f"ws {ws}" if ws is not None else "-"
                apps = ", ".join(r["name"] for r in sl["rules"])
                wins = ", ".join(w["label"] for w in sl["windows"])
                subtitle = (f"→ {apps}" if apps else "") + ("   " if apps and wins else "") + (f"open: {wins}" if wins else "")
                chips = []
                if sl["windows"]:
                    chips.append((str(len(sl["windows"])), "ok"))
                row = list_row(title + (f"  (slot {sl['slot']})" if sl["slot"] else ""), subtitle or "empty", chips)
                row.slot = sl; row.mon = m  # type: ignore[attr-defined]
                lb.append(row)
            lb.connect("row-activated", self._slot_menu)
            col.append(lb)
            self.grid_box.append(col)

    def _slot_menu(self, _lb, row) -> None:
        sl, m = row.slot, row.mon  # type: ignore[attr-defined]
        pop = Gtk.Popover(); box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_margin_top(6); box.set_margin_bottom(6); box.set_margin_start(6); box.set_margin_end(6)
        if m and sl["slot"]:
            def assign_here() -> None:
                pop.popdown()
                r = Rule.new("assign", {"app_id": ""}, [f"workspace number {sl['workspace']}"])
                r.target = {"monitor": m["id"], "slot": sl["slot"]}
                self.win.panels["rules"].new_rule_prefilled(r)
                self.win.show_section("rules")
            box.append(button(f"Assign an app to ws {sl['workspace']}…", assign_here, icon="list-add-symbolic"))

            def from_window() -> None:
                pop.popdown()
                w = swayipc.focused_window()
                if w is None or not (w.app_id or w.cls):
                    self.win.toast("Focus a window first", error=True); return
                crit = {"app_id": w.app_id} if w.app_id else {"class": w.cls}
                r = Rule.new("assign", crit, [f"workspace number {sl['workspace']}"], name=w.label)
                r.target = {"monitor": m["id"], "slot": sl["slot"]}
                self.win.run_outcome(lambda: self.ctl.save_rule(r, "common")); self.refresh()
            box.append(button("Assign the focused window's app here", from_window, icon="focus-windows-symbolic"))
        if sl["workspace"] is not None and swayipc.available():
            box.append(button(f"Go to ws {sl['workspace']}", lambda: (pop.popdown(), swayipc.command(f"workspace number {sl['workspace']}")), icon="go-jump-symbolic"))
        for r in sl["rules"]:
            box.append(button(f"Edit rule: {r['name']}", lambda rid=r["id"]: (pop.popdown(), setattr(self.win.panels["rules"], "selected_id", rid), self.win.show_section("rules"), self.win.panels["rules"].refresh()), icon="document-edit-symbolic"))
        pop.set_child(box); pop.set_parent(row); pop.popup()
