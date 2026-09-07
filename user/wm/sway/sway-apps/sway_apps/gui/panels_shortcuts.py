"""Shortcuts: tool-owned bindings (editable) + nix-owned ones (read-only, greyed)."""
from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, GLib, Gtk  # noqa: E402

from .. import discover, log, shortcuts as sc_mod  # noqa: E402
from ..shortcuts import CATEGORIES, KINDS, TMUX_TABLES, Shortcut  # noqa: E402
from ..state import SCOPES  # noqa: E402
from .panels import Panel  # noqa: E402
from .widgets import button, chip, combo_row, combo_value, confirm, entry_row, list_row, scrolled, switch_row  # noqa: E402

_log = log.get("gui.shortcuts")

_MOD_NAMES = {Gdk.ModifierType.SUPER_MASK: "Super", Gdk.ModifierType.CONTROL_MASK: "Ctrl",
              Gdk.ModifierType.ALT_MASK: "Alt", Gdk.ModifierType.SHIFT_MASK: "Shift"}


def _keyval_to_sway(keyval: int, state: Gdk.ModifierType) -> str | None:
    name = Gdk.keyval_name(keyval)
    if not name or name in ("Super_L", "Super_R", "Control_L", "Control_R", "Alt_L", "Alt_R", "Shift_L", "Shift_R",
                            "Meta_L", "Meta_R", "Hyper_L", "Hyper_R", "ISO_Level3_Shift"):
        return None
    mods = [n for m, n in _MOD_NAMES.items() if state & m]
    if all(x in mods for x in ("Super", "Ctrl", "Alt")):
        mods = ["Hyper"] + [m for m in mods if m not in ("Super", "Ctrl", "Alt")]
    # single-letter keysyms: sway folds case, store lower for clarity
    if len(name) == 1:
        name = name.lower()
    return "+".join(mods + [name])


