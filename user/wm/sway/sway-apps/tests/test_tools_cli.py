"""Tools (sidebar launchers) + their CLI, driven in-process through
`sway_apps.cli.main([...]) --json` against a temp state dir.

Nothing here may touch a live sway/tmux/git: every persisting call passes
`--no-git` (and `--no-apply` where the subcommand has it), and the reload,
commit and swaymsg entry points are mocked as a safety net.
Run: python3 -m unittest discover -s tests -v
"""
from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import cli, generate, gitsync, paths, swayipc  # noqa: E402
from sway_apps import shortcuts as sc_mod  # noqa: E402

APP_TOGGLE = "~/.config/sway/scripts/app-toggle.sh"
TOOL_KEYS = {"id", "name", "command", "app_id", "icon", "order", "enabled", "notes", "updated_at"}
PERSIST = ("--no-git",)                      # tools add|set|rm only know --no-git
KEY_PERSIST = ("--no-apply", "--no-git")     # tools key has the full persist_flags set


class ToolsCli(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="sway-apps-tools-"))
        self.state_dir = self.tmp / "state"
        self.state_dir.mkdir()
        self.common = self.state_dir / "common.json"
        self.profile = self.state_dir / "TESTPROF.json"
        self.common.write_text(json.dumps({"version": 1}))
        self.profile.write_text(json.dumps({"version": 1}))
        # env read at call time by paths.profile_name() / paths.git_enabled()
        self._env = {k: os.environ.get(k) for k in ("SWAY_APPS_PROFILE", "SWAY_APPS_GIT", "ENV_PROFILE")}
        os.environ["SWAY_APPS_PROFILE"] = "TESTPROF"
        os.environ["SWAY_APPS_GIT"] = "0"
        # module globals computed at import: point every output path into the tempdir
        self._paths = (paths.STATE_DIR, paths.INCLUDE_FILE, paths.TMUX_INCLUDE, sc_mod.TMUX_INCLUDE)
        paths.STATE_DIR = self.state_dir
        paths.INCLUDE_FILE = self.tmp / "cfg" / "sway" / "sway-apps.conf"
        paths.TMUX_INCLUDE = self.tmp / "cfg" / "tmux" / "sway-apps.conf"
        sc_mod.TMUX_INCLUDE = paths.TMUX_INCLUDE
        # deterministic conflict checks (no reading ~/.config/sway/config or tmux.conf)
        self.nix = []
        self._start(mock.patch.object(sc_mod, "nix_bindings", side_effect=lambda *a, **k: list(self.nix)))
        self._start(mock.patch.object(sc_mod, "tmux_bindings", return_value=[]))
        # safety net: nothing may reload sway, source tmux, commit, or run swaymsg
        self.apply_mock = self._start(mock.patch.object(generate, "apply", return_value={"path": "mock", "reloaded": False}))
        self.commit_mock = self._start(mock.patch.object(gitsync, "commit", return_value=None))
        self._start(mock.patch.object(swayipc, "command", side_effect=AssertionError("swaymsg must not run in tests")))
        self._start(mock.patch.object(swayipc, "reload", side_effect=AssertionError("sway reload must not run in tests")))

    def tearDown(self):
        paths.STATE_DIR, paths.INCLUDE_FILE, paths.TMUX_INCLUDE, sc_mod.TMUX_INCLUDE = self._paths
        for k, v in self._env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def _start(self, patcher):
        m = patcher.start()
        self.addCleanup(patcher.stop)
        return m

    # ---- helpers -----------------------------------------------------------
    def run_cli(self, *args: str):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = cli.main(["--json", *args])
        out = buf.getvalue()
        return rc, (json.loads(out) if out.strip() else None)

    def add(self, command="pavucontrol", app_id="org.pa", name="Audio", *extra):
        rc, data = self.run_cli("tools", "add", "--command", command, "--app-id", app_id, "--name", name, *extra, *PERSIST)
        self.assertEqual(rc, 0, data)
        return data["tool"]

    def layer(self, path: Path, section="tools"):
        return json.loads(path.read_text()).get(section, [])

    def seed(self, path: Path, **sections):
        doc = json.loads(path.read_text())
        doc.update(sections)
        path.write_text(json.dumps(doc))

    # ---- add ---------------------------------------------------------------
    def test_add_generates_deterministic_id_and_persists(self):
        t = self.add()
        self.assertEqual(t["id"], "t-" + hashlib.sha1(b"org.pa|pavucontrol").hexdigest()[:8])
        stored = self.layer(self.common)
        self.assertEqual([x["id"] for x in stored], [t["id"]])
        s = stored[0]
        self.assertEqual((s["name"], s["command"], s["app_id"]), ("Audio", "pavucontrol", "org.pa"))
        self.assertEqual(s["icon"], "application-x-executable-symbolic")
        self.assertEqual((s["order"], s["enabled"], s["notes"]), (100, True, ""))
        self.assertGreater(s["updated_at"], 0)          # stamped by State.upsert
        self.assertEqual(self.layer(self.profile), [])  # common scope by default

    def test_add_explicit_fields_and_missing_command(self):
        t = self.add("blueman-manager", "blueman", "BT", "--id", "bt", "--icon", "bluetooth-symbolic", "--order", "5",
                     "--notes", "tray twin", "--disabled")
        self.assertEqual(t["id"], "bt")
        self.assertEqual((t["icon"], t["order"], t["notes"], t["enabled"], t["scope"]), ("bluetooth-symbolic", 5, "tray twin", False, "common"))
        s = self.layer(self.common)[0]
        self.assertEqual((s["id"], s["icon"], s["order"], s["enabled"]), ("bt", "bluetooth-symbolic", 5, False))
        # name defaults to the command's first word; no command at all is an error
        rc, data = self.run_cli("tools", "add", "--command", "foo --bar", *PERSIST)
        self.assertEqual((rc, data["tool"]["name"], data["tool"]["app_id"]), (0, "foo", ""))
        rc, data = self.run_cli("tools", "add", "--name", "nothing", *PERSIST)
        self.assertEqual(rc, 2)
        self.assertIn("--command or --desktop", data["error"])

    def test_add_profile_scope_vs_common_scope(self):
        c = self.add("pavucontrol", "org.pa", "Audio")
        p = self.add("blueman-manager", "blueman", "BT", "--scope", "profile")
        self.assertEqual((c["scope"], p["scope"]), ("common", "profile"))
        self.assertEqual([x["id"] for x in self.layer(self.common)], [c["id"]])
        self.assertEqual([x["id"] for x in self.layer(self.profile)], [p["id"]])
        rc, items = self.run_cli("tools", "list")
        self.assertEqual({x["id"]: x["scope"] for x in items}, {c["id"]: "common", p["id"]: "profile"})

    def test_add_duplicate_id_rejected_without_force(self):
        t = self.add()
        # same app_id + command -> same generated id
        rc, data = self.run_cli("tools", "add", "--command", "pavucontrol", "--app-id", "org.pa", "--name", "Other", *PERSIST)
        self.assertEqual(rc, 2)
        self.assertEqual(data, {"error": f"tool {t['id']} exists; --force to replace"})
        # explicit clashing --id too
        rc, data = self.run_cli("tools", "add", "--command", "x", "--id", t["id"], *PERSIST)
        self.assertEqual(rc, 2)
        self.assertIn("exists", data["error"])
        stored = self.layer(self.common)
        self.assertEqual([(x["id"], x["name"]) for x in stored], [(t["id"], "Audio")])  # untouched

    def test_add_force_replaces_in_place(self):
        t = self.add()
        t2 = self.add("pavucontrol", "org.pa", "Sound", "--force", "--icon", "audio-symbolic", "--order", "7")
        self.assertEqual(t2["id"], t["id"])
        stored = self.layer(self.common)
        self.assertEqual(len(stored), 1)
        self.assertEqual((stored[0]["name"], stored[0]["icon"], stored[0]["order"]), ("Sound", "audio-symbolic", 7))

    # ---- set ---------------------------------------------------------------
    def test_set_rename_and_fields(self):
        t = self.add()
        rc, data = self.run_cli("tools", "set", t["id"], "--name", "Sound", "--command", "pwvucontrol", "--app-id", "com.saivert.pwvucontrol",
                                "--icon", "audio-volume-high-symbolic", "--order", "3", "--notes", "pipewire", *PERSIST)
        self.assertEqual(rc, 0, data)
        got = data["tool"]
        self.assertEqual(got["id"], t["id"])  # rename never changes the id
        self.assertEqual((got["name"], got["command"], got["app_id"], got["icon"], got["order"], got["notes"], got["scope"]),
                         ("Sound", "pwvucontrol", "com.saivert.pwvucontrol", "audio-volume-high-symbolic", 3, "pipewire", "common"))
        s = self.layer(self.common)[0]
        self.assertEqual((s["name"], s["command"], s["app_id"], s["order"]), ("Sound", "pwvucontrol", "com.saivert.pwvucontrol", 3))
        rc, items = self.run_cli("tools", "list")
        self.assertEqual(items[0]["launch"], f"{APP_TOGGLE} com.saivert.pwvucontrol pwvucontrol")

    def test_set_disable_enable_and_invalid_rejected(self):
        t = self.add()
        rc, data = self.run_cli("tools", "set", t["id"], "--disable", *PERSIST)
        self.assertEqual((rc, data["tool"]["enabled"]), (0, False))
        self.assertFalse(self.layer(self.common)[0]["enabled"])
        rc, data = self.run_cli("tools", "set", t["id"], "--enable", *PERSIST)
        self.assertEqual((rc, data["tool"]["enabled"]), (0, True))
        self.assertTrue(self.layer(self.common)[0]["enabled"])
        # an empty command / name fails validation and leaves the state alone
        rc, data = self.run_cli("tools", "set", t["id"], "--command", "", *PERSIST)
        self.assertEqual(rc, 2)
        self.assertIn("invalid tool: empty command", data["error"])
        rc, data = self.run_cli("tools", "set", t["id"], "--name", "  ", *PERSIST)
        self.assertEqual(rc, 2)
        self.assertIn("empty name", data["error"])
        self.assertEqual((self.layer(self.common)[0]["command"], self.layer(self.common)[0]["name"]), ("pavucontrol", "Audio"))

    def test_set_lookup_by_name_and_unknown(self):
        t = self.add()
        rc, data = self.run_cli("tools", "set", "audio", "--order", "3", *PERSIST)   # case-insensitive name lookup
        self.assertEqual((rc, data["tool"]["id"], data["tool"]["order"]), (0, t["id"], 3))
        rc, data = self.run_cli("tools", "set", "nope", "--order", "1", *PERSIST)
        self.assertEqual((rc, data), (2, {"error": "no tool 'nope'"}))
        # two tools sharing a name make the name ambiguous -> error, not a guess
        self.add("blueman-manager", "blueman", "Audio")
        rc, data = self.run_cli("tools", "set", "Audio", "--order", "9", *PERSIST)
        self.assertEqual(rc, 2)
        self.assertIn("no tool", data["error"])

    def test_set_scope_profile_moves_layer_without_shadow(self):
        t = self.add()
        rc, data = self.run_cli("tools", "set", t["id"], "--scope", "profile", "--disable", *PERSIST)
        self.assertEqual((rc, data["tool"]["scope"], data["tool"]["enabled"]), (0, "profile", False))
        self.assertEqual(self.layer(self.common), [])                     # moved, not shadowed
        prof = self.layer(self.profile)
        self.assertEqual([(x["id"], x["enabled"], x["name"]) for x in prof], [(t["id"], False, "Audio")])
        # and back to common drops the profile copy
        rc, data = self.run_cli("tools", "set", t["id"], "--scope", "common", "--enable", *PERSIST)
        self.assertEqual((rc, data["tool"]["scope"]), (0, "common"))
        self.assertEqual(self.layer(self.profile), [])
        self.assertTrue(self.layer(self.common)[0]["enabled"])

    # ---- rm ----------------------------------------------------------------
    def test_rm_removes_from_both_layers(self):
        self.seed(self.common, tools=[{"id": "t1", "name": "A", "command": "a"}, {"id": "t2", "name": "B", "command": "b"}])
        self.seed(self.profile, tools=[{"id": "t1", "enabled": False}])
        rc, data = self.run_cli("tools", "rm", "t1", *PERSIST)
        self.assertEqual(rc, 0, data)
        self.assertEqual(data["removed"], "t1")
        self.assertEqual([x["id"] for x in self.layer(self.common)], ["t2"])
        self.assertEqual(self.layer(self.profile), [])
        rc, data = self.run_cli("tools", "rm", "t1", *PERSIST)
        self.assertEqual((rc, data), (2, {"error": "no tool 't1'"}))

    # ---- list --------------------------------------------------------------
    def test_list_ordering_and_json_shape(self):
        self.seed(self.common, tools=[{"id": "t1", "name": "Zed", "command": "z", "order": 20},
                                      {"id": "t2", "name": "beta", "command": "b", "order": 10},
                                      {"id": "t3", "name": "Alpha", "command": "a", "app_id": "alpha", "order": 10}])
        rc, items = self.run_cli("tools", "list")
        self.assertEqual(rc, 0)
        self.assertEqual([x["id"] for x in items], ["t3", "t2", "t1"])   # (order, name.lower())
        for x in items:
            self.assertEqual(set(x), TOOL_KEYS | {"scope", "launch", "key"})
        self.assertEqual(items[0]["launch"], f"{APP_TOGGLE} alpha a")
        self.assertEqual(items[1]["launch"], "b")                      # no app_id -> plain command
        self.assertEqual([x["key"] for x in items], [None, None, None])
        self.assertEqual({x["scope"] for x in items}, {"common"})

    def test_list_profile_override_wins_fieldwise(self):
        self.seed(self.common, tools=[{"id": "t1", "name": "Audio", "command": "pavucontrol", "app_id": "org.pa", "icon": "audio-symbolic", "order": 50},
                                      {"id": "t2", "name": "BT", "command": "blueman-manager", "order": 60}])
        self.seed(self.profile, tools=[{"id": "t1", "enabled": False, "order": 1}])
        rc, items = self.run_cli("tools", "list")
        by = {x["id"]: x for x in items}
        self.assertEqual(len(items), 2)                                # merged by id, no duplicate
        t1 = by["t1"]
        self.assertEqual((t1["enabled"], t1["order"], t1["scope"]), (False, 1, "profile"))          # overridden fields
        self.assertEqual((t1["name"], t1["command"], t1["app_id"], t1["icon"]), ("Audio", "pavucontrol", "org.pa", "audio-symbolic"))  # inherited
        self.assertEqual(t1["launch"], f"{APP_TOGGLE} org.pa pavucontrol")
        self.assertEqual((by["t2"]["scope"], by["t2"]["enabled"]), ("common", True))
        self.assertEqual([x["id"] for x in items], ["t1", "t2"])       # the override's order sorts it first

    # ---- run ---------------------------------------------------------------
    def test_run_execs_app_toggle_command(self):
        t = self.add()
        plain = self.add("foo --bar", "", "Foo")
        quoted = self.add("kitty --class scratch", "title:^Scratch Pad", "Pad")
        with mock.patch.object(swayipc, "available", return_value=True), mock.patch.object(swayipc, "exec_") as ex:
            rc, data = self.run_cli("tools", "run", t["id"])
            self.assertEqual(rc, 0, data)
            self.assertEqual(data, {"launched": t["id"], "command": f"{APP_TOGGLE} org.pa pavucontrol"})
            ex.assert_called_once_with(f"{APP_TOGGLE} org.pa pavucontrol")
            ex.reset_mock()
            rc, data = self.run_cli("tools", "run", "Foo")            # by name
            self.assertEqual((rc, data["command"]), (0, "foo --bar"))
            ex.assert_called_once_with("foo --bar")
            ex.reset_mock()
            rc, data = self.run_cli("tools", "run", quoted["id"])
            self.assertEqual(rc, 0)
            ex.assert_called_once_with(f"{APP_TOGGLE} 'title:^Scratch Pad' kitty --class scratch")

    def test_run_without_sway_socket_errors(self):
        t = self.add()
        with mock.patch.object(swayipc, "available", return_value=False), mock.patch.object(swayipc, "exec_") as ex:
            rc, data = self.run_cli("tools", "run", t["id"])
            self.assertEqual((rc, data), (2, {"error": "no sway socket"}))
            ex.assert_not_called()
            rc, data = self.run_cli("tools", "run", "ghost")
            self.assertEqual((rc, data), (2, {"error": "no tool 'ghost'"}))
            ex.assert_not_called()

    # ---- key ---------------------------------------------------------------
    def test_key_creates_tools_category_shortcut(self):
        t = self.add()
        rc, data = self.run_cli("tools", "key", t["id"], "Hyper+Shift+F9", *KEY_PERSIST)
        self.assertEqual(rc, 0, data)
        self.assertEqual(set(data), {"shortcut", "written"})           # --no-apply: no apply/live/commit keys
        x = data["shortcut"]
        self.assertEqual(x["id"], "k-" + hashlib.sha1(sc_mod.fold("Hyper+Shift+F9").encode()).hexdigest()[:8])
        self.assertEqual((x["kind"], x["category"], x["app_id"], x["command"], x["name"], x["keys"]),
                         ("app", "Tools", "org.pa", "pavucontrol", "Audio", "Hyper+Shift+F9"))
        self.assertEqual(x["line"], f"bindsym Mod4+Control+Mod1+Shift+F9 exec {APP_TOGGLE} org.pa pavucontrol")
        # persisted in the tool's (common) layer and visible through both listings
        self.assertEqual([(s["id"], s["category"]) for s in self.layer(self.common, "shortcuts")], [(x["id"], "Tools")])
        self.assertEqual(self.layer(self.profile, "shortcuts"), [])
        rc, items = self.run_cli("tools", "list")
        self.assertEqual(items[0]["key"], "Hyper+Shift+F9")
        rc, scs = self.run_cli("shortcuts", "list", "--category", "Tools")
        self.assertEqual([(s["id"], s["keys"], s["conflict"]) for s in scs], [(x["id"], "Hyper+Shift+F9", None)])
        self.apply_mock.assert_not_called()

    def test_key_rebind_keeps_id_and_none_removes(self):
        t = self.add()
        rc, first = self.run_cli("tools", "key", t["id"], "Hyper+Shift+F9", *KEY_PERSIST)
        rc, second = self.run_cli("tools", "key", t["id"], "Hyper+Shift+F6", *KEY_PERSIST)
        self.assertEqual(rc, 0, second)
        self.assertEqual(second["shortcut"]["id"], first["shortcut"]["id"])       # rebind updates, never duplicates
        self.assertEqual(second["shortcut"]["keys"], "Hyper+Shift+F6")
        self.assertEqual([s["keys"] for s in self.layer(self.common, "shortcuts")], ["Hyper+Shift+F6"])
        rc, items = self.run_cli("tools", "list")
        self.assertEqual(items[0]["key"], "Hyper+Shift+F6")
        rc, data = self.run_cli("tools", "key", t["id"], "none", *KEY_PERSIST)
        self.assertEqual(rc, 0, data)
        self.assertEqual(data["removed_shortcut"], first["shortcut"]["id"])
        self.assertEqual(self.layer(self.common, "shortcuts"), [])
        rc, items = self.run_cli("tools", "list")
        self.assertIsNone(items[0]["key"])
        self.assertEqual([x["id"] for x in items], [t["id"]])                     # the tool itself survives
        rc, data = self.run_cli("tools", "key", t["id"], "none", *KEY_PERSIST)
        self.assertEqual((rc, data), (2, {"error": "Audio has no key"}))

    def test_key_profile_tool_exec_kind_lands_in_profile_layer(self):
        t = self.add("nm-connection-editor", "", "Network", "--scope", "profile")
        rc, data = self.run_cli("tools", "key", "Network", "Super+F10", *KEY_PERSIST)
        self.assertEqual(rc, 0, data)
        x = data["shortcut"]
        self.assertEqual((x["kind"], x["app_id"], x["category"]), ("exec", "", "Tools"))   # no app_id -> plain exec
        self.assertEqual(x["line"], "bindsym Mod4+F10 exec nm-connection-editor")
        self.assertEqual(self.layer(self.common, "shortcuts"), [])
        self.assertEqual([(s["id"], s["kind"]) for s in self.layer(self.profile, "shortcuts")], [(x["id"], "exec")])
        rc, items = self.run_cli("tools", "list")
        self.assertEqual((items[0]["key"], items[0]["scope"]), ("Super+F10", "profile"))

    def test_key_nix_conflict_rejected_unless_override(self):
        t = self.add()
        self.nix[:] = [{"keys": "Hyper+Shift+F9", "sway_keys": "Mod4+Control+Mod1+Shift+F9", "fold": sc_mod.fold("Hyper+Shift+F9"),
                        "command": "exec nix-thing", "flags": "", "program": "sway", "category": "System"}]
        rc, data = self.run_cli("tools", "key", t["id"], "hyper+shift+f9", *KEY_PERSIST)   # folded compare
        self.assertEqual(rc, 2)
        self.assertIn("bound by nix", data["error"])
        self.assertEqual(self.layer(self.common, "shortcuts"), [])
        rc, data = self.run_cli("tools", "key", t["id"], "Bogus+F9", *KEY_PERSIST)
        self.assertEqual(rc, 2)
        self.assertIn("invalid shortcut", data["error"])
        rc, data = self.run_cli("tools", "key", t["id"], "Hyper+Shift+F9", "--override", *KEY_PERSIST)
        self.assertEqual(rc, 0, data)
        self.assertTrue(data["shortcut"]["override"])
        self.assertEqual([s["override"] for s in self.layer(self.common, "shortcuts")], [True])

    # regression: `tools key B KEYS` used to overwrite tool A's shortcut silently (same key-derived id)
    def test_key_tool_conflict_rejected(self):
        a = self.add()
        b = self.add("blueman-manager", "blueman", "BT")
        rc, first = self.run_cli("tools", "key", a["id"], "Hyper+Shift+F9", *KEY_PERSIST)
        self.assertEqual(rc, 0, first)
        rc, data = self.run_cli("tools", "key", b["id"], "Hyper+Shift+F9", *KEY_PERSIST)
        self.assertNotEqual(rc, 0)
        self.assertIn("already used", data["error"])
        rc, items = self.run_cli("tools", "list")
        self.assertEqual({x["id"]: x["key"] for x in items}, {a["id"]: "Hyper+Shift+F9", b["id"]: None})
        self.assertEqual([s["command"] for s in self.layer(self.common, "shortcuts")], ["pavucontrol"])

    # ---- hygiene -----------------------------------------------------------
    def test_nothing_written_outside_tempdir(self):
        t = self.add()
        rc, keyed = self.run_cli("tools", "key", t["id"], "Hyper+Shift+F9", *KEY_PERSIST)
        rc, edited = self.run_cli("tools", "set", t["id"], "--order", "2", *PERSIST)
        rc, unkeyed = self.run_cli("tools", "key", t["id"], "none", *KEY_PERSIST)
        rc, removed = self.run_cli("tools", "rm", t["id"], *PERSIST)
        for res in (keyed, edited, unkeyed, removed):
            self.assertTrue(res["written"], res)
            for p in res["written"]:
                self.assertTrue(Path(p).is_relative_to(self.tmp), p)
            self.assertNotIn("commit", res)
            self.assertNotIn("apply", res)
        # include / tmux targets are inside the tempdir and were never generated (--no-apply)
        for p in (paths.INCLUDE_FILE, paths.TMUX_INCLUDE, sc_mod.TMUX_INCLUDE):
            self.assertTrue(p.is_relative_to(self.tmp), p)
            self.assertFalse(p.exists(), p)
        self.apply_mock.assert_not_called()
        self.commit_mock.assert_not_called()
        # atomic writes leave no temp files behind, and only the two layers exist
        self.assertEqual(sorted(p.name for p in self.state_dir.iterdir()), ["TESTPROF.json", "common.json"])
        self.assertEqual(self.layer(self.common), [])
        self.assertEqual(self.layer(self.common, "shortcuts"), [])


if __name__ == "__main__":
    unittest.main(verbosity=1)
