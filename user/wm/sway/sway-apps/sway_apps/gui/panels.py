"""The five sections. Each panel = toolbar + list (left) + detail (right)."""
from __future__ import annotations

import time
from typing import Any

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402

from .. import discover, log, paths, swayipc  # noqa: E402
from ..rules import CRITERIA_KEYS, KINDS, Rule  # noqa: E402
from ..state import SCOPES, StartupEntry  # noqa: E402
from .forms import RuleForm  # noqa: E402
from .widgets import (button, chip, combo_row, combo_value, confirm, empty_state, entry_row, list_row,  # noqa: E402
                      scrolled, section, switch_row)

_log = log.get("gui.panels")

ON_OFF = ["", "enable", "disable", "toggle"]
INHIBIT = ["", "focus", "fullscreen", "open", "visible", "none"]
BORDERS = ["", "none", "normal", "pixel", "csd"]
LAYOUTS = ["", "tabbed", "stacking", "splith", "splitv", "default", "toggle split"]
CRIT_TEXT = ["app_id", "class", "instance", "title", "window_role", "window_type", "shell", "con_mark", "workspace"]


class Panel(Gtk.Box):
    """Common frame: toolbar row on top, Paned(list, detail) below."""

    def __init__(self, win, title: str) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win = win
        self.ctl = win.ctl
        self.toolbar = Adw.HeaderBar()
        self.toolbar.set_show_end_title_buttons(True)
        self.toolbar.set_title_widget(Adw.WindowTitle(title=title))
        self.append(self.toolbar)
        self.paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL, vexpand=True)
        self.paned.set_position(440)
        self.paned.set_shrink_start_child(False)
        self.paned.set_shrink_end_child(False)
        self.append(self.paned)
        self.listbox = Gtk.ListBox()
        self.listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.listbox.add_css_class("sa-list")
        self.listbox.add_css_class("background")
        self.listbox.connect("row-selected", self._on_select)
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.search = Gtk.SearchEntry(placeholder_text="Search…")
        self.search.set_margin_start(8); self.search.set_margin_end(8); self.search.set_margin_top(8); self.search.set_margin_bottom(4)
        self.search.connect("search-changed", lambda *_: self.refresh())
        left.append(self.search)
        left.append(scrolled(self.listbox))
        left.set_size_request(320, -1)
        self.paned.set_start_child(left)
        self.detail = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.detail.add_css_class("sa-detail")
        self.paned.set_end_child(scrolled(self.detail))
        self.items: list[Any] = []
        self.selected_id: str | None = None
        # Unsaved-edit tracking: the detail form sets self._dirty_save to a
        # callable that persists the current form; None when nothing pending.
        self._dirty_save = None
        self._dirty_banner: Adw.Banner | None = None
        self.show_placeholder()

    def has_unsaved(self) -> bool:
        return self._dirty_save is not None

    def save_unsaved(self) -> bool:
        """Persist pending edits (used by the footer Apply). True if saved."""
        if self._dirty_save is None:
            return False
        fn = self._dirty_save
        self._dirty_save = None
        fn()
        return True

    def mark_dirty(self, save_fn) -> None:
        self._dirty_save = save_fn
        if self._dirty_banner is not None:
            self._dirty_banner.set_revealed(True)

    def clear_dirty(self) -> None:
        self._dirty_save = None
        if self._dirty_banner is not None:
            self._dirty_banner.set_revealed(False)

    def attach_banner(self, on_save) -> None:
        """Top-of-detail banner shown while the form has unsaved changes."""
        b = Adw.Banner(title="Unsaved changes — Save applies them to sway and commits")
        b.set_button_label("Save")
        b.connect("button-clicked", lambda *_: on_save())
        b.set_revealed(False)
        self._dirty_banner = b
        self.detail.append(b)

    # hooks
    def on_show(self) -> None:
        self.refresh()

    def refresh(self) -> None:  # pragma: no cover - overridden
        pass

    def _on_select(self, _lb, row) -> None:
        if row is None or getattr(row, "item", None) is None:
            return
        self.selected_id = getattr(row, "item_id", None)
        self.show_detail(row.item)  # type: ignore[attr-defined]

    def show_detail(self, item) -> None:  # pragma: no cover - overridden
        pass

    def clear_detail(self) -> None:
        self._dirty_save = None
        self._dirty_banner = None
        child = self.detail.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            self.detail.remove(child)
            child = nxt

    def show_placeholder(self, title: str = "Nothing selected", desc: str = "Pick an item on the left.") -> None:
        self.clear_detail()
        self.detail.append(empty_state(title, desc))

    def fill_list(self, rows: list[tuple[str, Gtk.ListBoxRow, Any]]) -> None:
        self.listbox.remove_all()
        reselect = None
        for item_id, row, item in rows:
            row.item_id = item_id  # type: ignore[attr-defined]
            row.item = item  # type: ignore[attr-defined]
            self.listbox.append(row)
            if item_id == self.selected_id:
                reselect = row
        if reselect is not None:
            self.listbox.select_row(reselect)
        elif rows:
            pass
        else:
            self.show_placeholder("No items", "Nothing matches the current filter.")

    def query(self) -> str:
        return self.search.get_text().strip().lower()

    def header_button(self, label: str, cb, icon: str | None = None, style: str = "", start: bool = True) -> Gtk.Button:
        b = button(label, cb, style, icon)
        (self.toolbar.pack_start if start else self.toolbar.pack_end)(b)
        return b

    def detail_header(self, title: str, subtitle: str) -> None:
        t = Gtk.Label(label=title, xalign=0, wrap=True)
        t.add_css_class("sa-detail-title")
        s = Gtk.Label(label=subtitle, xalign=0, wrap=True, selectable=True)
        s.add_css_class("sa-detail-sub")
        self.detail.append(t)
        self.detail.append(s)

    def action_bar(self, *buttons: Gtk.Button) -> None:
        bar = Gtk.Box(spacing=8, halign=Gtk.Align.END, margin_top=14)
        for b in buttons:
            bar.append(b)
        self.detail.append(bar)


