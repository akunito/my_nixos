"""Unit tests for the pure-python core: rule parsing/rendering, form mapping,
state layering. Run: python3 -m unittest discover -s tests (or pytest)."""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps.rules import Rule, parse_config, parse_line  # noqa: E402
from sway_apps.gui.forms import RuleForm  # noqa: E402
from sway_apps import state as st  # noqa: E402


class ParseRender(unittest.TestCase):
    def test_roundtrip_simple(self):
        line = 'for_window [app_id="kitty"] floating enable, sticky enable'
        r = parse_line(line)
        self.assertEqual(r.kind, "for_window")
        self.assertEqual(r.criteria, {"app_id": "kitty"})
        self.assertEqual(r.actions, ["floating enable", "sticky enable"])
        self.assertEqual(r.render(), line)

    def test_multi_criteria_and_regex(self):
        line = 'for_window [app_id="electron" title="^Element"] floating enable'
        r = parse_line(line)
        self.assertEqual(r.criteria, {"app_id": "electron", "title": "^Element"})
        self.assertEqual(r.render(), line)

    def test_escaped_regex_kept(self):
        line = 'assign [app_id="^md\\.Obsidian$"] workspace number 21'
        r = parse_line(line)
        self.assertEqual(r.criteria["app_id"], "^md\\.Obsidian$")
        self.assertEqual(r.render(), line)

    def test_no_focus(self):
        r = parse_line('no_focus [app_id="mako"]')
        self.assertEqual(r.kind, "no_focus")
        self.assertEqual(r.actions, [])
        self.assertEqual(r.render(), 'no_focus [app_id="mako"]')

    def test_flag_criteria(self):
        r = Rule.new("for_window", {"app_id": "x", "floating": "true"}, ["sticky enable"])
        self.assertEqual(r.render(), 'for_window [app_id="x" floating] sticky enable')

    def test_not_a_rule(self):
        self.assertIsNone(parse_line("bindsym Mod4+Return exec kitty"))
        self.assertIsNone(parse_line("# for_window [app_id=x] floating enable"))

    def test_merge_duplicates(self):
        text = ('for_window [app_id="kitty"] floating enable\n'
                'for_window [app_id="kitty"] sticky enable\n'
                'for_window [app_id="kitty"] floating enable\n')
        rules = parse_config(text)
        self.assertEqual(len(rules), 1)
        self.assertEqual(rules[0].actions, ["floating enable", "sticky enable"])

    def test_stable_ids(self):
        a = Rule.new("for_window", {"app_id": "kitty"}, ["floating enable"])
        b = Rule.new("for_window", {"app_id": "kitty"}, ["sticky enable"])
        c = Rule.new("assign", {"app_id": "kitty"}, ["workspace number 1"])
        self.assertEqual(a.id, b.id)      # identity = kind + criteria
        self.assertNotEqual(a.id, c.id)

    def test_problems(self):
        self.assertIn("unknown sway command 'florting' in action 'florting enable'",
                      Rule.new("for_window", {"app_id": "x"}, ["florting enable"]).problems())
        self.assertTrue(Rule.new("for_window", {"bogus": "x"}, ["floating enable"]).problems())
        self.assertTrue(Rule.new("for_window", {"app_id": "x"}, []).problems())
        self.assertTrue(Rule.new("assign", {"app_id": "x"}, ["floating enable"]).problems())
        self.assertTrue(Rule.new("no_focus", {"app_id": "x"}, ["floating enable"]).problems())
        self.assertTrue(Rule.new("for_window", {"app_id": "x"}, ["floating enable, sticky enable"]).problems())
        self.assertTrue(Rule.new("for_window", {"title": "("}, ["floating enable"]).problems())
        self.assertEqual(Rule.new("assign", {"app_id": "x"}, ["workspace number 3"]).problems(), [])
        self.assertEqual(Rule.new("assign", {"app_id": "x"}, ["output DP-1"]).problems(), [])

    def test_live_commands(self):
        self.assertEqual(Rule.new("assign", {"app_id": "x"}, ["workspace number 3"]).live_commands(),
                         ["move container to workspace number 3"])
        self.assertEqual(Rule.new("no_focus", {"app_id": "x"}, []).live_commands(), [])


