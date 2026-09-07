"""Profiles (see other machines' layers, copy across, snapshots) and NFS."""
from __future__ import annotations

import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402

from .. import generate, gitsync, log, nfsctl, paths, profiles as pf  # noqa: E402
from .panels import Panel  # noqa: E402
from .widgets import button, chip, confirm, list_row, scrolled  # noqa: E402

_log = log.get("gui.sync")


def _bg(fn, done):
    def worker():
        try:
            r, err = fn(), None
        except Exception as exc:  # noqa: BLE001
            r, err = None, exc
            _log.warning("background task failed: %s", exc)
        GLib.idle_add(lambda: (done(r, err), False)[1])
    threading.Thread(target=worker, daemon=True).start()


# ==========================================================================
# Profiles

class ProfilesPanel(Gtk.Box):
    """Left: pick section + other profile; centre: items with checkboxes and
    where they live; right: actions (pull here / push there / snapshots)."""

    def __init__(self, win) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win = win; self.ctl = win.ctl
        self.toolbar = Adw.HeaderBar(); self.toolbar.set_title_widget(Adw.WindowTitle(title="Profiles", subtitle="compare and copy configuration between machines"))
        self.append(self.toolbar)
        self.section = Gtk.DropDown.new_from_strings(list(pf.SECTIONS)); self.section.set_selected(2)
        self.section.connect("notify::selected", lambda *_: self.refresh())
        self.other = Gtk.DropDown.new_from_strings(["(other profile)"]); self.other.connect("notify::selected", lambda *_: self.refresh())
        self.toolbar.pack_start(self.section); self.toolbar.pack_start(self.other)
        self.toolbar.pack_end(button("Snapshots", self.show_snapshots, icon="document-open-recent-symbolic"))
        self.toolbar.pack_end(button("Snapshot now", self.snapshot_now, icon="camera-photo-symbolic"))
        self.info = Gtk.Label(xalign=0, wrap=True); self.info.add_css_class("dim-label"); self.info.set_margin_start(12); self.info.set_margin_top(6)
        self.append(self.info)
        self.listbox = Gtk.ListBox(); self.listbox.set_selection_mode(Gtk.SelectionMode.NONE); self.listbox.add_css_class("sa-list")
        self.append(scrolled(self.listbox))
        bar = Gtk.Box(spacing=8, margin_top=8, margin_bottom=8, margin_start=12, margin_end=12)
        self.sel_all = button("Select all", lambda: self._select(True)); self.sel_none = button("None", lambda: self._select(False))
        self.pull_btn = button("Pull selected → here", self.pull, style="suggested-action", icon="go-down-symbolic")
        self.push_btn = button("Push selected → other", self.push, icon="go-up-symbolic")
        for b in (self.sel_all, self.sel_none, Gtk.Box(hexpand=True), self.pull_btn, self.push_btn):
            bar.append(b)
        self.append(bar)
        self._checks: list[tuple[Gtk.CheckButton, str, str]] = []  # (check, id, side)

    def on_show(self, section: str | None = None) -> None:
        names = [n for n in pf.profile_files() if n != paths.profile_name()]
        cur = self.other.get_selected_item().get_string() if self.other.get_selected_item() else None
        self.other.set_model(Gtk.StringList.new(names or ["(no other profile)"]))
        if cur in names:
            self.other.set_selected(names.index(cur))
        if section in pf.SECTIONS:
            self.section.set_selected(list(pf.SECTIONS).index(section))
        self.refresh()

    def _sel_section(self) -> str:
        return list(pf.SECTIONS)[self.section.get_selected()]

    def _sel_other(self) -> str | None:
        it = self.other.get_selected_item()
        n = it.get_string() if it else None
        return n if n and not n.startswith("(") else None

    def refresh(self) -> None:
        self.listbox.remove_all(); self._checks = []
        other, sec, me = self._sel_other(), self._sel_section(), paths.profile_name()
        if not other:
            self.info.set_text("No other profile layer in the repo yet."); return
        d = pf.diff(other, me, sec)
        common_items = pf.layer("common").get(sec, [])
        self.info.set_text(f"{sec}: {len(d['only_a'])} only in {other} · {len(d['only_b'])} only in {me} · {len(d['changed'])} differ · {len(d['same'])} same · {len(common_items)} shared in common.json")

        def add_group(title: str, items: list[dict], side: str, style: str):
            if not items:
                return
            hdr = Gtk.ListBoxRow(selectable=False, activatable=False)
            l = Gtk.Label(label=title.upper(), xalign=0); l.add_css_class("sa-section-title"); l.set_margin_start(6); l.set_margin_top(10); hdr.set_child(l)
            self.listbox.append(hdr)
            for x in items:
                cb = Gtk.CheckButton(); cb.set_valign(Gtk.Align.CENTER)
                row = list_row(pf.label(sec, x), f"id {x.get('id')}", [(side, style)], trailing=cb)
                row.set_activatable(False)
                self.listbox.append(row); self._checks.append((cb, x["id"], side))
        if not any(d.values()):
            row = Gtk.ListBoxRow(selectable=False, activatable=False)
            row.set_child(Gtk.Label(label=f"Neither {other} nor {me} has machine-specific {sec}.\nAll {len(common_items)} {sec} live in common.json, which every machine shares, so they are already identical everywhere. "
                                          f"Only per-machine overrides (items saved into a <PROFILE>.json layer) show up here.", xalign=0, wrap=True, margin_top=24, margin_start=12, margin_end=12, css_classes=["dim-label"]))
            self.listbox.append(row)
            return
        add_group(f"only in {other}", d["only_a"], other, "profile")
        add_group(f"differ ({other} version shown)", [c["a"] for c in d["changed"]], other, "warn")
        add_group(f"only in {me}", d["only_b"], me, "common")
        add_group("identical in both", d["same"], "both", "")

    def _select(self, on: bool) -> None:
        for cb, _i, _s in self._checks:
            cb.set_active(on)

    def _chosen(self, side_filter: set[str]) -> list[str]:
        return [i for cb, i, side in self._checks if cb.get_active() and side in side_filter]

    def _do_copy(self, src: str, dst: str, ids: list[str]) -> None:
        sec = self._sel_section()
        if not ids:
            self.win.toast("Select items first", error=True); return
        body = f"{len(ids)} {sec} item(s) from {src} → {dst}.\nA snapshot is taken first; you can restore it from Snapshots."
        def go():
            with log.action("gui.profiles.copy", source=src, to=dst, section=sec, count=len(ids)):
                res = pf.copy_items(src, dst, sec, ids=ids)
                if dst == paths.profile_name():
                    generate.apply(State_reload(self.ctl), reload=True)
                try:
                    sha = gitsync.commit(pf.copied_files(), f"copy {len(ids)} {sec} from {src} to {dst}")
                    if sha and gitsync.auto_sync_enabled():
                        gitsync.sync()
                except Exception as exc:
                    _log.warning("commit/sync failed: %s", exc)
            self.win.toast(f"Copied {len(res['copied'])} {sec} item(s) {src} → {dst} · snapshot {res['snapshot']}")
            self.ctl.reload_state(); self.refresh(); self.win.refresh_git()
            for p in self.win.panels.values():
                if hasattr(p, "refresh") and p is not self:
                    try: p.refresh()
                    except Exception: pass
        confirm(self.win, f"Copy to {dst}?", body, "Copy", go)

    def pull(self) -> None:
        other = self._sel_other()
        if other:
            self._do_copy(other, paths.profile_name(), self._chosen({other}))

    def push(self) -> None:
        other = self._sel_other()
        if other:
            self._do_copy(paths.profile_name(), other, self._chosen({paths.profile_name(), "both"}))

    def snapshot_now(self) -> None:
        d = pf.snapshot("manual")
        try:
            gitsync.commit(pf.copied_files(), f"snapshot {d.name}")
        except Exception as exc:
            _log.warning("commit failed: %s", exc)
        self.win.toast(f"Snapshot {d.name}"); self.win.refresh_git()

    def show_snapshots(self) -> None:
        dlg = Adw.Dialog(title="Snapshots"); dlg.set_content_width(760); dlg.set_content_height(560)
        tv = Adw.ToolbarView(); hb = Adw.HeaderBar(); tv.add_top_bar(hb)
        lb = Gtk.ListBox(); lb.add_css_class("sa-list"); lb.set_selection_mode(Gtk.SelectionMode.NONE)
        snaps = list(reversed(pf.snapshots()))
        if not snaps:
            lb.append(list_row("No snapshots yet", "one is taken automatically before every copy or restore"))
        for s in snaps:
            box = Gtk.Box(spacing=6)
            def mk(sid):
                def restore_all():
                    confirm(self.win, f"Restore {sid}?", "All state files are replaced by the snapshot. The current state is snapshotted first.", "Restore", lambda: self._restore(sid, None))
                def restore_sec():
                    sec = self._sel_section()
                    confirm(self.win, f"Restore only {sec} from {sid}?", f"Section {sec} of every file is replaced; other sections stay. The current state is snapshotted first.", "Restore section", lambda: self._restore(sid, [sec]))
                return restore_all, restore_sec
            ra, rs = mk(s["id"])
            box.append(button("Restore all", ra, style="destructive-action")); box.append(button(f"Restore {self._sel_section()}", rs))
            d = pf.diff_snapshot(s["id"])
            changed = sum(v["only_now"] + v["only_snapshot"] + v["changed"] for per in d.values() for v in per.values())
            lb.append(list_row(s["id"], f"{s.get('reason', '')} · taken on {s.get('profile', '?')} · {changed} item(s) differ from now", [], trailing=box))
        tv.set_content(scrolled(lb)); dlg.set_child(tv); dlg.present(self.win)

    def _restore(self, sid: str, sections) -> None:
        with log.action("gui.profiles.restore", snapshot=sid, sections=sections):
            touched = pf.restore(sid, sections=sections)
            generate.apply(State_reload(self.ctl), reload=True)
            try:
                sha = gitsync.commit(pf.copied_files(), f"restore {', '.join(touched)} from {sid}")
                if sha and gitsync.auto_sync_enabled():
                    gitsync.sync()
            except Exception as exc:
                _log.warning("commit/sync failed: %s", exc)
        self.win.toast(f"Restored {', '.join(touched)} from {sid}")
        self.ctl.reload_state(); self.refresh(); self.win.refresh_git()
        for p in self.win.panels.values():
            if hasattr(p, "refresh") and p is not self:
                try: p.refresh()
                except Exception: pass


