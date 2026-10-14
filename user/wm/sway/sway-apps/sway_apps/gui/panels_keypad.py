"""Keypad (SWAY-18): the Razer Tartarus V2 drawn on a canvas, one key edited at a time.
Click a key, type or capture its keyd action, Save writes keyd-devices.json, Deploy runs
install.sh (keyd is a system service). Data and rules: sway_apps/keypad.py."""
from __future__ import annotations

import copy
import shlex

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Adw, Gdk, Gtk, Pango, PangoCairo  # noqa: E402

from .. import keypad as kp  # noqa: E402
from .. import log, paths, swayipc  # noqa: E402
from .panels_monitors import _rgba  # noqa: E402
from .widgets import button, confirm  # noqa: E402

_log = log.get("gui.keypad")

PAD = 16
# GDK keyval names -> keyd key names, for the capture (the rest match once lowercased)
KEYVAL_TO_KEYD = {"escape": "esc", "return": "enter", "page_up": "pageup", "page_down": "pagedown",
                  "control_l": "leftcontrol", "control_r": "rightcontrol", "shift_l": "leftshift",
                  "shift_r": "rightshift", "alt_l": "leftalt", "alt_r": "rightalt", "super_l": "leftmeta",
                  "super_r": "rightmeta", "iso_level3_shift": "rightalt", "caps_lock": "capslock",
                  "kp_enter": "kpenter", "period": "dot", "bracketleft": "leftbrace", "bracketright": "rightbrace",
                  "num_lock": "numlock", "scroll_lock": "scrolllock", "print": "sysrq", "iso_left_tab": "tab"}
MODIFIER_KEYVALS = {"control_l", "control_r", "shift_l", "shift_r", "alt_l", "alt_r", "super_l", "super_r",
                    "iso_level3_shift", "meta_l", "meta_r", "hyper_l", "hyper_r"}


def keyd_name(keyval_name: str) -> str:
    n = keyval_name.lower()
    return KEYVAL_TO_KEYD.get(n, n)


class KeypadCanvas(Gtk.DrawingArea):
    def __init__(self, panel: "KeypadPanel") -> None:
        super().__init__(hexpand=True)
        self.panel = panel
        self.set_content_height(360)
        self.set_draw_func(self._draw)
        self._view = (1.0, 0.0, 0.0)
        click = Gtk.GestureClick()
        click.connect("released", self._click)
        self.add_controller(click)

    def _fit(self, m: kp.Model, width: int, height: int) -> tuple[float, float, float]:
        f = min((width - 2 * PAD) / m.size[0], (height - 2 * PAD) / m.size[1])
        return f, (width - m.size[0] * f) / 2, (height - m.size[1] * f) / 2

    def _click(self, _g, _n, x: float, y: float) -> None:
        m = self.panel.model
        if m is None:
            return
        f, ox, oy = self._view
        lx, ly = (x - ox) / f, (y - oy) / f
        hit = next((k for k in m.keys if k.x <= lx < k.x + k.w and k.y <= ly < k.y + k.h), None)
        if hit is not None:
            self.panel.select_key(hit.id)

    def _text(self, cr, text: str, x: float, y: float, w: float, rgb, alpha: float, size: int, bold: bool = False) -> None:
        layout = PangoCairo.create_layout(cr)
        layout.set_font_description(Pango.FontDescription.from_string(f"Sans {'Bold ' if bold else ''}{size}"))
        layout.set_width(int(max(1, w) * Pango.SCALE))
        layout.set_ellipsize(Pango.EllipsizeMode.END)
        layout.set_alignment(Pango.Alignment.CENTER)
        layout.set_text(text, -1)
        cr.move_to(x, y)
        cr.set_source_rgba(*rgb, alpha)
        PangoCairo.show_layout(cr, layout)

    def _draw(self, _area, cr, width: int, height: int) -> None:
        m, dev = self.panel.model, self.panel.device
        if m is None or dev is None:
            return
        self._view = f, ox, oy = self._fit(m, width, height)
        fg = _rgba(self, "window_fg_color", (0.9, 0.9, 0.9))
        acc = _rgba(self, "accent_color", (0.47, 0.68, 0.93))
        warn = _rgba(self, "warning_color", (0.96, 0.76, 0.3))
        # body outline
        cr.set_source_rgba(*fg, 0.05)
        _round(cr, ox, oy, m.size[0] * f, m.size[1] * f, 18)
        cr.fill()
        for label, x, y, w, h in m.decor:
            _round(cr, ox + x * f, oy + y * f, w * f, h * f, 10)
            cr.set_source_rgba(*fg, 0.08)
            cr.fill()
            self._text(cr, label, ox + x * f, oy + (y + h / 2 - 7) * f, w * f, fg, 0.45, 8)
        for k in m.keys:
            x, y, w, h = ox + k.x * f, oy + k.y * f, k.w * f, k.h * f
            action = kp.action_of(dev, k)
            changed = action != k.code
            sel = k.id == self.panel.sel_key
            _round(cr, x, y, w, h, 8)
            cr.set_source_rgba(*(acc if changed else fg), 0.22 if changed else 0.10)
            cr.fill_preserve()
            cr.set_line_width(3 if sel else 1.2)
            cr.set_source_rgba(*(acc if sel else fg), 1.0 if sel else 0.35)
            cr.stroke()
            self._text(cr, k.id, x + 4, y + 3, w - 8, fg, 0.55, 7)
            bad = kp.validate(action) is not None
            self._text(cr, action, x + 2, y + h / 2 - 4, w - 4, warn if bad else fg, 1.0, 9, bold=True)


