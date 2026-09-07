"""Unit tests for cross-profile compare/copy and snapshots (sway_apps.profiles)
plus the `profiles` CLI. Run: python3 -m unittest discover -s tests -v

Every test works in a private temp state dir (paths.STATE_DIR / profiles.SNAP_DIR
are swapped in setUp and restored in tearDown); the real repo state under
user/wm/sway/apps is never touched. No GTK: sway_apps.gui is never imported.
"""
from __future__ import annotations

import contextlib
import copy
import io
import json
import logging
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import log, paths  # noqa: E402
from sway_apps import profiles as pf  # noqa: E402

# Keep the package logger silent and file/syslog-free for the whole module:
# cli.main() calls log.setup(), which is a no-op once _configured is set.
_pkg_logger = logging.getLogger(getattr(log, "_ROOT", "sway_apps"))
_pkg_logger.addHandler(logging.NullHandler())
_pkg_logger.propagate = False
log._configured = True

PROFILE = "X13"  # the "current" machine for every test (SWAY_APPS_PROFILE)

COMMON = {
    "version": 1,
    "rules": [{"id": "r-common", "kind": "for_window", "criteria": {"app_id": "kitty"}, "actions": ["floating enable"], "name": "kitty"}],
    "startup": [{"id": "s-common", "name": "Mako", "command": "mako", "order": 1}],
    "shortcuts": [{"id": "k-common", "keys": "Hyper+a", "name": "A", "command": "a"}],
    "tools": [{"id": "t-common", "name": "Files", "command": "nautilus"}],
    "monitors": [],
    "nodes": [{"id": "NAS", "ssh": "akunito@192.168.20.200"}],
}
DESK = {
    "version": 1,
    "rules": [{"id": "r1", "kind": "assign", "criteria": {"app_id": "code"}, "actions": ["workspace number 12"], "name": "code", "updated_at": 10},
              {"id": "r2", "kind": "for_window", "criteria": {"app_id": "x"}, "actions": ["floating enable"], "name": "x"}],
    "startup": [{"id": "s1", "name": "Waybar", "command": "waybar", "order": 1}, {"id": "s2", "name": "Foo", "command": "foo", "order": 2}],
    "shortcuts": [{"id": "k2", "keys": "Hyper+b", "name": "B"}, {"id": "k3", "keys": "Hyper+c", "name": "C-desk"}],
    "tools": [{"id": "t1", "name": "Audio", "command": "pavucontrol", "updated_at": 5}],
    "monitors": [{"id": "main", "criteria": "S", "group": 1, "primary": True}, {"id": "second", "criteria": "D", "group": 2}],
    "nodes": [{"id": "VPS", "ssh": "akunito@100.64.0.6:56777"}, {"id": "LOCAL"}],
}
X13 = {
    "version": 1,
    "rules": [{"id": "r1", "kind": "assign", "criteria": {"app_id": "code"}, "actions": ["workspace number 12"], "name": "code", "updated_at": 99},
              {"id": "r3", "kind": "no_focus", "criteria": {"app_id": "mako"}, "actions": [], "name": "mako"}],
    "startup": [{"id": "s1", "name": "Waybar", "command": "waybar -b top", "order": 1}, {"id": "s3", "name": "Bar", "command": "bar", "order": 3}],
    "shortcuts": [{"id": "k3", "keys": "Hyper+c", "name": "C-x13"}, {"id": "k4", "keys": "Hyper+d", "name": "D"}],
    "tools": [{"id": "t1", "name": "Audio", "command": "pavucontrol", "updated_at": 7}],
    "monitors": [{"id": "main", "criteria": "L", "group": 1, "primary": True}],
    "nodes": [{"id": "VPS", "ssh": "akunito@100.64.0.6:56777"}],
}

# DESK (a) vs X13 (b), per section: ids in only_a / only_b / changed / same.
EXPECTED_DIFF = {
    "rules": (["r2"], ["r3"], [], ["r1"]),          # r1 differs only in updated_at
    "startup": (["s2"], ["s3"], ["s1"], []),
    "shortcuts": (["k2"], ["k4"], ["k3"], []),
    "tools": ([], [], [], ["t1"]),                  # t1 differs only in updated_at
    "monitors": (["second"], [], ["main"], []),
    "nodes": (["LOCAL"], [], [], ["VPS"]),
}


def _ids(items):
    return [x["id"] for x in items]


