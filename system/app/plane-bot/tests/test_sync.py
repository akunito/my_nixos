import unittest

from helpers import PID, item, make_mirror
from plane_bot import sync_items


class ScriptedPlane:
    """Serves whatever list the test puts in .items, newest-updated first like the API."""

    def __init__(self, items):
        self.items = items
        self.calls = 0

    def work_items(self, pid, order_by="-updated_at", fields=None):
        self.calls += 1
        rows = [i for i in self.items if i["project"] == pid]
        for r in sorted(rows, key=lambda r: r["updated_at"], reverse=True):
            yield r


class SyncTests(unittest.TestCase):
    def test_first_sync_stores_cursor_and_reports_everything_new(self):
        m = make_mirror()
        pid = PID["HOME"]
        plane = ScriptedPlane([item("HOME", 1, "a", "Todo", updated="2026-09-01T10:00:00+02:00"),
                               item("HOME", 2, "b", "Todo", updated="2026-09-02T10:00:00+02:00")])
        # the mirror already holds seed HOME-1..4; a re-sync of unchanged rows reports nothing
        changes = sync_items(plane, m, pid)
        self.assertEqual(sorted(c[1]["sequence_id"] for c in changes), [1, 2])  # names differ from seed -> changed
        self.assertEqual(m.get_meta(f"cursor:{pid}"), "2026-09-02T10:00:00+02:00")

    def test_incremental_stops_at_cursor(self):
        m = make_mirror()
        pid = PID["HOME"]
        plane = ScriptedPlane([item("HOME", 1, "a", "Todo", updated="2026-09-01T10:00:00+02:00"),
                               item("HOME", 2, "b", "Todo", updated="2026-09-02T10:00:00+02:00")])
        sync_items(plane, m, pid)
        # second pass: nothing newer -> no changes, cursor unchanged
        self.assertEqual(sync_items(plane, m, pid), [])
        # a newer edit of HOME-1 shows up as exactly one change with the previous row attached
        plane.items[0] = item("HOME", 1, "a renamed", "In Progress", updated="2026-09-03T10:00:00+02:00")
        changes = sync_items(plane, m, pid)
        self.assertEqual(len(changes), 1)
        prev, new = changes[0]
        self.assertEqual(prev["name"], "a")
        self.assertEqual(new["name"], "a renamed")
        self.assertEqual(m.get_meta(f"cursor:{pid}"), "2026-09-03T10:00:00+02:00")

    def test_full_sync_marks_vanished_items_deleted(self):
        m = make_mirror()
        pid = PID["HOME"]
        plane = ScriptedPlane([item("HOME", 1, "Fix the tap", "Todo", "medium", ["diego"])])
        changes = sync_items(plane, m, pid, full=True)
        gone = sorted(c[0]["id"] for c in changes if c[1] is None)
        self.assertEqual(gone, ["i-HOME-2", "i-HOME-3", "i-HOME-4"])
        self.assertEqual([r["seq"] for r in m.items_in([pid])], [1])

    def test_updated_at_alone_is_a_change_so_comments_are_seen(self):
        m = make_mirror()
        pid = PID["HOME"]
        seed = [i for i in __import__("helpers").seed_items() if i["project"] == pid]
        plane = ScriptedPlane(seed)
        sync_items(plane, m, pid, full=True)
        touched = dict(seed[0], updated_at="2026-09-20T10:00:00+02:00")  # same fields, newer timestamp (a comment)
        plane.items[0] = touched
        changes = sync_items(plane, m, pid)
        self.assertEqual([c[1]["id"] for c in changes], [touched["id"]])

    def test_unchanged_rows_are_not_changes(self):
        m = make_mirror()
        pid = PID["HOME"]
        seed = [i for i in __import__("helpers").seed_items() if i["project"] == pid]
        plane = ScriptedPlane(seed)
        self.assertEqual(sync_items(plane, m, pid, full=True), [])


if __name__ == "__main__":
    unittest.main()


class ClientThrottle(unittest.TestCase):
    def test_429_waits_and_retries_once(self):
        from plane_bot import Plane, PlaneError
        p = Plane("http://x", "ws", "tok")
        Plane.PACE = 0
        Plane.RETRY_429 = 0
        calls = {"n": 0}

        def fake_once(method, path, params=None, body=None):
            calls["n"] += 1
            if calls["n"] == 1:
                raise PlaneError(429, "RATE_LIMIT_EXCEEDED")
            return {"ok": True}

        p._req_once = fake_once
        self.assertEqual(p._req("GET", "projects/"), {"ok": True})
        self.assertEqual(calls["n"], 2)

        def always(method, path, params=None, body=None):
            raise PlaneError(429, "RATE_LIMIT_EXCEEDED")

        p._req_once = always
        with self.assertRaises(PlaneError):
            p._req("GET", "projects/")
