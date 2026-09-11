"""The leak matrix: nothing from outside a chat's project table may ever appear in a reply.

Every command form × every chat × every requester, and for every reply we
assert that no identifier prefix and no ticket title of a project outside
that chat shows up. ORB is in the mirror (as it would be if the sync token
could see it) and in no chat: it must be invisible everywhere.
"""
import unittest

from helpers import ALL_IDENTS, HOME, MY, TG_AGA, TG_DIEGO, TG_STRANGER, World, seed_items

CHAT_PROJECTS = {MY: {"AINF", "APORT"}, HOME: {"IRIN", "HOME"}}
TITLES = {}
for it in seed_items():
    ident = it["id"].split("-")[1]
    TITLES.setdefault(ident, []).append(it["name"])

FORMS = ["/status", "/status all", "/status all all", "/status all diego", "/status all aga", "/status all komi",
         "/help", "/whoami", "/show {p}-1", "/status {p}", "/status {p} all", "/status {p} diego", "/status {p} aga",
         "/status {p} komi", "/new {p} leak probe"]
THREADS = [None, "4", "5", "11", "777"]


class LeakMatrix(unittest.TestCase):
    def assert_scoped(self, chat, out, ctx):
        if not out:
            return
        for ident in ALL_IDENTS:
            if ident in CHAT_PROJECTS[chat]:
                continue
            self.assertNotIn(ident + "-", out, f"{ctx}: leaked identifier {ident}")
            self.assertNotIn(f"<b>{ident}</b>", out, f"{ctx}: leaked project block {ident}")
            for title in TITLES.get(ident, []):
                self.assertNotIn(title, out, f"{ctx}: leaked title {title!r}")

    def test_matrix(self):
        for chat in (MY, HOME):
            for form in FORMS:
                probes = [form.format(p=p) for p in ALL_IDENTS] if "{p}" in form else [form]
                for text in probes:
                    for thread in THREADS:
                        for user in (TG_DIEGO, TG_AGA, TG_STRANGER):
                            w = World()
                            out = w.say(chat, thread, text, user)
                            self.assert_scoped(chat, out, (chat, thread, text, user))

    def test_unknown_chat_is_silent_for_everything(self):
        w = World()
        for text in ["/status", "/status all all", "/status AINF", "/help", "/whoami", "+ hello", "/new AINF x"]:
            self.assertIsNone(w.say("-1009999", "4", text, TG_DIEGO), text)
        self.assertEqual(w.planes, [])

    def test_foreign_project_wording_does_not_reveal_existence(self):
        w = World()
        real = w.say(HOME, None, "/status AINF")
        fake = w.say(HOME, None, "/status ZZZZ")
        self.assertEqual(real, fake)
        self.assertEqual(w.say(HOME, None, "/show AINF-1"), w.say(HOME, None, "/show ZZZZ-1"))

    def test_diego_assigned_orb_ticket_never_shows_even_to_diego(self):
        w = World()
        for chat, thread in ((MY, None), (MY, "4"), (HOME, None)):
            for text in ("/status", "/status all", "/status all all"):
                out = w.say(chat, thread, text, TG_DIEGO) or ""
                self.assertNotIn("ORB", out)
                self.assertNotIn("SECRET", out)


if __name__ == "__main__":
    unittest.main()