class ProfilesBase(unittest.TestCase):
    def setUp(self):
        self.d = Path(tempfile.mkdtemp(prefix="sway-apps-test-"))
        self._old = (paths.STATE_DIR, pf.SNAP_DIR, os.environ.get("SWAY_APPS_PROFILE"))
        paths.STATE_DIR = self.d
        pf.SNAP_DIR = self.d / "snapshots"
        os.environ["SWAY_APPS_PROFILE"] = PROFILE
        for name, doc in (("common", COMMON), ("DESK", DESK), ("X13", X13)):
            (self.d / f"{name}.json").write_text(json.dumps(copy.deepcopy(doc)))

    def tearDown(self):
        paths.STATE_DIR, pf.SNAP_DIR, old_profile = self._old
        if old_profile is None:
            os.environ.pop("SWAY_APPS_PROFILE", None)
        else:
            os.environ["SWAY_APPS_PROFILE"] = old_profile

    # -- helpers ---------------------------------------------------------
    def file(self, name: str) -> Path:
        return self.d / f"{name}.json"

    def freeze_time(self, stamp="20260907-120000", now=1757246400, stamps=None):
        """Pin time inside the profiles module only (dir stamps + updated_at)."""
        patcher = mock.patch.object(pf, "time")
        t = patcher.start()
        self.addCleanup(patcher.stop)
        if stamps is not None:
            t.strftime.side_effect = stamps
        else:
            t.strftime.return_value = stamp
        t.time.return_value = now
        return t

    def cli(self, *argv: str):
        from sway_apps import cli
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = cli.main(list(argv))
        return rc, out.getvalue(), err.getvalue()

    def cli_json(self, *argv: str):
        rc, out, err = self.cli("--json", *argv)
        return rc, json.loads(out), err


class Diff(ProfilesBase):
    def test_diff_every_section_kind(self):
        for section, (only_a, only_b, changed, same) in EXPECTED_DIFF.items():
            d = pf.diff("DESK", "X13", section)
            with self.subTest(section=section):
                self.assertEqual(set(d), {"only_a", "only_b", "changed", "same"})
                self.assertEqual(_ids(d["only_a"]), only_a)
                self.assertEqual(_ids(d["only_b"]), only_b)
                self.assertEqual([c["a"]["id"] for c in d["changed"]], changed)
                self.assertEqual([c["b"]["id"] for c in d["changed"]], changed)
                self.assertEqual(_ids(d["same"]), same)
        # the changed pair carries both sides verbatim
        c = pf.diff("DESK", "X13", "shortcuts")["changed"][0]
        self.assertEqual((c["a"]["name"], c["b"]["name"]), ("C-desk", "C-x13"))
        # diff is symmetric
        rev = pf.diff("X13", "DESK", "monitors")
        self.assertEqual((_ids(rev["only_a"]), _ids(rev["only_b"])), ([], ["second"]))
        # a profile without a file is an empty layer, and asking does not create it
        d = pf.diff("DESK", "NOPE", "nodes")
        self.assertEqual((_ids(d["only_a"]), d["only_b"], d["changed"], d["same"]), (["VPS", "LOCAL"], [], [], []))
        self.assertFalse(self.file("NOPE").exists())

    def test_diff_ignores_updated_at_only_change(self):
        # coded contract: _strip drops exactly updated_at, so an item that differs
        # only by its timestamp is "same", any other field difference is "changed"
        self.assertEqual(pf._strip({"id": "a", "updated_at": 5, "x": 1}), {"id": "a", "x": 1})
        self.assertEqual(pf._strip({"id": "a"}), {"id": "a"})
        rules = pf.diff("DESK", "X13", "rules")
        self.assertEqual(_ids(rules["same"]), ["r1"])
        self.assertEqual(rules["changed"], [])
        self.assertEqual(_ids(pf.diff("DESK", "X13", "tools")["same"]), ["t1"])
        # flip one real field on X13's r1: now it is changed, not same
        x13 = json.loads(self.file("X13").read_text())
        x13["rules"][0]["actions"] = ["workspace number 13"]
        self.file("X13").write_text(json.dumps(x13))
        rules = pf.diff("DESK", "X13", "rules")
        self.assertEqual([c["a"]["id"] for c in rules["changed"]], ["r1"])
        self.assertEqual(rules["same"], [])
        # _by_id skips items without an id instead of crashing
        self.assertEqual(pf._by_id([{"id": "a"}, {"name": "no-id"}, {"id": "b"}]), {"a": {"id": "a"}, "b": {"id": "b"}})

    def test_summary_counts(self):
        expected = {s: {"only_a": len(a), "only_b": len(b), "changed": len(c), "same": len(d)}
                    for s, (a, b, c, d) in EXPECTED_DIFF.items()}
        self.assertEqual(pf.summary("DESK", "X13"), expected)
        self.assertEqual(list(pf.summary("DESK", "X13")), list(pf.SECTIONS))
        # against a missing profile everything of DESK is only_a
        vs_nothing = pf.summary("DESK", "NOPE")
        self.assertEqual({s: v["only_a"] for s, v in vs_nothing.items()},
                         {"rules": 2, "startup": 2, "shortcuts": 2, "tools": 1, "monitors": 2, "nodes": 2})
        self.assertTrue(all(v["only_b"] == v["changed"] == v["same"] == 0 for v in vs_nothing.values()))
        # the CLI reports the same numbers, and `profiles list` counts per layer
        rc, out, _ = self.cli_json("profiles", "diff", "DESK", "X13")
        self.assertEqual((rc, out), (0, expected))
        rc, out, _ = self.cli_json("profiles", "diff", "DESK", "X13", "--section", "shortcuts")
        self.assertEqual(rc, 0)
        self.assertEqual((_ids(out["only_a"]), _ids(out["only_b"]), len(out["changed"]), out["same"]), (["k2"], ["k4"], 1, []))
        rc, rows, _ = self.cli_json("profiles", "list")
        self.assertEqual(rc, 0)
        self.assertEqual([(r["profile"], r["current"], r["shortcuts"], r["nodes"]) for r in rows],
                         [("DESK", False, 2, 2), ("X13", True, 2, 1), ("common", False, 1, 1)])

    def test_label_formats(self):
        self.assertEqual(pf.label("rules", DESK["rules"][1]), 'for_window [app_id="x"] floating enable')
        self.assertEqual(pf.label("rules", DESK["rules"][0]), 'assign [app_id="code"] workspace number 12')
        self.assertEqual(pf.label("rules", {"id": "r9", "name": "named override"}), "named override")  # partial override: no criteria
        self.assertEqual(pf.label("rules", {"id": "r9"}), "r9")
        self.assertEqual(pf.label("shortcuts", DESK["shortcuts"][0]), "Hyper+b → B")
        self.assertEqual(pf.label("shortcuts", {"id": "k", "keys": "Hyper+z", "command": "foo"}), "Hyper+z → foo")
        self.assertEqual(pf.label("shortcuts", {"id": "k"}), "? → ")
        self.assertEqual(pf.label("startup", DESK["startup"][0]), "Waybar (waybar)")
        self.assertEqual(pf.label("tools", DESK["tools"][0]), "Audio")
        self.assertEqual(pf.label("tools", {"id": "t9"}), "t9")
        self.assertEqual(pf.label("monitors", DESK["monitors"][0]), "main = S (group 1)")
        self.assertEqual(pf.label("monitors", {"id": "tv"}), "tv =  (group 0)")
        self.assertEqual(pf.label("nodes", DESK["nodes"][0]), "VPS akunito@100.64.0.6:56777")
        self.assertEqual(pf.label("nodes", DESK["nodes"][1]), "LOCAL local")


