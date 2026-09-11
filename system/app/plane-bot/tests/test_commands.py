import unittest

from helpers import HOME, MY, PID, TG_AGA, TG_DIEGO, TG_STRANGER, World, sid


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.w = World()

    def test_new_in_topic_uses_topic_project_and_callers_token(self):
        out = self.w.say(HOME, "5", "/new Fix the roof", TG_AGA)
        self.assertIn("✅", out)
        self.assertIn("HOME-99", out)
        pid, body = self.w.planes[-1].created[-1]
        self.assertEqual(pid, PID["HOME"])
        self.assertEqual(body["name"], "Fix the roof")
        self.assertEqual(body["state"], sid("HOME", "Todo"))
        self.assertEqual(self.w.planes[-1].token, "tok-aga")

    def test_new_with_explicit_project(self):
        out = self.w.say(MY, None, "/new APORT: New landing copy")
        self.assertIn("APORT-99", out)
        self.assertEqual(self.w.planes[-1].created[-1][1]["name"], "New landing copy")
        out = self.w.say(MY, "4", "/new aport Another one")
        self.assertIn("APORT-99", out)

    def test_new_in_general_without_project_asks(self):
        out = self.w.say(MY, None, "/new Something")
        self.assertIn("Which project", out)
        self.assertEqual(self.w.planes, [])

    def test_new_foreign_project_falls_back_to_title_or_asks(self):
        # "IRIN" is not a project in MY, so it is just the first word of a title in General -> asks
        out = self.w.say(MY, None, "/new IRIN leak")
        self.assertIn("Which project", out)
        # in a topic it becomes a ticket titled "IRIN leak" in the topic's project, never in IRIN
        out = self.w.say(MY, "4", "/new IRIN leak")
        self.assertIn("AINF-99", out)
        self.assertEqual(self.w.planes[-1].created[-1][0], PID["AINF"])

    def test_plus_capture_only_inside_project_topic(self):
        self.assertIsNone(self.w.say(MY, None, "+ not a ticket"))
        self.assertIsNone(self.w.say(MY, "777", "+ not a ticket"))
        out = self.w.say(MY, "11", "+ SEO audit")
        self.assertIn("APORT-99", out)
        self.assertEqual(self.w.planes[-1].created[-1][1]["name"], "SEO audit")

    def test_plain_text_is_ignored(self):
        self.assertIsNone(self.w.say(MY, "4", "hello there"))
        self.assertIsNone(self.w.say(MY, "4", "status"))

    def test_read_only_alias_cannot_create(self):
        self.w.cfg.users["komi"].telegram_id = "333"
        out = self.w.say(MY, "11", "/new APORT x", "333")
        self.assertIn("read-only", out)
        self.assertEqual(self.w.planes, [])

    def test_stranger_cannot_create(self):
        out = self.w.say(MY, "4", "+ sneaky", TG_STRANGER)
        self.assertIn("Not registered", out)
        self.assertEqual(self.w.planes, [])

    def test_whoami(self):
        out = self.w.say(MY, "4", "/whoami", TG_DIEGO, "Akunito")
        self.assertIn("<code>111</code>", out)
        self.assertIn("@Akunito", out)
        self.assertIn("diego (can act)", out)
        self.assertIn("This topic: AINF", out)
        self.assertIn("Projects here: AINF, APORT", out)
        out = self.w.say(HOME, None, "/whoami", TG_STRANGER)
        self.assertIn("nobody", out)
        self.assertIn("Projects here: HOME, IRIN", out)

    def test_command_with_bot_suffix(self):
        self.assertIn("Plane bot", self.w.say(MY, "4", "/help@aku_plane_bot"))

    def test_unknown_command_is_silent(self):
        self.assertIsNone(self.w.say(MY, "4", "/restart vps"))

    def test_show_missing(self):
        self.assertIn("not found", self.w.say(MY, "4", "/show AINF-4040"))
        self.assertIn("Usage", self.w.say(MY, "4", "/show"))


if __name__ == "__main__":
    unittest.main()
