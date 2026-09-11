"""Plane webhook receiver for the Plane bot (F3): instant events, the poller stays as reconciliation.

Plane POSTs {"event", "action", "data", "activity", ...} with X-Plane-Signature =
HMAC-SHA256(secret, body) in hex. We accept only `issue` and `issue_comment`
events, normalise the expanded payload (state/assignees may be objects) into
the same shape the REST list returns, upsert the mirror and hand the
(previous, new) pair to the Notifier — the exact path the poller uses, so the
chat scope and the echo rule are the same code. Comments are notified straight
from the payload and remembered in `seen_comments`, so the poller's later
comment fetch does not repeat them.

Plane reaches us at http://host.docker.internal:<port>/plane from the rootless
container (10.0.2.2 -> host loopback), which its SSRF guard only allows once
WEBHOOK_ALLOWED_HOSTS=host.docker.internal is set in plane-aio's environment.
Plane deactivates a webhook after 5 failed deliveries: always answer 200 once
the signature is valid, even for events we ignore.
"""
import hashlib
import hmac
import json
import logging
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

log = logging.getLogger("plane-bot.webhook")


def verify(secret, body, signature):
    if not secret:
        return False
    expected = hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, (signature or "").strip())


def _id(v):
    """UUID string from a UUID string or an expanded {id: ...} object."""
    if isinstance(v, dict):
        return v.get("id")
    return v


def normalise_issue(data):
    """Webhook `issue` data -> the dict shape Mirror.upsert_item expects."""
    if not isinstance(data, dict) or not data.get("id"):
        return None
    out = dict(data)
    out["state"] = _id(data.get("state"))
    out["project"] = _id(data.get("project") or data.get("project_id"))
    out["assignees"] = [_id(a) for a in (data.get("assignees") or []) if _id(a)]
    out["created_by"] = _id(data.get("created_by"))
    out["updated_by"] = _id(data.get("updated_by"))
    return out


class WebhookReceiver:
    def __init__(self, cfg, mirror, notifier, secret, debug_dir=None):
        self.cfg = cfg
        self.mirror = mirror
        self.notifier = notifier
        self.secret = secret
        self.debug_dir = debug_dir
        self.lock = threading.Lock()

    # ------------------------------------------------------------- handling
    def handle(self, body, signature):
        """(http status, info). Pure: no HTTP here, so tests can drive it."""
        if not verify(self.secret, body, signature):
            return 401, "bad signature"
        try:
            payload = json.loads(body)
        except ValueError:
            return 400, "bad json"
        self._debug_dump(payload)
        event, action = payload.get("event"), payload.get("action")
        data = payload.get("data") or {}
        activity = payload.get("activity") or {}
        try:
            with self.lock:
                if event == "issue":
                    return 200, self._issue(action, data, activity)
                if event == "issue_comment":
                    return 200, self._comment(action, data, activity)
        except Exception as e:  # a bad event must not make Plane retry and deactivate us
            log.exception("webhook %s/%s failed: %s", event, action, e)
            return 200, "error logged"
        return 200, f"ignored {event}/{action}"

    def _issue(self, action, data, activity):
        # Plane sends the participle from its activity log ("created"/"updated"/"deleted"),
        # webhook_send_task's HTTP-method mapping would give "create"/"update"/"delete": accept both.
        if action in ("delete", "deleted"):
            return "delete ignored"
        item = normalise_issue(data)
        if not item or not item.get("project"):
            return "no item"
        project = self.mirror.project(item["project"])
        if not project:
            return "project out of scope"
        actor = _id((activity or {}).get("actor"))
        if actor:
            item["updated_by"] = actor
            if action in ("create", "created"):
                item["created_by"] = item.get("created_by") or actor
        prev = self.mirror.upsert_item(item)
        if prev is not None and prev.get("updated_at") == _canon(item.get("updated_at")) and _same(prev, item):
            return "already mirrored"  # the poller (or a bot command) got here first
        sent = self.notifier.process([(prev, item)])
        return f"issue {action}: {sent} message(s)"

    def _comment(self, action, data, activity):
        if action not in ("create", "created") or not isinstance(data, dict):
            return f"comment {action} ignored"
        cid = data.get("id")
        issue_id = _id(data.get("issue") or data.get("issue_id"))
        if not cid or not issue_id:
            return "comment without ids"
        if self.mirror.comment_seen(cid):
            return "comment already seen"
        row = self.mirror.item(issue_id)
        if not row:
            return "comment on item out of scope"
        comment = dict(data)  # deliver_comments marks it seen
        comment["actor"] = _id(data.get("actor") or (activity or {}).get("actor") or data.get("created_by"))
        sent = self.notifier.deliver_comments(row, [comment])
        return f"comment: {sent} message(s)"

    def _debug_dump(self, payload):
        if not self.debug_dir:
            return
        try:
            import os
            import time
            os.makedirs(self.debug_dir, exist_ok=True)
            name = f"{int(time.time() * 1000)}-{payload.get('event')}-{payload.get('action')}.json"
            with open(os.path.join(self.debug_dir, name), "w") as fh:
                json.dump(payload, fh, indent=1)
        except Exception as e:
            log.warning("debug dump failed: %s", e)

    # ------------------------------------------------------------- HTTP
    def serve(self, host, port):
        receiver = self

        class Handler(BaseHTTPRequestHandler):
            server_version = "plane-bot/1"

            def log_message(self, fmt, *args):
                log.debug("%s %s", self.client_address[0], fmt % args)

            def do_POST(self):
                if self.path.rstrip("/") != "/plane":
                    return self._reply(404, "unknown path")
                n = int(self.headers.get("Content-Length", "0") or 0)
                body = self.rfile.read(min(n, 1_000_000))
                code, info = receiver.handle(body, self.headers.get("X-Plane-Signature"))
                if code == 200:
                    log.info("webhook %s: %s", self.headers.get("X-Plane-Event", "?"), info)
                else:
                    log.warning("webhook rejected (%s): %s", code, info)
                self._reply(code, info)

            def do_GET(self):
                self._reply(200, "ok") if self.path.rstrip("/") == "/health" else self._reply(404, "unknown path")

            def _reply(self, code, text):
                body = json.dumps({"ok": code == 200, "info": text}).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        srv = ThreadingHTTPServer((host, port), Handler)
        srv.daemon_threads = True
        log.info("webhook listening on %s:%d", host, port)
        srv.serve_forever()


def _canon(s):
    import datetime as dt
    try:
        t = dt.datetime.fromisoformat((s or "").replace("Z", "+00:00"))
    except ValueError:
        return s
    return (t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)).astimezone(dt.timezone.utc).isoformat()


def _same(prev, item):
    return (prev.get("state") == item.get("state") and json.loads(prev.get("assignees") or "[]") == sorted(item.get("assignees") or [])
            and (prev.get("priority") or "none") == (item.get("priority") or "none") and prev.get("target_date") == item.get("target_date")
            and prev.get("name") == item.get("name"))
