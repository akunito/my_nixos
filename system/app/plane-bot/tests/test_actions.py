import datetime as dt
import unittest

from helpers import HOME, MY, PID, UID, TG_AGA, TG_DIEGO, TG_STRANGER, World, sid
from plane_bot import parse_due


def hexid(item_id):
    return item_id  # synthetic ids are not UUIDs; tests use the mirror directly for lookups


class WriteCommands(unittest.TestCase):
    def setUp(self):
        self.w = World()

    def last_patch(self):
        return self.w.planes[-1].updated[-1]

    def test_assign_alias_adds_member_with_callers_token(self):
        out = self.w.say(HOME, "5", "/assign HOME-3 aga", TG_DIEGO)
        pid, iid, body = self.last_patch()
        self.assertEqual((pid, iid, body), (PID["HOME"], "i-HOME-3", {"assignees": [UID["aga"]]}))
        self.assertEqual(self.w.planes[-1].token, "tok-diego")
        self.assertIn("HOME-3", out)
        self.assertIn("aga", out)
        self.assertTrue(out.keyboard)
        self.assertEqual(out.item, "i-HOME-3")
        # mirror refreshed
        self.assertEqual(self.w.mirror.item("i-HOME-3")["assignees"], [UID["aga"]])

    def test_assign_me_and_none(self):
        self.w.say(HOME, "5", "/assign HOME-1 me", TG_AGA)
        self.assertEqual(self.last_patch()[2], {"assignees": sorted([UID["diego"], UID["aga"]])})
        self.w.say(HOME, "5", "/assign HOME-1 none", TG_AGA)
        self.assertEqual(self.last_patch()[2], {"assignees": []})

    def test_assign_non_member_is_refused(self):
        out = self.w.say(HOME, "5", "/assign HOME-1 komi", TG_DIEGO)
        self.assertIn("not a member of HOME", out)
        self.assertEqual(self.w.planes, [])

    def test_assign_foreign_project_is_unknown_here(self):
        self.assertEqual(self.w.say(HOME, "5", "/assign AINF-1 me", TG_DIEGO), "Unknown project here.")
        self.assertEqual(self.w.say(MY, "4", "/done HOME-1", TG_DIEGO), "Unknown project here.")
        self.assertEqual(self.w.planes, [])

    def test_prio_and_bad_prio(self):
        self.w.say(MY, "4", "/prio AINF-3 urgent")
        self.assertEqual(self.last_patch()[2], {"priority": "urgent"})
        self.assertIn("Usage", self.w.say(MY, "4", "/prio AINF-3 asap"))

    def test_state_and_done(self):
        self.w.say(MY, "4", "/state AINF-3 progress")
        self.assertEqual(self.last_patch()[2], {"state": sid("AINF", "In Progress")})
        self.w.say(MY, "4", "/done AINF-3")
        self.assertEqual(self.last_patch()[2], {"state": sid("AINF", "Done")})
        self.assertIn("has no state named In Review", self.w.say(HOME, "5", "/state HOME-1 review"))

    def test_due_words(self):
        self.w.say(MY, "4", "/due AINF-3 none")
        self.assertEqual(self.last_patch()[2], {"target_date": None})
        self.w.say(MY, "4", "/due AINF-3 2026-10-01")
        self.assertEqual(self.last_patch()[2], {"target_date": "2026-10-01"})
        self.assertIn("Usage", self.w.say(MY, "4", "/due AINF-3 someday"))

    def test_read_only_and_stranger_cannot_write(self):
        self.w.cfg.users["komi"].telegram_id = "333"
        self.assertIn("read-only", self.w.say(MY, "11", "/done APORT-1", "333"))
        self.assertIn("Not registered", self.w.say(MY, "4", "/done AINF-1", TG_STRANGER))
        self.assertEqual(self.w.planes, [])

    def test_show_and_new_carry_keyboards(self):
        out = self.w.say(HOME, "5", "/show HOME-1")
        self.assertTrue(out.keyboard and out.item == "i-HOME-1")
        labels = [b["text"] for row in out.keyboard["inline_keyboard"] for b in row]
        self.assertEqual(labels, ["▶ In Progress", "✅ Done", "👤 Me"])
        out = self.w.say(HOME, "5", "/show HOME-4")  # Done -> only reopen
        self.assertEqual([b["text"] for row in out.keyboard["inline_keyboard"] for b in row], ["↩ Todo"])