# ==========================================================================
# Rules

class RulesPanel(Panel):
    def __init__(self, win) -> None:
        super().__init__(win, "Window rules")
        self.kind_filter = Gtk.DropDown.new_from_strings(["all kinds", *KINDS])
        self.kind_filter.connect("notify::selected", lambda *_: self.refresh())
        self.toolbar.pack_start(self.kind_filter)
        self.header_button("New rule", self.new_rule, icon="list-add-symbolic", style="suggested-action", start=False)
        self.header_button("From window", self.from_window, icon="focus-windows-symbolic", start=False)
        self._draft: Rule | None = None

    def refresh(self) -> None:
        self.ctl.reload_state()
        rules = self.ctl.state.rules()
        k = self.kind_filter.get_selected()
        if k > 0:
            rules = [r for r in rules if r.kind == KINDS[k - 1]]
        q = self.query()
        if q:
            rules = [r for r in rules if q in r.render().lower() or q in r.name.lower() or q in r.id]
        rules.sort(key=lambda r: (r.kind != "for_window", r.name.lower()))
        rows = []
        for r in rules:
            chips = []
            if r.kind != "for_window":
                chips.append((r.kind, r.kind))
            chips.append((r.scope, r.scope))
            sw = Gtk.Switch(active=r.enabled, valign=Gtk.Align.CENTER)
            sw.connect("state-set", lambda _s, state, rule=r: self._toggle(rule, state))
            rows.append((r.id, list_row(r.name, r.render(), chips, disabled=not r.enabled, trailing=sw), r))
        self.fill_list(rows)
        self.toolbar.get_title_widget().set_subtitle(f"{len(rules)} shown · {len(self.ctl.state.rules())} total")

    def _toggle(self, rule: Rule, state: bool) -> bool:
        self.win.run_outcome(lambda: self.ctl.toggle_rule(rule, state))
        GLib.idle_add(self.refresh)
        return False

    def new_rule(self, criteria: dict[str, str] | None = None, name: str = "") -> None:
        self._draft = Rule.new("for_window", criteria or {"app_id": ""}, ["floating enable"], name=name)
        self.listbox.unselect_all()
        self.selected_id = None
        self.show_detail(self._draft, is_new=True)

    def new_rule_prefilled(self, rule: Rule) -> None:
        """Open the editor on an unsaved rule built elsewhere (workspace map)."""
        self._draft = rule
        self.listbox.unselect_all()
        self.selected_id = None
        self.show_detail(rule, is_new=True)

    def new_rule_from_window(self, w: swayipc.Window) -> None:
        crit = {"app_id": w.app_id} if w.app_id else ({"class": w.cls} if w.cls else {"title": w.title or ""})
        self.new_rule(crit, name=w.label)
        self.win.show_section("rules")

    def from_window(self) -> None:
        pop = Gtk.Popover()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        lb = Gtk.ListBox()
        lb.add_css_class("sa-list")
        wins = swayipc.windows() if swayipc.available() else []
        for w in wins:
            row = list_row(w.label, (w.title or "")[:60], [(f"ws {w.workspace}", "")])
            row.window = w  # type: ignore[attr-defined]
            lb.append(row)
        if not wins:
            lb.append(list_row("No open windows", ""))

        def pick(_lb, row):
            if row is not None and hasattr(row, "window"):
                pop.popdown()
                self.new_rule_from_window(row.window)
        lb.connect("row-activated", pick)
        sw = scrolled(lb)
        sw.set_size_request(420, 360)
        box.append(sw)
        pop.set_child(box)
        pop.set_parent(self.toolbar)
        pop.popup()

    # ---- detail -------------------------------------------------------------
    def show_detail(self, rule: Rule, is_new: bool = False) -> None:
        self.clear_detail()
        form = RuleForm.from_actions(rule.actions)
        self.attach_banner(lambda: do_save())
        self.detail_header("New rule" if is_new else rule.name, rule.render() if not is_new else "fill in the criteria and actions, then Test or Save")

        g_meta = Adw.PreferencesGroup(title="Rule")
        name_row = entry_row("Name", rule.name)
        kind_row = combo_row("Kind", list(KINDS), rule.kind, "for_window: on map · assign: workspace/output at map · no_focus")
        scope_row = combo_row("Scope", list(SCOPES), rule.scope, f"common = every machine · profile = only {paths.profile_name()}")
        enabled_row = switch_row("Enabled", rule.enabled)
        for r in (name_row, kind_row, scope_row, enabled_row):
            g_meta.add(r)
        self.detail.append(g_meta)

        g_crit = Adw.PreferencesGroup(title="Criteria", description="POSIX regex, unanchored, case-sensitive (like sway). Empty = ignored.")
        crit_rows: dict[str, Adw.EntryRow] = {}
        for key in CRIT_TEXT:
            r = entry_row(key, rule.criteria.get(key, ""))
            if key == "app_id":
                pick_btn = Gtk.Button(icon_name="focus-windows-symbolic", valign=Gtk.Align.CENTER, tooltip_text="Take from an open window")
                pick_btn.add_css_class("flat")
                pick_btn.connect("clicked", lambda *_: self._pick_into(crit_rows))
                r.add_suffix(pick_btn)
            crit_rows[key] = r
            g_crit.add(r)
        flag_floating = switch_row("floating", "floating" in rule.criteria, "only floating windows")
        flag_tiling = switch_row("tiling", "tiling" in rule.criteria, "only tiled windows")
        g_crit.add(flag_floating); g_crit.add(flag_tiling)
        self.detail.append(g_crit)

        g_act = Adw.PreferencesGroup(title="Actions")
        f_floating = combo_row("Floating", ON_OFF, form.floating)
        f_sticky = combo_row("Sticky", ON_OFF, form.sticky)
        f_full = combo_row("Fullscreen", ON_OFF, form.fullscreen)
        f_inh = combo_row("Inhibit idle", INHIBIT, form.inhibit_idle)
        roles = [m.id for m in self.ctl.state.monitors()]
        cur_role = rule.target.get("monitor", "") if rule.target else ""
        role_opts = ["(number below)"] + roles + ([cur_role] if cur_role and cur_role not in roles else [])
        f_role = combo_row("Target monitor (role)", role_opts, cur_role or "(number below)",
                           "symbolic: resolves to this machine's decade, renumbers if the group changes")
        f_slot = Adw.SpinRow.new_with_range(1, 10, 1); f_slot.set_title("Target slot (1-10)")
        f_slot.set_value(int(rule.target.get("slot", 1)) if rule.target else 1)
        f_ws = entry_row("Move to workspace (number)", form.workspace)
        f_out = entry_row("Move to output", form.output)
        f_rw = entry_row("Resize width", form.resize_w)
        f_rh = entry_row("Resize height", form.resize_h)
        f_center = switch_row("Center", form.center, "move position center")
        f_border = combo_row("Border", BORDERS, form.border)
        f_bpx = entry_row("Border px", form.border_px)
        f_op = entry_row("Opacity (0-1)", form.opacity)
        f_mark = entry_row("Mark", form.mark)
        f_layout = combo_row("Layout", LAYOUTS, form.layout)
        for r in (f_role, f_slot, f_ws, f_out, f_floating, f_sticky, f_full, f_inh, f_rw, f_rh, f_center, f_border, f_bpx, f_op, f_mark, f_layout):
            g_act.add(r)
        self.detail.append(g_act)

        f_blur = f_shadows = f_cr = None
        if self.ctl.swayfx:
            g_fx = Adw.PreferencesGroup(title="SwayFX")
            f_blur = combo_row("Blur", ON_OFF, form.blur)
            f_shadows = combo_row("Shadows", ON_OFF, form.shadows)
            f_cr = entry_row("Corner radius", form.corner_radius)
            for r in (f_blur, f_shadows, f_cr):
                g_fx.add(r)
            self.detail.append(g_fx)

        g_adv = Adw.PreferencesGroup(title="Advanced", description="One sway command per line; appended verbatim.")
        adv = Gtk.TextView(monospace=True, accepts_tab=False)
        adv.get_buffer().set_text("\n".join(form.advanced))
        adv.set_size_request(-1, 70)
        adv_frame = Gtk.Frame()
        adv_frame.set_child(adv)
        g_adv.add(adv_frame)
        self.detail.append(g_adv)

        preview = Gtk.Label(xalign=0, wrap=True, selectable=True)
        preview.add_css_class("sa-mono")
        preview.add_css_class("dim-label")
        self.detail.append(section("Preview"))
        self.detail.append(preview)

        def collect() -> Rule:
            crit = {k: r.get_text().strip() for k, r in crit_rows.items() if r.get_text().strip()}
            if flag_floating.get_active():
                crit["floating"] = "true"
            if flag_tiling.get_active():
                crit["tiling"] = "true"
            f = RuleForm(
                floating=combo_value(f_floating), sticky=combo_value(f_sticky), fullscreen=combo_value(f_full),
                inhibit_idle=combo_value(f_inh), workspace=f_ws.get_text(), output=f_out.get_text(),
                resize_w=f_rw.get_text(), resize_h=f_rh.get_text(), center=f_center.get_active(),
                border=combo_value(f_border), border_px=f_bpx.get_text(), opacity=f_op.get_text(),
                mark=f_mark.get_text(), layout=combo_value(f_layout),
                blur=combo_value(f_blur) if f_blur else "", shadows=combo_value(f_shadows) if f_shadows else "",
                corner_radius=f_cr.get_text() if f_cr else "",
                advanced=[l for l in adv.get_buffer().get_text(*adv.get_buffer().get_bounds(), False).splitlines() if l.strip()],
            )
            kind = combo_value(kind_row)
            actions = f.to_actions()
            if kind == "assign":
                # assign takes exactly one target: workspace or output
                if f.workspace.strip():
                    ws = f.workspace.strip()
                    actions = [f"workspace number {ws}" if ws.isdigit() else f"workspace {ws}"]
                elif f.output.strip():
                    actions = [f"output {f.output.strip()}"]
            elif kind == "no_focus":
                actions = []
            new = Rule(id=rule.id, kind=kind, criteria=crit, actions=actions, name=name_row.get_text().strip(),
                       enabled=enabled_row.get_active(), notes=rule.notes, scope=combo_value(scope_row))
            role_sel = combo_value(f_role)
            if role_sel and role_sel != "(number below)" and kind != "no_focus":
                new.target = {"monitor": role_sel, "slot": int(f_slot.get_value())}
                n, _prob = self.ctl.state.resolve_target(new)
                if n is not None:
                    new.actions = new.with_workspace_number(n).actions
            else:
                new.target = None
            if is_new or new.criteria_key() != rule.criteria_key():
                # criteria changed -> identity changes, unless editing keeps the same id on purpose
                new.id = new.default_id() if is_new else rule.id
            if not new.name:
                new.name = new.default_name()
            return new

        baseline = rule.render() + "|" + str(rule.enabled) + "|" + rule.scope + "|" + rule.name

        def update_preview(*_a) -> None:
            r = collect()
            probs = r.problems()
            _n, tprob = self.ctl.state.resolve_target(r)
            if tprob:
                probs = probs + [tprob]
            preview.set_text(r.render() + ("\n⚠ " + "; ".join(probs) if probs else ""))
            now = r.render() + "|" + str(r.enabled) + "|" + r.scope + "|" + r.name
            if is_new or now != baseline:
                self.mark_dirty(do_save)
            else:
                self.clear_dirty()
        update_preview()
        for r in list(crit_rows.values()) + [f_ws, f_out, f_rw, f_rh, f_bpx, f_op, f_mark, name_row] + ([f_cr] if f_cr else []):
            r.connect("changed", update_preview)
        for r in [f_floating, f_sticky, f_full, f_inh, f_border, f_layout, kind_row, scope_row, f_role] + ([f_blur, f_shadows] if f_blur else []):
            r.connect("notify::selected", update_preview)
        f_slot.connect("notify::value", update_preview)
        for r in (flag_floating, flag_tiling, f_center, enabled_row):
            r.connect("notify::active", update_preview)
        adv.get_buffer().connect("changed", update_preview)

        def do_test() -> None:
            r = collect()
            out = self.win.run_outcome(lambda: self.ctl.test_rule(r))
            if out is not None and out.ok:
                wins = self.ctl.matching_windows(r)
                if not wins:
                    self.win.toast("No open window matches these criteria")

        def do_match() -> None:
            wins = self.ctl.matching_windows(collect())
            self.win.toast(("Matches: " + ", ".join(f"{w.label} (ws {w.workspace})" for w in wins)) if wins else "No open window matches")

        def do_save() -> None:
            r = collect()
            out = self.win.run_outcome(lambda: self.ctl.save_rule(r, r.scope))
            if out is not None and out.ok:
                self.clear_dirty()
                self.selected_id = r.id
                self._draft = None
                self.refresh()

        def do_delete() -> None:
            confirm(self.win, "Remove rule?", rule.render(), "Remove", lambda: (
                self.win.run_outcome(lambda: self.ctl.delete_rule(rule)), self.show_placeholder(), self.refresh()))

        btns = [button("Match", do_match), button("Test", do_test, icon="media-playback-start-symbolic"),
                button("Save & apply", do_save, style="suggested-action", icon="document-save-symbolic")]
        if not is_new:
            btns.insert(0, button("Delete", do_delete, style="destructive-action"))
        self.action_bar(*btns)

    def _pick_into(self, crit_rows: dict[str, Adw.EntryRow]) -> None:
        pop = Gtk.Popover()
        lb = Gtk.ListBox()
        lb.add_css_class("sa-list")
        for w in (swayipc.windows() if swayipc.available() else []):
            row = list_row(w.label, (w.title or "")[:60], [(f"ws {w.workspace}", "")])
            row.window = w  # type: ignore[attr-defined]
            lb.append(row)

        def pick(_lb, row):
            w = row.window
            pop.popdown()
            if w.app_id:
                crit_rows["app_id"].set_text(w.app_id)
            elif w.cls:
                crit_rows["class"].set_text(w.cls)
            if w.instance:
                crit_rows["instance"].set_text("")
        lb.connect("row-activated", pick)
        sw = scrolled(lb)
        sw.set_size_request(420, 320)
        pop.set_child(sw)
        pop.set_parent(crit_rows["app_id"])
        pop.popup()


