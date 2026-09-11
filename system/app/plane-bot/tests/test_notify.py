import copy
import json
import unittest

from helpers import HOME, MY, PID, UID, FakeCommentsPlane, FakeTelegram, World, item
from notify import Notifier, strip_html


def as_prev(mirror, item_id):
    """The mirror row as `sync_items` hands it back (assignees JSON-encoded)."""
    r = mirror.item(item_id)
    p = dict(r)
    p["assignees"] = json.dumps(sorted(r["assignees"]))
    return p


class NotifyWorld(World):
    def __init__(self, aga_on_telegram=True):
        super().__init__()
        if not aga_on_telegram:
            self.cfg.users["aga"].telegram_id = ""
        self.tg = FakeTelegram()
        self.plane = FakeCommentsPlane()
        self.n = Notifier(self.cfg, self.mirror, self.tg, self.plane)

    def change(self, ident, seq, **fields):
        """Apply a change to a seeded item and return the (prev, new) pair the sync would report."""
        it = next(i for i in __import__("helpers").seed_items() if i["id"] == f"i-{ident}-{seq}")
        prev = as_prev(self.mirror, it["id"])
        new = copy.deepcopy(it)
        for k, v in fields.items():
            if k == "assignees":
                v = [UID[a] for a in v]
            if k == "state":
                from helpers import sid
                v = sid(ident, v)
            new[k] = v
        new["updated_at"] = "2026-09-12T10:00:00+02:00"
        self.mirror.upsert_item(new)
        return prev, new

    def create(self, ident, seq, name, by, **kw):
        new = item(ident, seq, name, kw.pop("state", "Todo"), kw.pop("priority", "none"), kw.pop("assignees", []), **kw)
        new["created_by"] = UID[by]
        new["updated_by"] = UID[by]
        self.mirror.upsert_item(new)
        return None, new


class EchoRule(unittest.TestCase):
    def test_diego_creating_in_his_own_project_is_silent(self):
        w = NotifyWorld()
        pair = w.create("AINF", 50, "New infra task", by="diego")
        self.assertEqual(w.n.process([pair]), 0)
        self.assertEqual(w.tg.sent, [])

    def test_n8n_created_ticket_always_posts_even_if_actor_is_diego(self):
        w = NotifyWorld()
        pair = w.create("AINF", 51, "Monthly tax doc", by="diego", external="n8n", assignees=["diego"])
        self.assertEqual(w.n.process([pair]), 1)
        chat, thread, text, _ = w.tg.sent[0]
        self.assertEqual((chat, thread), (MY, "4"))
        self.assertIn("🆕", text)
        self.assertIn("AINF-51", text)

    def test_aga_creating_in_home_notifies_diego_in_home_topic(self):
        w = NotifyWorld()
        pair = w.create("HOME", 50, "Buy diapers", by="aga")
        self.assertEqual(w.n.process([pair]), 1)
        chat, thread, text, _ = w.tg.sent[0]
        self.assertEqual((chat, thread), (HOME, "5"))
        self.assertIn("by aga", text)

    def test_diego_creating_in_home_is_silent_until_aga_is_on_telegram(self):
        w = NotifyWorld(aga_on_telegram=False)
        self.assertEqual(w.n.process([w.create("HOME", 50, "x", by="diego")]), 0)
        w2 = NotifyWorld(aga_on_telegram=True)
        self.assertEqual(w2.n.process([w2.create("HOME", 50, "x", by="diego")]), 1)

    def test_komi_acting_in_shared_project_notifies_diego(self):
        w = NotifyWorld()
        pair = w.create("APORT", 50, "Komi's idea", by="komi")
        self.assertEqual(w.n.process([pair]), 1)
        self.assertEqual(w.tg.sent[0][:2], (MY, "11"))

    def test_first_sync_is_not_the_notifiers_business_but_created_with_existing_card_is_skipped(self):
        w = NotifyWorld()
        pair = w.create("HOME", 50, "x", by="aga")
        w.mirror.set_post(pair[1]["id"], HOME, 42, "5")  # the bot's /new reply already announced it
        self.assertEqual(w.n.process([pair]), 0)