class Forms(unittest.TestCase):
    def test_form_roundtrip(self):
        actions = ["move container to output DP-1", "move container to workspace number 1", "floating enable",
                   "sticky enable", "fullscreen enable", "inhibit_idle focus", "resize set 800 600",
                   "move position center", "border pixel 2", "opacity 0.9", "mark foo", "layout tabbed",
                   "blur enable", "shadows disable", "corner_radius 8", "title_format %title"]
        f = RuleForm.from_actions(actions)
        self.assertEqual(f.output, "DP-1")
        self.assertEqual(f.workspace, "1")
        self.assertEqual((f.resize_w, f.resize_h), ("800", "600"))
        self.assertEqual(f.border, "pixel"); self.assertEqual(f.border_px, "2")
        self.assertEqual(f.advanced, ["title_format %title"])
        self.assertEqual(set(f.to_actions()), set(actions))

    def test_assign_targets_land_in_fields(self):
        self.assertEqual(RuleForm.from_actions(["workspace number 11"]).workspace, "11")
        self.assertEqual(RuleForm.from_actions(["output DP-2"]).output, "DP-2")
        self.assertEqual(RuleForm.from_actions(["workspace number 11"]).advanced, [])

    def test_output_with_spaces_quoted(self):
        f = RuleForm(output="Samsung Electric Company Odyssey G70NC H1AK500000")
        self.assertEqual(f.to_actions(), ['move container to output "Samsung Electric Company Odyssey G70NC H1AK500000"'])


class Layering(unittest.TestCase):
    def test_profile_overrides_common(self):
        d = Path(tempfile.mkdtemp())
        common, prof = d / "common.json", d / "P.json"
        common.write_text(json.dumps({"version": 1, "rules": [
            {"id": "r1", "kind": "for_window", "criteria": {"app_id": "a"}, "actions": ["floating enable"], "name": "a", "enabled": True},
            {"id": "r2", "kind": "for_window", "criteria": {"app_id": "b"}, "actions": ["floating enable"], "name": "b", "enabled": True},
        ], "startup": []}))
        prof.write_text(json.dumps({"version": 1, "rules": [{"id": "r1", "enabled": False}], "startup": [
            {"id": "s1", "name": "x", "command": "x", "order": 1}]}))
        s = st.State(common, prof)
        rules = {r.id: r for r in s.rules()}
        self.assertFalse(rules["r1"].enabled)
        self.assertEqual(rules["r1"].scope, "profile")
        self.assertEqual(rules["r1"].actions, ["floating enable"])  # field-wise merge
        self.assertEqual(rules["r2"].scope, "common")
        self.assertEqual([e.id for e in s.startup()], ["s1"])
        # moving a rule to common removes the profile shadow
        r1 = rules["r1"]; r1.enabled = True
        s.save_rule(r1, "common")
        self.assertEqual([x["id"] for x in s.profile["rules"]], [])
        s.write()
        again = st.State(common, prof)
        self.assertTrue(again.rule("r1").enabled)
        self.assertTrue(s.remove("rules", "r2"))
        self.assertIsNone(st.State(*s.write() and (common, prof)).rule("r2"))


if __name__ == "__main__":
    unittest.main(verbosity=1)