class ParseDue(unittest.TestCase):
    def test_forms(self):
        today = dt.date(2026, 9, 11)  # a Friday
        self.assertEqual(parse_due("today", today), "2026-09-11")
        self.assertEqual(parse_due("tomorrow", today), "2026-09-12")
        self.assertEqual(parse_due("fri", today), "2026-09-18")  # next Friday, never today
        self.assertEqual(parse_due("Monday", today), "2026-09-14")
        self.assertEqual(parse_due("+3d", today), "2026-09-14")
        self.assertEqual(parse_due("10-01", today), "2026-10-01")
        self.assertEqual(parse_due("2026-12-24", today), "2026-12-24")
        self.assertIsNone(parse_due("none", today))
        with self.assertRaises(ValueError):
            parse_due("nope", today)


class Callbacks(unittest.TestCase):
    """Buttons: callback data carries the item id; the chat's table still decides."""

    def setUp(self):
        self.w = World()
        # give the seeded items UUID-shaped ids so item_by_hex works
        import uuid
        self.uuid_of = {}
        for r in self.w.mirror.items_in(list(PID.values())):
            u = str(uuid.uuid5(uuid.NAMESPACE_URL, r["id"]))
            self.uuid_of[r["identifier"]] = u
            self.w.mirror.db.execute("UPDATE items SET id=? WHERE id=?", (u, r["id"]))
            from helpers import FakePlane
            FakePlane.store[u] = dict(FakePlane.store[r["id"]], id=u)
        self.w.mirror.db.commit()

    def data(self, ident, action):
        return f"a:{action}:{self.uuid_of[ident].replace('-', '')}"

    def test_done_button_patches_with_users_token_and_returns_card(self):
        toast, card = self.w.bot.callback(HOME, TG_AGA, self.data("HOME-1", "d"))
        self.assertEqual(toast, "Done")
        self.assertEqual(self.w.planes[-1].token, "tok-aga")
        self.assertEqual(self.w.planes[-1].updated[-1][2], {"state": sid("HOME", "Done")})
        self.assertIn("Done", card)
        self.assertEqual([b["text"] for row in card.keyboard["inline_keyboard"] for b in row], ["↩ Todo"])

    def test_me_button(self):
        toast, card = self.w.bot.callback(HOME, TG_AGA, self.data("HOME-1", "m"))
        self.assertEqual(toast, "Assigned to you")
        self.assertEqual(self.w.planes[-1].updated[-1][2], {"assignees": sorted([UID["diego"], UID["aga"]])})
        toast, card = self.w.bot.callback(HOME, TG_AGA, self.data("HOME-1", "m"))
        self.assertEqual((toast, card), ("Already yours", None))

    def test_button_on_foreign_item_is_refused_in_wrong_chat(self):
        toast, card = self.w.bot.callback(MY, TG_DIEGO, self.data("HOME-1", "d"))
        self.assertEqual((toast, card), ("Not available here", None))
        toast, card = self.w.bot.callback(HOME, TG_DIEGO, self.data("ORB-1", "d"))
        self.assertEqual((toast, card), ("Not available here", None))
        self.assertEqual(self.w.planes, [])

    def test_stranger_and_read_only_and_unknown_chat(self):
        toast, _ = self.w.bot.callback(HOME, TG_STRANGER, self.data("HOME-1", "d"))
        self.assertIn("Not registered", toast)
        self.w.cfg.users["komi"].telegram_id = "333"
        toast, _ = self.w.bot.callback(MY, "333", self.data("APORT-1", "d"))
        self.assertIn("read-only", toast)
        self.assertEqual(self.w.bot.callback("-1009", TG_DIEGO, self.data("HOME-1", "d")), (None, None))
        self.assertEqual(self.w.planes, [])

    def test_already_in_state(self):
        toast, card = self.w.bot.callback(HOME, TG_DIEGO, self.data("HOME-2", "p"))  # already In Progress
        self.assertEqual((toast, card), ("Already In Progress", None))


