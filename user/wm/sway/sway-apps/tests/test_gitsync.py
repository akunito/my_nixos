"""Git sync between machines (sway_apps.gitsync): commit/status/push/pull,
the id-keyed three-way merge and the fetch->rebase->merge->push `sync()`.

Every test builds throwaway repos in a tempdir (a bare origin plus clones A
and B) and points `paths.STATE_DIR` at a clone; the real ~/.dotfiles checkout
is never touched (guarded by `_use()`).
Run: python3 -m unittest discover -s tests -v
"""
from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import gitsync, paths  # noqa: E402

REL_DIR = Path("user/wm/sway/apps")
COMMON = str(REL_DIR / "common.json")
PROFILE = str(REL_DIR / "TEST.json")


def rule(i: str, action: str, t: int = 0) -> dict:
    return {"id": i, "kind": "for_window", "criteria": {"app_id": i}, "actions": [action],
            "name": i, "enabled": True, "updated_at": t}


def doc(**sections) -> dict:
    d = {"version": 1, "rules": [], "startup": [], "monitors": [], "shortcuts": [], "tools": [], "nodes": [], "settings": {}}
    d.update(sections)
    return d


def write(path: Path, d: dict) -> None:
    # Single-line JSON: any two edits to one file are a textual conflict, so
    # the sync tests deterministically reach the semantic merge.
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(d, sort_keys=True) + "\n")


def read(path: Path) -> dict:
    return json.loads(path.read_text())