class Targets(unittest.TestCase):
    def _state(self):
        d = Path(tempfile.mkdtemp())
        common, prof = d / "common.json", d / "P.json"
        common.write_text(json.dumps({"version": 1, "rules": [
            {"id": "r1", "kind": "assign", "criteria": {"app_id": "code"}, "actions": ["workspace number 12"], "name": "code",
             "target": {"monitor": "main", "slot": 2}},
            {"id": "r2", "kind": "for_window", "criteria": {"app_id": "x"}, "actions": ["floating enable", "move container to workspace number 21"],
             "name": "x", "target": {"monitor": "second", "slot": 1}},
            {"id": "r3", "kind": "assign", "criteria": {"app_id": "tvapp"}, "actions": ["workspace number 31"], "name": "tv",
             "target": {"monitor": "tv", "slot": 1}},
        ], "startup": []}))
        prof.write_text(json.dumps({"version": 1, "monitors": [
            {"id": "main", "criteria": "A B C", "group": 1, "primary": True},
            {"id": "second", "criteria": "D E F", "group": 5},
        ]}))
        return st.State(common, prof)

    def test_resolution_and_fallback(self):
        s = self._state()
        lines = {r.id: r.render() for r in s.resolved_rules()}
        self.assertEqual(lines["r1"], 'assign [app_id="code"] workspace number 12')
        self.assertEqual(lines["r2"], 'for_window [app_id="x"] floating enable, move container to workspace number 51')
        self.assertEqual(lines["r3"], 'assign [app_id="tvapp"] workspace number 31')  # tv undefined -> numeric fallback
        probs = s.target_problems()
        self.assertEqual([r.id for r, _ in probs], ["r3"])
        self.assertIn("'tv'", probs[0][1])

    def test_pins_and_conf(self):
        from sway_apps import monitors as mon
        s = self._state()
        pins = mon.render_pins(s)
        self.assertIn('workspace 11 output "A B C"', pins)
        self.assertIn('workspace 60 output "D E F"', pins)
        self.assertEqual(pins.count("\nworkspace "), 20)
        self.assertEqual(mon.pins_conf_text(s), "1|A B C\n5|D E F\n")
        self.assertEqual(s.monitor_for_workspace(57).id, "second")
        self.assertIsNone(s.monitor_for_workspace(31))

    def test_workspace_number_rewrite(self):
        r = Rule.new("for_window", {"app_id": "x"}, ["floating enable"])
        self.assertIsNone(r.workspace_number())
        r2 = r.with_workspace_number(23)
        self.assertEqual(r2.actions, ["move container to workspace number 23", "floating enable"])
        r3 = Rule.new("assign", {"app_id": "x"}, ["workspace number 11"]).with_workspace_number(41)
        self.assertEqual(r3.actions, ["workspace number 41"])

    def test_nwg_outputs_parse(self):
        from sway_apps import monitors as mon
        text = '''# Generated by nwg-displays
output "DP-2" {
    mode  2560x1440@144.0Hz
    pos 4663 786
    transform 90
    scale 1.25
    scale_filter nearest
    adaptive_sync off
    dpms on
}
output "DP-1" {
    mode  3840x2160@120.0Hz
    pos 2103 1394
    transform normal
    scale 1.5
}
'''
        b = mon.parse_nwg_outputs(text)
        self.assertEqual(set(b), {"DP-1", "DP-2"})
        self.assertEqual(b["DP-2"]["transform"], "90")
        self.assertEqual(b["DP-1"]["scale"], "1.5")
        self.assertEqual(b["DP-2"]["mode"], "2560x1440@144.0Hz")


class SemanticMerge(unittest.TestCase):
    def _doc(self, rules):
        return json.dumps({"version": 1, "rules": rules, "startup": [], "monitors": [], "settings": {}})

    def test_three_way(self):
        from sway_apps import gitsync
        r = lambda i, a, t=0: {"id": i, "kind": "for_window", "criteria": {"app_id": i}, "actions": [a], "name": i, "enabled": True, "updated_at": t}
        base = self._doc([r("a", "floating enable"), r("b", "floating enable"), r("c", "floating enable"), r("d", "floating enable")])
        ours = self._doc([r("a", "floating disable", 10), r("b", "floating enable"), r("d", "floating enable"), r("e", "sticky enable", 5)])   # a edited, c deleted, e added
        theirs = self._doc([r("a", "sticky enable", 20), r("b", "sticky enable", 7), r("c", "floating enable"), r("d", "floating enable"), r("f", "border none", 3)])  # a edited (newer), b edited, f added
        m = json.loads(gitsync.merge_state_json(base, ours, theirs))
        got = {x["id"]: x["actions"][0] for x in m["rules"]}
        self.assertEqual(got["a"], "sticky enable")     # both edited: newer wins
        self.assertEqual(got["b"], "sticky enable")     # only they edited
        self.assertNotIn("c", got)                      # we deleted, they didn't touch
        self.assertEqual(got["d"], "floating enable")   # untouched
        self.assertEqual(got["e"], "sticky enable")     # we added
        self.assertEqual(got["f"], "border none")       # they added

    def test_delete_vs_edit_keeps_edit(self):
        from sway_apps import gitsync
        r = lambda i, a, t=0: {"id": i, "actions": [a], "updated_at": t}
        base = self._doc([r("a", "x")]); ours = self._doc([]); theirs = self._doc([r("a", "y", 9)])
        m = json.loads(gitsync.merge_state_json(base, ours, theirs))
        self.assertEqual([x["actions"] for x in m["rules"]], [["y"]])