class Assignment(unittest.TestCase):
    def test_assigning_diego_mentions_him_in_the_project_topic(self):
        w = NotifyWorld()
        prev, new = w.change("HOME", 3, assignees=["diego"], updated_by=UID["aga"])
        self.assertEqual(w.n.process([(prev, new)]), 1)
        chat, thread, text, _ = w.tg.sent[0]
        self.assertEqual((chat, thread), (HOME, "5"))
        self.assertIn('<a href="tg://user?id=111">diego</a>', text)
        self.assertIn("you were assigned", text)
        self.assertIn("HOME-3", text)
        self.assertIn("by aga", text)

    def test_self_assignment_is_silent(self):
        w = NotifyWorld()
        prev, new = w.change("HOME", 3, assignees=["diego"], updated_by=UID["diego"])
        self.assertEqual(w.n.process([(prev, new)]), 0)

    def test_assigning_komi_rings_nobody(self):
        w = NotifyWorld()
        prev, new = w.change("APORT", 2, assignees=["diego", "komi"], updated_by=UID["diego"])
        self.assertEqual(w.n.process([(prev, new)]), 0)

    def test_assignment_message_becomes_the_card(self):
        w = NotifyWorld()
        prev, new = w.change("HOME", 3, assignees=["diego"], updated_by=UID["aga"])
        w.n.process([(prev, new)])
        self.assertIsNotNone(w.mirror.get_post("i-HOME-3", HOME))


class Closing(unittest.TestCase):
    def test_done_edits_the_existing_card_silently(self):
        w = NotifyWorld()
        w.mirror.set_post("i-HOME-1", HOME, 500, "5")
        prev, new = w.change("HOME", 1, state="Done", updated_by=UID["aga"])
        self.assertEqual(w.n.process([(prev, new)]), 0)
        self.assertEqual(len(w.tg.edited), 1)
        chat, mid, text = w.tg.edited[0]
        self.assertEqual((chat, mid), (HOME, 500))
        self.assertIn("✅", text)
        self.assertIn("Done", text)
        self.assertIn("by aga", text)

    def test_done_without_card_posts_a_line(self):
        w = NotifyWorld()
        prev, new = w.change("HOME", 1, state="Done", updated_by=UID["aga"])
        self.assertEqual(w.n.process([(prev, new)]), 1)
        self.assertIn("✅", w.tg.sent[0][2])

    def test_cancelled_uses_its_own_icon(self):
        w = NotifyWorld()
        prev, new = w.change("IRIN", 1, state="Cancelled", updated_by=UID["diego"])
        w.n.process([(prev, new)])
        self.assertIn("🚫", w.tg.sent[0][2])

    def test_own_done_in_own_project_is_silent(self):
        w = NotifyWorld()
        w.mirror.set_post("i-AINF-1", MY, 600, "4")
        prev, new = w.change("AINF", 1, state="Done", updated_by=UID["diego"])
        self.assertEqual(w.n.process([(prev, new)]), 0)
        self.assertEqual(w.tg.edited, [])

    def test_priority_change_edits_card_only(self):
        w = NotifyWorld()
        w.mirror.set_post("i-HOME-1", HOME, 500, "5")
        prev, new = w.change("HOME", 1, priority="urgent", updated_by=UID["aga"])
        self.assertEqual(w.n.process([(prev, new)]), 0)
        self.assertEqual(len(w.tg.edited), 1)
        self.assertIn("🔥", w.tg.edited[0][2])
        # without a card: nothing at all
        w2 = NotifyWorld()
        prev, new = w2.change("HOME", 1, priority="urgent", updated_by=UID["aga"])
        self.assertEqual(w2.n.process([(prev, new)]), 0)
        self.assertEqual(w2.tg.sent, [])


