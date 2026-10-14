"""Monitors: the output layout canvas (displays.py), roles/pins, and the Workspaces map."""
from __future__ import annotations

from dataclasses import asdict

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Adw, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from .. import displays as dsp  # noqa: E402
from .. import log, monitors as mon, paths, swayipc  # noqa: E402
from ..rules import Rule  # noqa: E402
from ..state import SCOPES, Monitor  # noqa: E402
from .controller import Outcome  # noqa: E402
from .panels import Panel  # noqa: E402
from .widgets import button, chip, combo_row, combo_value, confirm, entry_row, list_row, scrolled, switch_row  # noqa: E402

_log = log.get("gui.monitors")

SNAP_PX = 14          # snapping distance on screen, converted to layout px at drag start
CANVAS_PAD = 16


def _rgba(widget: Gtk.Widget, name: str, fallback: tuple[float, float, float]) -> tuple[float, float, float]:
    try:
        ok, c = widget.get_style_context().lookup_color(name)
        if ok:
            return c.red, c.green, c.blue
    except Exception:
        pass
    return fallback


class LayoutCanvas(Gtk.DrawingArea):
    """Outputs drawn to scale in layout (logical) coordinates; drag to arrange
    (edges snap, overlap is refused), click to select."""

    def __init__(self, panel: "MonitorsPanel") -> None:
        super().__init__(hexpand=True)
        self.panel = panel
        self.set_content_height(250)
        self.set_draw_func(self._draw)
        self._view: tuple[float, float, float] | None = None   # (factor, ox, oy) layout -> widget
        self._drag: dict | None = None
        drag = Gtk.GestureDrag()
        drag.connect("drag-begin", self._begin)
        drag.connect("drag-update", self._update)
        drag.connect("drag-end", self._end)
        self.add_controller(drag)

    # ---- geometry --------------------------------------------------------------
    def _rects(self) -> dict[str, tuple[int, int, int, int]]:
        return {k: r for k, r in ((k, self.panel.rect_of(k)) for k in self.panel.work) if r}

    def _fit(self, rects: dict[str, tuple[int, int, int, int]]) -> tuple[float, float, float]:
        if not rects:
            return 1.0, 0.0, 0.0
        x0 = min(r[0] for r in rects.values()); y0 = min(r[1] for r in rects.values())
        x1 = max(r[0] + r[2] for r in rects.values()); y1 = max(r[1] + r[3] for r in rects.values())
        w, h = self.get_width() - 2 * CANVAS_PAD, self.get_height() - 2 * CANVAS_PAD
        f = min(w / max(1, x1 - x0), h / max(1, y1 - y0))
        return f, CANVAS_PAD + (w - (x1 - x0) * f) / 2 - x0 * f, CANVAS_PAD + (h - (y1 - y0) * f) / 2 - y0 * f

    def _hit(self, x: float, y: float) -> str | None:
        if self._view is None:
            return None
        f, ox, oy = self._view
        lx, ly = (x - ox) / f, (y - oy) / f
        for k, (rx, ry, rw, rh) in self._rects().items():
            if rx <= lx < rx + rw and ry <= ly < ry + rh and self.panel.work[k].enabled:
                return k
        return None

    # ---- drag ------------------------------------------------------------------------
    def _begin(self, _g, x: float, y: float) -> None:
        k = self._hit(x, y)
        if k is None:
            self._drag = None
            return
        self.panel.select_output(k)
        c = self.panel.work[k]
        self._drag = {"key": k, "x": c.x, "y": c.y, "view": self._view}

    def _update(self, _g, dx: float, dy: float) -> None:
        if not self._drag:
            return
        f = self._drag["view"][0]
        k = self._drag["key"]
        r = self.panel.rect_of(k)
        others = [v for kk, v in self._rects().items() if kk != k and self.panel.work[kk].enabled]
        x, y = dsp.snap(others, r[2], r[3], int(round(self._drag["x"] + dx / f)), int(round(self._drag["y"] + dy / f)),
                        max(1, int(SNAP_PX / f)))
        c = self.panel.work[k]
        if (c.x, c.y) != (x, y):
            c.x, c.y = x, y
            self.queue_draw()

    def _end(self, _g, dx: float, dy: float) -> None:
        if not self._drag:
            return
        moved = abs(dx) > 2 or abs(dy) > 2
        k = self._drag["key"]
        self._drag = None
        if moved:
            r = self.panel.rect_of(k)
            others = [v for kk, v in self._rects().items() if kk != k and self.panel.work[kk].enabled]
            c = self.panel.work[k]
            c.x, c.y = dsp.attach(others, r[2], r[3], c.x, c.y)
            dsp.normalize(self.panel.work, {k: (r[2], r[3]) for k, r in self._rects().items()})
            self.panel.layout_edited()

    # ---- draw --------------------------------------------------------------------------
    def _draw(self, _area, cr, width: int, height: int) -> None:
        rects = self._rects()
        self._view = self._drag["view"] if self._drag else self._fit(rects)
        f, ox, oy = self._view
        fg = _rgba(self, "window_fg_color", (0.9, 0.9, 0.9))
        acc = _rgba(self, "accent_color", (0.47, 0.68, 0.93))
        warn = _rgba(self, "warning_color", (0.96, 0.76, 0.3))
        if not rects:
            self._text(cr, "No outputs", CANVAS_PAD, CANVAS_PAD, fg, 1.0, bold=True)
            return
        sel = self.panel.sel_hw
        for k, (rx, ry, rw, rh) in sorted(rects.items(), key=lambda kv: kv[0] == sel):
            c = self.panel.work[k]
            x, y, w, h = ox + rx * f + 2, oy + ry * f + 2, rw * f - 4, rh * f - 4
            role = self.panel.role_of(k)
            base = acc if role is not None and role.primary else fg
            cr.rectangle(x, y, w, h)
            cr.set_source_rgba(*base, 0.16 if c.enabled else 0.04)
            cr.fill_preserve()
            cr.set_line_width(3 if k == sel else 1.5)
            if not c.enabled:
                cr.set_dash([6, 4])
            cr.set_source_rgba(*(acc if k == sel else base), 1.0 if k == sel else 0.55)
            cr.stroke()
            cr.set_dash([])
            info = self.panel.label_of(k)
            cr.save()
            cr.rectangle(x, y, w, h)
            cr.clip()
            ty = y + 6
            ty = self._text(cr, info[0], x + 8, ty, fg, 1.0, bold=True)
            for line, is_warn in info[1:]:
                ty = self._text(cr, line, x + 8, ty, warn if is_warn else fg, 0.9 if is_warn else 0.7)
            cr.restore()

    def _text(self, cr, text: str, x: float, y: float, rgb, alpha: float, bold: bool = False) -> float:
        layout = PangoCairo.create_layout(cr)
        fd = Pango.FontDescription.from_string(("Sans Bold 10" if bold else "Sans 9"))
        layout.set_font_description(fd)
        layout.set_text(text, -1)
        cr.move_to(x, y)
        cr.set_source_rgba(*rgb, alpha)
        PangoCairo.show_layout(cr, layout)
        return y + layout.get_pixel_size()[1] + 1


