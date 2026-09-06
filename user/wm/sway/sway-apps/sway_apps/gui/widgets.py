"""Small reusable GTK pieces."""
from __future__ import annotations

from typing import Callable

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402


def chip(text: str, style: str = "") -> Gtk.Label:
    lbl = Gtk.Label(label=text)
    lbl.add_css_class("sa-chip")
    if style:
        lbl.add_css_class(style)
    lbl.set_valign(Gtk.Align.CENTER)
    return lbl


def list_row(title: str, subtitle: str, chips: list[tuple[str, str]] | None = None, disabled: bool = False,
             trailing: Gtk.Widget | None = None) -> Gtk.ListBoxRow:
    row = Gtk.ListBoxRow()
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
    text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, hexpand=True)
    t = Gtk.Label(label=title, xalign=0, ellipsize=3)
    t.add_css_class("sa-row-title")
    s = Gtk.Label(label=subtitle, xalign=0, ellipsize=3)
    s.add_css_class("sa-row-sub")
    text.append(t)
    if subtitle:
        text.append(s)
    box.append(text)
    for c, style in chips or []:
        box.append(chip(c, style))
    if trailing is not None:
        box.append(trailing)
    row.set_child(box)
    if disabled:
        row.add_css_class("sa-row-disabled")
    return row


def section(title: str) -> Gtk.Label:
    lbl = Gtk.Label(label=title.upper(), xalign=0)
    lbl.add_css_class("sa-section-title")
    return lbl


def entry_row(title: str, value: str = "", placeholder: str = "", subtitle: str = "") -> Adw.EntryRow:
    row = Adw.EntryRow(title=title)
    row.set_text(value)
    if placeholder:
        row.set_property("placeholder-text", placeholder) if hasattr(row.props, "placeholder_text") else None
    return row


def combo_row(title: str, options: list[str], current: str, subtitle: str = "") -> Adw.ComboRow:
    row = Adw.ComboRow(title=title)
    if subtitle:
        row.set_subtitle(subtitle)
    model = Gtk.StringList.new(options)
    row.set_model(model)
    try:
        row.set_selected(options.index(current))
    except ValueError:
        row.set_selected(0)
    return row


def combo_value(row: Adw.ComboRow) -> str:
    item = row.get_selected_item()
    return item.get_string() if item is not None else ""


def switch_row(title: str, active: bool, subtitle: str = "") -> Adw.SwitchRow:
    row = Adw.SwitchRow(title=title)
    if subtitle:
        row.set_subtitle(subtitle)
    row.set_active(active)
    return row


def button(label: str, on_click: Callable[[], None], style: str = "", icon: str | None = None) -> Gtk.Button:
    if icon:
        b = Gtk.Button()
        content = Adw.ButtonContent(icon_name=icon, label=label)
        b.set_child(content)
    else:
        b = Gtk.Button(label=label)
    if style:
        for s in style.split():
            b.add_css_class(s)
    b.connect("clicked", lambda *_: on_click())
    return b


def empty_state(title: str, description: str, icon: str = "view-list-symbolic") -> Adw.StatusPage:
    page = Adw.StatusPage(title=title, description=description, icon_name=icon)
    page.add_css_class("compact")
    return page


def scrolled(child: Gtk.Widget) -> Gtk.ScrolledWindow:
    sw = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
    sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    sw.set_child(child)
    return sw


def confirm(parent: Gtk.Window, heading: str, body: str, action: str, on_confirm: Callable[[], None]) -> None:
    dlg = Adw.AlertDialog(heading=heading, body=body)
    dlg.add_response("cancel", "Cancel")
    dlg.add_response("ok", action)
    dlg.set_response_appearance("ok", Adw.ResponseAppearance.DESTRUCTIVE)
    dlg.set_default_response("cancel")

    def _resp(_d, resp):
        if resp == "ok":
            on_confirm()
    dlg.connect("response", _resp)
    dlg.present(parent)
