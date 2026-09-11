"""Notifications for the Plane bot: mirror diffs -> Telegram messages, scoped per chat.

Events (from `sync_items` (previous_row, new_item) pairs):
  created      new item                      -> card in the project's topic
  assigned     assignees gained a person     -> message mentioning them (new message: must ring)
  closed       state group -> completed/cancelled -> edit the card in place (silent) or a short line
  changed      state/priority/due changed    -> edit the card if there is one, otherwise nothing
  comment      new comment on a changed item -> quoted comment, replying to the card

Audience of a chat for a project = configured users WITH a Telegram id who are
members of that project. Echo rule: nothing is posted when the only person
who would hear it is the actor — except items with external_source=n8n, which
always post (n8n creates them with Diego's token).

Scope: a project's events go to the chats whose table contains that project,
and nowhere else. `chats_for(ident)` is the only lookup used.
"""
import html
import logging
import re

from tgcommon import esc

log = logging.getLogger("plane-bot.notify")

PRIORITY_ICON = {"urgent": "🔥", "high": "🔴", "medium": "🟠", "low": "🟢", "none": "⚪"}
COMMENT_MAX = 300
TAG_RE = re.compile(r"<[^>]+>")


def strip_html(s):
    return html.unescape(TAG_RE.sub("", s or "")).strip()