class Shortcuts(unittest.TestCase):
    def test_keys(self):
        from sway_apps import shortcuts as sc
        self.assertEqual(sc.sway_keys("hyper+shift+N"), "Mod4+Control+Mod1+Shift+N")
        self.assertEqual(sc.fold("Hyper+Shift+N"), sc.fold("Mod4+Control+Mod1+Shift+n"))
        self.assertEqual(sc.sway_keys("Super+Return"), "Mod4+Return")
        self.assertEqual(sc.friendly_keys("Mod4+Control+Mod1+Shift+n"), "Hyper+Shift+n")
        self.assertEqual(sc.friendly_keys("Mod4+Tab"), "Super+Tab")
        with self.assertRaises(ValueError):
            sc.normalize_keys("Bogus+x")
        with self.assertRaises(ValueError):
            sc.normalize_keys("Hyper+Shift")

    def test_render_and_conflicts(self):
        from sway_apps import shortcuts as sc
        nix = [{"keys": "Hyper+t", "sway_keys": "Mod4+Control+Mod1+T", "fold": sc.fold("Hyper+T"), "command": "exec kitty", "flags": ""}]
        a = sc.Shortcut.new("Hyper+t", "app", app_id="kitty", command="kitty")
        b = sc.Shortcut.new("Hyper+Shift+z", "sway", command="workspace 3", locked=True)
        c = sc.Shortcut.new("hyper+shift+Z", "exec", command="foo")  # same folded keys as b
        c.id = "k-other"  # ids derive from the folded keys, so a duplicate can only appear after a `set --keys`
        conf = sc.conflicts([a, b, c], nix)
        self.assertEqual(conf[a.id]["nix"], "exec kitty")
        self.assertEqual(conf[b.id]["tool"], [c.id])
        text, warns = sc.render_all([a, b], nix)
        self.assertNotIn("kitty", text)                 # blocked: nix key, no override
        self.assertTrue(any("override" in w for w in warns))
        self.assertIn("bindsym --locked Mod4+Control+Mod1+Shift+z workspace 3", text)
        a.override = True
        text, warns = sc.render_all([a, b], nix)
        self.assertIn("unbindsym Mod4+Control+Mod1+t\nbindsym Mod4+Control+Mod1+t exec ~/.config/sway/scripts/app-toggle.sh kitty kitty", text)
        self.assertEqual(warns, [])
        # flags of the nix binding are repeated on the unbindsym
        nix2 = [{"keys": "Super+l", "sway_keys": "Mod4+l", "fold": sc.fold("Super+l"), "command": "exec lock", "flags": "--release"}]
        d = sc.Shortcut.new("Super+l", "exec", command="other", override=True)
        text, _ = sc.render_all([d], nix2)
        self.assertIn("unbindsym --release Mod4+l\nbindsym Mod4+l exec other", text)
        self.assertIn("bindsym --release Mod4+l exec lock\n", sc.validation_context(nix2))

    def test_nix_parse(self):
        from sway_apps import shortcuts as sc
        d = Path(tempfile.mkdtemp()); cfg = d / "config"
        cfg.write_text("bindsym Mod4+Control+Mod1+Shift+r reload\nbindsym --release Mod4+l exec lock\n# bindsym Mod4+x nope\nset $x 1\n")
        nb = sc.nix_bindings(cfg)
        self.assertEqual([(b["keys"], b["command"], b["flags"]) for b in nb], [("Hyper+Shift+r", "reload", ""), ("Super+l", "exec lock", "--release")])


