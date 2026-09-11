#!/usr/bin/env python3
"""Plane Telegram bot (@aku_plane_bot).

One daemon on VPS_PROD next to Plane. Each Telegram forum group is an
*audience*: the chat -> projects table (PLANE_CHATS) is the only thing that
decides which projects a group can see, list, create in or hear about. A
project that is not in a chat's table does not exist for that chat, and the
bot never derives a project from anything but that table.

Halves:
  1. Mirror: a sqlite copy of every in-scope project's work items, states and
     members, filled by polling the Plane REST API (the v1 list endpoint has
     no filters, so /status reads the mirror instead of paging Plane).
  2. Commands (long polling), answered in the topic they were asked in:
       /status [project|all] [user|all]   active tickets (see help)
       /show PROJ-12                      one ticket
       /new [PROJ] title  |  "+ title"    create a ticket (Todo) as the caller
       /whoami  /help
     Every write goes to Plane with the *caller's* API token, so Plane's own
     permissions apply on top of the chat scope.

Config comes from the environment (plane-bot.nix). CLI:
  plane-bot                       run the daemon
  plane-bot sync [--full]         one sync pass and exit
  plane-bot simulate --chat ID [--thread N] [--user TGID] "/status all"
                                  print the reply a message would get, no Telegram
"""
import datetime as dt
import json
import logging
import os
import re
import sqlite3
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zoneinfo

from notify import Notifier, keyboard_for
from tgcommon import Telegram, esc

log = logging.getLogger("plane-bot")

PRIORITY_ORDER = ["urgent", "high", "medium", "low", "none"]
PRIORITY_ICON = {"urgent": "🔥", "high": "🔴", "medium": "🟠", "low": "🟢", "none": "⚪"}
DEFAULT_ACTIVE_STATES = ["In Progress", "In Review", "Todo"]  # display order
LIST_CAP = 20
ITEM_FIELDS = "id,sequence_id,name,state,priority,assignees,target_date,updated_at,created_at,external_source,project,created_by,updated_by"
IDENT_RE = re.compile(r"^([A-Za-z][A-Za-z0-9]*)-(\d+)$")


# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------
class User:
    def __init__(self, alias, telegram_id="", email="", token=""):
        self.alias = alias
        self.telegram_id = str(telegram_id or "")
        self.email = (email or "").lower()
        self.token = token or ""

    @property
    def can_act(self):
        return bool(self.token)


class Config:
    def __init__(self, chats, users, plane_url="", public_url="", workspace="", sync_alias="",
                 active_states=None, state_dir=".", poll_seconds=60, full_sync_minutes=60, tz="Europe/Warsaw"):
        # chats: {chat_id(str): {IDENT: thread_id(str)}}
        self.chats = {str(c): {k.upper(): str(v) for k, v in (m or {}).items()} for c, m in (chats or {}).items()}
        self.users = {}
        for alias, u in (users or {}).items():
            if isinstance(u, User):
                self.users[alias.lower()] = u
            else:
                self.users[alias.lower()] = User(alias.lower(), u.get("telegramId", ""), u.get("email", ""), u.get("token", ""))
        self.plane_url = plane_url.rstrip("/")
        self.public_url = (public_url or plane_url).rstrip("/")
        self.workspace = workspace
        self.sync_alias = sync_alias.lower()
        self.active_states = list(active_states or DEFAULT_ACTIVE_STATES)
        self.state_dir = state_dir
        self.poll_seconds = int(poll_seconds)
        self.full_sync_minutes = int(full_sync_minutes)
        self.tz = zoneinfo.ZoneInfo(tz)

    @classmethod
    def from_env(cls, env=os.environ):
        return cls(
            chats=json.loads(env.get("PLANE_CHATS", "{}")),
            users=json.loads(env.get("PLANE_USERS", "{}")),
            plane_url=env.get("PLANE_URL", ""),
            public_url=env.get("PLANE_PUBLIC_URL", ""),
            workspace=env.get("PLANE_WORKSPACE", ""),
            sync_alias=env.get("SYNC_ALIAS", ""),
            active_states=[s.strip() for s in env.get("ACTIVE_STATES", "").split(",") if s.strip()] or None,
            state_dir=env.get("STATE_DIR", "/var/lib/plane-bot"),
            poll_seconds=env.get("POLL_SECONDS", "60"),
            full_sync_minutes=env.get("FULL_SYNC_MINUTES", "60"),
            tz=env.get("TZ", "Europe/Warsaw"),
        )

    # --- scope primitives: everything else goes through these two
    def chat_projects(self, chat_id):
        """{IDENT: thread} for a known chat, None for an unknown one."""
        return self.chats.get(str(chat_id))

    def project_for_thread(self, chat_id, thread):
        m = self.chat_projects(chat_id) or {}
        if thread is None:
            return None
        for ident, t in m.items():
            if t == str(thread):
                return ident
        return None

    def all_project_idents(self):
        out = set()
        for m in self.chats.values():
            out.update(m.keys())
        return sorted(out)

    def user_by_telegram(self, tg_id):
        tg_id = str(tg_id or "")
        if not tg_id:
            return None
        for u in self.users.values():
            if u.telegram_id == tg_id:
                return u
        return None

    def user_by_alias(self, alias):
        return self.users.get((alias or "").lower())

    def user_by_email(self, email):
        email = (email or "").lower()
        for u in self.users.values():
            if u.email == email:
                return u
        return None

    def sync_user(self):
        u = self.user_by_alias(self.sync_alias)
        if not u or not u.token:
            raise RuntimeError(f"SYNC_ALIAS {self.sync_alias!r} has no token")
        return u


# ----------------------------------------------------------------------------
# Plane REST client (v1)
# ----------------------------------------------------------------------------
class PlaneError(Exception):
    def __init__(self, status, body):
        super().__init__(f"plane HTTP {status}: {body[:200]}")
        self.status = status
        self.body = body