class ShortcutsPanel(Panel):
    def __init__(self, win) -> None:
        super().__init__(win, "Shortcuts")
        self.header_button("New shortcut", self.new_shortcut, icon="list-add-symbolic", style="suggested-action", start=False)
        self.show_nix = Gtk.ToggleButton(label="show nix", active=True)
        self.show_nix.set_tooltip_text("Also list the bindings nix owns (read-only)")
        self.show_nix.connect("toggled", lambda *_: self.refresh())
        self.toolbar.pack_start(self.show_nix)
        self.header_button("Free keys", self.show_free, icon="input-keyboard-symbolic")

    def show_free(self) -> None:
        used = {b["fold"] for b in sc_mod.nix_bindings()} | {sc_mod.fold(x.keys) for x in self.ctl.state.shortcuts() if not x.problems()}
        free_h = [k for k in "abcdefghijklmnopqrstuvwxyz" if "Mod4+Control+Mod1+" + k not in used]
        free_hs = [k for k in "abcdefghijklmnopqrstuvwxyz" if "Mod4+Control+Mod1+Shift+" + k not in used]
        self.win.toast(f"Free: Hyper+{' '.join(free_h) or '(none)'} · Hyper+Shift+{' '.join(free_hs) or '(none)'}", timeout=10)

    @staticmethod
    def _tmux_label(table: str, key: str) -> str:
        return {"prefix": "Ctrl+O, ", "root": "", "copy-mode-vi": "[copy] "}[table] + key

    def refresh(self) -> None:
        self.ctl.reload_state()
        st = self.ctl.state
        items = st.shortcuts()
        nix = sc_mod.nix_bindings()
        tmux_nix = sc_mod.tmux_bindings()
        kitty = sc_mod.kitty_bindings()
        conf = sc_mod.conflicts(items, nix, tmux_nix)
        cross = sc_mod.cross_conflicts(items, nix, tmux_nix)
        shadowed = {c["tmux_key"] for c in cross}
        q = self.query()
        entries: list[tuple[str, str, Gtk.ListBoxRow, object]] = []  # category, id, row, item
        for x in items:
            hay = (x.keys + x.name + x.command + x.app_id).lower()
            if q and q not in hay:
                continue
            is_tmux = x.kind == "tmux"
            label = self._tmux_label(x.table, x.keys) if is_tmux else x.keys
            chips = [(x.program, "profile" if is_tmux else "common"), (x.scope, x.scope)]
            c = conf.get(x.id)
            if c and c["nix"]:
                chips.append(("overrides nix" if x.override else "BLOCKED: nix key", "profile" if x.override else "err"))
            if c and c["tool"]:
                chips.append(("duplicate", "err"))
            if is_tmux and x.table == "root" and x.keys in shadowed:
                chips.append(("shadowed by sway", "err"))
            cat = x.category or sc_mod.guess_category(x.command, x.program)
            entries.append((cat, x.id, list_row(f"{label}   ·   {x.name}", x.command if is_tmux else x.sway_command(), chips, disabled=not x.enabled), x))
        if self.show_nix.get_active():
            overridden = {c["nix"] for i, c in conf.items() if c["nix"] and st.shortcut(i).override and st.shortcut(i).enabled}
            for b in nix:
                if q and not (q in b["keys"].lower() or q in b["command"].lower()):
                    continue
                if b["command"] in overridden:
                    continue
                entries.append((b["category"], f"nix:{b['fold']}", list_row(b["keys"], b["command"], [("nix", "")], disabled=True), b))
            tool_tmux = {f"tmux|{x.table}|{x.keys}" for x in items if x.kind == "tmux" and x.enabled and x.override}
            for t in tmux_nix:
                if t["fold"] in tool_tmux or (q and not (q in t["keys"].lower() or q in t["command"].lower())):
                    continue
                chips = [("tmux · nix", "")]
                if t["table"] == "root" and t["keys"] in shadowed:
                    chips.append(("shadowed by sway", "err"))
                entries.append(("Terminal", "tmuxnix:" + t["fold"], list_row(self._tmux_label(t["table"], t["keys"]), t["command"], chips, disabled=True), t))
            for k in kitty:
                if q and not (q in k["keys"].lower() or q in k["command"].lower()):
                    continue
                entries.append(("Terminal", "kitty:" + k["fold"], list_row(k["keys"], k["command"], [("kitty · nix", "")], disabled=True), k))
        order = {c: i for i, c in enumerate(CATEGORIES)}
        entries.sort(key=lambda e: (order.get(e[0], 99), e[0], not isinstance(e[3], Shortcut), (e[3].keys if isinstance(e[3], Shortcut) else e[3]["keys"]).lower()))
        rows = []
        last = None
        for cat, iid, row, item in entries:
            if cat != last:
                hdr = Gtk.ListBoxRow(selectable=False, activatable=False)
                lbl = Gtk.Label(label=cat.upper(), xalign=0)
                lbl.add_css_class("sa-section-title"); lbl.set_margin_start(6); lbl.set_margin_top(10)
                hdr.set_child(lbl)
                rows.append((f"hdr:{cat}", hdr, None))
                last = cat
            rows.append((iid, row, item))
        self.fill_list(rows)
        self.toolbar.get_title_widget().set_subtitle(f"{len(items)} yours · {len(nix)} sway/nix · {len(tmux_nix)} tmux/nix · {len(kitty)} kitty · {len(cross)} shadowed")
        if cross:
            self.win.toast("A sway binding shadows a tmux root key: " + ", ".join(c["tmux_key"] for c in cross[:3]), error=True)

    def new_shortcut(self, prefill: Shortcut | None = None) -> None:
        self.listbox.unselect_all()
        self.selected_id = None
        self.show_detail(prefill or Shortcut(id="", keys="", kind="app"), is_new=True)

    def new_from_app(self, app: discover.App) -> None:
        self.new_shortcut(Shortcut(id="", keys="", kind="app", app_id=app.app_id_guess, command=app.command, name=app.name))
        self.win.show_section("shortcuts")

    def show_detail(self, item, is_new: bool = False) -> None:
        if item is None:  # category header
            return
        if isinstance(item, dict):  # nix-owned sway / tmux binding or kitty map
            self.clear_detail()
            prog = item.get("program", "sway")
            if prog == "tmux":
                self.detail_header(self._tmux_label(item["table"], item["keys"]), item["command"])
                g = Adw.PreferencesGroup(title="Owned by nix (tmux.conf)", description="Defined in user/app/terminal/tmux.nix. Read-only here; take it over with a tmux shortcut of your own (Override).")
                g.add(Adw.ActionRow(title="table", subtitle=item["table"]))
                self.detail.append(g)
                self.action_bar(button("Override this key…", lambda: self.new_shortcut(Shortcut(id="", keys=item["keys"], kind="tmux", table=item["table"], command=item["command"], override=True, category="Terminal")), style="suggested-action"))
                return
            if prog == "kitty":
                self.detail_header(item["keys"], item["command"])
                g = Adw.PreferencesGroup(title="Owned by nix (kitty.conf)", description="Defined in user/app/terminal/kitty.nix. Listed for completeness; not managed here.")
                self.detail.append(g)
                return
            self.detail_header(item["keys"], item["command"])
            g = Adw.PreferencesGroup(title="Owned by nix", description="Defined in user/wm/sway/swayfx-config.nix. Read-only here; you can take the key over with a shortcut of your own.")
            g.add(Adw.ActionRow(title="sway keys", subtitle=item["sway_keys"]))
            if item["flags"]:
                g.add(Adw.ActionRow(title="flags", subtitle=item["flags"]))
            g.add(Adw.ActionRow(title="category", subtitle=item.get("category", "")))
            self.detail.append(g)
            self.action_bar(button("Override this key…", lambda: self.new_shortcut(Shortcut(id="", keys=item["keys"], kind="exec", command="", override=True, category=item.get("category", ""))), style="suggested-action"))
            return
        x: Shortcut = item
        self.clear_detail()
        self.attach_banner(lambda: do_save())
        self.detail_header("New shortcut" if is_new else f"{(self._tmux_label(x.table, x.keys) if x.kind == 'tmux' else x.keys)}  ·  {x.name}", x.render() if not is_new and not x.problems() else "press the keys, pick what it does, Save & apply")

        g = Adw.PreferencesGroup(title="Keys")
        keys = entry_row("Key combination", x.keys)
        keys.set_tooltip_text("Hyper = Super+Ctrl+Alt (Caps Lock on this setup). Examples: Hyper+Shift+n, Super+Return, Hyper+F9")
        cap = Gtk.Button(icon_name="input-keyboard-symbolic", valign=Gtk.Align.CENTER, tooltip_text="Capture: click, then press the combination")
        cap.add_css_class("flat")
        keys.add_suffix(cap)
        g.add(keys)
        hint = Adw.ActionRow(title="Capture limits", subtitle="A combination sway already binds never reaches this window: type it by hand.")
        hint.add_css_class("dim-label")
        g.add(hint)
        self.detail.append(g)

        def start_capture(*_a) -> None:
            cap.set_icon_name("media-record-symbolic")
            self.win.toast("Press the key combination now (Esc cancels)", timeout=6)
            ctrl = Gtk.EventControllerKey()

            def on_key(_c, keyval, _code, state):
                if Gdk.keyval_name(keyval) == "Escape":
                    self.win.remove_controller(ctrl); cap.set_icon_name("input-keyboard-symbolic"); return True
                spec = _keyval_to_sway(keyval, state)
                if spec is None:
                    return True  # modifier alone: keep waiting
                keys.set_text(spec)
                self.win.remove_controller(ctrl)
                cap.set_icon_name("input-keyboard-symbolic")
                return True
            ctrl.connect("key-pressed", on_key)
            ctrl.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
            self.win.add_controller(ctrl)
        cap.connect("clicked", start_capture)

        g2 = Adw.PreferencesGroup(title="Action")
        kind = combo_row("Kind", list(KINDS), x.kind, "app: launch or focus via app-toggle.sh · exec: run a command · sway: a sway command · tmux: a tmux bind")
        table = combo_row("tmux key table", list(TMUX_TABLES), x.table if x.table in TMUX_TABLES else "prefix", "prefix = after Ctrl+O · root = no prefix (e.g. C-M-e) · copy-mode-vi")
        category = combo_row("Category", list(CATEGORIES) + ([x.category] if x.category and x.category not in CATEGORIES else []), x.category or "Apps")
        app_id = entry_row("app_id (or title:^regex)", x.app_id)
        pick = Gtk.Button(icon_name="view-app-grid-symbolic", valign=Gtk.Align.CENTER, tooltip_text="Pick from installed apps")
        pick.add_css_class("flat"); app_id.add_suffix(pick)
        command = entry_row("Command", x.command)
        name = entry_row("Name", x.name)
        for r in (kind, table, category, app_id, command, name):
            g2.add(r)
        self.detail.append(g2)

        def sync_kind(*_a) -> None:
            k = combo_value(kind)
            table.set_visible(k == "tmux")
            app_id.set_visible(k == "app")
            keys.set_title("tmux key (e, C-M-e, F5)" if k == "tmux" else "Key combination")
        kind.connect("notify::selected", sync_kind)
        sync_kind()

        def do_pick(*_a) -> None:
            pop = Gtk.Popover(); box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            search = Gtk.SearchEntry(placeholder_text="search apps…"); box.append(search)
            lb = Gtk.ListBox(); lb.add_css_class("sa-list")
            apps = discover.apps()

            def fill(q=""):
                lb.remove_all()
                for a in apps:
                    if q and q not in a.name.lower() and q not in a.desktop_id.lower():
                        continue
                    row = list_row(a.name, f"{a.app_id_guess} · {a.command[:50]}", [(a.source, "")]); row.app = a; lb.append(row)  # type: ignore[attr-defined]
            fill()
            search.connect("search-changed", lambda e: fill(e.get_text().lower()))

            def chosen(_lb, row):
                a = row.app; pop.popdown()
                app_id.set_text(a.app_id_guess); command.set_text(a.command)
                if not name.get_text():
                    name.set_text(a.name)
            lb.connect("row-activated", chosen)
            sw = scrolled(lb); sw.set_size_request(460, 320); box.append(sw); pop.set_child(box); pop.set_parent(app_id); pop.popup()
        pick.connect("clicked", do_pick)

        g3 = Adw.PreferencesGroup(title="Options")
        override = switch_row("Override nix binding", x.override, "take the key over from nix with unbindsym + bindsym")
        release = switch_row("On release", x.release, "bindsym --release")
        locked = switch_row("Also when locked", x.locked, "bindsym --locked")
        enabled = switch_row("Enabled", x.enabled)
        scope = combo_row("Scope", list(SCOPES), x.scope)
        notes = entry_row("Notes", x.notes)
        for r in (override, release, locked, enabled, scope, notes):
            g3.add(r)
        self.detail.append(g3)

        preview = Gtk.Label(xalign=0, wrap=True, selectable=True)
        preview.add_css_class("sa-mono"); preview.add_css_class("dim-label")
        self.detail.append(preview)

        def collect() -> Shortcut:
            k = combo_value(kind)
            return Shortcut(id=x.id or "", keys=keys.get_text().strip(), kind=k, app_id=app_id.get_text().strip() if k == "app" else "",
                            command=command.get_text().strip(), name=name.get_text().strip(), enabled=enabled.get_active(),
                            release=release.get_active(), locked=locked.get_active(), override=override.get_active(),
                            notes=notes.get_text(), category=combo_value(category), table=combo_value(table) if k == "tmux" else "prefix",
                            updated_at=x.updated_at, scope=combo_value(scope))

        baseline = x.to_dict()

        def update(*_a) -> None:
            s = collect()
            if not s.id:
                s.id = s.default_id()
            probs = s.problems()
            txt = s.render() if not probs else "⚠ " + "; ".join(probs)
            others = [y for y in self.ctl.state.shortcuts() if y.id != s.id and y.id != x.id]
            c = sc_mod.conflicts(others + [s]).get(s.id) if not probs else None
            if c and c["tool"]:
                txt += f"\n⚠ duplicate of shortcut {c['tool'][0]}"
            elif c and c["nix"]:
                txt += ("\n↳ overrides nix: " if s.override else "\n⚠ nix binds this key: ") + c["nix"][:80] + ("" if s.override else "  (enable Override)")
            preview.set_text(txt)
            d = s.to_dict(); d["id"] = baseline.get("id"); d["updated_at"] = baseline.get("updated_at")
            if is_new or d != baseline:
                self.mark_dirty(do_save)
            else:
                self.clear_dirty()
        for r in (keys, app_id, command, name, notes):
            r.connect("changed", update)
        kind.connect("notify::selected", update); scope.connect("notify::selected", update)
        table.connect("notify::selected", update); category.connect("notify::selected", update)
        for r in (override, release, locked, enabled):
            r.connect("notify::active", update)
        update()

        def do_save() -> None:
            s = collect()
            if not s.id:
                s.id = s.default_id()
            if not s.name:
                s.name = s.default_name()
            out = self.win.run_outcome(lambda: self.ctl.save_shortcut(s, s.scope))
            if out is not None and out.ok:
                self.clear_dirty(); self.selected_id = s.id; self.refresh()

        def do_delete() -> None:
            confirm(self.win, "Remove shortcut?", x.render() if not x.problems() else x.keys, "Remove", lambda: (
                self.win.run_outcome(lambda: self.ctl.delete_shortcut(x)), self.show_placeholder(), self.refresh()))

        btns = [button("Save & apply", do_save, style="suggested-action", icon="document-save-symbolic")]
        if not is_new:
            btns.insert(0, button("Delete", do_delete, style="destructive-action"))
        self.action_bar(*btns)