class Adopt(unittest.TestCase):
    def test_adopt_unknown_assigns_role_and_free_decade(self):
        from unittest import mock
        from sway_apps import monitors as mon
        d = Path(tempfile.mkdtemp()); common, prof = d / "common.json", d / "P.json"
        common.write_text(json.dumps({"version": 1}))
        prof.write_text(json.dumps({"version": 1, "monitors": [{"id": "main", "criteria": "Lenovo X Y", "group": 1, "primary": True}],
                                    "settings": {"auto_adopt": True}}))
        s = st.State(common, prof)
        fake = [mon.LiveOutput("eDP-1", "Lenovo X Y", "Lenovo", "X", "Y", True, 0, 0, 1920, 1200, 1.0, "normal", 60, "11", True),
                mon.LiveOutput("HDMI-A-1", "Dell U2720 ABC", "Dell", "U2720", "ABC", True, 1920, 0, 2560, 1440, 1.0, "normal", 60, "1", False),
                mon.LiveOutput("HEADLESS-1", "Unknown Unknown Unknown", "Unknown", "Unknown", "Unknown", True, 9, 9, 1, 1, 1.0, "normal", 60, None, False)]
        with mock.patch.object(mon, "live_outputs", return_value=fake):
            created = mon.adopt_unknown(s)
        self.assertEqual([(m.id, m.group, m.criteria) for m in created], [("second", 2, "Dell U2720 ABC")])
        self.assertEqual(s.monitor("second").name, "Dell U2720")
        with mock.patch.object(mon, "live_outputs", return_value=fake):
            self.assertEqual(mon.adopt_unknown(s), [])  # idempotent


class TmuxShortcuts(unittest.TestCase):
    def test_tmux_parse_render_cross(self):
        from sway_apps import shortcuts as sc
        d = Path(tempfile.mkdtemp()); conf = d / "tmux.conf"
        conf.write_text('set -g prefix C-o\nbind -n S-Enter send-keys Escape\nbind e split-window -h\nbind-key -T copy-mode-vi y send-keys -X copy\n'
                        'bind -n C-M-e split-window -h -c "#{pane_current_path}"\nbind h display-menu -T "x" \\\n  "a" "b" "c"\n')
        tb = sc.tmux_bindings(conf)
        self.assertEqual([(t["table"], t["keys"]) for t in tb], [("root", "S-Enter"), ("prefix", "e"), ("copy-mode-vi", "y"), ("root", "C-M-e"), ("prefix", "h")])
        s = sc.Shortcut.new("e", "tmux", command="split-window -v", table="prefix", name="split", override=True)
        self.assertEqual(s.tmux_render(), "bind e split-window -v")
        r = sc.Shortcut.new("C-M-e", "tmux", command="kill-pane", table="root")
        text, warns = sc.render_tmux([s, r], tb)
        self.assertTrue(any("override" in w for w in warns))   # r collides with nix and has no override
        r.override = True
        text, warns = sc.render_tmux([s, r], tb)
        self.assertIn("unbind e\nbind e split-window -v", text)          # overrides the nix bind
        self.assertIn("unbind -n C-M-e\nbind -n C-M-e kill-pane", text)
        self.assertEqual(warns, [])
        c = sc.Shortcut.new("y", "tmux", command="x", table="copy-mode-vi")
        self.assertEqual(c.tmux_render(with_unbind=True), "unbind -T copy-mode-vi y\nbind -T copy-mode-vi y x")
        # cross: a sway binding on Ctrl+Alt+e shadows tmux's C-M-e
        nix = [{"keys": "Ctrl+Alt+e", "sway_keys": "Control+Mod1+e", "fold": sc.fold("Ctrl+Alt+e"), "command": "exec foo", "flags": "", "program": "sway", "category": "System"}]
        cross = sc.cross_conflicts([], nix, tb)
        self.assertEqual([(x["tmux_key"], x["shadowed_by"]) for x in cross], [("C-M-e", "nix: exec foo")])
        self.assertEqual(sc.cross_conflicts([], [], tb), [])
        self.assertEqual(sc.tmux_root_to_sway_fold("C-M-e"), "Control+Mod1+e")
        self.assertIsNone(sc.tmux_root_to_sway_fold("e"))

    def test_kitty_parse_and_categories(self):
        from sway_apps import shortcuts as sc
        d = Path(tempfile.mkdtemp()); conf = d / "kitty.conf"
        conf.write_text("font_size 12\nmap ctrl+shift+c send_text all \\x03\nmap shift+enter send_text all x\n")
        self.assertEqual([k["keys"] for k in sc.kitty_bindings(conf)], ["ctrl+shift+c", "shift+enter"])
        self.assertEqual(sc.guess_category("exec ~/.config/sway/scripts/app-toggle.sh kitty kitty"), "Apps")
        self.assertEqual(sc.guess_category("exec swaymsg '[app_id=gamescope] fullscreen enable'"), "Gaming")
        self.assertEqual(sc.guess_category("exec swaysome focus 3"), "Workspaces")
        self.assertEqual(sc.guess_category("focus left"), "Windows")
        self.assertEqual(sc.guess_category("exec swayosd-client --output-volume raise"), "Media")
        self.assertEqual(sc.guess_category("reload"), "System")