# ==========================================================================
# Startup

class StartupPanel(Panel):
    def __init__(self, win) -> None:
        super().__init__(win, "Startup apps")
        self.header_button("Run all", self.run_all, icon="media-playback-start-symbolic", style="suggested-action")
        self.header_button("Add", self.new_entry, icon="list-add-symbolic", start=False)
        self.header_button("Add from apps", lambda: self.win.show_section("apps"), icon="view-app-grid-symbolic", start=False)
        self.progress = Gtk.Label(xalign=0, wrap=True)
        self.progress.add_css_class("dim-label")
        self.progress.set_margin_start(12); self.progress.set_margin_bottom(6)
        self.insert_child_after(self.progress, self.toolbar)

    def refresh(self) -> None:
        self.ctl.reload_state()
        items = self.ctl.state.startup()
        q = self.query()
        if q:
            items = [e for e in items if q in e.name.lower() or q in e.command.lower() or q in e.app_id.lower()]
        rows = []
        for e in items:
            sub = e.command + (f"  →  ws {e.workspace}" if e.workspace else "") + (f"  ({e.app_id})" if e.app_id else "")
            sw = Gtk.Switch(active=e.enabled, valign=Gtk.Align.CENTER)
            sw.connect("state-set", lambda _s, state, entry=e: self._toggle(entry, state))
            rows.append((e.id, list_row(f"{e.order:>3}  {e.name}", sub, [(e.scope, e.scope)], disabled=not e.enabled, trailing=sw), e))
        self.fill_list(rows)
        self.toolbar.get_title_widget().set_subtitle(f"{sum(1 for e in items if e.enabled)} enabled · manual only, in order")

    def _toggle(self, e: StartupEntry, state: bool) -> bool:
        e.enabled = state
        self.win.run_outcome(lambda: self.ctl.save_startup(e, e.scope))
        GLib.idle_add(self.refresh)
        return False

    def _say(self, text: str) -> None:
        GLib.idle_add(self.progress.set_text, text)

    def run_all(self, only: list[str] | None = None) -> None:
        if not swayipc.available():
            self.win.toast("No sway socket", error=True)
            return
        self.progress.set_text("Running…")

        def done(results: list[dict]) -> None:
            ok = sum(1 for r in results if r.get("launched"))
            placed = sum(r.get("placed", 0) for r in results)
            errs = [r for r in results if r.get("error") or r.get("timeout")]
            msg = f"Startup: {ok}/{len(results)} launched, {placed} window(s) placed" + (f", {len(errs)} issue(s)" if errs else "")
            GLib.idle_add(self.progress.set_text, msg)
            GLib.idle_add(self.win.toast, msg, bool(errs))
        self.ctl.run_startup_async(only, self._say, done)

    def new_entry(self, entry: StartupEntry | None = None) -> None:
        self.listbox.unselect_all()
        self.selected_id = None
        self.show_detail(entry or StartupEntry(id="", name="", command=""), is_new=True)

    def new_entry_from_app(self, app: discover.App) -> None:
        self.new_entry(StartupEntry(id="", name=app.name, command=app.command, app_id=app.app_id_guess, desktop_id=app.desktop_id,
                                    wait_seconds=30))
        self.win.show_section("startup")

    def new_entry_from_window(self, w: swayipc.Window) -> None:
        cmd = ""
        for a in discover.apps(include_hidden=True):
            if w.app_id and (a.app_id_guess == w.app_id or w.app_id in a.app_id_candidates):
                cmd = a.command
                break
        self.new_entry(StartupEntry(id="", name=w.label, command=cmd, app_id=w.app_id or "", workspace=str(w.workspace_num or "")))
        self.win.show_section("startup")

    def show_detail(self, e: StartupEntry, is_new: bool = False) -> None:
        self.clear_detail()
        self.attach_banner(lambda: do_save())
        self.detail_header("New startup entry" if is_new else e.name, e.command if not is_new else "command is launched via `swaymsg exec`")
        g = Adw.PreferencesGroup(title="Entry")
        name = entry_row("Name", e.name)
        cmd = entry_row("Command", e.command)
        app_id = entry_row("Expected app_id (regex)", e.app_id)
        pick_btn = Gtk.Button(icon_name="focus-windows-symbolic", valign=Gtk.Align.CENTER, tooltip_text="Take from an open window")
        pick_btn.add_css_class("flat")
        app_id.add_suffix(pick_btn)
        ws = entry_row("Workspace", e.workspace)
        wait = Adw.SpinRow.new_with_range(0, 600, 5); wait.set_title("Wait for window (s)"); wait.set_value(e.wait_seconds)
        settle = Adw.SpinRow.new_with_range(0, 60, 0.5); settle.set_title("Settle (s)"); settle.set_digits(1); settle.set_value(e.settle_seconds)
        order = Adw.SpinRow.new_with_range(0, 9999, 10); order.set_title("Order"); order.set_value(e.order)
        scope = combo_row("Scope", list(SCOPES), e.scope)
        enabled = switch_row("Enabled", e.enabled)
        notes = entry_row("Notes", e.notes)
        for r in (name, cmd, app_id, ws, wait, settle, order, scope, enabled, notes):
            g.add(r)
        self.detail.append(g)

        def pick(*_a) -> None:
            pop = Gtk.Popover()
            lb = Gtk.ListBox(); lb.add_css_class("sa-list")
            for w in (swayipc.windows() if swayipc.available() else []):
                row = list_row(w.label, (w.title or "")[:60], [(f"ws {w.workspace}", "")]); row.window = w; lb.append(row)  # type: ignore[attr-defined]

            def chosen(_lb, row):
                pop.popdown(); app_id.set_text(row.window.app_id or row.window.cls or "")
                if not ws.get_text():
                    ws.set_text(str(row.window.workspace_num or ""))
            lb.connect("row-activated", chosen)
            sw = scrolled(lb); sw.set_size_request(420, 320); pop.set_child(sw); pop.set_parent(app_id); pop.popup()
        pick_btn.connect("clicked", pick)

        def collect() -> StartupEntry:
            from ..cli import _entry_id
            return StartupEntry(
                id=e.id or _entry_id(name.get_text(), cmd.get_text()), name=name.get_text().strip() or cmd.get_text().split()[0] if cmd.get_text().strip() else "",
                command=cmd.get_text().strip(), app_id=app_id.get_text().strip(), workspace=ws.get_text().strip(),
                wait_seconds=int(wait.get_value()), settle_seconds=float(settle.get_value()), enabled=enabled.get_active(),
                order=int(order.get_value()), notes=notes.get_text(), desktop_id=e.desktop_id, scope=combo_value(scope))

        def do_save() -> None:
            n = collect()
            out = self.win.run_outcome(lambda: self.ctl.save_startup(n, n.scope))
            if out is not None and out.ok:
                self.clear_dirty()
                self.selected_id = n.id
                self.refresh()

        def _dirty(*_a) -> None:
            self.mark_dirty(do_save)
        for r in (name, cmd, app_id, ws, notes):
            r.connect("changed", _dirty)
        for r in (wait, settle, order):
            r.connect("notify::value", _dirty)
        for r in (enabled,):
            r.connect("notify::active", _dirty)
        scope.connect("notify::selected", _dirty)
        if is_new:
            self.mark_dirty(do_save)

        def do_run() -> None:
            n = collect()
            if n.problems():
                self.win.toast("Invalid entry: " + "; ".join(n.problems()), error=True)
                return
            self.progress.set_text(f"Running {n.name}…")
            self.ctl.state.save_startup(n, n.scope) if not is_new else None
            from .. import startup as _startup
            import threading

            def worker():
                try:
                    r = _startup.run_entry(n, self._say)
                    msg = f"{n.name}: {len(r.get('windows', []))} window(s), {r.get('placed', 0)} placed" + (" (timeout waiting for app_id)" if r.get("timeout") else "")
                    GLib.idle_add(self.win.toast, msg, bool(r.get("timeout")))
                except Exception as exc:
                    GLib.idle_add(self.win.toast, f"Run failed: {exc}", True)
                GLib.idle_add(self.progress.set_text, "")
            threading.Thread(target=worker, daemon=True).start()

        def do_delete() -> None:
            confirm(self.win, "Remove startup entry?", e.command, "Remove", lambda: (
                self.win.run_outcome(lambda: self.ctl.delete_startup(e)), self.show_placeholder(), self.refresh()))

        btns = [button("Run", do_run, icon="media-playback-start-symbolic"), button("Save", do_save, style="suggested-action", icon="document-save-symbolic")]
        if not is_new:
            btns.insert(0, button("Delete", do_delete, style="destructive-action"))
        self.action_bar(*btns)


