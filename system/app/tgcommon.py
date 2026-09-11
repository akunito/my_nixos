"""Telegram Bot API helpers shared by the dotfiles bots (plane-bot, infra-bot).

stdlib only. A bot builds one `Telegram(token)` and uses:
  tg.call(method, **params)                  raw Bot API call, raises on ok=false
  tg.send(chat_id, text, thread=, reply_to=, reply_markup=)   HTML message
  tg.edit(chat_id, message_id, text, reply_markup=)
  tg.answer_callback(callback_query_id, text=)
  tg.poll(offset_file, on_message, on_callback)   long-poll loop, never returns
  esc(text)                                   HTML-escape for message bodies
  split_message(text)                         chunks under Telegram's 4096 limit
  Pending(ttl)                                nonce'd confirmations with expiry

`poll` persists the update offset so a restart never replays an update, and
treats HTTP 409 (another getUpdates consumer on the same token) as "wait",
because only ONE poller per bot token is allowed.
"""
import html
import json
import logging
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

TELEGRAM_API = "https://api.telegram.org"
MAX_TEXT = 4000  # Telegram hard limit is 4096; leave room for HTML slack

log = logging.getLogger("tgcommon")


def esc(s):
    return html.escape(str(s), quote=False)


def split_message(text, limit=MAX_TEXT):
    """Split on line boundaries so no chunk exceeds `limit` characters."""
    if len(text) <= limit:
        return [text]
    chunks, cur = [], ""
    for line in text.split("\n"):
        while len(line) > limit:  # a single monster line: hard cut
            chunks.append(line[:limit])
            line = line[limit:]
        if cur and len(cur) + 1 + len(line) > limit:
            chunks.append(cur)
            cur = line
        else:
            cur = line if not cur else cur + "\n" + line
    if cur:
        chunks.append(cur)
    return chunks


class Telegram:
    def __init__(self, token, api=TELEGRAM_API):
        self.token = token
        self.api = api
        self.username = ""

    def call(self, method, timeout=20, **params):
        data = urllib.parse.urlencode({k: v for k, v in params.items() if v not in ("", None)}).encode()
        req = urllib.request.Request(f"{self.api}/bot{self.token}/{method}", data=data)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = json.load(r)
        if not body.get("ok"):
            raise RuntimeError(f"telegram {method}: {body}")
        return body["result"]

    def send(self, chat_id, text, thread=None, reply_to=None, reply_markup=None):
        return self.call(
            "sendMessage",
            chat_id=chat_id,
            message_thread_id=thread,
            reply_to_message_id=reply_to,
            parse_mode="HTML",
            disable_web_page_preview="true",
            reply_markup=json.dumps(reply_markup) if reply_markup else None,
            text=text[:MAX_TEXT],
        )

    def send_long(self, chat_id, text, thread=None, reply_to=None):
        """Several messages when the text exceeds the limit; only the first replies."""
        out = []
        for i, chunk in enumerate(split_message(text)):
            out.append(self.send(chat_id, chunk, thread, reply_to if i == 0 else None))
        return out

    def edit(self, chat_id, message_id, text, reply_markup=None):
        return self.call(
            "editMessageText",
            chat_id=chat_id,
            message_id=message_id,
            parse_mode="HTML",
            disable_web_page_preview="true",
            reply_markup=json.dumps(reply_markup) if reply_markup else None,
            text=text[:MAX_TEXT],
        )

    def answer_callback(self, callback_query_id, text=None):
        return self.call("answerCallbackQuery", callback_query_id=callback_query_id, text=text)

    def set_commands(self, commands):
        """commands = [(name, description), ...]"""
        return self.call("setMyCommands", commands=json.dumps([{"command": c, "description": d} for c, d in commands]))

    def me(self):
        me = self.call("getMe")
        self.username = me.get("username", "")
        return me

    def poll(self, offset_file, on_message, on_callback=None, allowed_updates=("message", "callback_query")):
        try:
            offset = int(open(offset_file).read().strip())
        except (OSError, ValueError):
            offset = 0
        while True:
            try:
                qs = urllib.parse.urlencode({"timeout": 50, "offset": offset, "allowed_updates": json.dumps(list(allowed_updates))})
                with urllib.request.urlopen(f"{self.api}/bot{self.token}/getUpdates?{qs}", timeout=70) as r:
                    updates = json.load(r).get("result", [])
            except urllib.error.HTTPError as e:
                log.warning("getUpdates HTTP %s", e.code)
                time.sleep(30 if e.code == 409 else 10)
                continue
            except Exception as e:
                log.warning("getUpdates failed: %s", e)
                time.sleep(10)
                continue
            for u in updates:
                offset = u["update_id"] + 1
                try:
                    if u.get("callback_query") and on_callback:
                        on_callback(u["callback_query"])
                    elif u.get("message"):
                        on_message(u["message"])
                except Exception as e:  # one bad update must not kill the loop
                    log.exception("update %s failed: %s", u.get("update_id"), e)
            try:
                with open(offset_file, "w") as fh:
                    fh.write(str(offset))
            except OSError as e:
                log.warning("offset not saved: %s", e)


class Pending:
    """Nonce -> payload store for inline-button confirmations, with a TTL."""

    def __init__(self, ttl=120):
        self.ttl = ttl
        self.items = {}

    def add(self, payload):
        nonce = uuid.uuid4().hex[:10]
        self.items[nonce] = (time.time(), payload)
        return nonce

    def pop(self, nonce):
        """The payload, or None when unknown or expired (expired ones are dropped)."""
        got = self.items.pop(nonce, None)
        if not got:
            return None
        created, payload = got
        if time.time() - created > self.ttl:
            return None
        return payload

    def sweep(self):
        now = time.time()
        for k in [k for k, (t, _) in self.items.items() if now - t > self.ttl]:
            self.items.pop(k, None)