class Comments(unittest.TestCase):
    def test_new_comment_by_aga_is_quoted_to_diego(self):
        w = NotifyWorld()
        w.plane.comments_by_item["i-HOME-1"] = [
            {"id": "c1", "actor": UID["aga"], "comment_html": "<p>Called the <b>plumber</b> &amp; booked</p>", "created_at": "2026-09-12T09:59:00+02:00"},
            {"id": "c0", "actor": UID["aga"], "comment_html": "<p>old</p>", "created_at": "2026-08-01T09:00:00+02:00"},
        ]
        prev, new = w.change("HOME", 1, updated_by=UID["aga"])
        self.assertEqual(w.n.process([(prev, new)]), 1)
        text = w.tg.sent[0][2]
        self.assertIn("💬 <b>aga</b>", text)
        self.assertIn("Called the plumber &amp; booked", text)
        self.assertNotIn("old", text)

    def test_own_comment_is_silent_in_own_project(self):
        w = NotifyWorld()
        w.plane.comments_by_item["i-AINF-1"] = [{"id": "c1", "actor": UID["diego"], "comment_html": "<p>note</p>", "created_at": "2026-09-12T09:59:00+02:00"}]
        prev, new = w.change("AINF", 1, updated_by=UID["diego"])
        self.assertEqual(w.n.process([(prev, new)]), 0)

    def test_long_comment_is_truncated(self):
        w = NotifyWorld()
        w.plane.comments_by_item["i-HOME-1"] = [{"id": "c1", "actor": UID["aga"], "comment_html": "x" * 1000, "created_at": "2026-09-12T09:59:00+02:00"}]
        prev, new = w.change("HOME", 1, updated_by=UID["aga"])
        w.n.process([(prev, new)])
        self.assertIn("…", w.tg.sent[0][2])
        self.assertLess(len(w.tg.sent[0][2]), 500)

    def test_strip_html(self):
        self.assertEqual(strip_html("<p>a &lt;b&gt; <i>c</i></p>"), "a <b> c")


class NotificationLeakMatrix(unittest.TestCase):
    """An event in a project only ever reaches the chats whose table has that project."""

    def test_every_project_event_lands_only_in_its_chats(self):
        allowed = {"AINF": {MY}, "APORT": {MY}, "IRIN": {HOME}, "HOME": {HOME}, "ORB": set()}
        for ident in PID:
            for kind in ("created", "assigned", "done", "comment"):
                w = NotifyWorld()
                w.cfg.users["komi"].telegram_id = "333"  # make komi hearable so ORB has an audience
                if kind == "created":
                    pair = w.create(ident, 60, "leak probe", by="aga" if ident in ("IRIN", "HOME") else "komi")
                elif kind == "assigned":
                    pair = w.change(ident, 1, assignees=["diego", "aga", "komi"], updated_by=UID["aga"])
                elif kind == "done":
                    pair = w.change(ident, 1, state="Done", updated_by=UID["komi"])
                else:
                    w.plane.comments_by_item[f"i-{ident}-1"] = [{"id": "c", "actor": UID["komi"], "comment_html": "<p>leak probe</p>", "created_at": "2026-09-12T09:59:00+02:00"}]
                    pair = w.change(ident, 1, updated_by=UID["komi"])
                w.n.process([pair])
                chats = {s[0] for s in w.tg.sent} | {e[0] for e in w.tg.edited}
                self.assertTrue(chats <= allowed[ident], (ident, kind, chats))
                for chat, thread, text, _ in w.tg.sent:
                    self.assertEqual(thread, w.cfg.chats[chat][ident], (ident, kind, thread))

    def test_orb_never_reaches_anyone(self):
        w = NotifyWorld()
        w.cfg.users["komi"].telegram_id = "333"
        w.n.process([w.create("ORB", 60, "SECRET", by="komi")])
        w.n.process([w.change("ORB", 2, state="Done", updated_by=UID["komi"])])
        self.assertEqual(w.tg.sent, [])
        self.assertEqual(w.tg.edited, [])


if __name__ == "__main__":
    unittest.main()
