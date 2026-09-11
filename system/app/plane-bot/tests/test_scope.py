import unittest

from helpers import HOME, MY, TG_AGA, TG_DIEGO, TG_STRANGER, make_config
from plane_bot import ALL, Reply, resolve_status


class ScopeTests(unittest.TestCase):
    def setUp(self):
        self.cfg = make_config()

    def res(self, chat, thread, args, tg=TG_DIEGO):
        return resolve_status(self.cfg, chat, thread, args, tg)

    def test_bare_in_project_topic_is_that_project_for_me(self):
        s = self.res(MY, "4", [])
        self.assertEqual((s.projects, s.user.alias, s.mode), (["AINF"], "diego", "list"))

    def test_bare_in_general_is_summary_of_whole_chat(self):
        s = self.res(MY, None, [])
        self.assertEqual((s.projects, s.mode), (["AINF", "APORT"], "summary"))
        self.assertEqual(s.user.alias, "diego")

    def test_all_for_me_lists_every_chat_project(self):
        s = self.res(HOME, "5", ["all"])
        self.assertEqual((s.projects, s.mode, s.user.alias), (["HOME", "IRIN"], "list", "diego"))

    def test_all_other_user(self):
        s = self.res(HOME, None, ["all", "aga"])
        self.assertEqual((s.projects, s.mode, s.user.alias), (["HOME", "IRIN"], "list", "aga"))

    def test_all_all_is_group_summary(self):
        s = self.res(MY, "4", ["ALL", "All"])
        self.assertEqual((s.projects, s.mode, s.user), (["AINF", "APORT"], "summary_all", ALL))

    def test_project_all_groups_by_person(self):
        s = self.res(MY, None, ["aport", "all"])
        self.assertEqual((s.projects, s.mode, s.user), (["APORT"], "by_person", ALL))

    def test_project_user_case_insensitive_and_at(self):
        s = self.res(HOME, "4", ["home", "@Aga"])
        self.assertEqual((s.projects, s.user.alias), (["HOME"], "aga"))

    def test_project_arg_wins_over_topic(self):
        s = self.res(MY, "4", ["APORT"])
        self.assertEqual(s.projects, ["APORT"])

    def test_foreign_project_is_unknown_here(self):
        for chat, proj in ((MY, "IRIN"), (MY, "HOME"), (HOME, "AINF"), (HOME, "APORT"), (MY, "ORB"), (HOME, "ORB"), (MY, "NOPE")):
            with self.assertRaises(Reply) as cm:
                self.res(chat, None, [proj])
            self.assertEqual(cm.exception.text, "Unknown project here.", (chat, proj))

    def test_unknown_thread_in_known_chat_behaves_like_general(self):
        s = self.res(MY, "777", [])
        self.assertEqual((s.projects, s.mode), (["AINF", "APORT"], "summary"))

    def test_unknown_user_alias(self):
        with self.assertRaises(Reply) as cm:
            self.res(MY, "4", ["AINF", "bob"])
        self.assertIn("Unknown user", cm.exception.text)

    def test_unregistered_requester(self):
        with self.assertRaises(Reply) as cm:
            self.res(MY, "4", [], tg=TG_STRANGER)
        self.assertIn("Not registered", cm.exception.text)

    def test_unregistered_requester_may_still_ask_for_a_named_user(self):
        s = self.res(HOME, "4", ["IRIN", "aga"], tg=TG_STRANGER)
        self.assertEqual(s.user.alias, "aga")

    def test_too_many_args(self):
        with self.assertRaises(Reply) as cm:
            self.res(MY, "4", ["a", "b", "c"])
        self.assertIn("Usage", cm.exception.text)

    def test_aga_in_home(self):
        s = self.res(HOME, "5", [], tg=TG_AGA)
        self.assertEqual((s.projects, s.user.alias), (["HOME"], "aga"))

    def test_scope_never_contains_projects_outside_the_chat(self):
        forms = [[], ["all"], ["all", "all"], ["all", "aga"], ["AINF"], ["APORT", "all"]]
        for args in forms:
            try:
                s = self.res(MY, "4", args)
            except Reply:
                continue
            self.assertTrue(set(s.projects) <= {"AINF", "APORT"}, args)


if __name__ == "__main__":
    unittest.main()
