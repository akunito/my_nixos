"""Per-monitor Waybar (sway_apps/waybar.py): model layering, generation, CSS
rules for effective visibility / auto-all / sizes, the watch hooks. Offline:
sway is a fake. Run: python3 -m unittest discover -s tests"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import ipc, paths, watch, waybar  # noqa: E402
from sway_apps.state import Monitor, State  # noqa: E402

CATALOG = {
    "version": 1,
    "modules": {"sway/workspaces": {"disable-scroll": True, "format": "{icon}"}, "tray": {"icon-spacing": 8},
                "clock": {"format": "{:%H:%M}"}, "custom/llm": {"exec": "/nix/store/x-llm"}, "pulseaudio": {}},
    "layouts": {"primary": {"left": ["pulseaudio", "custom/llm"], "center": ["sway/workspaces"], "right": ["tray", "clock"]},
                "secondary": {"left": ["pulseaudio"], "center": ["sway/workspaces"], "right": ["tray", "clock"]}},
    "bar": {"layer": "top", "position": "top", "height": 30, "spacing": 0},
    "sizes": {"font": 13, "tray_icon": 16},
    "default_visible": "primary",
}
MAIN = "Samsung Electric Company Odyssey G70NC H1AK500000"
SECOND = "NSL RGB-27QHDS    Unknown"


def out(name, make, model, serial, ws, focused=False, nodes=None):
    """A get_tree output node (also good enough as a get_outputs entry)."""
    return {"type": "output", "name": name, "make": make, "model": model, "serial": serial, "active": True,
            "focused": focused, "current_workspace": ws,
            "nodes": nodes if nodes is not None else [{"type": "workspace", "name": ws, "fullscreen_mode": 1,
                                                      "nodes": [], "floating_nodes": []}]}


def ws(name, fullscreen=0, floating=False):
    con = {"type": "con", "fullscreen_mode": fullscreen, "nodes": [], "floating_nodes": []}
    node = {"type": "workspace", "name": name, "fullscreen_mode": 1, "nodes": [], "floating_nodes": []}  # as sway reports it
    node["floating_nodes" if floating else "nodes"].append(con)
    return node


DP1 = lambda **kw: out("DP-1", "Samsung Electric Company", "Odyssey G70NC", "H1AK500000", kw.pop("ws", "11"), **kw)
DP2 = lambda **kw: out("DP-2", "NSL", "RGB-27QHDS   ", "Unknown", kw.pop("ws", "21"), **kw)
HDMI = lambda **kw: out("HDMI-A-1", "Philips", "TV", "1", kw.pop("ws", "31"), **kw)
HDMI2 = lambda **kw: out("HDMI-A-2", "Acme", "Panel", "9", kw.pop("ws", "41"), **kw)


class FakeSway:
    def __init__(self, outputs, bar_ids=None, fail=False):
        self._outputs = outputs
        self.cmds: list[str] = []
        self._bar_ids = bar_ids
        self.fail = fail

    def command(self, cmd):
        self.cmds.append(cmd)
        if self.fail and cmd.startswith("bar "):
            raise ipc.IpcError("No bar with id")
        return [{"success": True}]

    def tree(self):
        return {"type": "root", "nodes": [{"type": "output", "name": "__i3", "nodes": []}] + self._outputs}

    def outputs(self):
        return self._outputs

    def bar_ids(self):
        return list(self._bar_ids if self._bar_ids is not None else ())


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.cfg = self.tmp / "cfg"
        self._patches = [
            mock.patch.object(paths, "STATE_DIR", self.tmp / "state"),
            mock.patch.dict(os.environ, {"SWAY_APPS_PROFILE": "TESTWB", "SWAY_APPS_GIT": "0"}),
        ]
        for name, rel in (("CATALOG_FILE", "sway-apps/waybar-modules.json"), ("BASE_CSS_FILE", "sway-apps/waybar-base.css"),
                          ("CONFIG_FILE", "waybar/config"), ("STYLE_FILE", "waybar/style.css"),
                          ("CSS_FILE", "waybar/sway-apps.css"), ("BARS_FILE", "sway/sway-apps-bars.conf")):
            self._patches.append(mock.patch.object(waybar, name, self.cfg / rel))
        self._patches.append(mock.patch.object(waybar, "LOCAL_FILE", self.tmp / "local" / "waybar.json"))
        for p in self._patches:
            p.start()
        (self.cfg / "sway-apps").mkdir(parents=True)
        (self.cfg / "sway-apps" / "waybar-modules.json").write_text(json.dumps(CATALOG))
        (self.cfg / "sway-apps" / "waybar-base.css").write_text("* { font-size: 13px; }\n")
        self.state = State()
        self.state.save_monitor(Monitor(id="main", criteria=MAIN, group=1, primary=True), "profile")
        self.state.save_monitor(Monitor(id="second", criteria=SECOND, group=2), "profile")
        self.state.write()

    def tearDown(self):
        for p in reversed(self._patches):
            p.stop()

    def model(self, catalog=None, local=None):
        return waybar.Model(State(), catalog=catalog, local=local)

    def set_profile_feat(self, feat):
        st = State()
        st.set_feature("waybar", feat, "profile")
        st.write()


class Catalog(Base):
    def test_fallback_when_missing(self):
        cat = waybar.load_catalog(self.tmp / "nope.json")
        self.assertIn("sway/workspaces", cat["modules"])
        self.assertEqual(cat["default_visible"], "primary")

    def test_clean_layout_drops_unknown_and_duplicates(self):
        lay = waybar.clean_layout({"left": ["clock", "custom/gcal", "clock"], "right": ["clock", "tray"], "center": "x"},
                                  CATALOG["modules"])
        self.assertEqual(lay, {"left": ["clock"], "center": [], "right": ["tray"]})

    def test_clean_layout_maps_renamed_modules(self):
        mods = {**CATALOG["modules"], "custom/idle": {}}
        lay = waybar.clean_layout({"right": ["idle_inhibitor", "tray", "custom/idle"]}, mods)
        self.assertEqual(lay["right"], ["custom/idle", "tray"])        # old name kept its slot, no duplicate

    def test_template_from_other_host_is_filtered(self):
        cat = json.loads(json.dumps(CATALOG))
        del cat["modules"]["custom/llm"]  # X13: no local LLM
        m = self.model(catalog=cat)
        self.assertEqual(m.by_key["main"].layout["left"], ["pulseaudio"])
        self.assertNotIn("custom/llm", waybar.render_config(m, {}))


class Layering(Base):
    def test_default_primary_policy(self):
        m = self.model()
        self.assertEqual([(b.key, b.visible, b.template) for b in m.bars],
                         [("main", True, "primary"), ("second", False, "secondary"), ("other", False, "secondary")])
        self.assertTrue(all(b.ws == "output" and b.size == 100 for b in m.bars))

    def test_default_all_policy(self):
        cat = dict(CATALOG, default_visible="all")
        m = self.model(catalog=cat)
        self.assertEqual([b.visible for b in m.bars], [True, True, False])

    def test_no_registry_catch_all_visible(self):
        st = State()
        for mon_ in st.monitors():
            st.remove("monitors", mon_.id)
        st.write()
        m = self.model()
        self.assertEqual([(b.key, b.visible) for b in m.bars], [("other", True)])

    def test_profile_then_local(self):
        self.set_profile_feat({"bars": {"second": {"visible": True, "ws": "all", "size": 120}}})
        m = self.model()
        b = m.by_key["second"]
        self.assertEqual((b.visible, b.ws, b.size, b.local), (True, "all", 120, {}))
        m = self.model(local={"bars": {"second": {"visible": False, "size": 999}}, "connectors": {}})
        b = m.by_key["second"]
        self.assertEqual((b.visible, b.ws, b.size), (False, "all", waybar.SIZE_MAX))
        self.assertEqual(b.saved, {"visible": True, "ws": "all", "size": 120})
        self.assertEqual(b.local, {"visible": False, "size": waybar.SIZE_MAX})

    def test_invalid_values_fall_back(self):
        self.set_profile_feat({"bars": {"main": {"ws": "bogus", "size": "x", "template": "nope"}}})
        b = self.model().by_key["main"]
        self.assertEqual((b.ws, b.size, b.template), ("output", 100, "primary"))

    def test_save_default_and_reset(self):
        waybar.save_local({"bars": {"second": {"visible": True, "ws": "all"}}, "connectors": {}})
        st = State()
        waybar.save_default(st)
        st.write()
        self.assertEqual(waybar.load_local()["bars"], {})
        b = self.model().by_key["second"]
        self.assertEqual((b.visible, b.ws, b.local), (True, "all", {}))
        self.assertEqual(State().profile["settings"]["waybar"]["bars"]["second"], {"visible": True, "ws": "all", "size": 100})
        waybar.save_local({"bars": {"second": {"visible": False}}, "connectors": {}})
        waybar.reset_local()
        self.assertTrue(self.model().by_key["second"].visible)

    def test_templates_and_custom_bar(self):
        st = State()
        waybar.set_template(st, "secondary", {"left": [], "center": ["sway/workspaces"], "right": ["clock", "bogus"]})
        waybar.set_bar_template(st, "main", "custom", {"left": ["clock"], "center": [], "right": ["tray"]})
        st.write()
        m = self.model()
        self.assertEqual(m.by_key["second"].layout, {"left": [], "center": ["sway/workspaces"], "right": ["clock"]})
        self.assertEqual(m.by_key["other"].layout["right"], ["clock"])
        self.assertEqual((m.by_key["main"].template, m.by_key["main"].layout["right"]), ("custom", ["tray"]))
        st = State()
        waybar.set_template(st, "secondary", None)
        waybar.set_bar_template(st, "main", "primary")
        st.write()
        m = self.model()
        self.assertEqual(m.by_key["second"].layout, m.default_template_layout("secondary"))
        self.assertNotIn("modules", State().profile["settings"]["waybar"]["bars"]["main"])

    def test_resolve(self):
        m = self.model()
        self.assertEqual(m.resolve("main").key, "main")
        self.assertEqual(m.resolve("wb-second").key, "second")
        self.assertEqual(m.resolve("DP-2", [DP1(), DP2()]).key, "second")
        self.assertEqual(m.resolve("HDMI-A-1", [HDMI()]).key, "other")
        with self.assertRaises(KeyError):
            m.resolve("nope")


class Generation(Base):
    def test_config_bars(self):
        m = self.model(local={"bars": {"second": {"size": 150}}, "connectors": {}})
        bars = json.loads(waybar.render_config(m, {"main": "DP-1", "second": "DP-2"}))
        self.assertEqual([b["id"] for b in bars], ["wb-main", "wb-second", "wb-other"])
        main, second, other = bars
        self.assertEqual(main["output"], ["DP-1", MAIN])
        self.assertEqual(other["output"], ["!DP-1", f"!{MAIN}", "!DP-2", f"!{SECOND}", "*"])
        for b in bars:
            self.assertTrue(b["ipc"])
            self.assertEqual(b["name"], b["id"])
            shown = {"layer": "top", "exclusive": True, "passthrough": False, "visible": True}
            self.assertEqual(b["modes"], {"dock": shown, "overlay": shown})
            self.assertTrue(b["reload_style_on_change"])
            self.assertTrue(b["sway/workspaces"]["all-outputs"])
        self.assertEqual(main["modules-left"], ["pulseaudio", "custom/llm"])
        self.assertIn("custom/llm", main)
        self.assertNotIn("custom/llm", second)  # only modules of its own layout
        self.assertEqual((main["height"], second["height"]), (30, 45))
        self.assertNotIn("icon-size", main["tray"])
        self.assertEqual(second["tray"]["icon-size"], 24)

    def test_absent_monitor_matches_by_hw_id_only(self):
        bars = json.loads(waybar.render_config(self.model(), {}))
        self.assertEqual(bars[0]["output"], [MAIN])

    def test_bars_conf(self):
        text = waybar.render_bars(self.model())
        self.assertIn("bar {\n    id wb-main\n    swaybar_command true\n    mode dock\n}", text)  # no window info: dock
        self.assertIn("bar {\n    id wb-second\n    swaybar_command true\n    mode invisible\n}", text)
        self.assertIn("id wb-other\n", text)
        self.assertEqual(waybar.parse_bars(text), {"wb-main": "dock", "wb-second": "invisible", "wb-other": "invisible"})

    def test_style_imports_generated_css_first(self):
        text = waybar.render_style("* { a: b; }\n")
        first_rule = [l for l in text.splitlines() if l and not l.startswith("/*")][0]
        self.assertEqual(first_rule, f'@import url("{waybar.CSS_FILE}");')
        self.assertTrue(text.endswith("* { a: b; }\n"))


class EffectiveVisibility(Base):
    def setUp(self):
        super().setUp()
        self.both = {"bars": {"second": {"visible": True}}, "connectors": {}}

    def modes(self, model, outputs):
        return waybar.bar_modes(model, waybar.windows(model, {"nodes": outputs}))

    def test_two_visible_bars_show_their_own(self):
        self.assertEqual(self.modes(self.model(local=self.both), [DP1(), DP2()]),
                         {"main": "dock", "second": "dock", "other": "invisible"})

    def test_single_visible_bar_shows_all(self):
        self.assertEqual(self.modes(self.model(), [DP1(), DP2()])["main"], "overlay")  # second hidden by default

    def test_monitor_absent_leaves_one_bar(self):
        self.assertEqual(self.modes(self.model(local=self.both), [DP1()])["main"], "overlay")

    def test_fullscreen_on_other_output_makes_solo(self):
        modes = self.modes(self.model(local=self.both), [DP1(nodes=[ws("11", fullscreen=1)]), DP2()])
        self.assertEqual((modes["main"], modes["second"]), ("dock", "overlay"))  # main stays docked under the game

    def test_fullscreen_floating_counts(self):
        wins = waybar.windows(self.model(local=self.both), {"nodes": [DP1(nodes=[ws("11", 1, floating=True)]), DP2()]})
        self.assertEqual([(w.key, w.fullscreen) for w in wins], [("main", True), ("second", False)])

    def test_fullscreen_on_hidden_workspace_ignored(self):
        dp1 = DP1(nodes=[ws("11"), ws("12", fullscreen=1)])
        modes = self.modes(self.model(local=self.both), [dp1, DP2()])
        self.assertEqual((modes["main"], modes["second"]), ("dock", "dock"))

    def test_global_fullscreen_hides_every_bar(self):
        wins = waybar.windows(self.model(local=self.both), {"nodes": [DP1(nodes=[ws("11", fullscreen=2)]), DP2()]})
        self.assertFalse(any(w.effective for w in wins))

    def test_ws_all(self):
        local = {"bars": {"second": {"visible": True, "ws": "all"}}, "connectors": {}}
        modes = self.modes(self.model(local=local), [DP1(), DP2()])
        self.assertEqual((modes["main"], modes["second"]), ("dock", "overlay"))

    def test_catch_all_on_two_outputs(self):
        local = {"bars": {"main": {"visible": False}, "other": {"visible": True}}, "connectors": {}}
        modes = self.modes(self.model(local=local), [DP1(), HDMI(), HDMI2(nodes=[ws("41", fullscreen=1)])])
        self.assertEqual(modes["other"], "overlay")  # its only drawn window is HDMI-A-1
        modes = self.modes(self.model(local=local), [DP1(), HDMI(), HDMI2()])
        self.assertEqual(modes["other"], "dock")

    def test_inactive_and_headless_outputs_skipped(self):
        dp2 = DP2()
        dp2["active"] = False
        headless = out("HEADLESS-1", "Unknown", "Unknown", "Unknown", "1")
        with mock.patch.object(paths, "E2E", False):
            wins = waybar.windows(self.model(), {"nodes": [DP1(), dp2, headless]})
        self.assertEqual([w.output for w in wins], ["DP-1"])

    def test_css_static_collapse_and_sizes(self):
        css = waybar.render_css(self.model(local={"bars": {"main": {"size": 150}}, "connectors": {}}))
        rule = [l for l in css.splitlines() if l.startswith("window#waybar.mode-dock #workspaces button:not(.current_output) label")][0]
        for prop in ("min-width: 0", "padding: 0", "margin: 0", "font-size: 0", "opacity: 0"):
            self.assertIn(prop, rule)
        self.assertIn("window#waybar.wb-main * { font-size: 20px; }", css)  # 13 * 1.5 = 19.5 -> 20
        self.assertIn("window#waybar.wb-main #workspaces button { min-width: 30px;", css)
        self.assertIn("window#waybar.wb-main #custom-notifications.hidden { margin: 0; padding: 0; }", css)
        self.assertNotIn("wb-second", css)  # 100 % = the base CSS untouched
        self.assertEqual(css, waybar.render_css(self.model(local={"bars": {"main": {"size": 150}}, "connectors": {}})))


class RuntimeOps(Base):
    def synced(self, outputs, **kw):
        rt = waybar.Runtime()
        sway = FakeSway(outputs, bar_ids=kw.pop("bar_ids", ["wb-main", "wb-second", "wb-other"]), **kw)
        with mock.patch.object(waybar, "reload_waybar", return_value=True):
            rt.sync(sway)
        sway.cmds.clear()
        return rt, sway

    def test_sync_sends_every_mode(self):
        sway = FakeSway([DP1(), DP2()], bar_ids=["wb-main", "wb-second", "wb-other"])
        with mock.patch.object(waybar, "reload_waybar", return_value=True):
            waybar.Runtime().sync(sway)
        self.assertEqual(sway.cmds, ["bar wb-main mode overlay; bar wb-second mode invisible; bar wb-other mode invisible"])

    def test_toggle_hides_one_bar_and_persists(self):
        rt, sway = self.synced([DP1(focused=True), DP2()])
        rt.set_live(["second"], sway, visible=True)  # two bars: both show their own
        self.assertEqual(sway.cmds, ["bar wb-main mode dock; bar wb-second mode dock"])
        res = rt.set_live(["second"], sway, visible=None)
        self.assertEqual(sway.cmds[-1], "bar wb-main mode overlay; bar wb-second mode invisible")
        self.assertFalse(res["bars"]["second"]["visible"])
        self.assertEqual(waybar.load_local()["bars"]["second"], {"visible": False})
        self.assertEqual(waybar.parse_bars(waybar.BARS_FILE.read_text())["wb-second"], "invisible")
        # a new process (CLI) reads what sway was told from the file
        waybar.Runtime().set_live(["second"], sway, visible=True)
        self.assertEqual(sway.cmds[-1], "bar wb-main mode dock; bar wb-second mode dock")

    def test_unchanged_visibility_sends_nothing(self):
        rt, sway = self.synced([DP1(focused=True)])
        rt.set_live(["main"], sway, visible=True)
        self.assertEqual(sway.cmds, [])

    def test_unknown_bar_triggers_sway_reload(self):
        rt, sway = self.synced([DP1(focused=True)])
        sway.fail, sway._bar_ids = True, ["bar-0"]
        with mock.patch.object(waybar, "reload_waybar", return_value=True) as rw:
            rt.set_live(["main"], sway, visible=False)
        self.assertIn("reload", sway.cmds)
        rw.assert_called()

    def test_ws_change_is_ipc_only(self):
        rt, sway = self.synced([DP1(), DP2()])
        rt.set_live(["second"], sway, visible=True)
        css = waybar.CSS_FILE.read_text()
        res = rt.set_live(["second"], sway, ws="all")
        self.assertEqual(res["modes"], {"wb-second": "overlay"})
        self.assertEqual(sway.cmds[-1], "bar wb-second mode overlay")
        self.assertEqual(waybar.CSS_FILE.read_text(), css)

    def test_fullscreen_refresh(self):
        rt, sway = self.synced([DP1(), DP2()])
        rt.set_live(["second"], sway, visible=True)
        sway._outputs = [DP1(), DP2(nodes=[ws("21", fullscreen=1)])]
        self.assertEqual(rt.refresh(sway), {"wb-main": "overlay"})
        self.assertEqual(rt.refresh(sway), {})

    def test_size_change_regenerates_and_restarts_waybar(self):
        rt, sway = self.synced([DP1(), DP2()])
        with mock.patch.object(waybar, "reload_waybar", return_value=True) as rw:
            res = rt.set_live(["main"], sway, size=120)
        self.assertTrue(res["sync"]["config_changed"])
        rw.assert_called_once_with(None)
        self.assertEqual(json.loads(waybar.CONFIG_FILE.read_text())[0]["height"], 36)

    def test_sync_idempotent(self):
        sway = FakeSway([DP1(), DP2()], bar_ids=["wb-main", "wb-second", "wb-other"])
        with mock.patch.object(waybar, "reload_waybar", return_value=True) as rw:
            first = waybar.Runtime().sync(sway)
            second = waybar.Runtime().sync(sway)
        self.assertTrue(first["config_changed"] and first["bars_changed"] and first["style_changed"])
        self.assertFalse(second["config_changed"] or second["bars_changed"] or second["style_changed"] or second["css_changed"])
        self.assertEqual(rw.call_count, 1)
        self.assertNotIn("reload", sway.cmds)
        self.assertTrue(waybar.CSS_FILE.read_text().startswith(waybar.CSS_HEADER))
        self.assertEqual(waybar.load_local()["connectors"], {"main": "DP-1", "second": "DP-2"})

    def test_sync_without_reload_leaves_pending_for_later(self):
        with mock.patch.object(waybar, "reload_waybar", return_value=True) as rw:
            waybar.Runtime().sync(None, reload=False)  # activation without a session
            rw.assert_not_called()
            pending = waybar.load_local()["pending_reload"]
            sway = FakeSway([DP1(), DP2()], bar_ids=["wb-main", "wb-second", "wb-other"])
            waybar.Runtime().sync(sway, reload=True)
        # connectors are new to the config -> changed -> unconditional reload
        rw.assert_called_once_with(None)
        self.assertNotIn("pending_reload", waybar.load_local())
        self.assertGreater(pending, 0)

    def test_pending_honours_waybar_start_time(self):
        sway = FakeSway([DP1(), DP2()], bar_ids=["wb-main", "wb-second", "wb-other"])
        with mock.patch.object(waybar, "reload_waybar", return_value=True):
            waybar.Runtime().sync(sway)
        local = waybar.load_local()
        local["pending_reload"] = 123.0
        waybar.save_local(local)
        with mock.patch.object(waybar, "reload_waybar", return_value=False) as rw:
            waybar.Runtime().sync(sway)
        rw.assert_called_once_with(123.0)

    def test_symlinked_style_is_replaced_by_a_file(self):
        target = self.tmp / "store-style.css"
        target.write_text(waybar.render_style("* { font-size: 13px; }\n"))
        waybar.STYLE_FILE.parent.mkdir(parents=True, exist_ok=True)
        waybar.STYLE_FILE.symlink_to(target)
        self.assertTrue(waybar.write_if_changed(waybar.STYLE_FILE, target.read_text()))
        self.assertFalse(waybar.STYLE_FILE.is_symlink())

    def test_status(self):
        st = waybar.status(self.model(), FakeSway([DP1(focused=True), DP2()]))
        self.assertEqual(st["focused_output"], "DP-1")
        main = st["bars"][0]
        self.assertEqual((main["outputs"], main["effective"], main["shows_all"], main["mode"]), (["DP-1"], True, True, "overlay"))


class WaybarProcess(Base):
    def test_restart_via_systemd(self):
        calls = []

        def run(argv, **kw):
            calls.append(argv)
            return mock.Mock(returncode=0, stdout="4242\n")
        with mock.patch.dict(os.environ, {"SWAY_APPS_WAYBAR_PIDFILE": ""}), mock.patch.object(paths, "E2E", False), \
                mock.patch.object(waybar.subprocess, "run", side_effect=run), \
                mock.patch.object(waybar, "_proc_start", return_value=100.0):
            os.environ.pop("SWAY_APPS_WAYBAR_PIDFILE")
            self.assertFalse(waybar.reload_waybar(since=50.0))  # started after the change
            self.assertTrue(waybar.reload_waybar(since=150.0))
        self.assertEqual(calls[-1], ["systemctl", "--user", "--no-block", "restart", "waybar.service"])

    def test_e2e_never_touches_the_session_waybar(self):
        with mock.patch.object(paths, "E2E", True), mock.patch.object(waybar.subprocess, "run") as run, \
                mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("SWAY_APPS_WAYBAR_PIDFILE", None)
            self.assertFalse(waybar.reload_waybar())
        run.assert_not_called()


class Hooks(Base):
    def test_apply_hooks_skip_when_include_redirected(self):
        with mock.patch.object(paths, "INCLUDE_FILE", self.tmp / "elsewhere.conf"), \
                mock.patch.object(waybar.Runtime, "sync") as sync:
            waybar.before_reload(State())
            waybar.after_apply(State(), True)
        sync.assert_not_called()

    def test_apply_hooks_run_for_the_session_include(self):
        with mock.patch.object(paths, "INCLUDE_FILE", paths.XDG_CONFIG_HOME / "sway" / "sway-apps.conf"), \
                mock.patch.object(waybar.SwayLink, "connect", return_value=None), \
                mock.patch.object(waybar.Runtime, "sync") as sync:
            waybar.before_reload(State())
            waybar.after_apply(State(), False)
            waybar.after_apply(State(), True)
        self.assertEqual([c.kwargs["reload"] for c in sync.call_args_list], [False, True])


class FakeCtx:
    def __init__(self, reg, sway):
        self.reg, self.sway = reg, sway
        self.conn = self

    def command(self, cmd):
        return self.sway.command(cmd)

    def tree(self):
        return self.sway.tree()

    def outputs(self):
        return self.sway.outputs()

    def request(self, _t):
        return self.sway.bar_ids()

    def schedule(self, key, delay, fn):
        self.reg.schedule(key, delay, fn)

    def invalidate(self):
        pass


class Watch(Base):
    def setUp(self):
        super().setUp()
        self.reg = watch.Registry()
        self.sway = FakeSway([DP1(focused=False), DP2(focused=True)], bar_ids=["wb-main", "wb-second", "wb-other"])
        self.reg.ctx = FakeCtx(self.reg, self.sway)
        waybar.setup_watch(self.reg)

    def test_registers(self):
        self.assertIn("waybar", self.reg.verbs)
        for ev in ("workspace", "window", "output"):
            self.assertIn(ev, self.reg.handlers)
        self.assertIn("waybar.start", self.reg._timer_fns)

    def test_hotkey_toggles_focused_monitor(self):
        self.reg.dispatch("binding", {"binding": {"command": "nop sway-apps waybar toggle"}})
        self.assertEqual(self.sway.cmds, ["bar wb-main mode dock; bar wb-second mode dock; bar wb-other mode invisible"])
        self.assertTrue(waybar.load_local()["bars"]["second"]["visible"])

    def test_verb_all_and_bar(self):
        self.reg.dispatch("binding", {"binding": {"command": "nop sway-apps waybar hide --all"}})
        self.assertEqual(waybar.parse_bars(waybar.BARS_FILE.read_text()),
                         {"wb-main": "invisible", "wb-second": "invisible", "wb-other": "invisible"})
        self.reg.dispatch("binding", {"binding": {"command": "nop sway-apps waybar show other"}})
        self.assertEqual(self.sway.cmds[-1], "bar wb-other mode dock")  # no window of its own: not the solo bar

    def test_events_throttled_to_one_pass(self):
        self.reg.cancel("waybar.start")
        for _ in range(5):
            self.reg.dispatch("workspace", {"change": "focus"})
            self.reg.dispatch("window", {"change": "fullscreen_mode"})
        self.reg.dispatch("window", {"change": "focus"})
        live = [k for k in self.reg._timer_fns if k.startswith("waybar.")]
        self.assertEqual(live, ["waybar.modes"])
        with mock.patch.object(waybar.Runtime, "refresh") as rc:
            self.reg._timer_fns["waybar.modes"][1](self.reg.ctx)
        rc.assert_called_once()

    def test_output_event_schedules_sync(self):
        self.reg.dispatch("output", {"change": "unspecified"})
        self.assertIn("waybar.outputs", self.reg._timer_fns)


if __name__ == "__main__":
    unittest.main()