# ==========================================================================
# Apps

class AppsPanel(Panel):
    SOURCES = ["all sources", "nix-profile", "system", "user", "flatpak-user", "flatpak-system", "other"]

    def __init__(self, win) -> None:
        super().__init__(win, "Applications")
        self.source = Gtk.DropDown.new_from_strings(self.SOURCES)
        self.source.connect("notify::selected", lambda *_: self.refresh())
        self.toolbar.pack_start(self.source)
        self.hidden = Gtk.ToggleButton(label="hidden")
        self.hidden.set_tooltip_text("Include NoDisplay entries")
        self.hidden.connect("toggled", lambda *_: self.refresh())
        self.toolbar.pack_start(self.hidden)
        self.header_button("Rescan", self.refresh, icon="view-refresh-symbolic", start=False)
        self._cache: list[discover.App] = []
        self._cache_key: tuple | None = None

    def refresh(self) -> None:
        key = (self.hidden.get_active(),)
        if key != self._cache_key:
            self._cache = discover.apps(include_hidden=self.hidden.get_active())
            self._cache_key = key
        items = self._cache
        s = self.source.get_selected()
        if s > 0:
            items = [a for a in items if a.source == self.SOURCES[s]]
        q = self.query()
        if q:
            items = [a for a in items if q in a.name.lower() or q in a.desktop_id.lower() or q in a.app_id_guess.lower()]
        rows = []
        for a in items:
            chips = [(a.source, "flatpak" if a.source.startswith("flatpak") else "")]
            rows.append((a.desktop_id, list_row(a.name, f"{a.desktop_id}  ·  app_id≈{a.app_id_guess}", chips), a))
        self.fill_list(rows)
        self.toolbar.get_title_widget().set_subtitle(f"{len(items)} shown · {len(self._cache)} discovered")

    def show_detail(self, a: discover.App) -> None:
        self.clear_detail()
        self.detail_header(a.name, a.path)
        g = Adw.PreferencesGroup(title="Desktop entry")
        for title, val in (("Desktop id", a.desktop_id), ("Source", a.source), ("Exec", a.exec), ("Command", a.command),
                           ("StartupWMClass", a.startup_wm_class or "—"), ("Flatpak id", a.flatpak_id or "—"),
                           ("Categories", ", ".join(a.categories) or "—")):
            r = Adw.ActionRow(title=title, subtitle=val)
            r.set_subtitle_selectable(True)
            g.add(r)
        self.detail.append(g)
        g2 = Adw.PreferencesGroup(title="app_id", description="Best guess first; learned values come from watching the real window.")
        for i, c in enumerate(a.app_id_candidates):
            r = Adw.ActionRow(title=c, subtitle="learned" if c == a.learned_app_id else ("guess" if i == 0 else "candidate"))
            open_ = [w for w in (swayipc.windows() if swayipc.available() else []) if swayipc.window_matches(w, {"app_id": f"^{c}$"})]
            if open_:
                r.add_suffix(chip(f"{len(open_)} open", "ok"))
            g2.add(r)
        self.detail.append(g2)

        def launch() -> None:
            self.win.toast(f"Launching {a.name}…")

            def done(res: dict) -> None:
                if res.get("learned_app_id"):
                    msg = f"{a.name}: learned app_id {res['learned_app_id']}"
                    self._cache_key = None
                elif res.get("launched"):
                    msg = f"{a.name}: {len(res.get('windows', []))} window(s) seen"
                else:
                    msg = f"{a.name}: {res.get('error', 'not launched')}"
                GLib.idle_add(self.win.toast, msg, not res.get("launched"))
                GLib.idle_add(self.refresh)
            self.ctl.launch_app_async(a, "", done)

        self.action_bar(
            button("Launch & learn app_id", launch, icon="media-playback-start-symbolic"),
            button("New rule", lambda: (self.win.panels["rules"].new_rule({"app_id": a.app_id_guess}, a.name), self.win.show_section("rules")), icon="view-grid-symbolic"),
            button("New shortcut", lambda: self.win.panels["shortcuts"].new_from_app(a), icon="input-keyboard-symbolic"),
            button("Add to startup", lambda: self.win.panels["startup"].new_entry_from_app(a), style="suggested-action", icon="list-add-symbolic"),
        )


