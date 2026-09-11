import hashlib
import hmac
import json
import unittest

from helpers import HOME, MY, PID, UID, FakeCommentsPlane, FakeTelegram, World, sid
from notify import Notifier
from webhook import WebhookReceiver, normalise_issue, verify

SECRET = "plane_wh_test"


def signed(payload):
    body = json.dumps(payload).encode()
    return body, hmac.new(SECRET.encode(), body, hashlib.sha256).hexdigest()


def issue_payload(action, ident, seq, name, state, assignees=(), actor="aga", updated="2026-09-12T10:00:00+02:00", **extra):
    data = {"id": f"i-{ident}-{seq}", "project": PID[ident], "sequence_id": seq, "name": name, "priority": extra.pop("priority", "medium"),
            "state": {"id": sid(ident, state), "name": state}, "assignees": [{"id": UID[a], "email": f"{a}@example.com"} for a in assignees],
            "target_date": None, "updated_at": updated, "created_at": "2026-09-12T09:00:00+02:00", "external_source": extra.pop("external", None),
            "created_by": UID[extra.pop("created_by", actor)]}
    data.update(extra)
    return {"event": "issue", "action": action, "webhook_id": "w", "workspace_id": "ws", "workspace_slug": "ws",
            "data": data, "activity": {"field": None, "old_value": None, "new_value": None, "actor": {"id": UID[actor], "display_name": actor}}}


class Rig(World):
    def __init__(self):
        super().__init__()
        self.tg = FakeTelegram()
        self.plane = FakeCommentsPlane()
        self.n = Notifier(self.cfg, self.mirror, self.tg, self.plane)
        self.rx = WebhookReceiver(self.cfg, self.mirror, self.n, SECRET)

    def post(self, payload, sig=None):
        body, s = signed(payload)
        return self.rx.handle(body, s if sig is None else sig)


class Signature(unittest.TestCase):
    def test_bad_signature_is_401_and_does_nothing(self):
        r = Rig()
        code, info = r.post(issue_payload("create", "HOME", 60, "x", "Todo"), sig="deadbeef")
        self.assertEqual(code, 401)
        self.assertEqual(r.tg.sent, [])
        self.assertIsNone(r.mirror.item("i-HOME-60"))

    def test_empty_secret_never_verifies(self):
        self.assertFalse(verify("", b"x", hmac.new(b"", b"x", hashlib.sha256).hexdigest()))

    def test_bad_json_is_400(self):
        r = Rig()
        body = b"not json"
        code, _ = r.rx.handle(body, hmac.new(SECRET.encode(), body, hashlib.sha256).hexdigest())
        self.assertEqual(code, 400)


class IssueEvents(unittest.TestCase):
    def test_create_by_aga_in_home_posts_card_and_mirrors_item(self):
        r = Rig()
        code, info = r.post(issue_payload("create", "HOME", 60, "Webhook ticket", "Todo"))
        self.assertEqual(code, 200)
        self.assertIn("1 message", info)
        self.assertEqual(r.tg.sent[0][:2], (HOME, "5"))
        self.assertIn("HOME-60", r.tg.sent[0][2])
        row = r.mirror.item("i-HOME-60")
        self.assertEqual(row["state_name"], "Todo")
        self.assertEqual(row["created_by"], UID["aga"])

    def test_expanded_objects_are_normalised(self):
        d = issue_payload("update", "HOME", 1, "n", "Done", assignees=["diego"])["data"]
        n = normalise_issue(d)
        self.assertEqual(n["state"], sid("HOME", "Done"))
        self.assertEqual(n["assignees"], [UID["diego"]])
        self.assertEqual(normalise_issue({"id": "x", "state": "s1", "assignees": ["u1"], "project": "p"})["assignees"], ["u1"])

    def test_update_to_done_edits_card_with_actor_from_activity(self):
        r = Rig()
        r.mirror.set_post("i-HOME-1", HOME, 500, "5")
        code, info = r.post(issue_payload("update", "HOME", 1, "Fix the tap", "Done", assignees=["diego"], actor="aga", created_by="diego"))
        self.assertEqual(code, 200)
        self.assertEqual(len(r.tg.edited), 1)
        self.assertIn("✅", r.tg.edited[0][2])
        self.assertIn("by aga", r.tg.edited[0][2])

    def test_out_of_scope_project_is_200_but_ignored(self):
        r = Rig()
        payload = issue_payload("create", "ORB", 60, "SECRET", "Todo", actor="komi")
        payload["data"]["project"] = "p-unknown"
        code, info = r.post(payload)
        self.assertEqual((code, info), (200, "project out of scope"))
        self.assertEqual(r.tg.sent, [])

    def test_orb_in_mirror_but_in_no_chat_reaches_nobody(self):
        r = Rig()
        r.cfg.users["komi"].telegram_id = "333"
        code, info = r.post(issue_payload("create", "ORB", 60, "SECRET", "Todo", actor="komi"))
        self.assertEqual(code, 200)
        self.assertEqual(r.tg.sent, [])

    def test_already_mirrored_by_poller_is_not_repeated(self):
        r = Rig()
        p = issue_payload("update", "HOME", 1, "Fix the tap", "Done", assignees=["diego"], actor="aga")
        r.post(p)
        n_before = len(r.tg.sent)
        code, info = r.post(p)
        self.assertEqual(info, "already mirrored")
        self.assertEqual(len(r.tg.sent), n_before)

    def test_delete_is_ignored_and_unknown_event_is_200(self):
        r = Rig()
        self.assertEqual(r.post(issue_payload("delete", "HOME", 1, "x", "Todo"))[1], "delete ignored")
        code, info = r.post({"event": "cycle", "action": "create", "data": {}})
        self.assertEqual((code, info), (200, "ignored cycle/create"))

    def test_echo_rule_still_applies(self):
        r = Rig()
        code, info = r.post(issue_payload("create", "AINF", 60, "own thing", "Todo", actor="diego"))
        self.assertEqual(code, 200)
        self.assertEqual(r.tg.sent, [])