class Plane:
    def __init__(self, base_url, workspace, token, timeout=30):
        self.base = base_url.rstrip("/")
        self.ws = workspace
        self.token = token
        self.timeout = timeout

    def _req(self, method, path, params=None, body=None):
        url = f"{self.base}/api/v1/workspaces/{self.ws}/{path.lstrip('/')}"
        if params:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode({k: v for k, v in params.items() if v not in (None, "")})
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("X-API-Key", self.token)
        req.add_header("Accept", "application/json")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                raw = r.read()
        except urllib.error.HTTPError as e:
            raise PlaneError(e.code, e.read().decode(errors="replace")) from None
        return json.loads(raw) if raw else None

    def get(self, path, **params):
        return self._req("GET", path, params)

    def post(self, path, body):
        return self._req("POST", path, body=body)

    def patch(self, path, body):
        return self._req("PATCH", path, body=body)

    def paged(self, path, per_page=100, **params):
        """Yield results across Plane's cursor pagination."""
        cursor = f"{per_page}:0:0"
        while True:
            page = self.get(path, per_page=per_page, cursor=cursor, **params)
            for r in page.get("results", []):
                yield r
            if not page.get("next_page_results"):
                return
            cursor = page.get("next_cursor")
            if not cursor:
                return

    def projects(self):
        return list(self.paged("projects/"))

    def states(self, pid):
        return list(self.paged(f"projects/{pid}/states/"))

    def members(self, pid):
        return self.get(f"projects/{pid}/members/") or []

    def work_items(self, pid, order_by="-updated_at", fields=ITEM_FIELDS):
        return self.paged(f"projects/{pid}/work-items/", order_by=order_by, fields=fields)

    def work_item(self, pid, iid):
        return self.get(f"projects/{pid}/work-items/{iid}/")

    def by_identifier(self, ident):
        return self.get(f"work-items/{ident}/")

    def create_work_item(self, pid, body):
        return self.post(f"projects/{pid}/work-items/", body)

    def update_work_item(self, pid, iid, body):
        return self.patch(f"projects/{pid}/work-items/{iid}/", body)

    def comments(self, pid, iid):
        return list(self.paged(f"projects/{pid}/work-items/{iid}/comments/"))

    def add_comment(self, pid, iid, comment_html):
        return self.post(f"projects/{pid}/work-items/{iid}/comments/", {"comment_html": comment_html})

    def activities(self, pid, iid):
        return list(self.paged(f"projects/{pid}/work-items/{iid}/activities/"))


# ----------------------------------------------------------------------------
# Mirror (sqlite)
# ----------------------------------------------------------------------------
SCHEMA = """
CREATE TABLE IF NOT EXISTS projects (id TEXT PRIMARY KEY, identifier TEXT, name TEXT);
CREATE TABLE IF NOT EXISTS states (id TEXT PRIMARY KEY, project TEXT, name TEXT, grp TEXT, sequence REAL, is_default INTEGER DEFAULT 0);
CREATE TABLE IF NOT EXISTS members (project TEXT, user_id TEXT, email TEXT, display_name TEXT, PRIMARY KEY (project, user_id));
CREATE TABLE IF NOT EXISTS items (
  id TEXT PRIMARY KEY, project TEXT, seq INTEGER, name TEXT, state TEXT, priority TEXT,
  target_date TEXT, updated_at TEXT, created_at TEXT, external_source TEXT, assignees TEXT, deleted INTEGER DEFAULT 0,
  created_by TEXT, updated_by TEXT);
CREATE INDEX IF NOT EXISTS items_project ON items(project, deleted);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
-- the bot's own message about an item in a chat, so later changes edit it instead of posting again
CREATE TABLE IF NOT EXISTS posts (item TEXT, chat TEXT, message_id INTEGER, thread TEXT, created_at TEXT, PRIMARY KEY (item, chat));
-- every bot message that is about an item (cards, assignment pings, quoted comments): reply-to resolution
CREATE TABLE IF NOT EXISTS msgmap (chat TEXT, message_id INTEGER, item TEXT, PRIMARY KEY (chat, message_id));
"""
# columns added after the first deploy; sqlite has no ADD COLUMN IF NOT EXISTS
MIGRATIONS = [("items", "created_by", "ALTER TABLE items ADD COLUMN created_by TEXT"),
              ("items", "updated_by", "ALTER TABLE items ADD COLUMN updated_by TEXT")]


