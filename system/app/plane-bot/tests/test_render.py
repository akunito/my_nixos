import unittest

from helpers import HOME, MY, TG_AGA, TG_DIEGO, World, item
from plane_bot import LIST_CAP


class RenderTests(unittest.TestCase):
    def setUp(self):
        self.w = World()

    def test_list_orders_state_then_priority_and_excludes_inactive(self):
        out = self.w.say(MY, "4", "/status")
        ids = [l.split(">")[1].split("<")[0] for l in out.split("\n") if "AINF-" in l]
        # In Progress first, then In Review, then Todo by urgent > medium(n8n) > low
        self.assertEqual(ids, ["AINF-1", "AINF-4", "AINF-2", "AINF-9", "AINF-3"])
        for excluded in ("Someday idea", "Parked thing", "Old task", "Unowned todo"):
            self.assertNotIn(excluded, out)
        self.assertIn("due 09-20", out)
        self.assertIn("🔥", out)
        self.assertIn('href="https://plane.example/ws/browse/AINF-1/"', out)

    def test_list_escapes_html_in_titles(self):
        self.w.mirror.upsert_item(item("AINF", 50, "Fix <b>bold</b> & co", "Todo", "low", ["diego"]))
        out = self.w.say(MY, "4", "/status")
        self.assertIn("Fix &lt;b&gt;bold&lt;/b&gt; &amp; co", out)

    def test_cap_per_project(self):
        for i in range(100, 100 + LIST_CAP + 5):
            self.w.mirror.upsert_item(item("AINF", i, f"bulk {i}", "Todo", "none", ["diego"]))
        out = self.w.say(MY, "4", "/status")
        self.assertIn("+", out)
        self.assertIn(" more", out)
        self.assertEqual(out.count(">AINF-"), LIST_CAP)

    def test_all_for_me_groups_by_project_and_skips_empty(self):
        out = self.w.say(MY, None, "/status all")
        self.assertIn("<b>AINF</b>", out)
        self.assertIn("<b>APORT</b>", out)
        self.assertIn("APORT-2", out)
        self.assertIn("APORT-3", out)
        self.assertNotIn("APORT-1", out)  # komi's

    def test_all_for_komi_read_only_alias(self):
        out = self.w.say(MY, None, "/status all komi")
        self.assertIn("APORT-1", out)
        self.assertIn("APORT-3", out)
        self.assertNotIn("AINF", out.replace("AINF-", ""))  # no AINF block at all

    def test_project_all_by_person_with_unassigned(self):
        out = self.w.say(HOME, "5", "/status HOME all")
        self.assertIn("<u>diego</u> (1)", out)
        self.assertIn("<u>aga</u> (1)", out)
        self.assertIn("<u>Unassigned</u> (1)", out)
        self.assertIn("HOME-3", out)
        self.assertNotIn("HOME-4", out)  # Done
        # people first, Unassigned last
        self.assertLess(out.index("<u>aga</u>"), out.index("<u>Unassigned</u>"))

    def test_general_summary_counts_for_me(self):
        out = self.w.say(MY, None, "/status")
        self.assertIn("Active tickets for diego", out)
        self.assertIn("<b>AINF</b> · 5: 1 in progress · 1 in review · 3 todo", out)
        self.assertIn("<b>APORT</b> · 2: 2 todo", out)
        self.assertIn("7 total", out)

    def test_group_summary_all_all(self):
        out = self.w.say(HOME, "4", "/status all all")
        self.assertIn("<b>HOME</b> · 3 (1 in progress · 2 todo) — ", out)
        self.assertIn("unassigned 1", out)
        self.assertIn("<b>IRIN</b> · 2", out)

    def test_empty_results_are_explicit(self):
        self.assertEqual(self.w.say(HOME, "4", "/status IRIN komi"), "komi is not a member of IRIN.")
        self.assertEqual(self.w.say(HOME, "4", "/status all komi"), "komi is not a member of any project here.")
        self.w.mirror.upsert_item(item("IRIN", 2, "Buy food", "Done", "medium", ["diego"]))
        self.assertEqual(self.w.say(HOME, "4", "/status", TG_DIEGO), "<b>IRIN</b> · no active tickets for diego.")

    def test_aga_sees_her_own_by_default(self):
        out = self.w.say(HOME, None, "/status all", TG_AGA)
        self.assertIn("IRIN-1", out)
        self.assertIn("HOME-2", out)
        self.assertNotIn("HOME-1", out)

    def test_show(self):
        out = self.w.say(HOME, "5", "/show home-2")
        self.assertIn("HOME-2", out)
        self.assertIn("Insurance papers", out)
        self.assertIn("aga", out)
        self.assertIn("due 2026-09-11", out)


if __name__ == "__main__":
    unittest.main()