class MonitorsPanel(Panel):
    def __init__(self, win) -> None:
        super().__init__(win, "Monitors")
        self.header_button("Fix group 0", lambda: self.win.run_outcome(self.ctl.fix_orphans), icon="edit-clear-all-symbolic")
        self.geom = Gtk.ToggleButton(label="pin geometry")
        self.geom.set_tooltip_text("Re-emit nwg-displays' geometry keyed by hardware id (survives connector renames)")
        self._geom_handler = self.geom.connect("toggled", self._on_geom)
        self.toolbar.pack_end(self.geom)
        self.header_button("Refresh", self.refresh, icon="view-refresh-symbolic", start=False)

        # ---- layout canvas + its action strip, between the toolbar and the list/detail
        self.outs: list[dsp.Live] = []
        self.work: dict[str, dsp.OutputConf] = {}
        self.sel_hw: str | None = None
        self._pos_sync = None   # the open Display form's (hw, refresh-position-spins)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_margin_start(12); box.set_margin_end(12); box.set_margin_top(8); box.set_margin_bottom(4)
        self.canvas = LayoutCanvas(self)
        frame = Gtk.Frame(child=self.canvas)
        box.append(frame)
        strip = Gtk.Box(spacing=8)
        self.layout_chip = chip("", "warn")
        self.layout_chip.set_visible(False)
        self.dpi_label = Gtk.Label(xalign=0, hexpand=True)
        self.dpi_label.add_css_class("dim-label")
        self.import_btn = button("Import nwg-displays", self.import_nwg, icon="document-import-symbolic")
        self.discard_btn = button("Discard", self.discard_layout)
        self.apply_btn = button("Apply…", self.apply_layout, style="suggested-action", icon="emblem-ok-symbolic")
        self.apply_btn.set_tooltip_text(f"Apply live; reverts in {dsp.DEFAULT_REVERT_SECONDS} s unless you press Keep")
        strip.append(self.layout_chip); strip.append(self.dpi_label)
        strip.append(button("X11 DPI…", self.dpi_dialog, icon="preferences-desktop-font-symbolic"))
        strip.append(self.import_btn); strip.append(self.discard_btn); strip.append(self.apply_btn)
        box.append(strip)
        self.insert_child_after(box, self.toolbar)
        self.paned.set_position(400)

    # ---- layout model ------------------------------------------------------------------
    def _live_conf(self) -> dict[str, dsp.OutputConf]:
        return dsp.merged_with_live(dsp.saved(self.ctl.state), self.outs)

    def _changes(self) -> dict[str, dsp.OutputConf]:
        cur = {o.hw_id: o.conf for o in self.outs}
        return {k: c for k, c in self.work.items() if k in cur and not c.same_layout(cur[k])}

    def load_layout(self, keep_edits: bool = False) -> None:
        try:
            self.outs = dsp.live()
        except Exception as exc:
            _log.warning("get_outputs failed: %s", exc)
            self.outs = []
        fresh = self._live_conf()
        if keep_edits and self.work:
            for k, c in fresh.items():
                self.work.setdefault(k, c)
        else:
            self.work = {k: dsp.OutputConf(**asdict(c)) for k, c in fresh.items()}
        self.layout_edited(redraw_only=True)

    def live_of(self, hw: str) -> dsp.Live | None:
        return next((o for o in self.outs if o.hw_id == hw), None)

    def native_of(self, hw: str) -> tuple[int, int] | None:
        c = self.work.get(hw)
        o = self.live_of(hw)
        return (c.size() if c else None) or (o.native if o else None)

    def rect_of(self, hw: str) -> tuple[int, int, int, int] | None:
        c = self.work.get(hw)
        if c is None:
            return None
        size = self.native_of(hw)
        if size:
            w, h = dsp.logical_size(*size, c.transform, c.scale)
        else:
            o = self.live_of(hw)
            if o is None or not o.rect[2]:
                return None
            w, h = o.rect[2], o.rect[3]
        return c.x, c.y, w, h

    def role_of(self, hw: str) -> Monitor | None:
        return self.ctl.state.monitor_by_criteria(hw)

    def label_of(self, hw: str) -> list:
        c = self.work[hw]
        o = self.live_of(hw)
        m = self.role_of(hw)
        title = (m.id if m else "unassigned") + ("  ★" if m and m.primary else "")
        lines: list[tuple[str, bool]] = [((o.name if o else c.connector or "absent") + ("" if c.enabled else " · off"), False)]
        size = self.native_of(hw)
        if c.mode or size:
            lines.append(((c.mode or f"{size[0]}x{size[1]}").replace("@", " @ "), False))
        exact = size is None or dsp.is_exact(*size, c.scale)
        r = self.rect_of(hw)
        lines.append((f"scale {dsp.fmt_scale(c.scale)}" + ("" if exact else " (forced)") + (f" · {r[2]}x{r[3]}" if r else ""), not exact))
        if c.transform != "normal":
            lines.append((f"rotated {c.transform}", False))
        if o and o.current_workspace and c.enabled:
            lines.append((f"ws {o.current_workspace}", False))
        return [title, *lines]

    def layout_edited(self, redraw_only: bool = False) -> None:
        n = len(self._changes())
        self.layout_chip.set_label(f"{n} output(s) changed")
        self.layout_chip.set_visible(n > 0)
        self.apply_btn.set_sensitive(n > 0 and dsp.owns())
        self.discard_btn.set_sensitive(n > 0)
        st = self.ctl.state
        self.import_btn.set_visible(dsp.owns() and not dsp.saved(st) and not st.feature(dsp.SETTINGS_KEY).get("imported_from")
                                    and dsp.nwg_file().exists())
        dpi, src = dsp.effective_dpi(st)
        zs = "xwayland_zero_scaling" in paths.SWAY_FEATURES
        self.dpi_label.set_label(("" if dsp.owns() else "Layout is read-only here (swayAppsOwnsOutputs off) · ")
                                 + (f"X11 DPI {dpi} ({src})" if zs else "X11 zero scaling off"))
        if self._pos_sync and self._pos_sync[0] in self.work:
            self._pos_sync[1]()
        self.canvas.queue_draw()

    def select_output(self, hw: str) -> None:
        self.sel_hw = hw
        self.canvas.queue_draw()
        m = self.role_of(hw)
        o = self.live_of(hw)
        want = m.id if m else (f"new:{o.name}" if o else None)
        row = self.listbox.get_first_child()
        while row is not None:
            if getattr(row, "item_id", None) == want:
                if self.listbox.get_selected_row() is not row:
                    self.listbox.select_row(row)
                return
            row = row.get_next_sibling()

    def discard_layout(self) -> None:
        self.load_layout()
        if self.selected_id:
            self.refresh()

    # ---- apply / keep / revert ---------------------------------------------------------
    def apply_layout(self) -> None:
        after = self._changes()
        if not after:
            return
        probs = dsp.check_layout({**self._live_conf(), **after}, self.outs)
        if probs:
            self.win.toast("; ".join(probs), error=True)
            return
        try:
            rec, res = dsp.apply_pending(after, dsp.DEFAULT_REVERT_SECONDS, outs=self.outs)
        except Exception as exc:
            _log.exception("apply failed")
            self.win.toast(f"Apply failed: {exc}", error=True)
            return
        bad = [r for r in res if not r["ok"]]
        if bad:
            self.win.toast(f"{bad[0]['error']} — change undone", error=True)
            self.load_layout()
            return
        if rec is None:
            return
        prim = next((m for m in self.ctl.state.monitors() if m.primary), None)
        old_scale = next((o.conf.scale for o in self.outs if prim and o.hw_id == prim.criteria), None)
        self._confirm(rec, prim, old_scale)

    def _confirm(self, rec: dict, prim: Monitor | None, old_scale: float | None) -> None:
        left = [dsp.DEFAULT_REVERT_SECONDS]
        dlg = Adw.AlertDialog(heading="Keep this display layout?", body=f"Reverting in {left[0]} s.")
        dlg.add_response("revert", "Revert")
        dlg.add_response("keep", "Keep")
        dlg.set_response_appearance("keep", Adw.ResponseAppearance.SUGGESTED)
        dlg.set_default_response("revert")
        dlg.set_close_response("revert")
        done = [False]

        def tick() -> bool:
            if done[0]:
                return False
            left[0] -= 1
            if left[0] <= 0:
                finish("revert")
                dlg.force_close()
                return False
            dlg.set_body(f"Reverting in {left[0]} s.")
            return True

        def finish(resp: str) -> None:
            if done[0]:
                return
            done[0] = True
            mine = dsp.claim(rec["token"])
            if resp == "keep":
                if mine is None:
                    self.win.toast("Too late: the layout was already reverted", error=True)
                else:
                    self._keep(mine, prim, old_scale)
            elif mine is not None:
                dsp.revert_record(mine)
                self.win.toast("Layout reverted")
            self.load_layout()
            self.refresh()

        dlg.connect("response", lambda _d, resp: finish(resp))
        GLib.timeout_add(1000, tick)
        dlg.present(self.win)

    def _keep(self, rec: dict, prim: Monitor | None, old_scale: float | None) -> None:
        def do() -> Outcome:
            self.ctl.reload_state()
            dsp.keep_record(self.ctl.state, rec)
            return self.ctl._finish("Display layout kept", True, None)
        out = self.win.run_outcome(do)
        if out is None or not out.ok or prim is None or "xwayland_zero_scaling" not in paths.SWAY_FEATURES:
            return
        new = dsp.saved(self.ctl.state).get(prim.criteria)
        if new is None or old_scale is None or abs(new.scale - old_scale) < 1e-6:
            return
        sug = dsp.suggest_dpi(new.scale)
        if sug != dsp.effective_dpi(self.ctl.state)[0]:
            self.dpi_dialog(suggest=sug, why=f"The primary monitor ({prim.id}) is now at scale {dsp.fmt_scale(new.scale)}: "
                                             f"DPI {sug} (96 × {dsp.fmt_scale(new.scale)}) keeps Steam and other X11 apps at their size.")

    def dpi_dialog(self, suggest: int | None = None, why: str = "") -> None:
        st = self.ctl.state
        cur, src = dsp.effective_dpi(st)
        if "xwayland_zero_scaling" not in paths.SWAY_FEATURES:
            self.win.toast("X11 DPI needs swayXwaylandZeroScaling on this machine", error=True)
            return
        prim = next((m for m in st.monitors() if m.primary), None)
        o = next((x for x in self.outs if prim and x.hw_id == prim.criteria), None)
        if suggest is None and o is not None:
            suggest = dsp.suggest_dpi(o.conf.scale)
        body = (why + "\n\n" if why else "") + f"Now {cur} ({src}). " + dsp.DPI_LIFETIME_NOTE
        if dsp.xwayland_running():
            body += "\nXwayland is running right now."
        dlg = Adw.AlertDialog(heading="X11 DPI (Xft.dpi for every X11 app)", body=body)
        spin = Adw.SpinRow.new_with_range(48, 400, 1)
        spin.set_title("DPI")
        spin.set_value(suggest or cur or 96)
        lb = Gtk.ListBox(); lb.add_css_class("boxed-list"); lb.append(spin)
        dlg.set_extra_child(lb)
        dlg.add_response("cancel", "Cancel")
        dlg.add_response("default", f"Nix default ({dsp.nix_dpi()})")
        dlg.add_response("set", "Set")
        dlg.set_response_appearance("set", Adw.ResponseAppearance.SUGGESTED)
        dlg.set_close_response("cancel")

        def resp(_d, r: str) -> None:
            if r == "cancel":
                return
            val = 0 if r == "default" else int(spin.get_value())

            def do() -> Outcome:
                self.ctl.reload_state()
                dsp.store(self.ctl.state, dpi=val)
                out = self.ctl._finish(f"X11 DPI {val or 'default'}", True, None)
                out.message += " · applies when Xwayland next starts"
                return out
            self.win.run_outcome(do)
            self.layout_edited()
        dlg.connect("response", resp)
        dlg.present(self.win)

    def import_nwg(self) -> None:
        def do() -> Outcome:
            self.ctl.reload_state()
            lay, notes = dsp.import_nwg(dsp.nwg_file().read_text(), dsp.connector_map(self.outs))
            if not lay:
                return Outcome(False, f"{dsp.nwg_file()}: no output blocks")
            import time as _t
            dsp.store(self.ctl.state, lay, imported_from=f"{dsp.nwg_file()} @ {_t.strftime('%Y-%m-%d')}")
            out = self.ctl._finish(f"Imported {len(lay)} output(s) from nwg-displays", True, None)
            if notes:
                out.message += " · " + "; ".join(notes)
            return out
        self.win.run_outcome(do)
        self.load_layout()

    # ---- list + detail ------------------------------------------------------------------
    def _on_geom(self, btn) -> None:
        self.win.run_outcome(lambda: self.ctl.set_pin_geometry(btn.get_active()))

    def refresh(self) -> None:
        self.ctl.reload_state()
        st = self.ctl.state
        self.geom.set_visible(not dsp.owns())
        with self.geom.handler_block(self._geom_handler):
            self.geom.set_active(bool(st.settings().get("pin_geometry")))
        self.load_layout(keep_edits=True)
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
            if o.hw_id in known or mon.skip_output(o.name):
                continue
            row = list_row(f"NEW  ·  {o.name}", o.hw_id, [("unknown output", "warn"), ("on" if o.active else "off", "")])
            rows.append((f"new:{o.name}", row, o))
        self.fill_list(rows)
        self.toolbar.get_title_widget().set_subtitle(f"{len(st.monitors())} roles · {sum(1 for o in live if o.active)} outputs on · profile {paths.profile_name()}")

    def _display_group(self, hw: str) -> Adw.PreferencesGroup | None:
        c = self.work.get(hw)
        if c is None:
            return None
        o = self.live_of(hw)
        desc = ("Edits move the picture above; Apply… sets them live with a 15 s revert."
                if dsp.owns() else "Read-only: swayAppsOwnsOutputs is off on this machine.")
        g = Adw.PreferencesGroup(title="Display", description=desc)
        enabled = switch_row("Enabled", c.enabled)
        g.add(enabled)

        modes = o.modes if o else []
        mode_labels = [dsp.fmt_mode(*m).replace("@", " @ ") for m in modes]
        mode_keys = [dsp.fmt_mode(*m) for m in modes]
        if c.mode and c.mode not in mode_keys:
            mode_keys.insert(0, c.mode); mode_labels.insert(0, c.mode.replace("@", " @ ") + " (saved)")
        if not c.mode:
            mode_keys.insert(0, ""); mode_labels.insert(0, "preferred")
        mode = combo_row("Mode", mode_labels, mode_labels[mode_keys.index(c.mode)] if c.mode in mode_keys else "")
        if not mode_keys:
            mode.set_sensitive(False)
        g.add(mode)
        transform = combo_row("Transform", list(dsp.TRANSFORMS), c.transform)
        g.add(transform)

        scale = Adw.ComboRow(title="Scale", subtitle="exact = integral logical size (k/120)")
        g.add(scale)
        forced = entry_row("Forced scale", dsp.fmt_scale(c.scale))
        forced_warn = Adw.ActionRow(title="Forced scale", subtitle=dsp.FORCED_SCALE_WARNING)
        forced_warn.add_css_class("warning")
        forced_warn.add_prefix(Gtk.Image.new_from_icon_name("dialog-warning-symbolic"))
        g.add(forced); g.add(forced_warn)
        vrr = switch_row("Adaptive sync", c.adaptive_sync)
        g.add(vrr)
        px = Adw.SpinRow.new_with_range(-20000, 20000, 1); px.set_title("Position X"); px.set_value(c.x)
        py = Adw.SpinRow.new_with_range(-20000, 20000, 1); py.set_title("Position Y"); py.set_value(c.y)
        g.add(px); g.add(py)
        scales: list[float | None] = []
        busy = [False]

        def fill_scales() -> None:
            busy[0] = True
            size = self.native_of(hw)
            labels: list[str] = []
            scales.clear()
            if size:
                for s, lw, lh in dsp.exact_scales(*size, c.transform):
                    scales.append(s); labels.append(f"{dsp.fmt_scale(s)}  —  {lw}x{lh}")
            exact = size is not None and any(abs(s - c.scale) < 1e-6 for s in scales)
            if not exact:
                lw, lh = dsp.logical_size(*size, c.transform, c.scale) if size else (0, 0)
                scales.insert(0, c.scale)
                labels.insert(0, f"{dsp.fmt_scale(c.scale)}  —  {lw}x{lh} (forced)" if size else dsp.fmt_scale(c.scale))
            scales.append(None); labels.append("Custom (forced)…")
            scale.set_model(Gtk.StringList.new(labels))
            scale.set_selected(next(i for i, s in enumerate(scales) if s is not None and abs(s - c.scale) < 1e-6))
            not_exact = bool(size) and not dsp.is_exact(*size, c.scale)
            forced.set_visible(not_exact); forced_warn.set_visible(not_exact)
            forced.set_text(dsp.fmt_scale(c.scale))
            busy[0] = False

        fill_scales()

        def changed() -> None:
            self.layout_edited()

        def on_enabled(*_a) -> None:
            c.enabled = enabled.get_active(); changed()

        def on_mode(*_a) -> None:
            i = mode.get_selected()
            if 0 <= i < len(mode_keys):
                c.mode = mode_keys[i]; fill_scales(); changed()

        def on_transform(*_a) -> None:
            c.transform = combo_value(transform); fill_scales(); changed()

        def on_scale(*_a) -> None:
            if busy[0]:
                return
            i = scale.get_selected()
            if not 0 <= i < len(scales):
                return
            if scales[i] is None:
                forced.set_visible(True); forced_warn.set_visible(True); forced.grab_focus()
                return
            c.scale = scales[i]; fill_scales(); changed()

        def on_forced(*_a) -> None:
            try:
                v = float(forced.get_text().replace(",", "."))
            except ValueError:
                return
            if 0.25 <= v <= 10:
                c.scale = dsp.norm_scale(v); fill_scales(); changed()

        def on_pos(*_a) -> None:
            if busy[0]:
                return
            c.x, c.y = int(px.get_value()), int(py.get_value()); changed()

        def sync_pos() -> None:
            if (int(px.get_value()), int(py.get_value())) != (c.x, c.y):
                busy[0] = True
                px.set_value(c.x); py.set_value(c.y)
                busy[0] = False
        self._pos_sync = (hw, sync_pos)

        enabled.connect("notify::active", on_enabled)
        mode.connect("notify::selected", on_mode)
        transform.connect("notify::selected", on_transform)
        scale.connect("notify::selected", on_scale)
        forced.connect("apply", on_forced)
        forced.set_show_apply_button(True)
        vrr.connect("notify::active", lambda *_a: (setattr(c, "adaptive_sync", vrr.get_active()), changed()))
        px.connect("notify::value", on_pos); py.connect("notify::value", on_pos)
        g.set_sensitive(dsp.owns())
        return g

    def show_detail(self, item, is_new: bool = False) -> None:
        if isinstance(item, mon.LiveOutput):
            hw_new = item.hw_id
            guess = "main" if not self.ctl.state.monitors() else "second" if not self.ctl.state.monitor("second") else f"mon{len(self.ctl.state.monitors()) + 1}"
            used = {m.group for m in self.ctl.state.monitors()}
            free = next((g for g in range(1, 10) if g not in used), 0)
            item = Monitor(id=guess, criteria=hw_new, group=free, name=f"{item.make} {item.model}".strip(), scope="profile")
            is_new = True
        m: Monitor = item
        if m.criteria in self.work and self.sel_hw != m.criteria:
            self.sel_hw = m.criteria
            self.canvas.queue_draw()
        self.clear_detail()
        self._pos_sync = None
        self.attach_banner(lambda: do_save())
        o = next((x for x in mon.live_outputs() if x.hw_id == m.criteria), None)
        self.detail_header(("New monitor: " if is_new else "") + (m.name or m.id), m.criteria)

        dg = self._display_group(m.criteria)
        if dg is not None:
            self.detail.append(dg)

        g = Adw.PreferencesGroup(title="Role", description="Roles are shared vocabulary across machines (main, second, tv, left). Rules target 'main slot 2', each machine maps the role to its own hardware id.")
        role = entry_row("Role id", m.id)
        name = entry_row("Name", m.name)
        crit = entry_row("Hardware id (make model serial)", m.criteria)
        pick = Gtk.Button(icon_name="video-display-symbolic", valign=Gtk.Align.CENTER, tooltip_text="Take from a connected output")
        pick.add_css_class("flat")
        crit.add_suffix(pick)
        group = Adw.SpinRow.new_with_range(0, 9, 1); group.set_title("Workspace group (decade)"); group.set_subtitle("0 = not pinned"); group.set_value(m.group)
        primary = switch_row("Primary", m.primary, "X11 DPI follows this monitor's scale")
        always = switch_row("Always connected", m.always_connected,
                            "force the kernel connector on: switching this monitor OFF no longer moves its workspaces (DP drops HPD like an unplug)")
        enabled = switch_row("Role enabled", m.enabled, "workspace pins of this role")
        scope = combo_row("Scope", list(SCOPES), m.scope)
        notes = entry_row("Notes", m.notes)
        for r in (role, name, crit, group, primary, always, enabled, scope, notes):
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
            sysfs = mon.sysfs_connector(o.name)
            kstat = mon.connector_status(sysfs) if sysfs else None
            for t, v in (("Mode", f"{o.width}x{o.height} @ {o.refresh:.3f} Hz"), ("Position", f"{o.x},{o.y}"), ("Scale", dsp.fmt_scale(o.scale)),
                         ("Transform", o.transform), ("Current workspace", o.current_workspace or "-"), ("Active", o.active),
                         ("Kernel connector", f"{sysfs or '?'} · {kstat or '?'}" + (" · FORCED" if sysfs and mon._load_forced().get(sysfs) == "on" else ""))):
                g2.add(Adw.ActionRow(title=t, subtitle=str(v)))
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
                           notes=notes.get_text(), always_connected=always.get_active(), scope=combo_value(scope))

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
        for r in (primary, always, enabled):
            r.connect("notify::active", _dirty)
        scope.connect("notify::selected", _dirty)
        if is_new:
            self.mark_dirty(do_save)

        def do_delete() -> None:
            users = [r for r in self.ctl.state.rules() if r.target and r.target.get("monitor") == m.id]
            body = m.criteria + (f"\n{len(users)} rule(s) target it; they keep their numeric workspace." if users else "")
            confirm(self.win, f"Remove monitor role {m.id}?", body, "Remove", lambda: (
                self.win.run_outcome(lambda: self.ctl.delete_monitor(m)), self.show_placeholder(), self.refresh()))

        btns = [button("Save role", do_save, style="suggested-action", icon="document-save-symbolic")]
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