# ==========================================================================
# Windows

class WindowsPanel(Panel):
    def __init__(self, win) -> None:
        super().__init__(win, "Open windows")
        self.header_button("Refresh", self.refresh, icon="view-refresh-symbolic")
        self.auto = Gtk.ToggleButton(label="auto", active=True)
        self.auto.set_tooltip_text("Refresh every 3 s while visible")
        self.toolbar.pack_start(self.auto)
        GLib.timeout_add_seconds(3, self._tick)

    def _tick(self) -> bool:
        if self.auto.get_active() and self.get_mapped():
            self.refresh()
        return True

    def refresh(self) -> None:
        wins = swayipc.windows() if swayipc.available() else []
        q = self.query()
        if q:
            wins = [w for w in wins if q in (w.app_id or "").lower() or q in (w.cls or "").lower() or q in (w.title or "").lower()]
        wins.sort(key=lambda w: ((w.workspace_num or 0), w.label.lower()))
        rows = []
        for w in wins:
            chips = [(f"ws {w.workspace}", ""), ("floating" if w.floating else "tiled", "")]
            if w.focused:
                chips.append(("focused", "ok"))
            rows.append((str(w.id), list_row(w.label, w.title or "", chips), w))
        self.fill_list(rows)
        self.toolbar.get_title_widget().set_subtitle(f"{len(wins)} windows" if swayipc.available() else "no sway socket")

    def show_detail(self, w: swayipc.Window) -> None:
        self.clear_detail()
        self.detail_header(w.label, w.title or "")
        g = Adw.PreferencesGroup(title="Identity")
        for title, val in (("app_id", w.app_id), ("class", w.cls), ("instance", w.instance), ("window_role", w.window_role),
                           ("shell", w.shell), ("pid", w.pid), ("con_id", w.id), ("workspace", w.workspace), ("output", w.output),
                           ("mode", "floating" if w.floating else "tiled"), ("sticky", w.sticky), ("fullscreen", w.fullscreen), ("marks", ", ".join(w.marks) or "—")):
            r = Adw.ActionRow(title=title, subtitle=str(val) if val not in (None, "") else "—")
            r.set_subtitle_selectable(True)
            g.add(r)
        self.detail.append(g)
        rules = [r for r in self.ctl.state.rules() if swayipc.window_matches(w, r.criteria)]
        g2 = Adw.PreferencesGroup(title=f"Matching rules ({len(rules)})")
        for r in rules:
            row = Adw.ActionRow(title=r.name, subtitle=r.render())
            row.set_subtitle_selectable(True)
            if not r.enabled:
                row.add_suffix(chip("disabled", "warn"))
            g2.add(row)
        if not rules:
            g2.add(Adw.ActionRow(title="No rule matches this window"))
        self.detail.append(g2)
        self.action_bar(
            button("Focus", lambda: swayipc.command(f"[con_id={w.id}] focus")),
            button("Add to startup", lambda: self.win.panels["startup"].new_entry_from_window(w), icon="list-add-symbolic"),
            button("New rule from window", lambda: self.win.panels["rules"].new_rule_from_window(w), style="suggested-action", icon="view-grid-symbolic"),
        )