class Tools(unittest.TestCase):
    def test_tool_launch_command_and_layering(self):
        t = st.Tool(id="t1", name="Audio", command="pavucontrol", app_id="org.pulseaudio.pavucontrol")
        self.assertEqual(t.launch_command(), "~/.config/sway/scripts/app-toggle.sh org.pulseaudio.pavucontrol pavucontrol")
        self.assertEqual(st.Tool(id="t2", name="x", command="foo --bar").launch_command(), "foo --bar")
        self.assertTrue(st.Tool(id="t3", name="", command="").problems())
        d = Path(tempfile.mkdtemp()); common, prof = d / "common.json", d / "P.json"
        common.write_text(json.dumps({"version": 1, "tools": [{"id": "t1", "name": "A", "command": "a", "order": 20}, {"id": "t2", "name": "B", "command": "b", "order": 10}]}))
        prof.write_text(json.dumps({"version": 1, "tools": [{"id": "t1", "enabled": False}]}))
        s = st.State(common, prof)
        self.assertEqual([t.id for t in s.tools()], ["t2", "t1"])   # ordered
        self.assertFalse(s.tool("t1").enabled)                       # profile override


class DockerBackend(unittest.TestCase):
    def test_helpers(self):
        from sway_apps import dockerctl as dk
        n = st.Node(id="VPS", ssh="akunito@100.64.0.6:56777", daemons=["rootless"])
        self.assertEqual(dk.ssh_target(n), ["-p", "56777", "akunito@100.64.0.6"])
        self.assertEqual(dk.ssh_target(st.Node(id="x", ssh="aga@host")), ["aga@host"])
        self.assertIn("DOCKER_HOST", dk._docker_prefix(n, "rootless"))
        self.assertEqual(dk._docker_prefix(st.Node(id="d"), "rootful"), "docker")
        self.assertEqual(dk._docker_prefix(st.Node(id="d", sudo_rootful=True), "rootful"), "sudo -n docker")
        self.assertEqual(dk._labels("a=1,com.docker.compose.project=immich,b=x=y"), {"a": "1", "com.docker.compose.project": "immich", "b": "x=y"})
        c = dk.Container(node="VPS", daemon="rootless", id="1", name="immich_server", image="i", state="running", status="Up",
                         project="immich", service="immich-server", working_dir="/home/a/.homelab/immich", config_files="/home/a/.homelab/immich/docker-compose.yml")
        comp = dk._compose(n, "rootless", c)
        self.assertTrue(comp.startswith("cd /home/a/.homelab/immich && env DOCKER_HOST"))
        self.assertIn("compose -p immich -f /home/a/.homelab/immich/docker-compose.yml", comp)
        self.assertTrue(st.Node(id="", ssh="nouser").problems())
        self.assertTrue(st.Node(id="n", daemons=["weird"]).problems())

    def test_monitoring_fmt(self):
        from sway_apps import monitoring as mo
        self.assertEqual(mo.fmt(None, "pct"), "—")
        self.assertEqual(mo.fmt(1, "bool"), "UP")
        self.assertEqual(mo.fmt(0, "bool"), "DOWN")
        self.assertEqual(mo.fmt(93.4, "pct"), "93%")
        self.assertEqual(mo.fmt(90061, "dur"), "1d 1h")
        self.assertEqual(mo.fmt(3700, "dur"), "1h 1m")
        self.assertEqual(mo.fmt(5 * 1024**3, "bytes"), "5.0 GiB")
