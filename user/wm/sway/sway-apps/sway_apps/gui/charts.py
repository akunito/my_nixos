"""Tiny cairo charts: level-coloured gauges and sparklines. Colours come from
the same base16 tokens as the rest of the UI (stylix or the built-in palette)."""
from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk  # noqa: E402

from . import theme  # noqa: E402

_TOKENS: dict[str, str] | None = None


def _rgb(hex6: str) -> tuple[float, float, float]:
    return tuple(int(hex6[i:i + 2], 16) / 255 for i in (0, 2, 4))  # type: ignore[return-value]


def palette() -> dict[str, tuple[float, float, float]]:
    global _TOKENS
    if _TOKENS is None:
        _TOKENS, _src = theme.load_tokens()
    t = _TOKENS
    return {"ok": _rgb(t["base0B"]), "warn": _rgb(t["base0A"]), "err": _rgb(t["base08"]), "": _rgb(t["base0D"]),
            "fg": _rgb(t["base05"]), "muted": _rgb(t["base03"])}


class Gauge(Gtk.Box):
    """title ......... value  +  a horizontal bar filled to pct and coloured by level."""

    def __init__(self, title: str, pct: float | None, value: str, level: str, subtitle: str = "") -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        head = Gtk.Box(spacing=8)
        t = Gtk.Label(label=title, xalign=0, hexpand=True, ellipsize=3); t.add_css_class("sa-gauge-title")
        v = Gtk.Label(label=value, xalign=1); v.add_css_class("sa-gauge-value")
        if level:
            v.add_css_class(f"sa-level-{level}")
        head.append(t); head.append(v)
        self.append(head)
        self.pct = None if pct is None else max(0.0, min(100.0, pct))
        self.level = level
        area = Gtk.DrawingArea(); area.set_content_height(7); area.set_hexpand(True)
        area.set_draw_func(self._draw)
        self.append(area)
        if subtitle:
            s = Gtk.Label(label=subtitle, xalign=0, ellipsize=3); s.add_css_class("sa-legend"); self.append(s)

    def _draw(self, _area, cr, w, h):
        p = palette()
        r = h / 2
        cr.set_source_rgba(*p["fg"], 0.12)
        _round_rect(cr, 0, 0, w, h, r); cr.fill()
        if self.pct is None:
            return
        fw = max(h, w * self.pct / 100) if self.pct > 0 else 0
        if fw:
            cr.set_source_rgb(*p[self.level or ""])
            _round_rect(cr, 0, 0, fw, h, r); cr.fill()


class Sparkline(Gtk.DrawingArea):
    """A filled line over a short series; colour by level. `ymax` pins the scale
    (e.g. 100 for percentages) so charts of the same kind are comparable."""

    def __init__(self, series: list[float | None], level: str = "", height: int = 38, ymax: float | None = None) -> None:
        super().__init__()
        self.series = series; self.level = level; self.ymax = ymax
        self.set_content_height(height); self.set_hexpand(True)
        self.set_draw_func(self._draw)

    def _draw(self, _area, cr, w, h):
        p = palette()
        pts = [(i, v) for i, v in enumerate(self.series) if v is not None]
        if len(pts) < 2:
            cr.set_source_rgba(*p["fg"], 0.35)
            cr.move_to(4, h / 2 + 4); cr.set_font_size(11); cr.show_text("no data"); return
        n = len(self.series)
        vals = [v for _i, v in pts]
        lo = 0.0
        hi = self.ymax if self.ymax is not None else max(vals)
        if hi <= lo:
            hi = lo + 1
        pad = 2
        def X(i): return pad + (w - 2 * pad) * i / max(1, n - 1)
        def Y(v): return h - pad - (h - 2 * pad) * (min(v, hi) - lo) / (hi - lo)
        col = p[self.level or ""]
        cr.set_source_rgba(*p["fg"], 0.08)
        for frac in (0.25, 0.5, 0.75):
            cr.move_to(0, h * frac); cr.line_to(w, h * frac)
        cr.set_line_width(1); cr.stroke()
        cr.move_to(X(pts[0][0]), h - pad)
        for i, v in pts:
            cr.line_to(X(i), Y(v))
        cr.line_to(X(pts[-1][0]), h - pad); cr.close_path()
        cr.set_source_rgba(*col, 0.18); cr.fill()
        cr.move_to(X(pts[0][0]), Y(pts[0][1]))
        for i, v in pts[1:]:
            cr.line_to(X(i), Y(v))
        cr.set_source_rgb(*col); cr.set_line_width(1.6); cr.stroke()


def _round_rect(cr, x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -1.5708, 0)
    cr.arc(x + w - r, y + h - r, r, 0, 1.5708)
    cr.arc(x + r, y + h - r, r, 1.5708, 3.14159)
    cr.arc(x + r, y + r, r, 3.14159, 4.71239)
    cr.close_path()


def card(title: str, subtitle: str = "", level: str = "") -> tuple[Gtk.Box, Gtk.Box]:
    """A rounded card with a title row; returns (card, body) — append widgets to body."""
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8); box.add_css_class("sa-card")
    head = Gtk.Box(spacing=8)
    t = Gtk.Label(label=title, xalign=0, hexpand=True); t.add_css_class("sa-card-title")
    head.append(t)
    if subtitle:
        s = Gtk.Label(label=subtitle, xalign=1); s.add_css_class("sa-legend")
        if level:
            s.remove_css_class("sa-legend"); s.add_css_class("sa-chip"); s.add_css_class(level)
        head.append(s)
    box.append(head)
    body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    box.append(body)
    return box, body