class Copy(ProfilesBase):
    def test_copy_selected_ids_merges_without_touching_others(self):
        before_desk = self.file("DESK").read_bytes()
        res = pf.copy_items("DESK", "X13", "shortcuts", ids=["k2"])
        self.assertEqual(res["copied"], ["k2"])
        self.assertEqual((res["section"], res["from"], res["to"], res["destination_total"]), ("shortcuts", "DESK", "X13", 3))
        self.assertIn(res["snapshot"], [s["id"] for s in pf.snapshots()])
        got = pf._by_id(pf.layer("X13")["shortcuts"])
        self.assertEqual(sorted(got), ["k2", "k3", "k4"])
        self.assertEqual(got["k3"], X13["shortcuts"][0])                     # untouched, byte for byte
        self.assertEqual(got["k4"], X13["shortcuts"][1])
        self.assertEqual(pf._strip(got["k2"]), DESK["shortcuts"][0])          # the copy, minus its fresh stamp
        # other sections of the destination and the source file are unchanged
        for sec in ("rules", "startup", "tools", "monitors", "nodes"):
            self.assertEqual(pf.layer("X13")[sec], X13[sec], sec)
        self.assertEqual(self.file("DESK").read_bytes(), before_desk)
        # library level: unknown ids copy nothing (the CLI is what rejects them)
        res = pf.copy_items("DESK", "X13", "shortcuts", ids=["nope"])
        self.assertEqual((res["copied"], res["destination_total"]), ([], 3))
        self.assertEqual(sorted(pf._by_id(pf.layer("X13")["shortcuts"])), ["k2", "k3", "k4"])
        # an unknown section is refused before anything happens (no snapshot either)
        n = len(pf.snapshots())
        with self.assertRaises(ValueError):
            pf.copy_items("DESK", "X13", "settings")
        self.assertEqual(len(pf.snapshots()), n)

    def test_copy_replace_drops_unlisted_destination_items(self):
        pf.copy_items("DESK", "X13", "shortcuts", replace=True)
        got = pf.layer("X13")["shortcuts"]
        self.assertEqual(_ids(got), ["k2", "k3"])                              # source order, k4 gone
        self.assertEqual([x["name"] for x in got], ["B", "C-desk"])           # k3 overwritten
        for sec in ("rules", "startup", "tools", "monitors", "nodes"):
            self.assertEqual(pf.layer("X13")[sec], X13[sec], sec)
        # replace + ids: the destination section becomes exactly the chosen ids
        res = pf.copy_items("DESK", "X13", "startup", ids=["s2"], replace=True)
        self.assertEqual((res["copied"], res["destination_total"]), (["s2"], 1))
        self.assertEqual(_ids(pf.layer("X13")["startup"]), ["s2"])
        # merge (default) keeps what is already there
        pf.copy_items("DESK", "X13", "startup", ids=["s1"])
        self.assertEqual(sorted(_ids(pf.layer("X13")["startup"])), ["s1", "s2"])

    def test_copy_common_to_profile_and_profile_to_profile(self):
        before_common = self.file("common").read_bytes()
        res = pf.copy_items("common", "X13", "tools")
        self.assertEqual(res["copied"], ["t-common"])
        self.assertEqual(sorted(_ids(pf.layer("X13")["tools"])), ["t-common", "t1"])
        self.assertEqual(self.file("common").read_bytes(), before_common)   # the source is read-only
        # profile -> profile
        res = pf.copy_items("DESK", "X13", "nodes")
        self.assertEqual(res["copied"], ["VPS", "LOCAL"])
        self.assertEqual(sorted(_ids(pf.layer("X13")["nodes"])), ["LOCAL", "VPS"])
        # profile -> common
        pf.copy_items("X13", "common", "monitors")
        self.assertEqual(_ids(pf.layer("common")["monitors"]), ["main"])
        # profile -> a layer that does not exist yet: created as a full, valid layer
        self.assertNotIn("NEW", pf.profile_files())
        res = pf.copy_items("DESK", "NEW", "monitors")
        self.assertEqual((res["copied"], res["destination_total"]), (["main", "second"], 2))
        new = json.loads(self.file("NEW").read_text())
        self.assertEqual(_ids(new["monitors"]), ["main", "second"])
        for sec in pf.SECTIONS:
            self.assertIn(sec, new)
        self.assertEqual(list(pf.profile_files()), ["DESK", "NEW", "X13", "common"])
        self.assertEqual(pf.profile_files()["NEW"], self.file("NEW"))

    def test_copy_stamps_updated_at_on_copied_items(self):
        # coded contract: every copied item gets updated_at = now (replace or merge),
        # whatever the source carried; the source keeps its own stamp
        self.freeze_time(now=1_700_000_000)
        pf.copy_items("DESK", "X13", "shortcuts", ids=["k2"])                 # source had no stamp
        pf.copy_items("DESK", "X13", "rules", ids=["r1"])                     # source stamp 10, dest had 99
        pf.copy_items("DESK", "X13", "monitors", replace=True)
        x13 = pf.layer("X13")
        self.assertEqual(pf._by_id(x13["shortcuts"])["k2"]["updated_at"], 1_700_000_000)
        self.assertEqual(pf._by_id(x13["rules"])["r1"]["updated_at"], 1_700_000_000)
        self.assertEqual([m["updated_at"] for m in x13["monitors"]], [1_700_000_000, 1_700_000_000])
        self.assertNotIn("updated_at", pf._by_id(x13["shortcuts"])["k3"])     # untouched neighbour: no stamp
        self.assertEqual(pf._by_id(pf.layer("DESK")["rules"])["r1"]["updated_at"], 10)
        # and because updated_at is ignored by diff, the copies now read as "same"
        self.assertEqual(_ids(pf.diff("DESK", "X13", "shortcuts")["same"]), ["k2"])
        self.assertEqual(_ids(pf.diff("DESK", "X13", "monitors")["same"]), ["main", "second"])

    def test_copy_and_restore_take_snapshot_first(self):
        self.assertFalse(pf.SNAP_DIR.exists())
        x13_before = self.file("X13").read_bytes()
        res = pf.copy_items("DESK", "X13", "shortcuts", replace=True)
        snaps = pf.snapshots()
        self.assertEqual(len(snaps), 1)
        self.assertEqual(snaps[0]["id"], res["snapshot"])
        self.assertEqual(snaps[0]["reason"], "copy-shortcuts-DESK-to-X13")
        # the snapshot holds the state as it was BEFORE the write
        self.assertEqual((Path(snaps[0]["path"]) / "X13.json").read_bytes(), x13_before)
        self.assertNotEqual(self.file("X13").read_bytes(), x13_before)
        x13_after_copy = self.file("X13").read_bytes()
        touched = pf.restore(snaps[0]["id"])
        self.assertEqual(touched, ["DESK.json", "X13.json", "common.json"])
        snaps = pf.snapshots()
        self.assertEqual(len(snaps), 2)
        # (listing is by dir name, so within one second the reason decides the order: look it up by reason)
        pre_restore = [s for s in snaps if s["reason"] != "copy-shortcuts-DESK-to-X13"]
        self.assertEqual(len(pre_restore), 1)
        self.assertEqual(pre_restore[0]["reason"], f"before-restore-{res['snapshot'][:15]}")
        self.assertEqual((Path(pre_restore[0]["path"]) / "X13.json").read_bytes(), x13_after_copy)  # state before the restore
        self.assertEqual(self.file("X13").read_bytes(), x13_before)