def _round(cr, x: float, y: float, w: float, h: float, r: float) -> None:
    import math
    r = min(r, w / 2, h / 2)
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


class KeypadPanel(Gtk.Box):
    def __init__(self, win) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win = win
        header = Adw.HeaderBar()
        self.title = Adw.WindowTitle(title="Keypad", subtitle="")
        header.set_title_widget(self.title)
        self.append(header)
        self.data = kp.load()
        self.saved = copy.deepcopy(self.data)
        self.dev_name = next(iter(self.data["devices"]), None)
        self.sel_key: str | None = None
        self.capturing = False

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin_top=12, margin_bottom=12,
                       margin_start=18, margin_end=18)
        self.canvas = KeypadCanvas(self)
        body.append(self.canvas)
        hint = Gtk.Label(label="Click a key. Highlighted keys differ from what the keypad sends by default.",
                         xalign=0.0, wrap=True)
        hint.add_css_class("dim-label")
        body.append(hint)

        self.group = Adw.PreferencesGroup(title="Key", description="Pick a key on the drawing.")
        self.key_row = Adw.ActionRow(title="—", subtitle="")
        self.action_row = Adw.EntryRow(title="Action (keyd)")
        self.action_row.connect("changed", lambda *_: self._on_edit())
        self.status_row = Adw.ActionRow(title="", subtitle="e.g. f, C-a, M-S-f2, macro(C-c 50ms C-v), overload(shift, esc)")
        self.group.add(self.key_row)
        self.group.add(self.action_row)
        self.group.add(self.status_row)
        tools = Gtk.Box(spacing=8, halign=Gtk.Align.END, margin_top=8)
        self.capture_btn = Gtk.ToggleButton(label="Capture")
        self.capture_btn.set_tooltip_text("Press the key or combination to send (Escape cancels)")
        self.capture_btn.connect("toggled", lambda b: self._capture(b.get_active()))
        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self._on_key)
        self.capture_btn.add_controller(keys)
        tools.append(self.capture_btn)
        tools.append(button("Default", self._default, icon="edit-undo-symbolic"))
        self.group.add(tools)
        body.append(self.group)

        scroller = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.set_child(Adw.Clamp(maximum_size=900, child=body))
        self.append(scroller)

        bar = Gtk.Box(spacing=8, halign=Gtk.Align.END, margin_top=6, margin_bottom=8, margin_end=12)
        self.save_btn = button("Save", self._save, style="suggested-action", icon="document-save-symbolic")
        self.deploy_btn = button("Deploy…", self._deploy, icon="software-update-available-symbolic")
        bar.append(button("Discard", self._discard))
        bar.append(self.deploy_btn)
        bar.append(self.save_btn)
        self.append(bar)
        self.refresh()

    # ---- state ------------------------------------------------------------------------
    @property
    def device(self) -> dict | None:
        return self.data["devices"].get(self.dev_name) if self.dev_name else None

    @property
    def model(self) -> kp.Model | None:
        return kp.device_model(self.device or {})

    def dirty(self) -> bool:
        return self.data != self.saved

    def refresh(self) -> None:
        dev, m = self.device, self.model
        if dev is None or m is None:
            self.title.set_subtitle("no keypad in keyd-devices.json")
            return
        pend = kp.pending(self.saved)
        state = ("unsaved changes" if self.dirty() else
                 "saved · live after Deploy (install.sh)" if self.dev_name in pend else "in sync with keyd")
        self.title.set_subtitle(f"{dev.get('name', m.name)} · {state}")
        self.save_btn.set_sensitive(self.dirty())
        self.deploy_btn.set_sensitive(not self.dirty())
        self.canvas.queue_draw()

    def select_key(self, kid: str) -> None:
        m, dev = self.model, self.device
        k = m.key(kid) if m else None
        if k is None or dev is None:
            return
        self.sel_key = kid
        self.group.set_description(None)
        self.key_row.set_title(f"Key {kid}")
        self.key_row.set_subtitle(f"sends {k.code} by default")
        self._set_entry(kp.action_of(dev, k))
        self.canvas.queue_draw()

    def _set_entry(self, text: str) -> None:
        self._loading = True
        self.action_row.set_text(text)
        self._loading = False
        self._validate()

    def _validate(self) -> str | None:
        err = kp.validate(self.action_row.get_text())
        self.status_row.set_title("✓ keyd accepts it" if err is None else f"✗ {err}")
        return err

    def _on_edit(self) -> None:
        if getattr(self, "_loading", False) or self.sel_key is None:
            return
        err = self._validate()
        if err is None:
            kp.set_action(self.device, self.model.key(self.sel_key), self.action_row.get_text())
            self.refresh()

    def _default(self) -> None:
        if self.sel_key is None:
            return
        k = self.model.key(self.sel_key)
        kp.set_action(self.device, k, None)
        self._set_entry(k.code)
        self.refresh()

    # ---- capture --------------------------------------------------------------------
    def _capture(self, on: bool) -> None:
        self.capturing = on and self.sel_key is not None
        if on and self.sel_key is None:
            self.capture_btn.set_active(False)
            self.win.toast("Pick a key on the drawing first")
            return
        self.capture_btn.set_label("Press a key…" if self.capturing else "Capture")
        if self.capturing:
            self.capture_btn.grab_focus()

    def _on_key(self, _ctl, keyval: int, keycode: int, state: Gdk.ModifierType) -> bool:
        if not self.capturing:
            return False
        name = (Gdk.keyval_name(keyval) or "").lower()
        if name in MODIFIER_KEYVALS:
            return True                                  # wait for the real key
        if name == "escape" and not state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK
                                             | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SUPER_MASK):
            self.capture_btn.set_active(False)
            return True
        ok, base, *_ = self.get_display().translate_key(keycode, 0, 0)
        key = keyd_name(Gdk.keyval_name(base) if ok and base else name)
        mods = {m for m, mask in (("C", Gdk.ModifierType.CONTROL_MASK), ("S", Gdk.ModifierType.SHIFT_MASK),
                                  ("A", Gdk.ModifierType.ALT_MASK), ("M", Gdk.ModifierType.SUPER_MASK)) if state & mask}
        self._set_entry(kp.chord(mods, key))
        self._on_edit()
        self.capture_btn.set_active(False)
        return True

    # ---- save / deploy ----------------------------------------------------------------
    def _save(self) -> None:
        bad = [k.id for k in (self.model.keys if self.model else ()) if kp.validate(kp.action_of(self.device, k))]
        if bad:
            self.win.toast(f"Fix keys {', '.join(bad)} first", error=True)
            return
        p = kp.save(self.data)
        if paths.git_enabled():
            from .. import gitsync
            try:
                gitsync.commit([p], f"sway-apps: keypad {self.dev_name} mapping")
            except Exception as exc:   # noqa: BLE001 - the file is saved either way
                _log.warning("keypad commit failed: %s", exc)
        self.saved = copy.deepcopy(self.data)
        self.win.toast("Keypad mapping saved · Deploy to make it live")
        self.refresh()

    def _discard(self) -> None:
        self.data = copy.deepcopy(self.saved)
        if self.sel_key:
            self.select_key(self.sel_key)
        self.refresh()

    def _deploy(self) -> None:
        prof = paths.profile_name()
        script = f"cd {paths.DOTFILES} && ./install.sh {paths.DOTFILES} {prof} -s -d"
        inner = f"{script}; echo; echo '--- deploy finished (exit '$?') --- press Enter to close'; read -r _"
        confirm(self.win, f"Deploy {prof}?", "keyd is a system service: install.sh rebuilds and restarts it "
                "(keyboards are released for a moment). Runs in a terminal and asks for your password.", "Deploy",
                lambda: (swayipc.exec_(f"kitty --class sway-apps-deploy --title 'Deploy {prof}' -e bash -lc {shlex.quote(inner)}"),
                         self.win.toast(f"Deploy of {prof} opened in a terminal")))
