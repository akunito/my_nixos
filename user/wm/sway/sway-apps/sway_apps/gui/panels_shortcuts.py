"""Shortcuts: tool-owned bindings (editable) + nix-owned ones (read-only, greyed)."""
from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, GLib, Gtk  # noqa: E402

from .. import discover, log, shortcuts as sc_mod  # noqa: E402
from ..shortcuts import KINDS, Shortcut  # noqa: E402
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

    def refresh(self) -> None:
        self.ctl.reload_state()
        st = self.ctl.state
        items = st.shortcuts()
        conf = sc_mod.conflicts(items)
        q = self.query()
        rows = []
        for x in items:
            if q and not (q in x.keys.lower() or q in x.name.lower() or q in x.command.lower() or q in x.app_id.lower()):
                continue
            chips = [(x.kind, x.kind if x.kind != "app" else "common"), (x.scope, x.scope)]
            c = conf.get(x.id)
            if c and c["nix"]:
                chips.append(("overrides nix" if x.override else "BLOCKED: nix key", "profile" if x.override else "err"))
            if c and c["tool"]:
                chips.append(("duplicate", "err"))
            rows.append((x.id, list_row(f"{x.keys}   ·   {x.name}", x.sway_command(), chips, disabled=not x.enabled), x))
        if self.show_nix.get_active():
            overridden = {c["nix"] for i, c in conf.items() if c["nix"] and st.shortcut(i).override and st.shortcut(i).enabled}
            for b in sorted(sc_mod.nix_bindings(), key=lambda b: b["fold"]):
                if q and not (q in b["keys"].lower() or q in b["command"].lower()):
                    continue
                if b["command"] in overridden:
                    continue
                row = list_row(b["keys"], b["command"], [("nix", "")], disabled=True)
                rows.append((f"nix:{b['fold']}", row, b))
        self.fill_list(rows)
        self.toolbar.get_title_widget().set_subtitle(f"{len(items)} yours · {len(sc_mod.nix_bindings())} nix · {sum(1 for c in conf.values() if c['nix'])} overrides")

    def new_shortcut(self, prefill: Shortcut | None = None) -> None:
        self.listbox.unselect_all()
        self.selected_id = None
        self.show_detail(prefill or Shortcut(id="", keys="", kind="app"), is_new=True)

    def new_from_app(self, app: discover.App) -> None:
        self.new_shortcut(Shortcut(id="", keys="", kind="app", app_id=app.app_id_guess, command=app.command, name=app.name))
        self.win.show_section("shortcuts")

    def show_detail(self, item, is_new: bool = False) -> None:
        if isinstance(item, dict):  # nix binding
            self.clear_detail()
            self.detail_header(item["keys"], item["command"])
            g = Adw.PreferencesGroup(title="Owned by nix", description="Defined in user/wm/sway/swayfx-config.nix. Read-only here; you can take the key over with a shortcut of your own.")
            g.add(Adw.ActionRow(title="sway keys", subtitle=item["sway_keys"]))
            if item["flags"]:
                g.add(Adw.ActionRow(title="flags", subtitle=item["flags"]))
            self.detail.append(g)
            self.action_bar(button("Override this key…", lambda: self.new_shortcut(Shortcut(id="", keys=item["keys"], kind="exec", command="", override=True)), style="suggested-action"))
            return
        x: Shortcut = item
        self.clear_detail()
        self.attach_banner(lambda: do_save())
        self.detail_header("New shortcut" if is_new else f"{x.keys}  ·  {x.name}", x.render() if not is_new and not x.problems() else "press the keys, pick what it does, Save & apply")

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
        kind = combo_row("Kind", list(KINDS), x.kind, "app: launch or focus via app-toggle.sh · exec: run a command · sway: a sway command")
        app_id = entry_row("app_id (or title:^regex)", x.app_id)
        pick = Gtk.Button(icon_name="view-app-grid-symbolic", valign=Gtk.Align.CENTER, tooltip_text="Pick from installed apps")
        pick.add_css_class("flat"); app_id.add_suffix(pick)
        command = entry_row("Command", x.command)
        name = entry_row("Name", x.name)
        for r in (kind, app_id, command, name):
            g2.add(r)
        self.detail.append(g2)

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
                            notes=notes.get_text(), updated_at=x.updated_at, scope=combo_value(scope))

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