class ReplyComment(unittest.TestCase):
    def setUp(self):
        self.w = World()
        self.w.mirror.set_post("i-HOME-1", HOME, 700, "5")
        self.w.mirror.map_message(HOME, 701, "i-HOME-1")

    def test_reply_to_card_adds_comment_with_callers_token(self):
        out = self.w.bot.reply_comment(HOME, TG_AGA, 700, "Plumber comes <tomorrow> & fixes it")
        self.assertEqual(out, "💬 added to HOME-1")
        pid, iid, html = self.w.planes[0].comments_added[0]
        self.assertEqual((pid, iid), (PID["HOME"], "i-HOME-1"))
        self.assertEqual(html, "<p>Plumber comes &lt;tomorrow&gt; &amp; fixes it</p>")
        self.assertEqual(self.w.planes[0].token, "tok-aga")

    def test_reply_to_secondary_message_also_resolves(self):
        self.assertEqual(self.w.bot.reply_comment(HOME, TG_DIEGO, 701, "ok"), "💬 added to HOME-1")

    def test_reply_to_unknown_message_or_command_is_ignored(self):
        self.assertIsNone(self.w.bot.reply_comment(HOME, TG_DIEGO, 9999, "hello"))
        self.assertIsNone(self.w.bot.reply_comment(HOME, TG_DIEGO, 700, "/status"))
        self.assertEqual(self.w.planes, [])

    def test_reply_in_wrong_chat_is_ignored(self):
        self.w.mirror.map_message(MY, 800, "i-HOME-1")  # would be a bug elsewhere; scope still holds
        self.assertIsNone(self.w.bot.reply_comment(MY, TG_DIEGO, 800, "leak"))
        self.assertEqual(self.w.planes, [])

    def test_stranger_reply(self):
        self.assertIn("Not registered", self.w.bot.reply_comment(HOME, TG_STRANGER, 700, "hi"))


class Scheduled(unittest.TestCase):
    def test_due_report_per_topic_with_mentions_and_scope(self):
        w = World()
        rep = w.bot.due_report(HOME, dt.date(2026, 9, 15))
        threads = [t for t, _ in rep]
        self.assertEqual(threads, ["5", "4"])  # HOME then IRIN (sorted by identifier)
        home_text = dict(rep)["5"]
        self.assertIn("HOME-2", home_text)          # due 09-11 -> overdue
        self.assertIn("overdue 09-11", home_text)
        self.assertIn('tg://user?id=222', home_text)  # aga mentioned
        irin_text = dict(rep)["4"]
        self.assertIn("IRIN-1", irin_text)
        self.assertIn("today", irin_text)
        for _, text in rep:
            self.assertNotIn("AINF", text)
        self.assertEqual(w.bot.due_report(MY, dt.date(2026, 9, 1)), [])  # nothing due yet in MY on that day

    def test_weekly_digest_scoped(self):
        w = World()
        w.mirror.upsert_item(dict(next(i for i in __import__("helpers").seed_items() if i["id"] == "i-HOME-4"), updated_at="2026-09-10T10:00:00+02:00"))
        out = w.bot.weekly_digest(HOME, dt.datetime(2026, 9, 13, 18, 0))
        self.assertIn("closed this week: 1", out)
        self.assertIn("HOME-4", out)
        self.assertIn("<b>IRIN</b>", out)
        self.assertNotIn("AINF", out)
        self.assertNotIn("ORB", out)


if __name__ == "__main__":
    unittest.main()