class Mirror:
    def __init__(self, path=":memory:"):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.lock = threading.RLock()
        with self.lock:
            self.db.executescript(SCHEMA)
            self.migrated = False
            for table, col, ddl in MIGRATIONS:
                cols = {r["name"] for r in self.db.execute(f"PRAGMA table_info({table})").fetchall()}
                if col not in cols:
                    self.db.execute(ddl)
                    self.migrated = True  # rows lack the new data: the daemon runs a silent full sync
            self.db.commit()

    def close(self):
        try:
            self.db.close()
        except Exception:
            pass

    def __del__(self):
        self.close()

    # --- writes
    def upsert_project(self, p):
        with self.lock, self.db:
            self.db.execute("INSERT OR REPLACE INTO projects (id, identifier, name) VALUES (?,?,?)",
                            (p["id"], p["identifier"].upper(), p.get("name", "")))

    def replace_states(self, pid, rows):
        with self.lock, self.db:
            self.db.execute("DELETE FROM states WHERE project=?", (pid,))
            self.db.executemany("INSERT OR REPLACE INTO states (id, project, name, grp, sequence, is_default) VALUES (?,?,?,?,?,?)",
                                [(s["id"], pid, s["name"], s.get("group", ""), s.get("sequence", 0), 1 if s.get("default") else 0) for s in rows])

    def replace_members(self, pid, rows):
        with self.lock, self.db:
            self.db.execute("DELETE FROM members WHERE project=?", (pid,))
            self.db.executemany("INSERT OR REPLACE INTO members (project, user_id, email, display_name) VALUES (?,?,?,?)",
                                [(pid, m["id"], (m.get("email") or "").lower(), m.get("display_name") or m.get("first_name") or "") for m in rows])

    def upsert_item(self, it):
        """Store one API item; returns the previous row (or None) for change detection."""
        with self.lock, self.db:
            prev = self.db.execute("SELECT * FROM items WHERE id=?", (it["id"],)).fetchone()
            self.db.execute(
                "INSERT OR REPLACE INTO items (id, project, seq, name, state, priority, target_date, updated_at, created_at, external_source, assignees, deleted, created_by, updated_by)"
                " VALUES (?,?,?,?,?,?,?,?,?,?,?,0,?,?)",
                (it["id"], it["project"], it.get("sequence_id"), it.get("name", ""), it.get("state"), it.get("priority") or "none",
                 it.get("target_date"), it.get("updated_at"), it.get("created_at"), it.get("external_source"),
                 json.dumps(sorted(it.get("assignees") or [])), it.get("created_by"), it.get("updated_by")))
            return dict(prev) if prev else None

    def mark_missing_deleted(self, pid, keep_ids):
        with self.lock, self.db:
            rows = self.db.execute("SELECT id FROM items WHERE project=? AND deleted=0", (pid,)).fetchall()
            gone = [r["id"] for r in rows if r["id"] not in keep_ids]
            self.db.executemany("UPDATE items SET deleted=1 WHERE id=?", [(g,) for g in gone])
            return gone

    def get_meta(self, key, default=None):
        with self.lock:
            r = self.db.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
        return r["value"] if r else default

    def set_meta(self, key, value):
        with self.lock, self.db:
            self.db.execute("INSERT OR REPLACE INTO meta (key, value) VALUES (?,?)", (key, value))

    def set_post(self, item_id, chat_id, message_id, thread):
        with self.lock, self.db:
            self.db.execute("INSERT OR REPLACE INTO posts (item, chat, message_id, thread, created_at) VALUES (?,?,?,?,?)",
                            (item_id, str(chat_id), int(message_id), str(thread) if thread is not None else None, dt.datetime.now(dt.timezone.utc).isoformat()))
            self.db.execute("INSERT OR REPLACE INTO msgmap (chat, message_id, item) VALUES (?,?,?)", (str(chat_id), int(message_id), item_id))

    def map_message(self, chat_id, message_id, item_id):
        with self.lock, self.db:
            self.db.execute("INSERT OR REPLACE INTO msgmap (chat, message_id, item) VALUES (?,?,?)", (str(chat_id), int(message_id), item_id))

    def get_post(self, item_id, chat_id):
        with self.lock:
            r = self.db.execute("SELECT * FROM posts WHERE item=? AND chat=?", (item_id, str(chat_id))).fetchone()
        return dict(r) if r else None

    def post_item(self, chat_id, message_id):
        """Item id behind one of the bot's own messages (for reply = comment)."""
        with self.lock:
            r = self.db.execute("SELECT item FROM msgmap WHERE chat=? AND message_id=?", (str(chat_id), int(message_id))).fetchone()
        return r["item"] if r else None

    def item_by_hex(self, hex32):
        h = hex32.strip().lower()
        if len(h) != 32:
            return None
        return self.item(f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}")

    def due_items(self, pids, active_names, today):
        """Active items with a target_date on or before `today` (ISO date string)."""
        return [r for r in self.items_in(pids, active_names) if r.get("target_date") and r["target_date"] <= today]

    def closed_since(self, pids, since_iso):
        rows = [r for r in self.items_in(pids) if (r.get("state_group") == "completed") and (r.get("updated_at") or "") >= since_iso]
        return sorted(rows, key=lambda r: r["updated_at"], reverse=True)

    def is_member(self, pid, email):
        with self.lock:
            r = self.db.execute("SELECT 1 FROM members WHERE project=? AND email=?", (pid, (email or "").lower())).fetchone()
        return bool(r)

    def item(self, item_id):
        with self.lock:
            r = self.db.execute("SELECT project FROM items WHERE id=?", (item_id,)).fetchone()
        if not r:
            return None
        for it in self.items_in([r["project"]]):
            if it["id"] == item_id:
                return it
        return None

    # --- reads
    def project_by_identifier(self, ident):
        with self.lock:
            r = self.db.execute("SELECT * FROM projects WHERE identifier=?", (ident.upper(),)).fetchone()
        return dict(r) if r else None

    def project(self, pid):
        with self.lock:
            r = self.db.execute("SELECT * FROM projects WHERE id=?", (pid,)).fetchone()
        return dict(r) if r else None

    def states_of(self, pid):
        with self.lock:
            return [dict(r) for r in self.db.execute("SELECT * FROM states WHERE project=? ORDER BY sequence", (pid,)).fetchall()]

    def state_by_name(self, pid, name):
        for s in self.states_of(pid):
            if s["name"].lower() == name.lower():
                return s
        return None

    def default_state(self, pid):
        for s in self.states_of(pid):
            if s["is_default"]:
                return s
        return None

    def user_id_by_email(self, email, pids=None):
        """Plane user id for an email, looked up among the members of `pids` only (no id from outside the scope)."""
        q, args = "SELECT user_id FROM members WHERE email=?", [(email or "").lower()]
        if pids is not None:
            if not pids:
                return None
            q += f" AND project IN ({','.join('?' * len(pids))})"
            args += list(pids)
        with self.lock:
            r = self.db.execute(q + " LIMIT 1", args).fetchone()
        return r["user_id"] if r else None

    def member_name(self, user_id):
        with self.lock:
            r = self.db.execute("SELECT display_name, email FROM members WHERE user_id=? LIMIT 1", (user_id,)).fetchone()
        return (r["display_name"] or r["email"]) if r else user_id[:8]

    def member_email(self, user_id):
        with self.lock:
            r = self.db.execute("SELECT email FROM members WHERE user_id=? LIMIT 1", (user_id,)).fetchone()
        return r["email"] if r else ""

    def items_in(self, pids, state_names=None):
        """Live items of the given project ids, enriched with identifier/state name/state group."""
        if not pids:
            return []
        q = ("SELECT i.*, p.identifier AS pident, s.name AS state_name, s.grp AS state_group FROM items i"
             " JOIN projects p ON p.id=i.project LEFT JOIN states s ON s.id=i.state"
             f" WHERE i.deleted=0 AND i.project IN ({','.join('?' * len(pids))})")
        with self.lock:
            rows = [dict(r) for r in self.db.execute(q, list(pids)).fetchall()]
        for r in rows:
            r["assignees"] = json.loads(r["assignees"] or "[]")
            r["identifier"] = f"{r['pident']}-{r['seq']}"
        if state_names is not None:
            wanted = {s.lower() for s in state_names}
            rows = [r for r in rows if (r["state_name"] or "").lower() in wanted]
        return rows

    def item_by_identifier(self, ident):
        m = IDENT_RE.match(ident.strip())
        if not m:
            return None
        p = self.project_by_identifier(m.group(1))
        if not p:
            return None
        for r in self.items_in([p["id"]]):
            if r["seq"] == int(m.group(2)):
                return r
        return None


# ----------------------------------------------------------------------------
# Sync (Plane -> mirror)
# ----------------------------------------------------------------------------
def parse_ts(s):
    if not s:
        return None
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def sync_catalog(plane, mirror, idents):
    """Projects/states/members for the identifiers in scope. Returns {IDENT: project row}."""
    found = {}
    for p in plane.projects():
        ident = (p.get("identifier") or "").upper()
        if ident in idents:
            mirror.upsert_project(p)
            found[ident] = p
    for ident, p in found.items():
        mirror.replace_states(p["id"], plane.states(p["id"]))
        try:
            mirror.replace_members(p["id"], plane.members(p["id"]))
        except PlaneError as e:
            log.warning("members of %s: %s", ident, e)
    missing = sorted(set(idents) - set(found))
    if missing:
        log.warning("projects in config but not visible to the sync token: %s", missing)
    return found


def sync_items(plane, mirror, pid, full=False):
    """Walk -updated_at until the stored cursor; returns [(prev_row_or_None, new_item)] changes.

    `full` walks every page and marks vanished items deleted (deletions never
    show up in an incremental walk)."""
    key = f"cursor:{pid}"
    cursor = None if full else parse_ts(mirror.get_meta(key))
    changes, seen, newest = [], set(), cursor
    for it in plane.work_items(pid):
        ts = parse_ts(it.get("updated_at"))
        if cursor and ts and ts <= cursor:
            break
        seen.add(it["id"])
        prev = mirror.upsert_item(it)
        if prev is None or _differs(prev, it):
            changes.append((prev, it))
        if ts and (newest is None or ts > newest):
            newest = ts
    if full:
        for gone in mirror.mark_missing_deleted(pid, seen):
            changes.append(({"id": gone, "deleted": 1}, None))
    if newest:
        mirror.set_meta(key, newest.isoformat())
    return changes