class Timestamps(unittest.TestCase):
    def test_webhook_utc_and_rest_offset_are_the_same_instant(self):
        r = Rig()
        r.post(issue_payload("updated", "HOME", 1, "Fix the tap", "Done", assignees=["diego"], actor="aga", updated="2026-09-12T08:00:00.5Z"))
        row = r.mirror.item("i-HOME-1")
        self.assertEqual(row["updated_at"], "2026-09-12T08:00:00.500000+00:00")
        from plane_bot import _differs
        rest_item = {"state": row["state"], "priority": row["priority"], "name": row["name"], "target_date": None,
                     "assignees": row["assignees"], "updated_at": "2026-09-12T10:00:00.500000+02:00"}
        prev = dict(row, assignees=json.dumps(sorted(row["assignees"])))
        self.assertFalse(_differs(prev, rest_item))


class CommentEvents(unittest.TestCase):
    def payload(self, cid, issue_id, actor, text):
        return {"event": "issue_comment", "action": "create", "data": {"id": cid, "issue": issue_id, "actor": UID[actor],
                "comment_html": f"<p>{text}</p>", "created_at": "2026-09-12T10:00:00+02:00"},
                "activity": {"actor": {"id": UID[actor]}}}

    def test_comment_is_quoted_once_even_if_poller_sees_it_later(self):
        r = Rig()
        code, info = r.post(self.payload("c1", "i-HOME-1", "aga", "webhook comment"))
        self.assertEqual(code, 200)
        self.assertEqual(len(r.tg.sent), 1)
        self.assertIn("webhook comment", r.tg.sent[0][2])
        # the poller later fetches the same comment: dedupe by id
        r.plane.comments_by_item["i-HOME-1"] = [{"id": "c1", "actor": UID["aga"], "comment_html": "<p>webhook comment</p>", "created_at": "2026-09-12T10:00:00+02:00"}]
        prev = dict(r.mirror.item("i-HOME-1"))
        prev["assignees"] = json.dumps(prev["assignees"])
        prev["updated_at"] = "2026-09-01T00:00:00+02:00"
        new = dict(r.mirror.item("i-HOME-1"), updated_at="2026-09-12T10:00:01+02:00", updated_by=UID["aga"])
        r.mirror.upsert_item(new)
        r.n.process([(prev, new)])
        self.assertEqual(len(r.tg.sent), 1)

    def test_plane_participle_verbs_are_accepted(self):
        r = Rig()
        p = self.payload("c9", "i-HOME-1", "aga", "participle")
        p["action"] = "created"
        self.assertEqual(r.post(p)[1], "comment: 1 message(s)")
        q = issue_payload("created", "HOME", 61, "participle issue", "Todo")
        self.assertIn("1 message", r.post(q)[1])
        d = issue_payload("deleted", "HOME", 61, "x", "Todo")
        self.assertEqual(r.post(d)[1], "delete ignored")

    def test_duplicate_delivery_is_ignored(self):
        r = Rig()
        r.post(self.payload("c2", "i-HOME-1", "aga", "once"))
        code, info = r.post(self.payload("c2", "i-HOME-1", "aga", "once"))
        self.assertEqual(info, "comment already seen")
        self.assertEqual(len(r.tg.sent), 1)

    def test_own_comment_in_own_project_silent_and_out_of_scope_item(self):
        r = Rig()
        self.assertEqual(r.post(self.payload("c3", "i-AINF-1", "diego", "mine"))[1], "comment: 0 message(s)")
        self.assertEqual(r.post(self.payload("c4", "i-nope", "aga", "x"))[1], "comment on item out of scope")
        self.assertEqual(r.tg.sent, [])


if __name__ == "__main__":
    unittest.main()
