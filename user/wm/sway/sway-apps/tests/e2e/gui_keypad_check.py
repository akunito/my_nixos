"""Drives the Keypad GUI page (SWAY-18) inside the nested sway (case_keypad_gui_page), against a
scratch copy of keyd-devices.json (SWAY_APPS_STATE_DIR, SWAY_APPS_GIT=0). Prints PASS/FAIL lines."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

os.environ.setdefault("GSK_RENDERER", "cairo")
os.environ.setdefault("GTK_A11Y", "none")
os.environ.setdefault("GDK_DEBUG", "no-portals")
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib  # noqa: E402

from sway_apps import keypad as kp  # noqa: E402
from sway_apps.gui.panels_keypad import KeypadPanel  # noqa: E402

failures: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(("PASS " if ok else "FAIL ") + name + (f" ({detail})" if detail and not ok else ""), flush=True)
    if not ok:
        failures.append(name)


class FakeWin:
    def __init__(self) -> None:
        self.toasts: list[tuple[str, bool]] = []

    def toast(self, text: str, error: bool = False, timeout: int = 4) -> None:
        self.toasts.append((text, error))


def pump(n: int = 20) -> None:
    ctx = GLib.MainContext.default()
    for _ in range(n):
        while ctx.pending():
            ctx.iteration(False)


def drive(app: Adw.Application) -> None:
    win = Adw.ApplicationWindow(application=app, title="keypad-check", default_width=900, default_height=900)
    fake = FakeWin()
    panel = KeypadPanel(fake)
    win.set_content(panel)
    win.present()
    pump(40)
    panel.on_show()
    check("device loaded", panel.model is not None and panel.dev_name == "razer_tartarus", str(panel.dev_name))
    # a click on key 20 of the drawing selects it
    f, ox, oy = panel.canvas._view
    k20 = panel.model.key("20")
    panel.canvas._click(None, 1, ox + (k20.x + k20.w / 2) * f, oy + (k20.y + k20.h / 2) * f)
    check("canvas click selects key 20", panel.sel_key == "20" and panel.action_row.get_text() == "f",
          f"{panel.sel_key} {panel.action_row.get_text()!r}")
    panel.select_key("07")
    check("key 07 shows its mapping", panel.key_row.get_title() == "Key 07" and panel.action_row.get_text() == "5")
    panel.action_row.set_text("C-a")
    check("valid edit applies", panel.profile["main"]["q"] == "C-a" and panel.dirty() and panel.save_btn.get_sensitive())
    panel.action_row.set_text("command(id)")
    check("command() refused, mapping kept", panel.profile["main"]["q"] == "C-a"
          and "root" in panel.status_row.get_title(), panel.status_row.get_title())
    panel.action_row.set_text("C-a")
    panel._save()
    saved = json.loads(kp.file_path().read_text())
    check("save writes the JSON", saved["devices"]["razer_tartarus"]["profiles"]["aion2"]["main"]["q"] == "C-a" and not panel.dirty())
    check("subtitle says it is not live yet", "Deploy" in panel.title.get_subtitle(), panel.title.get_subtitle())
    panel._default()
    check("Default drops the entry", "q" not in panel.profile["main"] and panel.action_row.get_text() == "q")
    panel._discard()
    check("Discard returns to the saved file", panel.profile["main"].get("q") == "C-a")
    # profiles: a new one copies the current mapping, edits stay in it, Use now switches
    check("starts on the default profile", panel.pid == "aion2", panel.pid)
    panel.new_profile("Lineage 2")
    pump()
    check("new profile selected, a copy", panel.pid == "lineage_2" and panel.profile["main"].get("q") == "C-a", panel.pid)
    panel.select_key("07")
    panel.action_row.set_text("6")
    check("edit lands in the new profile only", panel.profile["main"]["q"] == "6"
          and panel.device["profiles"]["aion2"]["main"]["q"] == "C-a")
    check("strip lists both", [c.get_label().split("  ")[0] for c in _children(panel.prof_box)] == ["Aion 2", "Native (no remap)", "Lineage 2"],
          str([c.get_label() for c in _children(panel.prof_box)]))
    check("Use now off while unsaved/undeployed", not panel.use_btn.get_sensitive())
    panel.rename_profile("L2 Reborn")
    panel._make_default()
    panel._save()
    saved = json.loads(kp.file_path().read_text())["devices"]["razer_tartarus"]
    check("saved: name, mapping, default", saved["profiles"]["lineage_2"] == {"name": "L2 Reborn", "main": {**saved["profiles"]["aion2"]["main"], "q": "6"}}
          and saved["default_profile"] == "lineage_2", json.dumps(saved)[:300])
    _children(panel.prof_box)[0].set_active(True)
    pump()
    check("clicking a profile shows its mapping", panel.pid == "aion2" and panel.action_row.get_text() == "C-a",
          f"{panel.pid} {panel.action_row.get_text()!r}")
    calls = []
    kp.activate = lambda dev, pid: (calls.append((dev, pid)), (True, f"{dev} -> {pid}"))[1]
    built = lambda d, pid, etc=None: dict(json.loads(kp.file_path().read_text())["devices"][d]["profiles"][pid]["main"])
    kp.deployed = built                                   # as if install.sh had built them
    kp.live_profile = lambda d, var=None: "aion2" if not calls else calls[-1][1]
    panel.select_profile("lineage_2")
    pump()
    check("Use now enabled once built", panel.use_btn.get_sensitive())
    panel._use()
    pump()
    check("Use now calls keypad-profile set", calls == [("razer_tartarus", "lineage_2")] and "live: L2 Reborn" in panel.title.get_subtitle(),
          f"{calls} {panel.title.get_subtitle()}")
    panel._make_default()
    check("default cannot be deleted", "default" in (kp.delete_profile(panel.device, "lineage_2") or ""))
    panel.select_profile("aion2")
    pump()
    panel.delete_profile()
    pump()
    check("delete drops it and falls back to the default", list(panel.device["profiles"]) == ["native", "lineage_2"] and panel.pid == "lineage_2")
    panel._discard()
    check("discard brings it back", "aion2" in panel.device["profiles"])
    check("no error toasts", not any(e for _t, e in fake.toasts), str(fake.toasts))


def _children(box) -> list:
    out, c = [], box.get_first_child()
    while c is not None:
        out.append(c)
        c = c.get_next_sibling()
    return out


def main() -> int:
    app = Adw.Application(application_id=None)

    def run(a) -> bool:
        try:
            drive(a)
        except Exception as exc:
            import traceback
            traceback.print_exc()
            check("drive", False, repr(exc))
        finally:
            a.quit()
        return False
    app.connect("activate", lambda a: GLib.idle_add(run, a))
    app.run([])
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