def _differs(prev, it):
    # updated_at alone counts: a new comment moves it without touching any listed field,
    # and the notifier needs to see those items to fetch their comments.
    return (prev.get("updated_at") != it.get("updated_at")
            or prev.get("state") != it.get("state") or prev.get("priority", "none") != (it.get("priority") or "none")
            or prev.get("name") != it.get("name") or prev.get("target_date") != it.get("target_date")
            or json.loads(prev.get("assignees") or "[]") != sorted(it.get("assignees") or []))


# ----------------------------------------------------------------------------
# Commands: parse -> scope -> query -> render
# ----------------------------------------------------------------------------
class Msg(str):
    """A reply that may carry an inline keyboard and the item it is about (so the
    daemon can register it as that item's card). Plain str for everything else."""

    def __new__(cls, text, keyboard=None, item=None):
        o = super().__new__(cls, text)
        o.keyboard = keyboard
        o.item = item
        return o


def parse_due(word, today):
    """'today' 'tomorrow' 'mon'..'sunday' 'YYYY-MM-DD' 'MM-DD' '+3d' 'none' -> ISO date or None; raises ValueError."""
    w = (word or "").strip().lower()
    if w in ("none", "clear", "-"):
        return None
    if w == "today":
        return today.isoformat()
    if w == "tomorrow":
        return (today + dt.timedelta(days=1)).isoformat()
    days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    for i, d in enumerate(days):
        if w in (d, d[:3]):
            delta = (i - today.weekday()) % 7 or 7
            return (today + dt.timedelta(days=delta)).isoformat()
    m = re.match(r"^\+(\d{1,3})d?$", w)
    if m:
        return (today + dt.timedelta(days=int(m.group(1)))).isoformat()
    m = re.match(r"^(\d{1,2})-(\d{1,2})$", w)
    if m:
        return dt.date(today.year, int(m.group(1)), int(m.group(2))).isoformat()
    return dt.date.fromisoformat(w).isoformat()


class Reply(Exception):
    """A user-facing answer that ends command handling (errors included)."""

    def __init__(self, text):
        super().__init__(text)
        self.text = text


ALL = "all"


class Scope:
    """What a /status may touch. projects = identifiers that are IN THIS CHAT, never anything else."""

    def __init__(self, chat_id, projects, user, mode):
        self.chat_id = chat_id
        self.projects = projects  # [IDENT] subset of cfg.chat_projects(chat_id)
        self.user = user          # User, ALL, or None (summary for everyone)
        self.mode = mode          # "list" | "by_person" | "summary" | "summary_all"


def resolve_status(cfg, chat_id, thread, args, requester_tg):
    """Turn `/status [project|all] [user|all]` into a Scope, or raise Reply.

    Only projects from cfg.chat_projects(chat_id) can ever end up in the Scope."""
    projects = cfg.chat_projects(chat_id)
    if projects is None:
        raise Reply("")  # unknown chat: callers must already have filtered; be silent anyway
    if len(args) > 2:
        raise Reply("Usage: /status [project|all] [user|all]")
    proj_arg = args[0] if args else None
    user_arg = args[1] if len(args) > 1 else None

    # --- project part
    if proj_arg is None:
        here = cfg.project_for_thread(chat_id, thread)
        if here:
            idents, default_mode = [here], "list"
        else:  # General topic: a summary, the full list would be too long
            idents, default_mode = sorted(projects), "summary"
    elif proj_arg.lower() == ALL:
        idents, default_mode = sorted(projects), "list"
    else:
        ident = proj_arg.upper()
        if ident not in projects:
            raise Reply("Unknown project here.")
        idents, default_mode = [ident], "list"

    # --- user part
    if user_arg is None:
        me = cfg.user_by_telegram(requester_tg)
        if not me:
            raise Reply("Not registered: your Telegram id is not mapped to a Plane account. Send /whoami to Diego.")
        user, mode = me, default_mode
    elif user_arg.lower() == ALL:
        user = ALL
        mode = "summary_all" if (proj_arg is None and default_mode == "summary") or (proj_arg and proj_arg.lower() == ALL) else "by_person"
    else:
        u = cfg.user_by_alias(user_arg.lstrip("@"))
        if not u:
            raise Reply(f"Unknown user {esc(user_arg)}. Known: {', '.join(sorted(cfg.users))}.")
        user, mode = u, default_mode
    return Scope(str(chat_id), idents, user, mode)


def _sort_key(cfg, r):
    st = (r.get("state_name") or "")
    lowered = [s.lower() for s in cfg.active_states]
    si = lowered.index(st.lower()) if st.lower() in lowered else len(lowered)
    pi = PRIORITY_ORDER.index(r.get("priority") or "none") if (r.get("priority") or "none") in PRIORITY_ORDER else len(PRIORITY_ORDER)
    return (si, pi, r.get("target_date") or "9999-99-99", r.get("seq") or 0)


def item_url(cfg, r):
    return f"{cfg.public_url}/{cfg.workspace}/browse/{r['identifier']}/"


def fmt_line(cfg, r, with_state=False):
    due = f" · due {r['target_date'][5:]}" if r.get("target_date") else ""
    st = f" · {esc(r.get('state_name') or '?')}" if with_state else ""
    return f"<a href=\"{item_url(cfg, r)}\">{r['identifier']}</a> {PRIORITY_ICON.get(r.get('priority') or 'none', '⚪')} {esc(r['name'])}{st}{due}"


def _mention(cfg, mirror, user_id):
    u = cfg.user_by_email(mirror.member_email(user_id))
    if u and u.telegram_id:
        return f'<a href="tg://user?id={u.telegram_id}">{esc(u.alias)}</a>'
    return esc(person_label(cfg, mirror, user_id))


def person_label(cfg, mirror, user_id):
    u = cfg.user_by_email(mirror.member_email(user_id))
    return u.alias if u else mirror.member_name(user_id)