class Notifier:
    def __init__(self, cfg, mirror, tg, plane):
        self.cfg = cfg
        self.mirror = mirror
        self.tg = tg
        self.plane = plane  # sync-user client, for fetching comments

    # ------------------------------------------------------------------ scope
    def chats_for(self, ident):
        """[(chat_id, thread)] whose table contains the project identifier."""
        out = []
        for chat_id, table in self.cfg.chats.items():
            if ident in table:
                out.append((chat_id, table[ident]))
        return out

    def audience(self, pid, actor_uid, is_n8n):
        """Aliases who would hear about this in any chat (before per-chat delivery)."""
        actor_email = self.mirror.member_email(actor_uid) if actor_uid else ""
        people = [u for u in self.cfg.users.values() if u.telegram_id and self.mirror.is_member(pid, u.email)]
        if is_n8n:
            return people
        return [u for u in people if u.email != actor_email]

    # ---------------------------------------------------------------- helpers
    def label(self, uid):
        u = self.cfg.user_by_email(self.mirror.member_email(uid)) if uid else None
        return u.alias if u else (self.mirror.member_name(uid) if uid else "someone")

    def mention(self, uid):
        u = self.cfg.user_by_email(self.mirror.member_email(uid))
        if u and u.telegram_id:
            return f'<a href="tg://user?id={u.telegram_id}">{esc(u.alias)}</a>'
        return esc(self.label(uid))

    def url(self, r):
        return f"{self.cfg.public_url}/{self.cfg.workspace}/browse/{r['identifier']}/"

    def link(self, r):
        return f'<a href="{self.url(r)}">{r["identifier"]}</a>'

    def card(self, r, head="", by=None):
        who = ", ".join(self.label(a) for a in r["assignees"]) or "unassigned"
        due = r.get("target_date") or "—"
        tail = f" <i>(by {esc(self.label(by))})</i>" if by else ""
        return (f"{head}{self.link(r)} <b>{esc(r['name'])}</b>{tail}\n"
                f"{esc(r.get('state_name') or '?')} · {PRIORITY_ICON.get(r.get('priority') or 'none', '⚪')} "
                f"{esc(r.get('priority') or 'none')} · {esc(who)} · due {esc(due)}")

    # ----------------------------------------------------------------- events
    def classify(self, prev, new):
        """Event names for one diff."""
        if new is None:
            return ["deleted"]
        if prev is None:
            return ["created"]
        ev = []
        old_a = set(prev.get("assignees") or [])
        new_a = set(new.get("assignees") or [])
        if new_a - old_a:
            ev.append("assigned")
        if prev.get("state") != new.get("state"):
            ev.append("closed" if new.get("state_group") in ("completed", "cancelled") else "changed")
        elif prev.get("priority") != new.get("priority") or prev.get("target_date") != new.get("target_date") or prev.get("name") != new.get("name"):
            ev.append("changed")
        if not ev:
            ev.append("touched")  # updated_at moved for something we don't show (e.g. a comment)
        return ev

    def new_comments(self, prev, row):
        """Comments created after the previous mirror row's updated_at."""
        if prev is None or not prev.get("updated_at"):
            return []
        try:
            comments = self.plane.comments(row["project"], row["id"])
        except Exception as e:  # never let a comment fetch break the sync
            log.warning("comments %s: %s", row["identifier"], e)
            return []
        since = prev["updated_at"]
        return sorted([c for c in comments if (c.get("created_at") or "") > since and not c.get("deleted_at")], key=lambda c: c["created_at"])

    def process(self, changes):
        """changes: [(prev_row_or_None, new_api_item_or_None)] from one sync pass of one project."""
        sent = 0
        for prev, new in changes:
            if new is None:
                continue  # deletions: silent for now
            row = self.mirror.item(new["id"])
            if not row:
                continue
            if prev is not None:
                prev = dict(prev)
                prev["assignees"] = _aslist(prev.get("assignees"))
            events = self.classify(prev, row)
            is_n8n = (row.get("external_source") or "") == "n8n"
            actor = row.get("created_by") if events == ["created"] else row.get("updated_by")
            comments = self.new_comments(prev, row) if prev is not None else []
            for chat_id, thread in self.chats_for(row["pident"]):
                sent += self.deliver(chat_id, thread, row, prev, events, actor, is_n8n, comments)
        return sent

    def deliver(self, chat_id, thread, row, prev, events, actor, is_n8n, comments):
        pid = row["project"]
        post = self.mirror.get_post(row["id"], chat_id)
        n = 0
        hearers = self.audience(pid, actor, is_n8n)

        if "created" in events:
            if post:  # announced already (the bot's own /new reply is the card)
                return 0
            if hearers:
                n += self._send_card(chat_id, thread, row, head="🆕 ", by=actor)
            return n

        if "assigned" in events:
            gained = set(row["assignees"]) - set(prev.get("assignees") or [])
            for uid in gained:
                u = self.cfg.user_by_email(self.mirror.member_email(uid))
                if not u or not u.telegram_id:
                    continue  # nobody to ring
                if not is_n8n and self.mirror.member_email(actor) == u.email:
                    continue  # assigned themselves
                text = f"👤 {self.mention(uid)}, you were assigned {self.link(row)} <b>{esc(row['name'])}</b> <i>(by {esc(self.label(actor))})</i>"
                m = self.tg.send(chat_id, text, thread, reply_to=post["message_id"] if post else None)
                n += 1
                if not post and m:
                    self.mirror.set_post(row["id"], chat_id, m["message_id"], thread)
                    post = self.mirror.get_post(row["id"], chat_id)

        if "closed" in events and hearers:
            head = "✅ " if row.get("state_group") == "completed" else "🚫 "
            if post:
                self._edit_card(chat_id, post, row, head=head, by=actor)
            else:
                n += self._send_card(chat_id, thread, row, head=head, by=actor)
        elif "changed" in events and post and hearers:
            self._edit_card(chat_id, post, row, by=actor)

        for c in comments:
            c_actor = c.get("actor") or c.get("created_by")
            if not self.audience(pid, c_actor, False):
                continue
            body = strip_html(c.get("comment_html"))
            if len(body) > COMMENT_MAX:
                body = body[:COMMENT_MAX - 1] + "…"
            text = f"💬 <b>{esc(self.label(c_actor))}</b> on {self.link(row)} {esc(row['name'])}:\n<i>{esc(body)}</i>"
            self.tg.send(chat_id, text, thread, reply_to=post["message_id"] if post else None)
            n += 1
        return n

    def _send_card(self, chat_id, thread, row, head="", by=None):
        m = self.tg.send(chat_id, self.card(row, head, by), thread)
        if m:
            self.mirror.set_post(row["id"], chat_id, m["message_id"], thread)
        return 1

    def _edit_card(self, chat_id, post, row, head="", by=None):
        try:
            self.tg.edit(chat_id, post["message_id"], self.card(row, head, by))
        except Exception as e:  # message too old / deleted: fall back to a new card next time
            log.warning("edit card %s in %s failed: %s", row["identifier"], chat_id, e)


def _aslist(v):
    if isinstance(v, list):
        return v
    try:
        import json
        return json.loads(v or "[]")
    except Exception:
        return []
