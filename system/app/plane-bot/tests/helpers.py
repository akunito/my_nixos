"""Synthetic world for the plane-bot tests. No real ticket data lives here.

Chats:
  MY   (-1001)  -> AINF (topic 4), APORT (topic 11)     Diego's group; APORT is shared with Komi
  HOME (-1002)  -> IRIN (topic 4), HOME (topic 5)       Diego + Aga
Projects in the mirror but in NO chat: ORB (Komi-only). It must never leak.
"""
import os
import sys
import warnings

warnings.filterwarnings("ignore", category=ResourceWarning)  # in-memory sqlite handles in throwaway Worlds

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from plane_bot import Bot, Config, Mirror  # noqa: E402

MY, HOME = "-1001", "-1002"
TG_DIEGO, TG_AGA, TG_STRANGER = "111", "222", "999"
UID = {"diego": "u-diego", "aga": "u-aga", "komi": "u-komi"}
EMAIL = {"diego": "diego@example.com", "aga": "aga@example.com", "komi": "komi@example.com"}
PID = {"AINF": "p-ainf", "APORT": "p-aport", "IRIN": "p-irin", "HOME": "p-home", "ORB": "p-orb"}
MEMBERS = {"AINF": ["diego"], "APORT": ["diego", "komi"], "IRIN": ["diego", "aga"], "HOME": ["diego", "aga"], "ORB": ["komi"]}
ALL_IDENTS = list(PID)


def make_config():
    return Config(
        chats={MY: {"AINF": "4", "APORT": "11"}, HOME: {"IRIN": "4", "HOME": "5"}},
        users={
            "diego": {"telegramId": TG_DIEGO, "email": EMAIL["diego"], "token": "tok-diego"},
            "aga": {"telegramId": TG_AGA, "email": EMAIL["aga"], "token": "tok-aga"},
            "komi": {"telegramId": "", "email": EMAIL["komi"], "token": ""},
        },
        plane_url="http://plane.test", public_url="https://plane.example", workspace="ws", sync_alias="diego",
    )


def states_for(ident):
    names = [("Backlog", "backlog", 1, True), ("Hold - Important", "unstarted", 2, False), ("Todo", "unstarted", 3, False),
             ("In Progress", "started", 4, False), ("Done", "completed", 6, False), ("Cancelled", "cancelled", 7, False)]
    if ident == "AINF":
        names.insert(4, ("In Review", "started", 5, False))
    return [{"id": f"s-{ident}-{n.lower().replace(' ', '')}", "name": n, "group": g, "sequence": seq, "default": d} for n, g, seq, d in names]


def sid(ident, name):
    return f"s-{ident}-{name.lower().replace(' ', '')}"


def item(ident, seq, name, state, priority="none", assignees=(), target_date=None, updated="2026-09-01T10:00:00+02:00", external=None):
    return {"id": f"i-{ident}-{seq}", "project": PID[ident], "sequence_id": seq, "name": name, "state": sid(ident, state),
            "priority": priority, "assignees": [UID[a] for a in assignees], "target_date": target_date,
            "updated_at": updated, "created_at": "2026-08-01T10:00:00+02:00", "external_source": external}


def seed_items():
    return [
        # AINF: Diego only, every state, priorities, due dates
        item("AINF", 1, "Fix split DNS", "In Progress", "high", ["diego"], "2026-09-20"),
        item("AINF", 2, "Rotate certs", "Todo", "urgent", ["diego"], "2026-09-12"),
        item("AINF", 3, "Write docs", "Todo", "low", ["diego"]),
        item("AINF", 4, "Review PR", "In Review", "medium", ["diego"]),
        item("AINF", 5, "Someday idea", "Backlog", "none", ["diego"]),
        item("AINF", 6, "Parked thing", "Hold - Important", "high", ["diego"]),
        item("AINF", 7, "Old task", "Done", "medium", ["diego"]),
        item("AINF", 8, "Unowned todo", "Todo", "medium", []),
        item("AINF", 9, "Monthly tax doc", "Todo", "medium", ["diego"], external="n8n"),
        # APORT: Diego + Komi
        item("APORT", 1, "Landing page", "In Progress", "medium", ["komi"]),
        item("APORT", 2, "SEO pass", "Todo", "low", ["diego"]),
        item("APORT", 3, "Pair task", "Todo", "high", ["diego", "komi"]),
        # IRIN / HOME: Diego + Aga
        item("IRIN", 1, "Vet appointment", "Todo", "high", ["aga"], "2026-09-15"),
        item("IRIN", 2, "Buy food", "In Progress", "medium", ["diego"]),
        item("HOME", 1, "Fix the tap", "Todo", "medium", ["diego"]),
        item("HOME", 2, "Insurance papers", "In Progress", "urgent", ["aga"], "2026-09-11"),
        item("HOME", 3, "Nobody's job", "Todo", "low", []),
        item("HOME", 4, "Done chore", "Done", "none", ["aga"]),
        # ORB: Komi only, never in any chat
        item("ORB", 1, "SECRET orbit task", "Todo", "high", ["komi"]),
        item("ORB", 2, "SECRET in progress", "In Progress", "high", ["diego"]),  # even Diego-assigned must not leak
    ]


def make_mirror():
    m = Mirror(":memory:")
    for ident, pid in PID.items():
        m.upsert_project({"id": pid, "identifier": ident, "name": ident})
        m.replace_states(pid, states_for(ident))
        m.replace_members(pid, [{"id": UID[a], "email": EMAIL[a], "display_name": a + "-plane"} for a in MEMBERS[ident]])
    for it in seed_items():
        m.upsert_item(it)
    return m


class FakePlane:
    """Records writes; returns a plausible created item."""

    def __init__(self, token):
        self.token = token
        self.created = []

    def create_work_item(self, pid, body):
        self.created.append((pid, body))
        ident = next(k for k, v in PID.items() if v == pid)
        return {"id": f"i-{ident}-new", "project": pid, "sequence_id": 99, "name": body["name"], "state": body.get("state"),
                "priority": "none", "assignees": [], "target_date": None, "updated_at": "2026-09-11T12:00:00+02:00",
                "created_at": "2026-09-11T12:00:00+02:00", "external_source": None}


class World:
    def __init__(self):
        self.cfg = make_config()
        self.mirror = make_mirror()
        self.planes = []

        def factory(token):
            p = FakePlane(token)
            self.planes.append(p)
            return p

        self.bot = Bot(self.cfg, self.mirror, plane_factory=factory)

    def say(self, chat, thread, text, user=TG_DIEGO, username=""):
        return self.bot.handle(chat, thread, text, user, username)


class FakeTelegram:
    """Records sends/edits; returns message ids like the Bot API."""

    def __init__(self):
        self.token = "fake"
        self.sent = []   # (chat, thread, text, reply_to)
        self.edited = []  # (chat, message_id, text)
        self._next = 1000

    def send(self, chat_id, text, thread=None, reply_to=None, reply_markup=None):
        self._next += 1
        self.sent.append((str(chat_id), str(thread) if thread is not None else None, text, reply_to))
        return {"message_id": self._next}

    def send_long(self, chat_id, text, thread=None, reply_to=None):
        return [self.send(chat_id, text, thread, reply_to)]

    def edit(self, chat_id, message_id, text, reply_markup=None):
        self.edited.append((str(chat_id), message_id, text))
        return {"message_id": message_id}


class FakeCommentsPlane:
    def __init__(self):
        self.comments_by_item = {}

    def comments(self, pid, iid):
        return list(self.comments_by_item.get(iid, []))