def render_status(cfg, mirror, scope):
    """One HTML text (may exceed 4000 chars; the sender splits it)."""
    pids = {}
    for ident in scope.projects:
        p = mirror.project_by_identifier(ident)
        if p:
            pids[ident] = p["id"]
    if not pids:
        return "No project data yet (first sync pending)."
    rows = mirror.items_in(list(pids.values()), cfg.active_states)
    by_project = {ident: [r for r in rows if r["project"] == pid] for ident, pid in pids.items()}

    if scope.mode in ("list", "by_person"):
        target_uid = None
        if scope.user not in (ALL, None):
            target_uid = mirror.user_id_by_email(scope.user.email, list(pids.values()))
            if not target_uid:
                where = scope.projects[0] if len(scope.projects) == 1 else "any project here"
                return f"{esc(scope.user.alias)} is not a member of {where}."
        blocks = []
        for ident in scope.projects:
            items = sorted(by_project.get(ident, []), key=lambda r: _sort_key(cfg, r))
            if scope.mode == "list":
                mine = [r for r in items if target_uid in r["assignees"]]
                if not mine:
                    if len(scope.projects) == 1:
                        return f"<b>{ident}</b> · no active tickets for {esc(scope.user.alias)}."
                    continue
                blocks.append(_block(cfg, ident, mine, with_state=True))
            else:  # by_person
                if not items:
                    if len(scope.projects) == 1:
                        return f"<b>{ident}</b> · no active tickets."
                    continue
                groups = {}
                for r in items:
                    keys = r["assignees"] or ["__unassigned__"]
                    for k in keys:
                        groups.setdefault(k, []).append(r)
                lines = [f"<b>{ident}</b>"]
                for k in sorted(groups, key=lambda k: (k == "__unassigned__", person_label(cfg, mirror, k) if k != "__unassigned__" else "")):
                    label = "Unassigned" if k == "__unassigned__" else person_label(cfg, mirror, k)
                    lines.append(f"<u>{esc(label)}</u> ({len(groups[k])})")
                    lines += ["  " + fmt_line(cfg, r, with_state=True) for r in groups[k][:LIST_CAP]]
                    if len(groups[k]) > LIST_CAP:
                        lines.append(f"  +{len(groups[k]) - LIST_CAP} more")
                blocks.append("\n".join(lines))
        if not blocks:
            who = "" if scope.user is ALL else f" for {esc(scope.user.alias)}"
            return f"No active tickets{who} in this group."
        return "\n\n".join(blocks)

    # summaries
    lowered = [s.lower() for s in cfg.active_states]
    if scope.mode == "summary":
        target_uid = mirror.user_id_by_email(scope.user.email, list(pids.values())) if scope.user not in (ALL, None) else None
        lines = [f"<b>Active tickets for {esc(scope.user.alias)}</b>"]
        total = 0
        for ident in scope.projects:
            mine = [r for r in by_project.get(ident, []) if target_uid in r["assignees"]]
            if not mine:
                continue
            total += len(mine)
            counts = {s: sum(1 for r in mine if (r["state_name"] or "").lower() == s) for s in lowered}
            parts = [f"{counts[s]} {cfg.active_states[i].lower()}" for i, s in enumerate(lowered) if counts[s]]
            lines.append(f"<b>{ident}</b> · {len(mine)}: " + " · ".join(parts))
        if total == 0:
            return f"No active tickets for {esc(scope.user.alias)} in this group."
        lines.append(f"<i>{total} total · /status &lt;project&gt; for the list</i>")
        return "\n".join(lines)

    # summary_all: per project, counts per person
    lines = ["<b>Active tickets by project</b>"]
    total = 0
    for ident in scope.projects:
        items = by_project.get(ident, [])
        if not items:
            continue
        total += len(items)
        per = {}
        for r in items:
            for k in (r["assignees"] or ["__unassigned__"]):
                per[k] = per.get(k, 0) + 1
        parts = []
        for k in sorted(per, key=lambda k: (-per[k], k)):
            parts.append(f"{'unassigned' if k == '__unassigned__' else esc(person_label(cfg, mirror, k))} {per[k]}")
        counts = {s: sum(1 for r in items if (r["state_name"] or "").lower() == s) for s in lowered}
        st = " · ".join(f"{counts[s]} {cfg.active_states[i].lower()}" for i, s in enumerate(lowered) if counts[s])
        lines.append(f"<b>{ident}</b> · {len(items)} ({st}) — " + ", ".join(parts))
    if total == 0:
        return "No active tickets in this group."
    return "\n".join(lines)


def _block(cfg, ident, items, with_state):
    lines = [f"<b>{ident}</b> ({len(items)})"]
    lines += [fmt_line(cfg, r, with_state) for r in items[:LIST_CAP]]
    if len(items) > LIST_CAP:
        lines.append(f"+{len(items) - LIST_CAP} more")
    return "\n".join(lines)


def render_show(cfg, mirror, r):
    who = ", ".join(person_label(cfg, mirror, a) for a in r["assignees"]) or "unassigned"
    due = r.get("target_date") or "—"
    return (f"<a href=\"{item_url(cfg, r)}\">{r['identifier']}</a> <b>{esc(r['name'])}</b>\n"
            f"{esc(r.get('state_name') or '?')} · {PRIORITY_ICON.get(r.get('priority') or 'none', '⚪')} {esc(r.get('priority') or 'none')} · {esc(who)} · due {esc(due)}")


HELP = """<b>Plane bot</b> — this group only sees its own projects.
/assign PROJ-12 &lt;alias|me|none&gt; · /prio PROJ-12 &lt;urgent|high|medium|low|none&gt;
/due PROJ-12 &lt;date|today|tomorrow|fri|+3d|none&gt; · /state PROJ-12 &lt;todo|progress|review|done|cancel&gt; · /done PROJ-12
Reply to any bot message about a ticket to add a comment. Buttons under a card change state / assign to you.
/status — this topic's project, my active tickets (in General: summary of every project)
/status &lt;project&gt; [user] — active tickets of a user in a project
/status &lt;project&gt; all — everyone's active tickets, grouped by person
/status all [user] — one user across every project here, grouped by project
/status all all — group summary: counts per project and person
/show PROJ-12 — one ticket
/new [PROJ] title — create a ticket (Todo) as you; or just write "+ title" in a project topic
/whoami — your Telegram id and mapping
Active = """ + ", ".join(DEFAULT_ACTIVE_STATES) + ". Users: aliases like diego, aga, komi."