class Snapshots(ProfilesBase):
    def test_snapshot_dir_name_and_meta(self):
        self.freeze_time(stamp="20260907-120000", now=1757246400)
        d = pf.snapshot("hello")
        self.assertEqual(d.name, "20260907-120000-X13-hello")               # <stamp>-<profile>-<reason>
        self.assertEqual(d.parent, pf.SNAP_DIR)
        self.assertEqual(sorted(p.name for p in d.iterdir()), ["DESK.json", "META.json", "X13.json", "common.json"])
        self.assertEqual((d / "DESK.json").read_bytes(), self.file("DESK").read_bytes())
        meta = json.loads((d / "META.json").read_text())
        self.assertEqual(meta, {"reason": "hello", "profile": "X13", "time": 1757246400,
                                "files": ["DESK.json", "X13.json", "common.json"]})
        listed = pf.snapshots()
        self.assertEqual(listed, [{"id": d.name, "path": str(d), **meta}])
        self.assertEqual(pf.snapshot_dir(d.name), d)
        self.assertEqual(pf.snapshot_dir("hello"), d)                        # unique substring is enough
        # a snapshot dir without META is still listed (id + path only)
        (d / "META.json").unlink()
        self.assertEqual(pf.snapshots(), [{"id": d.name, "path": str(d)}])

    def test_two_snapshots_in_one_second_get_distinct_names(self):
        self.freeze_time(stamp="20260907-120000")
        a, b, c = pf.snapshot("x"), pf.snapshot("x"), pf.snapshot("x")
        self.assertEqual([a.name, b.name, c.name], ["20260907-120000-X13-x", "20260907-120000-2-X13-x", "20260907-120000-3-X13-x"])
        self.assertTrue(a.is_dir() and b.is_dir() and c.is_dir())
        self.assertEqual(len({s["id"] for s in pf.snapshots()}), 3)
        self.assertTrue(all((p / "META.json").exists() for p in (a, b, c)))

    def test_snapshot_reason_sanitised(self):
        # a distinct stamp per case, so two reasons that sanitise to the same
        # text ("" and "///") do not collide within one second
        self.freeze_time(stamps=[f"20260907-1200{i:02d}" for i in range(20)])
        cases = {
            "copy rules/DESK to X13": "copy-rules-DESK-to-X13",   # spaces and slashes
            "  weird///name  ": "weird---name",                   # runs kept, ends trimmed
            "-x-": "x",
            "a" * 60: "a" * 40,                                   # capped at 40 chars
            "": "manual",
            "///": "manual",
            "keep_under-score": "keep_under-score",
        }
        for i, (reason, safe) in enumerate(cases.items()):
            with self.subTest(reason=reason):
                d = pf.snapshot(reason)
                self.assertEqual(d.name, f"20260907-1200{i:02d}-X13-{safe}")
                self.assertEqual(json.loads((d / "META.json").read_text())["reason"], reason)  # META keeps the original

    def test_prune_keeps_thirty_oldest_first_listing(self):
        self.assertEqual(pf.prune(), [])                                     # no snapshots dir yet
        self.assertEqual(pf.snapshots(), [])
        self.assertEqual(pf.KEEP, 30)
        self.freeze_time(stamps=[f"20260101-{i:06d}" for i in range(1, 100)])
        for i in range(32):
            pf.snapshot("bulk")                                              # snapshot() prunes to KEEP itself
        ids = [s["id"] for s in pf.snapshots()]
        self.assertEqual(len(ids), 30)
        self.assertEqual(ids, sorted(ids))                                   # listing is oldest first
        self.assertEqual(ids[0], "20260101-000003-X13-bulk")                # 000001 and 000002 were pruned
        self.assertEqual(ids[-1], "20260101-000032-X13-bulk")
        self.assertEqual(pf.prune(), [])                                     # exactly KEEP: nothing to do
        removed = pf.prune(keep=5)
        self.assertEqual(len(removed), 25)
        self.assertEqual(removed[0], "20260101-000003-X13-bulk")
        self.assertEqual([s["id"] for s in pf.snapshots()], [f"20260101-0000{i}-X13-bulk" for i in range(28, 33)])
        self.assertFalse((pf.SNAP_DIR / removed[0]).exists())

    def test_restore_all_files_one_file_one_section(self):
        originals = {n: self.file(n).read_bytes() for n in ("common", "DESK", "X13")}
        base = pf.snapshot("base").name
        pf.copy_items("DESK", "X13", "shortcuts", replace=True)             # X13 changes
        pf.copy_items("X13", "DESK", "startup", replace=True)               # DESK changes
        pf.copy_items("DESK", "common", "nodes")                            # common changes
        for n in originals:
            self.assertNotEqual(self.file(n).read_bytes(), originals[n], n)
        # one whole file
        self.assertEqual(pf.restore(base, files=["X13.json"]), ["X13.json"])
        self.assertEqual(self.file("X13").read_bytes(), originals["X13"])
        self.assertNotEqual(self.file("DESK").read_bytes(), originals["DESK"])
        self.assertNotEqual(self.file("common").read_bytes(), originals["common"])
        # one section across all files: DESK's startup comes back, common's nodes stay copied
        self.assertEqual(pf.restore(base, sections=["startup"]), ["DESK.json", "X13.json", "common.json"])
        self.assertEqual(pf.layer("DESK")["startup"], DESK["startup"])
        self.assertEqual(pf.layer("DESK"), pf._read(pf.SNAP_DIR / base / "DESK.json"))
        self.assertEqual(sorted(_ids(pf.layer("common")["nodes"])), ["LOCAL", "NAS", "VPS"])   # other section untouched
        # everything
        self.assertEqual(pf.restore(base), ["DESK.json", "X13.json", "common.json"])
        for n in originals:
            self.assertEqual(self.file(n).read_bytes(), originals[n], n)     # byte-identical copies
        self.assertEqual(len(pf.snapshots()), 1 + 3 + 3)                     # base, 3 copies, 3 before-restore

    def test_restore_unknown_snapshot_raises(self):
        with self.assertRaises(FileNotFoundError):
            pf.snapshot_dir("nope")                                          # no snapshots dir at all
        with self.assertRaises(FileNotFoundError):
            pf.restore("nope")
        self.freeze_time(stamps=[f"20260907-12000{i}" for i in range(1, 6)])   # 2 snapshots + the restore's own
        one, two = pf.snapshot("one"), pf.snapshot("two")
        with self.assertRaises(FileNotFoundError):
            pf.restore("nope")
        with self.assertRaises(FileNotFoundError):
            pf.diff_snapshot("nope")
        with self.assertRaises(FileNotFoundError):
            pf.snapshot_dir("X13")                                           # ambiguous substring
        self.assertEqual(pf.snapshot_dir("two"), two)
        self.assertEqual(len(pf.snapshots()), 2)                             # a failed restore takes no snapshot
        self.assertEqual(pf.restore("one", files=["X13.json"]), ["X13.json"])
        self.assertEqual(len(pf.snapshots()), 3)
        self.assertTrue(one.is_dir())

    def test_diff_snapshot_counts(self):
        base = pf.snapshot("base").name
        zero = {"only_snapshot": 0, "only_now": 0, "changed": 0}
        d = pf.diff_snapshot(base)
        self.assertEqual(set(d), {"DESK.json", "X13.json", "common.json"})
        self.assertTrue(all(v == zero for per in d.values() for v in per.values()))
        pf.copy_items("DESK", "X13", "shortcuts", replace=True)             # X13: +k2, -k4, k3 changed
        x13 = json.loads(self.file("X13").read_text())
        x13["tools"][0]["updated_at"] = 12345                                # timestamp-only edit
        self.file("X13").write_text(json.dumps(x13))
        d = pf.diff_snapshot(base)
        self.assertEqual(d["X13.json"]["shortcuts"], {"only_snapshot": 1, "only_now": 1, "changed": 1})
        self.assertEqual(d["X13.json"]["tools"], zero)                       # updated_at does not count
        for sec in ("rules", "startup", "monitors", "nodes"):
            self.assertEqual(d["X13.json"][sec], zero, sec)
        self.assertTrue(all(v == zero for v in d["DESK.json"].values()))
        self.assertTrue(all(v == zero for v in d["common.json"].values()))
        # a state file deleted since the snapshot: everything it had is only_snapshot
        self.file("DESK").unlink()
        d = pf.diff_snapshot(base)
        self.assertEqual({s: v["only_snapshot"] for s, v in d["DESK.json"].items()},
                         {"rules": 2, "startup": 2, "shortcuts": 2, "tools": 1, "monitors": 2, "nodes": 2})
        self.assertTrue(all(v["only_now"] == v["changed"] == 0 for v in d["DESK.json"].values()))
        self.assertFalse(self.file("DESK").exists())                         # diffing never recreates it

    def test_copied_files_includes_snapshots_only_when_present(self):
        state_files = {self.file("common"), self.file("DESK"), self.file("X13")}
        self.assertFalse(pf.SNAP_DIR.exists())
        self.assertEqual(set(pf.copied_files()), state_files)
        pf.snapshot("first")
        files = pf.copied_files()
        self.assertEqual(files[-1], pf.SNAP_DIR)                              # the whole dir, once, last
        self.assertEqual(set(files[:-1]), state_files)
        self.assertEqual(len(files), 4)
        # an empty snapshots dir still counts as present (note: prune(keep=0) is a
        # no-op because of snaps[:-0], so empty the dir by hand)
        shutil.rmtree(files[-1] / pf.snapshots()[0]["id"])
        self.assertEqual(pf.snapshots(), [])
        self.assertEqual(pf.copied_files()[-1], pf.SNAP_DIR)