# ==========================================================================
# Log

class LogPanel(Gtk.Box):
    def __init__(self, win) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win = win
        self.toolbar = Adw.HeaderBar()
        self.toolbar.set_title_widget(Adw.WindowTitle(title="Log", subtitle=str(paths.LOG_FILE)))
        self.append(self.toolbar)
        self.filter = Gtk.SearchEntry(placeholder_text="filter…")
        self.filter.connect("search-changed", lambda *_: self.refresh())
        self.toolbar.pack_start(self.filter)
        self.level = Gtk.DropDown.new_from_strings(["all", "info+", "warning+", "error"])
        self.level.set_selected(1)
        self.level.connect("notify::selected", lambda *_: self.refresh())
        self.toolbar.pack_start(self.level)
        self.follow = Gtk.ToggleButton(label="follow", active=True)
        self.toolbar.pack_end(self.follow)
        self.toolbar.pack_end(button("Refresh", self.refresh, icon="view-refresh-symbolic"))
        self.view = Gtk.TextView(editable=False, monospace=True, cursor_visible=False)
        self.view.set_left_margin(10); self.view.set_top_margin(6)
        self.add_css_class("sa-log")
        self.append(scrolled(self.view))
        self._size = -1
        GLib.timeout_add_seconds(2, self._tick)

    def on_show(self) -> None:
        self.refresh()

    def _tick(self) -> bool:
        if self.follow.get_active() and self.get_mapped():
            try:
                size = paths.LOG_FILE.stat().st_size
            except OSError:
                size = -1
            if size != self._size:
                self.refresh()
        return True

    def refresh(self) -> None:
        try:
            lines = paths.LOG_FILE.read_text(errors="replace").splitlines()
            self._size = paths.LOG_FILE.stat().st_size
        except OSError:
            lines = ["(no log yet)"]
        lvl = self.level.get_selected()
        if lvl == 1:
            lines = [l for l in lines if " DEBUG " not in l]
        elif lvl == 2:
            lines = [l for l in lines if " WARNING " in l or " ERROR " in l or " CRITICAL " in l]
        elif lvl == 3:
            lines = [l for l in lines if " ERROR " in l or " CRITICAL " in l]
        q = self.filter.get_text().strip().lower()
        if q:
            lines = [l for l in lines if q in l.lower()]
        lines = lines[-2000:]
        buf = self.view.get_buffer()
        buf.set_text("\n".join(lines))
        if self.follow.get_active():
            end = buf.get_end_iter()
            self.view.scroll_to_iter(end, 0.0, False, 0, 0)