class Bot:
    """Command dispatch. `plane_for(user)` builds a client with that user's token."""

    def __init__(self, cfg, mirror, plane_factory=None):
        self.cfg = cfg
        self.mirror = mirror
        self.plane_factory = plane_factory or (lambda token: Plane(cfg.plane_url, cfg.workspace, token))
        self.last_created = None

    # --- entry point used by both the Telegram loop and `simulate`
    def handle(self, chat_id, thread, text, from_id, from_username=""):
        """Reply text for a message, or None when the bot must stay silent."""
        projects = self.cfg.chat_projects(chat_id)
        if projects is None:
            log.info("ignored message from unknown chat %s", chat_id)
            return None
        text = (text or "").strip()
        if not text:
            return None
        self.last_created = None
        if text.startswith("/") or text.startswith("+"):
            log.info("cmd chat=%s thread=%s user=%s: %s", chat_id, thread, from_id, text[:80])
        try:
            if text.startswith("/"):
                return self._command(chat_id, thread, text, from_id, from_username)
            if text.startswith("+"):
                return self._capture(chat_id, thread, text[1:].strip(), from_id)
            return None
        except Reply as r:
            return r.text or None
        except PlaneError as e:
            log.warning("plane error: %s", e)
            if e.status in (401, 403):
                return "Plane refused that with your token (no permission)."
            return f"Plane error {e.status}."

    def _command(self, chat_id, thread, text, from_id, from_username):
        parts = text.split()
        cmd = parts[0][1:].split("@")[0].lower()
        args = parts[1:]
        if cmd in ("help", "start"):
            return HELP
        if cmd == "whoami":
            u = self.cfg.user_by_telegram(from_id)
            projects = ", ".join(sorted(self.cfg.chat_projects(chat_id)))
            here = self.cfg.project_for_thread(chat_id, thread) or "General"
            return (f"Telegram id <code>{esc(from_id)}</code>" + (f" (@{esc(from_username)})" if from_username else "")
                    + f"\nMapped to: {esc(u.alias) if u else 'nobody'}"
                    + (f" ({'can act' if u.can_act else 'read-only'})" if u else "")
                    + f"\nThis topic: {esc(here)}\nProjects here: {esc(projects)}")
        if cmd == "status":
            scope = resolve_status(self.cfg, chat_id, thread, args, from_id)
            return render_status(self.cfg, self.mirror, scope)
        if cmd == "show":
            if len(args) != 1:
                raise Reply("Usage: /show PROJ-12")
            return self._show(chat_id, args[0])
        if cmd == "new":
            if not args:
                raise Reply("Usage: /new [PROJ] title")
            return self._new(chat_id, thread, args, from_id)
        if cmd in ("assign", "prio", "due", "state", "done"):
            return self._write(cmd, chat_id, args, from_id)
        return None  # unknown command: silence (other bots may own it)

    # --- write actions -----------------------------------------------------
    def _scoped_item(self, chat_id, ident):
        """The mirror row for PROJ-N, only if PROJ is in this chat's table."""
        projects = self.cfg.chat_projects(chat_id)
        m = IDENT_RE.match((ident or "").strip())
        if not m or m.group(1).upper() not in projects:
            raise Reply("Unknown project here.")
        r = self.mirror.item_by_identifier(ident.upper())
        if not r:
            raise Reply(f"{esc(ident.upper())} not found (or not synced yet).")
        return r

    def _actor(self, from_id):
        u = self.cfg.user_by_telegram(from_id)
        if not u:
            raise Reply("Not registered: send /whoami to Diego.")
        if not u.can_act:
            raise Reply(f"{esc(u.alias)} is read-only here (no Plane token).")
        return u

    def _apply(self, user, row, body, chat_id, what):
        """PATCH with the user's token, refresh the mirror, return the new card."""
        plane = self.plane_factory(user.token)
        updated = plane.update_work_item(row["project"], row["id"], body)
        if not isinstance(updated, dict) or "id" not in updated:
            updated = plane.work_item(row["project"], row["id"])
        updated.setdefault("project", row["project"])
        updated.setdefault("updated_by", self.mirror.user_id_by_email(user.email, [row["project"]]))
        self.mirror.upsert_item(updated)
        fresh = self.mirror.item(row["id"]) or row
        log.info("%s %s in chat %s by %s: %s", what, row["identifier"], chat_id, user.alias, json.dumps(body))
        return self.card_msg(fresh)

    def card_msg(self, row, head=""):
        return Msg(head + render_show(self.cfg, self.mirror, row), keyboard=keyboard_for(row), item=row["id"])

    def _write(self, cmd, chat_id, args, from_id):
        usage = {"assign": "/assign PROJ-12 <alias|me|none>", "prio": "/prio PROJ-12 <urgent|high|medium|low|none>",
                 "due": "/due PROJ-12 <YYYY-MM-DD|today|tomorrow|fri|+3d|none>", "state": "/state PROJ-12 <todo|progress|review|done|cancel>",
                 "done": "/done PROJ-12"}
        need = 1 if cmd == "done" else 2
        if len(args) != need:
            raise Reply("Usage: " + usage[cmd])
        row = self._scoped_item(chat_id, args[0])
        user = self._actor(from_id)
        if cmd == "assign":
            who = args[1].lstrip("@").lower()
            if who == "none":
                return self._apply(user, row, {"assignees": []}, chat_id, "assign")
            target = user if who == "me" else self.cfg.user_by_alias(who)
            if not target:
                raise Reply(f"Unknown user {esc(args[1])}. Known: {', '.join(sorted(self.cfg.users))}.")
            uid = self.mirror.user_id_by_email(target.email, [row["project"]])
            if not uid:
                raise Reply(f"{esc(target.alias)} is not a member of {row['pident']}.")
            return self._apply(user, row, {"assignees": sorted(set(row["assignees"]) | {uid})}, chat_id, "assign")
        if cmd == "prio":
            pr = args[1].lower()
            if pr not in PRIORITY_ORDER:
                raise Reply("Usage: " + usage[cmd])
            return self._apply(user, row, {"priority": pr}, chat_id, "prio")
        if cmd == "due":
            try:
                date = parse_due(args[1], dt.datetime.now(self.cfg.tz).date())
            except ValueError:
                raise Reply("Usage: " + usage[cmd])
            return self._apply(user, row, {"target_date": date}, chat_id, "due")
        # state / done
        want = "done" if cmd == "done" else args[1].lower()
        names = {"todo": "Todo", "progress": "In Progress", "inprogress": "In Progress", "review": "In Review",
                 "done": "Done", "cancel": "Cancelled", "cancelled": "Cancelled", "backlog": "Backlog"}
        if want not in names:
            raise Reply("Usage: " + usage["state"])
        st = self.mirror.state_by_name(row["project"], names[want])
        if not st:
            raise Reply(f"{row['pident']} has no state named {names[want]}.")
        return self._apply(user, row, {"state": st["id"]}, chat_id, "state")

    # --- inline buttons ------------------------------------------------------
    def callback(self, chat_id, from_id, data):
        """Returns (toast, Msg|None). Scope: the item's project must be in this chat's table."""
        if self.cfg.chat_projects(chat_id) is None:
            return None, None
        try:
            _, action, hexid = (data or "").split(":")
        except ValueError:
            return "?", None
        row = self.mirror.item_by_hex(hexid)
        if not row or row["pident"] not in self.cfg.chat_projects(chat_id):
            return "Not available here", None
        try:
            user = self._actor(from_id)
            if action == "m":
                uid = self.mirror.user_id_by_email(user.email, [row["project"]])
                if not uid:
                    return f"{user.alias} is not a member of {row['pident']}", None
                if uid in row["assignees"]:
                    return "Already yours", None
                return "Assigned to you", self._apply(user, row, {"assignees": sorted(set(row["assignees"]) | {uid})}, chat_id, "assign")
            name = {"t": "Todo", "p": "In Progress", "d": "Done"}.get(action)
            if not name:
                return "?", None
            st = self.mirror.state_by_name(row["project"], name)
            if not st:
                return f"No {name} state in {row['pident']}", None
            if row.get("state") == st["id"]:
                return f"Already {name}", None
            return name, self._apply(user, row, {"state": st["id"]}, chat_id, "state")
        except Reply as r:
            return r.text, None
        except PlaneError as e:
            log.warning("callback plane error: %s", e)
            return "Plane refused (no permission)" if e.status in (401, 403) else f"Plane error {e.status}", None

    # --- reply to a bot message = comment ----------------------------------------
    def reply_comment(self, chat_id, from_id, replied_message_id, text):
        item_id = self.mirror.post_item(chat_id, replied_message_id)
        if not item_id or not (text or "").strip() or text.lstrip().startswith("/"):
            return None
        row = self.mirror.item(item_id)
        if not row or row["pident"] not in (self.cfg.chat_projects(chat_id) or {}):
            return None
        try:
            user = self._actor(from_id)
            self.plane_factory(user.token).add_comment(row["project"], row["id"], f"<p>{esc(text.strip())}</p>")
        except Reply as r:
            return r.text
        except PlaneError as e:
            return "Plane refused (no permission)" if e.status in (401, 403) else f"Plane error {e.status}"
        # the comment bumps updated_at: pull it into the mirror now so the sync does not echo it back
        try:
            fresh = self.plane_factory(user.token).work_item(row["project"], row["id"])
            fresh.setdefault("project", row["project"])
            self.mirror.upsert_item(fresh)
        except Exception as e:
            log.warning("refresh after comment: %s", e)
        log.info("comment on %s in chat %s by %s", row["identifier"], chat_id, user.alias)
        return f"💬 added to {row['identifier']}"

    # --- scheduled reports --------------------------------------------------------
    def due_report(self, chat_id, today):
        """[(thread, text)] per project topic: active items due today or overdue."""
        out = []
        for ident, thread in sorted((self.cfg.chat_projects(chat_id) or {}).items()):
            p = self.mirror.project_by_identifier(ident)
            if not p:
                continue
            rows = sorted(self.mirror.due_items([p["id"]], self.cfg.active_states, today.isoformat()), key=lambda r: (r["target_date"], _sort_key(self.cfg, r)))
            if not rows:
                continue
            lines = [f"📅 <b>{ident}</b> · due today or overdue ({len(rows)})"]
            for r in rows[:LIST_CAP]:
                who = " ".join(_mention(self.cfg, self.mirror, a) for a in r["assignees"])
                tag = "today" if r["target_date"] == today.isoformat() else f"overdue {r['target_date'][5:]}"
                lines.append(f"{fmt_line(self.cfg, r)} · <i>{tag}</i>" + (f" {who}" if who else ""))
            out.append((thread, "\n".join(lines)))
        return out

    def weekly_digest(self, chat_id, now):
        projects = sorted((self.cfg.chat_projects(chat_id) or {}).keys())
        pids = {i: self.mirror.project_by_identifier(i)["id"] for i in projects if self.mirror.project_by_identifier(i)}
        since = (now - dt.timedelta(days=7)).isoformat()
        closed = self.mirror.closed_since(list(pids.values()), since)
        scope = Scope(str(chat_id), sorted(pids), ALL, "summary_all")
        head = f"📋 <b>Weekly</b> · {now.date().isoformat()}\n✅ closed this week: {len(closed)}"
        if closed:
            head += "\n" + "\n".join("  " + fmt_line(self.cfg, r) for r in closed[:LIST_CAP])
            if len(closed) > LIST_CAP:
                head += f"\n  +{len(closed) - LIST_CAP} more"
        return head + "\n\n" + render_status(self.cfg, self.mirror, scope)

    def _show(self, chat_id, ident):
        projects = self.cfg.chat_projects(chat_id)
        m = IDENT_RE.match(ident.strip())
        if not m or m.group(1).upper() not in projects:
            raise Reply("Unknown project here.")
        r = self.mirror.item_by_identifier(ident.upper())
        if not r:
            raise Reply(f"{esc(ident.upper())} not found (or not synced yet).")
        return self.card_msg(r)

    def _new(self, chat_id, thread, args, from_id):
        projects = self.cfg.chat_projects(chat_id)
        ident = None
        if args and args[0].upper() in projects:
            ident, args = args[0].upper(), args[1:]
        elif args and args[0].upper().rstrip(":") in projects:
            ident, args = args[0].upper().rstrip(":"), args[1:]
        if not ident:
            ident = self.cfg.project_for_thread(chat_id, thread)
        if not ident:
            raise Reply("Which project? Use /new PROJ title, or write in a project topic.")
        title = " ".join(args).strip()
        if not title:
            raise Reply("Usage: /new [PROJ] title")
        return self._create(chat_id, ident, title, from_id)

    def _capture(self, chat_id, thread, title, from_id):
        ident = self.cfg.project_for_thread(chat_id, thread)
        if not ident or not title:
            return None  # "+" outside a project topic is just text
        return self._create(chat_id, ident, title, from_id)

    def _create(self, chat_id, ident, title, from_id):
        u = self.cfg.user_by_telegram(from_id)
        if not u:
            raise Reply("Not registered: send /whoami to Diego.")
        if not u.can_act:
            raise Reply(f"{esc(u.alias)} is read-only here (no Plane token).")
        p = self.mirror.project_by_identifier(ident)
        if not p:
            raise Reply(f"{ident} is not synced yet, try again in a minute.")
        state = self.mirror.state_by_name(p["id"], "Todo") or self.mirror.default_state(p["id"])
        body = {"name": title[:255]}
        if state:
            body["state"] = state["id"]
        created = self.plane_factory(u.token).create_work_item(p["id"], body)
        created.setdefault("project", p["id"])
        created.setdefault("created_by", self.mirror.user_id_by_email(u.email, [p["id"]]))
        self.mirror.upsert_item(created)
        self.last_created = created["id"]  # the daemon registers its reply as this item's card
        log.info("created %s-%s in chat %s by %s", ident, created.get("sequence_id"), chat_id, u.alias)
        r = self.mirror.item_by_identifier(f"{ident}-{created.get('sequence_id')}")
        if not r:
            return f"✅ Created {ident}-{created.get('sequence_id')}"
        return self.card_msg(r, head="✅ ")