class GitSync(unittest.TestCase):
    def setUp(self):
        self._env = os.environ.copy()
        self._globals = (paths.STATE_DIR, paths.DOTFILES, gitsync._top_cache)
        self._null = logging.NullHandler()
        logging.getLogger("sway-apps").addHandler(self._null)  # keep lastResort quiet
        self.tmp = Path(tempfile.mkdtemp(prefix="sway-apps-gitsync-")).resolve()
        gitconfig = self.tmp / "gitconfig"
        gitconfig.write_text("[user]\n\tname = T\n\temail = t@example.invalid\n[init]\n\tdefaultBranch = main\n"
                             "[commit]\n\tgpgsign = false\n[tag]\n\tgpgsign = false\n[pull]\n\trebase = false\n")
        for k in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "SWAY_APPS_GIT", "SWAY_APPS_AUTO_SYNC", "ENV_PROFILE"):
            os.environ.pop(k, None)
        os.environ.update({
            "GIT_CONFIG_GLOBAL": str(gitconfig), "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "T", "GIT_AUTHOR_EMAIL": "t@example.invalid",
            "GIT_COMMITTER_NAME": "T", "GIT_COMMITTER_EMAIL": "t@example.invalid",
            "GIT_AUTHOR_DATE": "2026-09-07T10:00:00+0000", "GIT_COMMITTER_DATE": "2026-09-07T10:00:00+0000",
            "SWAY_APPS_PROFILE": "TEST",
        })
        self.origin = self.tmp / "origin.git"
        self.A, self.B = self.tmp / "A", self.tmp / "B"
        self.git(self.tmp, "init", "--quiet", "--bare", "--initial-branch=main", str(self.origin))
        self.git(self.tmp, "clone", "--quiet", str(self.origin), str(self.A))
        write(self.A / COMMON, doc(rules=[rule("x", "floating enable"), rule("y", "floating enable")]))
        write(self.A / PROFILE, doc(shortcuts=[{"id": "k1", "keys": "Hyper+a", "name": "A", "updated_at": 0}]))
        (self.A / "README.md").write_text("hello\n")
        self.git(self.A, "add", "-A")
        self.git(self.A, "commit", "--quiet", "-m", "init")
        self.git(self.A, "push", "--quiet", "-u", "origin", "main")
        self.git(self.tmp, "clone", "--quiet", str(self.origin), str(self.B))
        self._use(self.A)

    def tearDown(self):
        paths.STATE_DIR, paths.DOTFILES, gitsync._top_cache = self._globals
        os.environ.clear(); os.environ.update(self._env)
        logging.getLogger("sway-apps").removeHandler(self._null)
        shutil.rmtree(self.tmp, ignore_errors=True)

    # -- helpers ---------------------------------------------------------
    def git(self, cwd: Path, *args: str) -> str:
        return subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True, text=True).stdout

    def _use(self, clone: Path) -> None:
        """Point the module at `clone` and prove we are nowhere near ~/.dotfiles."""
        paths.STATE_DIR = clone / REL_DIR
        paths.DOTFILES = clone
        gitsync._top_cache = None
        if gitsync.in_repo():
            top = gitsync.toplevel().resolve()
            self.assertEqual(top, clone.resolve())
            self.assertTrue(str(top).startswith(str(self.tmp) + os.sep), top)

    def head(self, clone: Path) -> str:
        return self.git(clone, "rev-parse", "HEAD").strip()

    def origin_main(self) -> str:
        return self.git(self.origin, "rev-parse", "main").strip()

    def changed(self, clone: Path) -> list[str]:
        return sorted(self.git(clone, "show", "--name-only", "--format=", "HEAD").split())

    def set_rule(self, clone: Path, rid: str, action: str, t: int) -> None:
        d = read(clone / COMMON)
        for r in d["rules"]:
            if r["id"] == rid:
                r["actions"] = [action]; r["updated_at"] = t
                break
        else:
            d["rules"].append(rule(rid, action, t))
        write(clone / COMMON, d)

    def commit(self, clone: Path, files: list[Path], msg: str) -> str | None:
        self._use(clone)
        return gitsync.commit(files, msg)

    def sync(self, clone: Path, **kw) -> dict:
        self._use(clone)
        return gitsync.sync(**kw)

    # -- commit / status / push / pull ---------------------------------
    def test_commit_only_stages_given_files(self):
        self.set_rule(self.A, "x", "sticky enable", 5)
        (self.A / "README.md").write_text("changed\n")
        sha = self.commit(self.A, [self.A / COMMON], "edit x")
        self.assertRegex(sha, r"^[0-9a-f]{7,}$")
        self.assertEqual(self.changed(self.A), [COMMON])
        self.assertEqual(self.git(self.A, "log", "-1", "--format=%s").strip(), "sway-apps: edit x")
        self.assertEqual(self.git(self.A, "status", "--porcelain").splitlines(), [" M README.md"])  # untouched, unstaged
        self.assertEqual(self.git(self.A, "diff", "--cached", "--name-only"), "")

    def test_commit_returns_none_when_clean_or_outside_repo(self):
        before = self.head(self.A)
        self.assertTrue(gitsync.in_repo())
        self.assertEqual(gitsync._rel([paths.common_file(), paths.profile_file()]), [COMMON, PROFILE])
        self.assertIsNone(gitsync.commit([paths.common_file(), paths.profile_file()], "noop"))
        self.assertIsNone(gitsync.commit([paths.STATE_DIR / "missing.json"], "noop"))
        self.assertEqual(self.head(self.A), before)
        norepo = self.tmp / "norepo" / "user" / "wm" / "sway" / "apps"
        norepo.mkdir(parents=True)
        write(norepo / "common.json", doc())
        paths.STATE_DIR = norepo; paths.DOTFILES = self.tmp / "norepo"; gitsync._top_cache = None
        self.assertFalse(gitsync.in_repo())
        self.assertIsNone(gitsync.toplevel())
        self.assertIsNone(gitsync.commit([norepo / "common.json"], "outside"))
        self.assertEqual(gitsync.status(), {"enabled": True, "repo": False})

    def test_commit_directory_snapshots(self):
        snap = paths.STATE_DIR / "snapshots" / "20260907-100000"
        write(snap / "common.json", doc())
        write(snap / "TEST.json", doc())
        (self.A / "README.md").write_text("changed\n")
        sha = self.commit(self.A, [self.A / REL_DIR / "snapshots"], "snapshot")
        self.assertIsNotNone(sha)
        self.assertEqual(self.changed(self.A), [str(REL_DIR / "snapshots" / "20260907-100000" / "TEST.json"),
                                                str(REL_DIR / "snapshots" / "20260907-100000" / "common.json")])
        self.assertEqual(self.git(self.A, "status", "--porcelain").splitlines(), [" M README.md"])
        self.assertIsNone(self.commit(self.A, [self.A / REL_DIR / "snapshots"], "again"))

    def test_git_disabled_env_skips_commit_and_status(self):
        os.environ["SWAY_APPS_GIT"] = "0"
        self.assertFalse(paths.git_enabled())
        before = self.head(self.A)
        self.set_rule(self.A, "x", "sticky enable", 5)
        self.assertIsNone(gitsync.commit([paths.common_file()], "edit x"))
        self.assertEqual(self.head(self.A), before)
        self.assertEqual(self.git(self.A, "status", "--porcelain").splitlines(), [f" M {COMMON}"])  # not even staged
        self.assertEqual(gitsync.status(), {"enabled": False})
        self.assertEqual(gitsync.sync()["ok"], False)
        self.assertIn("skipped", gitsync.sync())
        del os.environ["SWAY_APPS_GIT"]
        self.assertIsNotNone(gitsync.commit([paths.common_file()], "edit x"))

    def test_status_dirty_ahead_behind(self):
        st = gitsync.status()
        self.assertEqual((st["enabled"], st["repo"], st["branch"], st["upstream"]), (True, True, "main", "origin/main"))
        self.assertEqual((st["dirty"], st["ahead"], st["behind"]), ([], 0, 0))
        d = read(self.A / PROFILE); d["shortcuts"][0]["name"] = "B"; write(self.A / PROFILE, d)
        self.assertEqual(gitsync.status()["dirty"], [f"M {PROFILE}"])
        self.commit(self.A, [self.A / PROFILE], "rename")
        st = gitsync.status()
        self.assertEqual((st["dirty"], st["ahead"], st["behind"]), ([], 1, 0))
        self.git(self.A, "push", "--quiet")
        self.assertEqual(gitsync.status()["ahead"], 0)
        self._use(self.B)
        self.assertEqual(gitsync.status()["behind"], 0)  # status() does not fetch
        self.git(self.B, "fetch", "--quiet")
        st = gitsync.status()
        self.assertEqual((st["ahead"], st["behind"]), (0, 1))
        self.set_rule(self.B, "y", "border none", 3)
        self.commit(self.B, [self.B / COMMON], "y")
        st = gitsync.status()
        self.assertEqual((st["ahead"], st["behind"], st["dirty"]), (1, 1, []))

    def test_push_and_pull_against_origin(self):
        self.set_rule(self.A, "x", "sticky enable", 5)
        self.commit(self.A, [self.A / COMMON], "edit x")
        self.assertNotEqual(self.origin_main(), self.head(self.A))
        out = gitsync.push()
        self.assertIn("Done", out)
        self.assertEqual(self.origin_main(), self.head(self.A))
        self._use(self.B)
        out = gitsync.pull()
        self.assertIn("Fast-forward", out)
        self.assertEqual(self.head(self.B), self.head(self.A))
        self.assertEqual(read(self.B / COMMON), read(self.A / COMMON))
        # diverged: pull is --ff-only and must refuse rather than create a merge commit
        self.set_rule(self.A, "x", "border none", 6)
        self.commit(self.A, [self.A / COMMON], "x again")
        gitsync.push()
        self.set_rule(self.B, "y", "opacity 0.9", 7)
        self.commit(self.B, [self.B / COMMON], "y")
        b_head = self.head(self.B)
        with self.assertRaises(RuntimeError):
            gitsync.pull()
        self.assertEqual(self.head(self.B), b_head)
        self.assertEqual(self.git(self.B, "rev-list", "--count", "--merges", "HEAD").strip(), "0")

    # -- three-way merge ------------------------------------------------
    def test_merge_both_edited_newest_updated_at_wins(self):
        base = [rule("a", "base", 0)]
        self.assertEqual(gitsync._merge_section(base, [rule("a", "ours", 10)], [rule("a", "theirs", 20)]), [rule("a", "theirs", 20)])
        self.assertEqual(gitsync._merge_section(base, [rule("a", "ours", 30)], [rule("a", "theirs", 20)]), [rule("a", "ours", 30)])
        self.assertEqual(gitsync._merge_section(base, [rule("a", "ours", 10)], [rule("a", "theirs", 10)]), [rule("a", "ours", 10)])  # tie -> ours
        # no timestamps at all counts as 0 on both sides -> ours
        self.assertEqual(gitsync._merge_section([{"id": "a", "v": 0}], [{"id": "a", "v": 1}], [{"id": "a", "v": 2}]), [{"id": "a", "v": 1}])

    def test_merge_one_sided_delete_wins_over_untouched(self):
        base = [rule("a", "x"), rule("b", "x")]
        self.assertEqual(gitsync._merge_section(base, [rule("b", "x")], base), [rule("b", "x")])   # we deleted a
        self.assertEqual(gitsync._merge_section(base, base, [rule("a", "x")]), [rule("a", "x")])   # they deleted b
        self.assertEqual(gitsync._merge_section(base, [], []), [])                                   # deleted everywhere

    def test_merge_delete_vs_edit_keeps_edit(self):
        base = [rule("a", "x", 0)]
        self.assertEqual(gitsync._merge_section(base, [], [rule("a", "y", 9)]), [rule("a", "y", 9)])
        self.assertEqual(gitsync._merge_section(base, [rule("a", "y", 9)], []), [rule("a", "y", 9)])
        # an edit that did not bump updated_at still counts as an edit
        self.assertEqual(gitsync._merge_section(base, [], [rule("a", "y", 0)]), [rule("a", "y", 0)])

    def test_merge_new_on_both_sides_both_kept(self):
        self.assertEqual(gitsync._merge_section([], [rule("x", "1")], [rule("y", "2")]), [rule("x", "1"), rule("y", "2")])
        base = [rule("a", "0")]
        merged = gitsync._merge_section(base, [rule("a", "0"), rule("x", "1")], [rule("a", "0"), rule("y", "2")])
        self.assertEqual([r["id"] for r in merged], ["a", "x", "y"])
        # same new id created independently on both sides: newest wins, one copy
        merged = gitsync._merge_section([], [rule("n", "ours", 1)], [rule("n", "theirs", 2)])
        self.assertEqual(merged, [rule("n", "theirs", 2)])

    def test_merge_one_sided_edit_and_identical_edits(self):
        base = [rule("a", "x", 5)]
        # only they edited: theirs wins even though its stamp is older than ours
        self.assertEqual(gitsync._merge_section(base, base, [rule("a", "y", 1)]), [rule("a", "y", 1)])
        self.assertEqual(gitsync._merge_section(base, [rule("a", "y", 1)], base), [rule("a", "y", 1)])
        # identical edit on both sides collapses to one copy
        self.assertEqual(gitsync._merge_section(base, [rule("a", "y", 7)], [rule("a", "y", 7)]), [rule("a", "y", 7)])
        self.assertEqual(gitsync._merge_section([], [rule("z", "q")], [rule("z", "q")]), [rule("z", "q")])

    def test_merge_ordering_ours_first_then_theirs(self):
        base = [rule("a", "0"), rule("b", "0"), rule("c", "0")]
        ours = [rule("c", "0"), rule("a", "0")]                            # b deleted, reordered
        theirs = [rule("a", "0"), rule("b", "0"), rule("c", "0"), rule("d", "0")]
        merged = gitsync._merge_section(base, ours, theirs)
        self.assertEqual([r["id"] for r in merged], ["c", "a", "d"])
        self.assertEqual(gitsync._merge_section(base, [], theirs), [rule("d", "0")])

    def test_merge_state_json_top_level_keys(self):
        ours = json.dumps({"version": 1, "rules": [rule("a", "o", 1)], "settings": {"a": 1, "b": 2}, "custom": {"k": 1}})
        theirs = json.dumps({"version": 3, "rules": [rule("b", "t", 1)], "tools": [{"id": "t1", "name": "T"}],
                             "settings": {"b": 9, "c": 3}})
        out = gitsync.merge_state_json("", ours, theirs)
        self.assertTrue(out.endswith("\n"))
        m = json.loads(out)
        self.assertEqual(m["version"], 3)
        self.assertEqual(m["custom"], {"k": 1})
        self.assertEqual(m["settings"], {"a": 1, "b": 2, "c": 3})              # union, ours wins
        self.assertEqual([r["id"] for r in m["rules"]], ["a", "b"])
        self.assertEqual(m["tools"], [{"id": "t1", "name": "T"}])               # section only on their side
        for sec in gitsync._SECTIONS:
            self.assertIsInstance(m[sec], list)
        self.assertEqual(json.loads(gitsync.merge_state_json(ours, ours, ours)), json.loads(gitsync.merge_state_json("", ours, ours)))

    # -- sync -------------------------------------------------------------
    def test_sync_fast_forwards_when_only_remote_changed(self):
        self.set_rule(self.A, "x", "sticky enable", 5)
        self.commit(self.A, [self.A / COMMON], "edit x")
        gitsync.push()
        res = self.sync(self.B)
        self.assertEqual(res, {"ok": True, "behind": 1, "ahead": 0, "merged": [], "pushed": False})
        self.assertEqual(self.head(self.B), self.head(self.A))
        self.assertEqual(read(self.B / COMMON)["rules"][0]["actions"], ["sticky enable"])
        self.assertEqual(self.git(self.B, "rev-list", "--count", "--merges", "HEAD").strip(), "0")

    def test_sync_pushes_when_only_local_changed(self):
        self.set_rule(self.A, "x", "sticky enable", 5)
        self.commit(self.A, [self.A / COMMON], "edit x")
        head = self.head(self.A)
        self.assertNotEqual(self.origin_main(), head)
        res = self.sync(self.A, push_after=False)
        self.assertEqual(res, {"ok": True, "behind": 0, "ahead": 1, "merged": [], "pushed": False})
        self.assertNotEqual(self.origin_main(), head)
        res = self.sync(self.A)
        self.assertEqual(res, {"ok": True, "behind": 0, "ahead": 1, "merged": [], "pushed": True})
        self.assertEqual(self.origin_main(), head)  # rebase onto an unchanged upstream is a no-op
        self.assertEqual(self.sync(self.A), {"ok": True, "behind": 0, "ahead": 0, "merged": [], "pushed": False})

    def test_sync_semantic_merge_same_file_different_items(self):
        self.set_rule(self.A, "x", "sticky enable", 10)
        self.commit(self.A, [self.A / COMMON], "A edits x")
        gitsync.push()
        self.set_rule(self.B, "y", "border none", 11)
        self.commit(self.B, [self.B / COMMON], "B edits y")
        res = self.sync(self.B)
        self.assertTrue(res["ok"], res)
        self.assertEqual((res["behind"], res["ahead"], res["merged"], res["pushed"]), (1, 1, [COMMON], True))
        got = {r["id"]: r["actions"][0] for r in read(self.B / COMMON)["rules"]}
        self.assertEqual(got, {"x": "sticky enable", "y": "border none"})
        self.assertEqual(self.origin_main(), self.head(self.B))
        self.assertEqual(self.git(self.B, "rev-list", "--count", "--merges", "HEAD").strip(), "0")  # linear history
        self.assertFalse((self.B / ".git" / "rebase-merge").exists())
        res = self.sync(self.A)
        self.assertEqual((res["ok"], res["behind"], res["merged"]), (True, 1, []))
        self.assertEqual({r["id"]: r["actions"][0] for r in read(self.A / COMMON)["rules"]}, got)

    def test_sync_conflicting_item_newest_updated_at_wins(self):
        # x: B is newer -> B's edit survives; y: A is newer -> A's edit survives
        self.set_rule(self.A, "x", "A-x", 10); self.set_rule(self.A, "y", "A-y", 30)
        self.commit(self.A, [self.A / COMMON], "A")
        gitsync.push()
        self.set_rule(self.B, "x", "B-x", 20); self.set_rule(self.B, "y", "B-y", 5)
        self.commit(self.B, [self.B / COMMON], "B")
        res = self.sync(self.B)
        self.assertTrue(res["ok"], res)
        self.assertEqual(res["merged"], [COMMON])
        got = {r["id"]: (r["actions"][0], r["updated_at"]) for r in read(self.B / COMMON)["rules"]}
        self.assertEqual(got, {"x": ("B-x", 20), "y": ("A-y", 30)})
        self.assertTrue(self.sync(self.A)["ok"])
        self.assertEqual({r["id"]: (r["actions"][0], r["updated_at"]) for r in read(self.A / COMMON)["rules"]}, got)

    def test_sync_refuses_when_unpushed_commits_touch_non_state_files(self):
        self.set_rule(self.A, "x", "sticky enable", 10)
        self.commit(self.A, [self.A / COMMON], "A")
        gitsync.push()
        # dirty state files: refused before anything is fetched or rebased
        self._use(self.B)
        self.set_rule(self.B, "y", "dirty", 1)
        res = gitsync.sync()
        self.assertFalse(res["ok"]); self.assertIn("uncommitted", res["error"])
        self.git(self.B, "checkout", "--", COMMON)
        # a human's commit on a non-state file sits in the unpushed range
        (self.B / "README.md").write_text("human work\n")
        self.git(self.B, "commit", "--quiet", "-am", "human: readme")
        self.set_rule(self.B, "y", "border none", 11)
        self.commit(self.B, [self.B / COMMON], "B")
        head = self.head(self.B)
        res = self.sync(self.B)
        self.assertFalse(res["ok"])
        self.assertIn("non-state files", res["error"]); self.assertIn("README.md", res["error"])
        self.assertEqual(self.head(self.B), head)                              # nothing rebased
        self.assertNotEqual(self.origin_main(), head)                          # nothing pushed
        self.assertFalse((self.B / ".git" / "rebase-merge").exists())
        self.assertEqual(self.git(self.B, "status", "--porcelain"), "")

    def test_auto_sync_enabled_default_and_config(self):
        from sway_apps.gui import theme
        self.assertEqual(theme.CONFIG_FILE, paths.XDG_CONFIG_HOME / "sway-apps" / "config.json")
        old = theme.CONFIG_FILE
        theme.CONFIG_FILE = self.tmp / "config" / "sway-apps" / "config.json"
        try:
            self.assertTrue(gitsync.auto_sync_enabled())                          # no config file -> default on
            theme.CONFIG_FILE.parent.mkdir(parents=True)
            theme.CONFIG_FILE.write_text(json.dumps({"auto_sync": False}))
            self.assertFalse(gitsync.auto_sync_enabled())
            theme.CONFIG_FILE.write_text(json.dumps({"theme": "x"}))              # key absent -> default on
            self.assertTrue(gitsync.auto_sync_enabled())
            theme.CONFIG_FILE.write_text("{not json")
            self.assertTrue(gitsync.auto_sync_enabled())
            theme.CONFIG_FILE.write_text(json.dumps({"auto_sync": False}))
            os.environ["SWAY_APPS_AUTO_SYNC"] = "1"                                # env overrides the file
            self.assertTrue(gitsync.auto_sync_enabled())
            theme.CONFIG_FILE.write_text(json.dumps({"auto_sync": True}))
            for v in ("0", "false", "no"):
                os.environ["SWAY_APPS_AUTO_SYNC"] = v
                self.assertFalse(gitsync.auto_sync_enabled(), v)
        finally:
            theme.CONFIG_FILE = old

    def test_sync_converges_both_clones(self):
        # A: edits x + renames k1; B: adds rule z + adds shortcut k2. Both files
        # conflict textually, both are merged semantically, and after each side
        # syncs the two checkouts (and origin) are byte-identical.
        self.set_rule(self.A, "x", "A-x", 10)
        d = read(self.A / PROFILE); d["shortcuts"][0].update(name="A-name", updated_at=10); write(self.A / PROFILE, d)
        self.commit(self.A, [self.A / COMMON, self.A / PROFILE], "A")
        gitsync.push()
        self.set_rule(self.B, "z", "B-z", 20)
        d = read(self.B / PROFILE); d["shortcuts"].append({"id": "k2", "keys": "Hyper+b", "name": "B", "updated_at": 20}); write(self.B / PROFILE, d)
        self.commit(self.B, [self.B / COMMON, self.B / PROFILE], "B")
        res = self.sync(self.B)
        self.assertTrue(res["ok"], res)
        self.assertEqual(sorted(res["merged"]), sorted([COMMON, PROFILE]))
        self.assertTrue(res["pushed"])
        res = self.sync(self.A)
        self.assertEqual((res["ok"], res["behind"], res["ahead"], res["merged"], res["pushed"]), (True, 1, 0, [], False))
        self.assertEqual(self.head(self.A), self.head(self.B))
        self.assertEqual(self.origin_main(), self.head(self.A))
        for rel in (COMMON, PROFILE):
            self.assertEqual((self.A / rel).read_text(), (self.B / rel).read_text())
            self.assertEqual(self.git(self.A, "status", "--porcelain", "--", rel), "")
        common = read(self.A / COMMON)
        self.assertEqual({r["id"]: r["actions"][0] for r in common["rules"]}, {"x": "A-x", "y": "floating enable", "z": "B-z"})
        self.assertEqual(common["version"], 1)
        prof = read(self.A / PROFILE)
        self.assertEqual({s["id"]: s["name"] for s in prof["shortcuts"]}, {"k1": "A-name", "k2": "B"})
        self.assertEqual(self.git(self.A, "rev-list", "--count", "--merges", "HEAD").strip(), "0")


if __name__ == "__main__":
    unittest.main(verbosity=1)