def State_reload(ctl):
    ctl.reload_state()
    return ctl.state


# ==========================================================================
# NFS

class NfsPanel(Panel):
    def __init__(self, win) -> None:
        super().__init__(win, "NFS")
        self.header_button("Refresh", self.load, icon="view-refresh-symbolic")
        self._mounts: list[nfsctl.NfsMount] = []
        self._loading = False
        self.progress = Gtk.Label(xalign=0); self.progress.add_css_class("dim-label"); self.progress.set_margin_start(12)
        self.insert_child_after(self.progress, self.toolbar)

    def on_show(self) -> None:
        self.load()

    def load(self) -> None:
        if self._loading:
            return
        self._loading = True; self.progress.set_text("Reading mount units…")
        def done(res, err):
            self._loading = False; self.progress.set_text(f"Error: {err}" if err else "")
            if not err:
                self._mounts = res; self.refresh()
        _bg(lambda: nfsctl.mounts(), done)

    def refresh(self) -> None:
        rows = []
        for m in self._mounts:
            chips = [("mounted" if m.active else m.sub_state, "ok" if m.active else "warn")]
            if m.automount_unit:
                chips.append(("automount " + ("on" if m.automount_active else "off"), "" if m.automount_active else "warn"))
            if m.server_reachable is not None:
                chips.append(("server up" if m.server_reachable else "SERVER DOWN", "ok" if m.server_reachable else "err"))
            if m.usage.get("pct"):
                chips.append((f"{m.usage['pct']} used · {m.usage['avail']} free", ""))
            rows.append((m.unit, list_row(m.where, m.what, chips, disabled=not m.active), m))
        self.fill_list(rows)
        self.toolbar.get_title_widget().set_subtitle(f"{len(self._mounts)} NFS mounts · {sum(1 for m in self._mounts if m.active)} mounted")

    def show_detail(self, m: nfsctl.NfsMount) -> None:
        self.clear_detail()
        self.detail_header(m.where, m.what)
        g = Adw.PreferencesGroup(title="Mount")
        for t, v in (("Unit", m.unit), ("State", f"{'mounted' if m.active else 'not mounted'} · {m.sub_state} · result {m.result or '—'}"), ("Since", m.since or "—"),
                     ("Server", f"{m.server}  ·  {'reachable' if m.server_reachable else 'NOT reachable' if m.server_reachable is not None else '?'} (tcp 2049)"),
                     ("Export", m.export), ("Type", m.fstype), ("Options", m.options or "—"),
                     ("Automount", (f"{m.automount_unit} · {'active' if m.automount_active else 'inactive'} · idle timeout {m.automount_idle}") if m.automount_unit else "none"),
                     ("Usage", " · ".join(f"{k} {v}" for k, v in m.usage.items()) or "—")):
            r = Adw.ActionRow(title=t, subtitle=str(v)); r.set_subtitle_selectable(True); g.add(r)
        self.detail.append(g)
        self.detail.append(Gtk.Label(label="Force = umount -f (server gone) · Lazy = umount -l (detach now, clean up when idle). Automount off stops the .automount unit so an access does not re-mount it.", xalign=0, wrap=True, css_classes=["dim-label"]))

        def act(what: str, need_confirm: bool):
            def run():
                self.progress.set_text(f"{what} {m.where}…")
                _bg(lambda: nfsctl.action(m, what), lambda r, e: (self.progress.set_text(""), self.win.toast(f"{what} {m.where}: {r if not e else e}", error=bool(e)), self.load()))
            if need_confirm:
                confirm(self.win, f"{what} {m.where}?", m.what, what, run)
            else:
                run()
        self.action_bar(button("Mount", lambda: act("mount", False), style="suggested-action"), button("Unmount", lambda: act("umount", True)),
                        button("Force unmount", lambda: act("umount-force", True), style="destructive-action"), button("Lazy unmount", lambda: act("umount-lazy", True)),
                        button("Remount", lambda: act("remount", True)),
                        button("Automount off" if m.automount_active else "Automount on", lambda: act("automount-off" if m.automount_active else "automount-on", False)))