# ----------------------------------------------------------------------------
# Daemon
# ----------------------------------------------------------------------------
class Daemon:
    def __init__(self, cfg):
        self.cfg = cfg
        os.makedirs(cfg.state_dir, exist_ok=True)
        self.mirror = Mirror(os.path.join(cfg.state_dir, "mirror.sqlite"))
        self.bot = Bot(cfg, self.mirror)
        self.tg = Telegram(os.environ.get("TELEGRAM_BOT_TOKEN", ""))
        self.catalog = {}
        self.notifier = None
        self.bot_id = None
        self.silent_full_pending = self.mirror.migrated  # schema grew: refill quietly

    def sync_once(self, full=False, notify=True):
        plane = Plane(self.cfg.plane_url, self.cfg.workspace, self.cfg.sync_user().token)
        if self.notifier is None:
            self.notifier = Notifier(self.cfg, self.mirror, self.tg, plane)
        if full or not self.catalog:
            self.catalog = sync_catalog(plane, self.mirror, set(self.cfg.all_project_idents()))
        n = 0
        for ident, p in self.catalog.items():
            first = self.mirror.get_meta(f"cursor:{p['id']}") is None  # never synced: everything is "new", say nothing
            try:
                changes = sync_items(plane, self.mirror, p["id"], full=full)
            except PlaneError as e:
                log.warning("sync %s: %s", ident, e)
                continue
            n += len(changes)
            if changes and notify and not first and self.tg.token:
                try:
                    sent = self.notifier.process(changes)
                    if sent:
                        log.info("notify %s: %d message(s)", ident, sent)
                except Exception as e:
                    log.exception("notify %s failed: %s", ident, e)
        return n

    def run_sync(self):
        last_full = 0
        while True:
            try:
                full = time.time() - last_full > self.cfg.full_sync_minutes * 60
                if self.silent_full_pending:
                    n = self.sync_once(full=True, notify=False)
                    self.silent_full_pending = False
                    full = True
                else:
                    n = self.sync_once(full=full)
                if full:
                    last_full = time.time()
                if n:
                    log.info("sync: %d change(s)%s", n, " (full)" if full else "")
            except Exception as e:
                log.warning("sync failed: %s", e)
            time.sleep(self.cfg.poll_seconds)

    def on_message(self, m):
        chat_id = str(m.get("chat", {}).get("id"))
        if self.cfg.chat_projects(chat_id) is None:
            return
        thread = m.get("message_thread_id") if m.get("is_topic_message") else None
        frm = m.get("from", {})
        text = m.get("text") or ""
        rt = m.get("reply_to_message") or {}
        # a reply to one of OUR messages about a ticket = comment (unless it is a command)
        if rt and str(rt.get("from", {}).get("id")) == str(self.bot_id) and not text.lstrip().startswith("/") and not text.lstrip().startswith("+"):
            ans = self.bot.reply_comment(chat_id, frm.get("id"), rt.get("message_id"), text)
            if ans:
                self.tg.send(chat_id, ans, thread, reply_to=m.get("message_id"))
            return
        reply = self.bot.handle(chat_id, thread, text, frm.get("id"), frm.get("username", ""))
        if reply:
            self.send_reply(chat_id, thread, reply, m.get("message_id"))

    def send_reply(self, chat_id, thread, reply, reply_to):
        kb = getattr(reply, "keyboard", None)
        item = getattr(reply, "item", None)
        if kb:
            sent = [self.tg.send(chat_id, str(reply), thread, reply_to=reply_to, reply_markup=kb)]
        else:
            sent = self.tg.send_long(chat_id, str(reply), thread, reply_to=reply_to)
        if item and sent:
            self.mirror.map_message(chat_id, sent[0]["message_id"], item)
            if not self.mirror.get_post(item, chat_id):  # first card of this item here
                self.mirror.set_post(item, chat_id, sent[0]["message_id"], thread)

    def on_callback(self, cq):
        msg = cq.get("message") or {}
        chat_id = str(msg.get("chat", {}).get("id"))
        if self.cfg.chat_projects(chat_id) is None:
            return
        toast, card = self.bot.callback(chat_id, cq.get("from", {}).get("id"), cq.get("data", ""))
        try:
            self.tg.answer_callback(cq.get("id"), toast)
        except Exception as e:
            log.warning("answerCallbackQuery: %s", e)
        if card:
            try:
                self.tg.edit(chat_id, msg.get("message_id"), str(card), reply_markup=card.keyboard)
            except Exception as e:
                log.warning("edit after callback: %s", e)

    def run_scheduler(self):
        """08:00 due-today per project topic; Sunday 18:00 weekly digest in General. Once per day, via meta."""
        while True:
            now = dt.datetime.now(self.cfg.tz)
            today = now.date().isoformat()
            try:
                if now.hour == 8 and self.mirror.get_meta(f"due:{today}") is None:
                    for chat_id in self.cfg.chats:
                        for thread, text in self.bot.due_report(chat_id, now.date()):
                            self.tg.send(chat_id, text, thread)
                    self.mirror.set_meta(f"due:{today}", "1")
                    log.info("due report sent")
                if now.weekday() == 6 and now.hour == 18 and self.mirror.get_meta(f"weekly:{today}") is None:
                    for chat_id in self.cfg.chats:
                        self.tg.send_long(chat_id, self.bot.weekly_digest(chat_id, now), None)
                    self.mirror.set_meta(f"weekly:{today}", "1")
                    log.info("weekly digest sent")
            except Exception as e:
                log.warning("scheduler: %s", e)
            time.sleep(60)

    def run(self):
        if not self.tg.token:
            log.error("TELEGRAM_BOT_TOKEN missing")
            sys.exit(1)
        try:
            self.bot_id = self.tg.me().get("id")
            self.tg.set_commands([
                ("status", "Active tickets: /status [project|all] [user|all]"),
                ("show", "One ticket: /show PROJ-12"),
                ("new", "Create a ticket: /new [PROJ] title"),
                ("assign", "/assign PROJ-12 <alias|me|none>"),
                ("prio", "/prio PROJ-12 <urgent|high|medium|low|none>"),
                ("due", "/due PROJ-12 <date|today|tomorrow|fri|+3d|none>"),
                ("state", "/state PROJ-12 <todo|progress|review|done|cancel>"),
                ("done", "/done PROJ-12"),
                ("whoami", "Your Telegram id and mapping"),
                ("help", "What this bot does"),
            ])
        except Exception as e:
            log.warning("getMe/setMyCommands failed: %s", e)
        threading.Thread(target=self.run_sync, name="sync", daemon=True).start()
        threading.Thread(target=self.run_scheduler, name="scheduler", daemon=True).start()
        self.tg.poll(os.path.join(self.cfg.state_dir, "offset"), self.on_message, self.on_callback)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stdout)
    cfg = Config.from_env()
    if argv and argv[0] == "sync":
        d = Daemon(cfg)
        n = d.sync_once(full="--full" in argv, notify="--notify" in argv)
        print(f"synced, {n} change(s)")
        return
    if argv and argv[0] == "simulate":
        chat = thread = user = None
        text = []
        it = iter(argv[1:])
        for a in it:
            if a == "--chat":
                chat = next(it)
            elif a == "--thread":
                thread = next(it)
            elif a == "--user":
                user = next(it)
            else:
                text.append(a)
        d = Daemon(cfg)
        joined = " ".join(text)
        if joined == "@due":
            for th, t in d.bot.due_report(chat, dt.datetime.now(cfg.tz).date()):
                print(f"[topic {th}]\n{t}\n")
            return
        if joined == "@weekly":
            print(d.bot.weekly_digest(chat, dt.datetime.now(cfg.tz)))
            return
        if joined.startswith("a:"):
            print(d.bot.callback(chat, user, joined))
            return
        reply = d.bot.handle(chat, thread, joined, user)
        print(reply if reply is not None else "<silence>")
        return
    Daemon(cfg).run()


if __name__ == "__main__":
    main()
