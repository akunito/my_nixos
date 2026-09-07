"""Tools: sidebar launchers (utilities) and their editor."""
from __future__ import annotations

import hashlib

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402

from .. import discover, log, swayipc  # noqa: E402
from ..shortcuts import Shortcut  # noqa: E402
from ..state import SCOPES, Tool  # noqa: E402
from .panels import Panel  # noqa: E402
from .widgets import button, combo_row, combo_value, confirm, entry_row, list_row, scrolled, switch_row  # noqa: E402

_log = log.get("gui.tools")

ICONS = ["application-x-executable-symbolic", "preferences-desktop-wallpaper-symbolic", "video-display-symbolic", "network-vpn-symbolic",
         "audio-volume-high-symbolic", "bluetooth-symbolic", "network-wired-symbolic", "preferences-system-sharing-symbolic",
         "computer-symbolic", "utilities-system-monitor-symbolic", "application-x-addon-symbolic", "preferences-desktop-theme-symbolic",
         "preferences-system-symbolic", "utilities-terminal-symbolic", "folder-symbolic", "web-browser-symbolic", "input-keyboard-symbolic",
         "camera-photo-symbolic", "printer-symbolic", "drive-harddisk-symbolic", "emblem-system-symbolic"]


class ToolsPanel(Panel):
    def __init__(self, win) -> None:
        super().__init__(win, "Tools")
        self.header_button("Add from apps", self.add_from_apps, icon="view-app-grid-symbolic", start=False)
        self.header_button("New tool", lambda: self.new_tool(), icon="list-add-symbolic", style="suggested-action", start=False)

    def tool_key(self, t: Tool) -> Shortcut | None:
        for x in self.ctl.state.shortcuts():
            if x.kind == "app" and x.app_id == t.app_id and x.command == t.command:
                return x
            if x.kind == "exec" and not t.app_id and x.command == t.command:
                return x
        return None

    def refresh(self) -> None:
        self.ctl.reload_state()
        items = self.ctl.state.tools()
        q = self.query()
        rows = []
        for t in items:
            if q and q not in (t.name + t.command + t.app_id).lower():
                continue
            k = self.tool_key(t)
            chips = [(k.keys, "common")] if k else [("no key", "")]
            chips.append((t.scope, t.scope))
            img = Gtk.Image.new_from_icon_name(t.icon); img.set_valign(Gtk.Align.CENTER)
            row = list_row(f"{t.order:>3}  {t.name}", t.launch_command(), chips, disabled=not t.enabled, trailing=img)
            rows.append((t.id, row, t))
        self.fill_list(rows)
        self.toolbar.get_title_widget().set_subtitle(f"{len(items)} tools · shown in the sidebar · click to launch or focus")
        self.win.refresh_tools_sidebar()

    def new_tool(self, t: Tool | None = None) -> None:
        self.listbox.unselect_all(); self.selected_id = None
        self.show_detail(t or Tool(id="", name="", command=""), is_new=True)

    def add_from_apps(self) -> None:
        pop = Gtk.Popover(); box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        search = Gtk.SearchEntry(placeholder_text="search apps…"); box.append(search)
        lb = Gtk.ListBox(); lb.add_css_class("sa-list")
        apps = discover.apps(include_hidden=True)

        def fill(q=""):
            lb.remove_all()
            for a in apps:
                if q and q not in a.name.lower() and q not in a.desktop_id.lower():
                    continue
                row = list_row(a.name, f"{a.app_id_guess} · {a.command[:50]}", [(a.source, "")]); row.app = a; lb.append(row)  # type: ignore[attr-defined]
        fill(); search.connect("search-changed", lambda e: fill(e.get_text().lower()))

        def chosen(_lb, row):
            a = row.app; pop.popdown()
            icon = a.icon if a.icon and "/" not in a.icon else "application-x-executable-symbolic"
            self.new_tool(Tool(id="", name=a.name, command=a.command, app_id=a.app_id_guess, icon=icon))
        lb.connect("row-activated", chosen)
        sw = scrolled(lb); sw.set_size_request(460, 340); box.append(sw); pop.set_child(box); pop.set_parent(self.toolbar); pop.popup()

    def show_detail(self, t: Tool, is_new: bool = False) -> None:
        self.clear_detail()
        self.attach_banner(lambda: do_save())
        self.detail_header("New tool" if is_new else t.name, t.launch_command() if not is_new else "a sidebar launcher: focus the window if open, start it otherwise")
        g = Adw.PreferencesGroup(title="Tool")
        name = entry_row("Name", t.name)
        command = entry_row("Command", t.command)
        app_id = entry_row("app_id to focus (empty = always start)", t.app_id)
        icon = combo_row("Icon", ICONS + ([t.icon] if t.icon and t.icon not in ICONS else []), t.icon or ICONS[0])
        order = Adw.SpinRow.new_with_range(0, 9999, 10); order.set_title("Order"); order.set_value(t.order)
        enabled = switch_row("Enabled", t.enabled, "shown in the sidebar")
        scope = combo_row("Scope", list(SCOPES), t.scope)
        notes = entry_row("Notes", t.notes)
        for r in (name, command, app_id, icon, order, enabled, scope, notes):
            g.add(r)
        self.detail.append(g)
        k = self.tool_key(t) if not is_new else None
        g2 = Adw.PreferencesGroup(title="Keyboard", description="Bound through the Shortcuts section (category Tools).")
        krow = Adw.ActionRow(title="Key", subtitle=k.keys if k else "none")
        kb = Gtk.Button(label="Change…" if k else "Assign key…", valign=Gtk.Align.CENTER)
        kb.connect("clicked", lambda *_: self.assign_key(t, k))
        krow.add_suffix(kb)
        g2.add(krow)
        self.detail.append(g2)

        def collect() -> Tool:
            cmd = command.get_text().strip(); aid = app_id.get_text().strip()
            return Tool(id=t.id or "t-" + hashlib.sha1(f"{aid}|{cmd}".encode()).hexdigest()[:8], name=name.get_text().strip(), command=cmd,
                        app_id=aid, icon=combo_value(icon), order=int(order.get_value()), enabled=enabled.get_active(),
                        notes=notes.get_text(), updated_at=t.updated_at, scope=combo_value(scope))

        def _dirty(*_a) -> None:
            self.mark_dirty(do_save)
        for r in (name, command, app_id, notes):
            r.connect("changed", _dirty)
        for r in (icon, scope):
            r.connect("notify::selected", _dirty)
        order.connect("notify::value", _dirty); enabled.connect("notify::active", _dirty)
        if is_new:
            self.mark_dirty(do_save)

        def do_save() -> None:
            n = collect()
            out = self.win.run_outcome(lambda: self.ctl.save_tool(n, n.scope))
            if out is not None and out.ok:
                self.clear_dirty(); self.selected_id = n.id; self.refresh()

        def do_run() -> None:
            n = collect()
            try:
                swayipc.exec_(n.launch_command()); self.win.toast(f"Launched {n.name}")
            except Exception as exc:
                self.win.toast(f"Launch failed: {exc}", error=True)

        def do_delete() -> None:
            confirm(self.win, f"Remove tool {t.name}?", t.launch_command(), "Remove", lambda: (
                self.win.run_outcome(lambda: self.ctl.delete_tool(t)), self.show_placeholder(), self.refresh()))

        btns = [button("Launch", do_run, icon="media-playback-start-symbolic"), button("Save & apply", do_save, style="suggested-action", icon="document-save-symbolic")]
        if not is_new:
            btns.insert(0, button("Delete", do_delete, style="destructive-action"))
        self.action_bar(*btns)

    def assign_key(self, t: Tool, existing: Shortcut | None) -> None:
        sc = existing or Shortcut(id="", keys="", kind="app" if t.app_id else "exec", app_id=t.app_id, command=t.command, name=t.name, category="Tools")
        panel = self.win.panels["shortcuts"]
        if existing:
            panel.selected_id = existing.id
            self.win.show_section("shortcuts"); panel.refresh()
            row = panel.listbox.get_selected_row()
            if row is not None:
                panel.show_detail(row.item)
        else:
            panel.new_shortcut(sc)
            self.win.show_section("shortcuts")