class Cli(ProfilesBase):
    def test_cli_copy_dry_run_and_yes(self):
        from sway_apps import cli
        x13_before = self.file("X13").read_bytes()
        rc, out, err = self.cli_json("profiles", "copy", "DESK", "--to", "X13", "--section", "shortcuts", "--ids", "k2")
        self.assertEqual(rc, 0)
        self.assertEqual(out, {"dry_run": True, "items": ["k2"]})
        self.assertIn("Would copy 1 shortcuts item(s) from DESK to X13", err)
        self.assertIn("[k2] Hyper+b → B", err)
        self.assertIn("--yes", err)
        self.assertEqual(self.file("X13").read_bytes(), x13_before)         # nothing written
        self.assertFalse(pf.SNAP_DIR.exists())                               # not even a snapshot
        with mock.patch.object(cli.generate, "apply") as apply_, mock.patch.object(cli.gitsync, "commit") as commit:
            rc, out, err = self.cli_json("profiles", "copy", "DESK", "--to", "X13", "--section", "shortcuts", "--ids", "k2",
                                         "--yes", "--no-apply", "--no-git")
        self.assertEqual(rc, 0)
        self.assertEqual(out["copied"], ["k2"])
        self.assertEqual((out["from"], out["to"], out["section"], out["destination_total"]), ("DESK", "X13", "shortcuts", 3))
        self.assertEqual([s["id"] for s in pf.snapshots()], [out["snapshot"]])
        self.assertNotIn("dry_run", out)
        self.assertNotIn("apply", out); self.assertNotIn("commit", out)
        apply_.assert_not_called(); commit.assert_not_called()
        self.assertEqual(sorted(_ids(pf.layer("X13")["shortcuts"])), ["k2", "k3", "k4"])
        self.assertEqual(pf._by_id(pf.layer("X13")["shortcuts"])["k3"]["name"], "C-x13")
        # --replace through the CLI, destination defaulting to the current profile (X13)
        with mock.patch.object(cli.generate, "apply") as apply_, mock.patch.object(cli.gitsync, "commit") as commit:
            rc, out, _ = self.cli_json("profiles", "copy", "DESK", "--section", "shortcuts", "--replace", "--yes", "--no-apply", "--no-git")
        self.assertEqual((rc, out["copied"], out["to"]), (0, ["k2", "k3"], "X13"))
        self.assertEqual(_ids(pf.layer("X13")["shortcuts"]), ["k2", "k3"])
        apply_.assert_not_called(); commit.assert_not_called()

    def test_cli_snapshot_restore_yes_sections(self):
        from sway_apps import cli
        with mock.patch.object(cli.generate, "apply") as apply_, mock.patch.object(cli.gitsync, "commit") as commit:
            rc, out, _ = self.cli_json("profiles", "snapshot", "create", "base", "--no-git")
            self.assertEqual(rc, 0)
            base = out["snapshot"]
            self.assertEqual(out, {"snapshot": base})
            self.assertEqual(json.loads((pf.SNAP_DIR / base / "META.json").read_text())["reason"], "base")
            pf.copy_items("DESK", "X13", "shortcuts", replace=True)
            pf.copy_items("DESK", "X13", "startup", replace=True)
            # snapshot list + diff through the CLI
            rc, listed, _ = self.cli_json("profiles", "snapshot", "list")
            self.assertEqual((rc, [s["id"] for s in listed]), (0, [s["id"] for s in pf.snapshots()]))
            rc, sdiff, _ = self.cli_json("profiles", "snapshot", "diff", base)
            self.assertEqual((rc, sdiff["X13.json"]["shortcuts"]), (0, {"only_snapshot": 1, "only_now": 1, "changed": 1}))
            # dry run: reports the diff, writes nothing
            x13_before = self.file("X13").read_bytes()
            n = len(pf.snapshots())
            rc, out, err = self.cli_json("profiles", "snapshot", "restore", base, "--sections", "shortcuts")
            self.assertEqual(rc, 0)
            self.assertEqual((out["dry_run"], out["snapshot"]), (True, base))
            self.assertEqual(out["diff"]["X13.json"]["startup"], {"only_snapshot": 1, "only_now": 1, "changed": 1})
            self.assertIn("sections: shortcuts", err)
            self.assertEqual(self.file("X13").read_bytes(), x13_before)
            self.assertEqual(len(pf.snapshots()), n)
            # --yes with one section: shortcuts come back, the startup copy survives
            rc, out, _ = self.cli_json("profiles", "snapshot", "restore", base, "--yes", "--sections", "shortcuts", "--no-apply", "--no-git")
        self.assertEqual(rc, 0)
        self.assertEqual((out["restored"], out["snapshot"]), (["DESK.json", "X13.json", "common.json"], base))
        self.assertNotIn("apply", out); self.assertNotIn("commit", out)
        apply_.assert_not_called(); commit.assert_not_called()
        x13 = pf.layer("X13")
        self.assertEqual(x13["shortcuts"], X13["shortcuts"])
        self.assertEqual(_ids(x13["startup"]), ["s1", "s2"])                 # still DESK's startup
        self.assertEqual([x["command"] for x in x13["startup"]], ["waybar", "foo"])
        self.assertEqual(len(pf.snapshots()), n + 1)                         # the before-restore snapshot
        self.assertEqual(sum(1 for s in pf.snapshots() if s["reason"].startswith("before-restore-")), 1)

    def test_cli_copy_same_source_and_destination_fails_cleanly(self):
        rc, out, err = self.cli_json("profiles", "copy", "DESK", "--to", "DESK", "--section", "shortcuts", "--yes", "--no-apply", "--no-git")
        self.assertEqual(rc, 2)
        self.assertEqual(out, {"error": "source and destination are the same profile"})
        self.assertNotIn("Traceback", err)
        self.assertFalse(pf.SNAP_DIR.exists())
        # destination defaults to the current profile, so copying X13 into "here" is the same mistake
        rc, out, _ = self.cli_json("profiles", "copy", "X13", "--section", "shortcuts")
        self.assertEqual((rc, out), (2, {"error": "source and destination are the same profile"}))
        # human mode: one clean line on stderr, nothing on stdout
        rc, out, err = self.cli("profiles", "copy", "DESK", "--to", "DESK", "--section", "shortcuts")
        self.assertEqual((rc, out), (2, ""))
        self.assertEqual(err, "error: source and destination are the same profile\n")
        # the other guards are just as clean
        rc, out, _ = self.cli_json("profiles", "copy", "DESK", "--to", "X13", "--section", "shortcuts", "--ids", "k2", "nope", "zz")
        self.assertEqual((rc, out), (2, {"error": "not in DESK/shortcuts: nope, zz"}))
        rc, out, _ = self.cli_json("profiles", "copy", "common", "--to", "X13", "--section", "monitors")
        self.assertEqual((rc, out), (2, {"error": "nothing to copy from common/monitors"}))
        self.assertEqual(self.file("X13").read_text(), json.dumps(X13))     # never written
        self.assertFalse(pf.SNAP_DIR.exists())


if __name__ == "__main__":
    unittest.main(verbosity=1)
