#!/usr/bin/env python3
"""L4 API functional tests (APLANE-12) against dev's `qa` workspace. Stdlib only.

Run by l4-api.sh on the VPS after L3-00 (dev safety). Every test cleans up what it
creates; the wrapper reseeds afterwards anyway. Prints PASS/FAIL lines; exit 1 on any FAIL.
Env: PT_BASE, PT_QA_PASSWORD, PT_QA_TOKEN_ALICE, PT_QA_TOKEN_BOB, PT_MANIFEST, PT_DEV_AIO.
"""
import hashlib
import hmac
import http.cookiejar
import http.server
import json
import os
import subprocess
import threading
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE = os.environ["PT_BASE"]
HOST = urllib.parse.urlparse(BASE).hostname
M = json.load(open(os.environ["PT_MANIFEST"]))
QA = M["workspaces"]["qa"]
QAA, QAG = QA["projects"]["QAA"], QA["projects"]["QAG"]
SLUG = "qa"
results = []


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


class Client:
    """A browser-like session (cookies + CSRF) or an API-key client."""

    def __init__(self, user=None, token=None):
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar), NoRedirect)
        self.token = token
        if user:
            self._login(user)

    def _login(self, user):
        csrf = self.req("GET", "/auth/get-csrf-token/")[1]["csrf_token"]
        body = urllib.parse.urlencode({"csrfmiddlewaretoken": csrf, "email": f"{user}@plane-tests.invalid",
                                       "password": os.environ["PT_QA_PASSWORD"]}).encode()
        status, _, headers = self.req("POST", "/auth/sign-in/", raw=body, ctype="application/x-www-form-urlencoded")
        if status != 302 or "error_code" in headers.get("Location", ""):
            raise RuntimeError(f"login {user} failed: {status} {headers.get('Location')}")

    def csrf(self):
        return next((c.value for c in self.jar if c.name == "csrftoken"), "")

    def req(self, method, path, data=None, raw=None, ctype="application/json", url=None, extra=None):
        body = raw if raw is not None else (json.dumps(data).encode() if data is not None else None)
        r = urllib.request.Request(url or BASE + path, data=body, method=method)
        r.add_header("Referer", BASE + "/")
        if body is not None:
            r.add_header("Content-Type", ctype)
        if method not in ("GET", "HEAD") and not url:
            r.add_header("X-CSRFToken", self.csrf())
        if self.token:
            r.add_header("X-API-Key", self.token)
        for k, v in (extra or {}).items():
            r.add_header(k, v)
        try:
            resp = self.opener.open(r, timeout=30)
        except urllib.error.HTTPError as e:
            resp = e
        content = resp.read()
        try:
            parsed = json.loads(content) if content else None
        except ValueError:
            parsed = content
        return resp.status if hasattr(resp, "status") else resp.code, parsed, resp.headers


def test(tid):
    def deco(fn):
        def run():
            try:
                detail = fn() or ""
                results.append(True)
                print(f"PASS {tid} {detail}".rstrip())
            except AssertionError as e:
                results.append(False)
                print(f"FAIL {tid} {e}")
            except Exception as e:  # noqa: BLE001
                results.append(False)
                print(f"FAIL {tid} {type(e).__name__}: {e}")
                traceback.print_exc(limit=2)
        run.tid = tid
        return run
    return deco


def expect(cond, msg):
    if not cond:
        raise AssertionError(msg)


def dev_shell(code):
    out = subprocess.run(["docker", "exec", "-i", "-w", "/app/backend", os.environ["PT_DEV_AIO"], "python", "manage.py", "shell"],
                         input=code, capture_output=True, text=True, timeout=120)
    return [l for l in out.stdout.splitlines() if l.startswith("OUT ")]


def multipart(fields, filename, content, ctype):
    boundary = uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{filename}"\r\n'
                 f"Content-Type: {ctype}\r\n\r\n".encode() + content + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


alice = Client("qa-alice")
bob = Client("qa-bob")
carol = Client("qa-carol")
alice_key = Client(token=os.environ["PT_QA_TOKEN_ALICE"])
bob_key = Client(token=os.environ["PT_QA_TOKEN_BOB"])


@test("L4-01-attachment-presigned-https-public-host")
def t_attachment():
    issue = QAA["issues"][0]
    base = f"/api/assets/v2/workspaces/{SLUG}/projects/{QAA['id']}/issues/{issue}/attachments/"
    payload = f"plane-tests attachment {uuid.uuid4()}".encode()
    s, r, _ = alice.req("POST", base, {"name": "probe.txt", "size": len(payload), "type": "text/plain"})
    expect(s in (200, 201), f"create {s} {r}")
    url = urllib.parse.urlparse(r["upload_data"]["url"])
    expect(url.scheme == "https", f"presigned scheme {url.scheme} (A-03)")
    expect(url.hostname == HOST, f"presigned host {url.hostname}, want {HOST} (A-02)")
    asset = r["asset_id"]
    try:
        body, ctype = multipart(r["upload_data"]["fields"], "probe.txt", payload, "text/plain")
        s, _, _ = Client().req("POST", "", raw=body, ctype=ctype, url=r["upload_data"]["url"])
        expect(s in (200, 204), f"upload to MinIO {s}")
        s, _, _ = alice.req("PATCH", f"{base}{asset}/", {})
        expect(s in (200, 204), f"mark uploaded {s}")
        s, _, h = alice.req("GET", f"{base}{asset}/")
        expect(s in (301, 302), f"download redirect {s}")
        loc = urllib.parse.urlparse(h["Location"])
        expect(loc.scheme == "https" and loc.hostname == HOST, f"download url {loc.scheme}://{loc.hostname}")
        s, got, _ = Client().req("GET", "", url=h["Location"])
        expect(s == 200 and got == payload, f"downloaded {s} {got!r:.60}")
    finally:
        alice.req("DELETE", f"{base}{asset}/")
    return f"{HOST} https, round-trip {len(payload)} bytes"


@test("L4-02-pages-api-with-api-key-on-internal-api")
def t_pages():
    base = f"/api/workspaces/{SLUG}/projects/{QAA['id']}/pages/"
    s, r, _ = alice_key.req("POST", base, {"name": f"L4 page {uuid.uuid4().hex[:6]}"})
    expect(s == 201, f"create {s} {r}")
    pid = r["id"]
    try:
        s, r, _ = alice_key.req("GET", f"{base}{pid}/")
        expect(s == 200 and r["id"] == pid, f"retrieve {s}")
        s, r, _ = alice_key.req("GET", base)
        expect(s == 200 and pid in [p["id"] for p in r], f"list {s}")
        bogus = "x" * 40  # a syntactically plausible key that does not exist
        s, _, _ = Client(token=bogus).req("GET", base)
        expect(s in (401, 403), f"bogus key got {s}")
        s, _, _ = Client().req("GET", base)
        expect(s in (401, 403), f"anonymous got {s}")
    finally:
        alice_key.req("POST", f"{base}{pid}/archive/", {})
        s, _, _ = alice_key.req("DELETE", f"{base}{pid}/")
    expect(s == 204, f"delete {s}")
    return "create/retrieve/list/delete with X-API-Key; bogus key + anonymous refused"


@test("L4-03-favorites-crud-cross-session")
def t_favorites():
    page = QAA["pages"]["QA page to pin"]
    base = f"/api/workspaces/{SLUG}/user-favorites/"
    s, r, _ = alice.req("POST", base, {"entity_type": "page", "entity_identifier": page, "project_id": QAA["id"],
                                       "entity_data": {"name": "QA page to pin"}})
    expect(s in (200, 201), f"create page favourite {s} {r}")
    fid = r["id"]
    s, r2, _ = alice.req("POST", base, {"entity_type": "issue", "entity_identifier": QAA["issues"][1], "project_id": QAA["id"],
                                        "name": "QAA-2 x", "entity_data": {"name": "QAA-2 x"}})
    expect(s in (200, 201), f"create issue favourite {s} {r2}")
    try:
        s, _, _ = alice.req("PATCH", f"{base}{fid}/", {"sequence": 12345.5})
        expect(s in (200, 204), f"update sequence {s}")
        other = Client("qa-alice")  # a second device
        s, lst, _ = other.req("GET", base)
        seen = {f["id"]: f for f in lst}
        expect(fid in seen and seen[fid]["sequence"] == 12345.5, f"second session sees {seen.get(fid)}")
        expect(r2["id"] in seen and seen[r2["id"]]["entity_type"] == "issue", "issue favourite accepted (no choices constraint)")
        s, lst, _ = bob.req("GET", base)
        expect(fid not in [f["id"] for f in lst or []], "favourites are per-user")
    finally:
        for f in (fid, r2["id"]):
            alice.req("DELETE", f"{base}{f}/")
    s, lst, _ = alice.req("GET", base)
    expect(fid not in [f["id"] for f in lst], "deleted")
    return "page + issue favourites, sequence persists across sessions, per-user, delete"


@test("L4-03b-pin-lifecycle-backend-contract")
def t_pin_lifecycle():
    """What the backend does to a favourite when its entity changes (APLANE-13, B-08…B-10).

    The sidebar resolves pins from their UUIDs precisely because of what this pins down:
    the row's stored label never follows a rename, and a deleted work item leaves its
    favourite behind — so the frontend is the one that has to drop it.
    """
    proj = f"/api/workspaces/{SLUG}/projects/{QAA['id']}"
    favs = f"/api/workspaces/{SLUG}/user-favorites/"
    # only a completed / cancelled work item can be archived, so start it there
    s, issue, _ = alice.req("POST", f"{proj}/issues/", {"name": "L4-03b item before rename",
                                                       "state_id": QAA["states"]["completed"]})
    expect(s == 201, f"create item {s} {issue}")
    s, page, _ = alice.req("POST", f"{proj}/pages/", {"name": "L4-03b page before rename"})
    expect(s == 201, f"create page {s} {page}")
    pins = {}
    try:
        for kind, eid in (("issue", issue["id"]), ("page", page["id"])):
            s, r, _ = alice.req("POST", favs, {"entity_type": kind, "entity_identifier": eid,
                                               "project_id": QAA["id"], "name": "STALE LABEL"})
            expect(s in (200, 201), f"pin {kind} {s} {r}")
            pins[kind] = r["id"]

        # renamed: the entity changes, the favourite's stored label does NOT
        expect(alice.req("PATCH", f"{proj}/issues/{issue['id']}/", {"name": "L4-03b item renamed"})[0] in (200, 204), "rename item")
        expect(alice.req("PATCH", f"{proj}/pages/{page['id']}/", {"name": "L4-03b page renamed"})[0] in (200, 204), "rename page")
        s, r, _ = alice.req("GET", f"{proj}/issues/{issue['id']}/")
        expect(s == 200 and r["name"] == "L4-03b item renamed", f"item reads back renamed: {s} {r.get('name')}")
        stored = {f["id"]: f for f in alice.req("GET", favs)[1]}
        expect(stored[pins["issue"]]["name"] == "STALE LABEL",
               f"favourite label still stale: {stored[pins['issue']]['name']} (this is why pins resolve by UUID)")

        # archived work item: kept, and flagged so the sidebar can link to the archived route
        expect(alice.req("POST", f"{proj}/issues/{issue['id']}/archive/", {})[0] in (200, 201), "archive item")
        s, r, _ = alice.req("GET", f"{proj}/issues/{issue['id']}/")
        expect(s == 200 and r.get("archived_at"), f"archived item still readable with archived_at: {s}")
        expect(pins["issue"] in {f["id"] for f in alice.req("GET", favs)[1]}, "archiving a work item keeps its favourite")

        # archived page: upstream DELETES the favourite server-side (deviation from work items)
        expect(alice.req("POST", f"{proj}/pages/{page['id']}/archive/", {})[0] in (200, 201), "archive page")
        page_pin_after_archive = pins["page"] in {f["id"] for f in alice.req("GET", favs)[1]}

        # deleted work item: 404, and the favourite is LEFT BEHIND — the frontend drops it (B-10)
        expect(alice.req("DELETE", f"{proj}/issues/{issue['id']}/")[0] == 204, "delete item")
        expect(alice.req("GET", f"{proj}/issues/{issue['id']}/")[0] == 404, "deleted item reads 404")
        expect(pins["issue"] in {f["id"] for f in alice.req("GET", favs)[1]},
               "the backend leaves the favourite of a deleted work item behind (the frontend removes it)")
    finally:
        for fid in pins.values():
            alice.req("DELETE", f"{favs}{fid}/")
        alice.req("DELETE", f"{proj}/issues/{issue['id']}/")
        alice.req("DELETE", f"{proj}/pages/{page['id']}/")
    return ("rename keeps the stale label; archived item kept + archived_at; deleted item 404 with the "
            f"favourite left behind; archiving a page {'keeps' if page_pin_after_archive else 'deletes'} its favourite")


@test("L4-04-workspace-search-shapes")
def t_search():
    q = urllib.parse.urlencode({"search": "QAA", "workspace_search": "true"})
    s, r, _ = alice.req("GET", f"/api/workspaces/{SLUG}/search/?{q}")
    expect(s == 200, f"search {s}")
    issues = r["results"]["issue"]
    expect(issues, "no issue results")
    for key in ("id", "name", "project_id", "project__identifier", "sequence_id"):
        expect(key in issues[0], f"issue result lacks {key}: {sorted(issues[0])}")
    q = urllib.parse.urlencode({"search": "QA page", "workspace_search": "true"})
    s, r, _ = alice.req("GET", f"/api/workspaces/{SLUG}/search/?{q}")
    pages = r["results"]["page"]
    expect(pages, "no page results")
    for key in ("id", "name", "project_ids"):
        expect(key in pages[0], f"page result lacks {key}: {sorted(pages[0])}")
    return f"{len(issues)} issues, {len(pages)} pages with the fields the Pins dialog reads"


@test("L4-05-global-view-permissions")
def t_views():
    base = f"/api/workspaces/{SLUG}/views/"
    table = QA["views"]["QA Table"]
    s, _, _ = bob.req("PATCH", f"{base}{table}/", {"name": "hijacked"})
    expect(s in (400, 403), f"non-owner update got {s}")
    s, r, _ = alice.req("GET", f"{base}{table}/")
    expect(r["name"] == "QA Table", f"name changed to {r['name']}")
    s, _, _ = alice.req("PATCH", f"{base}{table}/", {"name": "QA Table"})
    expect(s == 200, f"owner update got {s}")
    s, v, _ = bob.req("POST", base, {"name": f"L4 temp {uuid.uuid4().hex[:6]}", "display_filters": {"layout": "kanban"}, "filters": {}})
    expect(s == 201, f"bob create {s}")
    try:
        s, _, _ = carol.req("DELETE", f"{base}{v['id']}/")
        expect(s in (400, 403), f"member non-owner delete got {s}")
        s, _, _ = alice.req("DELETE", f"{base}{v['id']}/")
        expect(s == 204, f"admin delete got {s}")
    finally:
        bob.req("DELETE", f"{base}{v['id']}/")
    return "owner-only update; admin (not member) may delete others' views"


@test("L4-06-A09-unsubscribed-assignee-notified-actor-not")
def t_notify():
    """Assigning someone subscribes them natively (issue_activities_task), so that path alone
    proves nothing about A-09. The case only Fix 4 covers: an assignee who is NOT subscribed
    (here: unsubscribed themselves) still hears about another user's change; the actor never does."""
    base = f"/api/workspaces/{SLUG}/projects/{QAA['id']}/issues/"
    ids = M["users"]
    alice_id, bob_id = ids["alice"]["id"], ids["bob"]["id"]
    s, r, _ = bob.req("POST", base, {"name": f"L4 notify {uuid.uuid4().hex[:6]}", "priority": "low"})
    expect(s == 201, f"bob create {s}")
    iid = r["id"]

    def counts():
        out = dev_shell(
            "from plane.db.models import Notification, IssueSubscriber\n"
            f"print('OUT', Notification.objects.filter(entity_identifier='{iid}', receiver_id='{alice_id}').count(),"
            f" Notification.objects.filter(entity_identifier='{iid}', receiver_id='{bob_id}').count(),"
            f" IssueSubscriber.objects.filter(issue_id='{iid}', subscriber_id='{alice_id}').count())")
        return tuple(map(int, out[0].split()[1:]))

    def wait_for(pred, what):
        for _ in range(30):
            c = counts()
            if pred(c):
                return c
            time.sleep(2)
        raise AssertionError(f"timed out waiting for {what}; last {c}")

    try:
        time.sleep(2)
        s, _, _ = bob.req("PATCH", f"{base}{iid}/", {"assignee_ids": [alice_id]})
        expect(s in (200, 204), f"assign {s}")
        wait_for(lambda c: c[0] >= 1 and c[2] == 1, "assignment notification + native auto-subscribe")
        s, _, _ = alice.req("DELETE", f"{base}{iid}/subscribe/")
        expect(s in (200, 204), f"alice unsubscribe {s}")
        before = wait_for(lambda c: c[2] == 0, "alice unsubscribed")
        time.sleep(2)
        s, _, _ = bob.req("PATCH", f"{base}{iid}/", {"priority": "urgent"})
        expect(s in (200, 204), f"bob change priority {s}")
        after = wait_for(lambda c: c[0] > before[0], "notification for the unsubscribed assignee — A-09 broken")
        expect(after[1] == 0, f"bob (the actor) got {after[1]} notification(s)")
    finally:
        bob.req("DELETE", f"{base}{iid}/")
    return f"unsubscribed assignee notified ({before[0]}→{after[0]}), actor not"


class Capture(http.server.BaseHTTPRequestHandler):
    hits = []

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        Capture.hits.append((dict(self.headers), body))
        self.send_response(200)
        self.end_headers()

    def log_message(self, *a):
        pass


@test("L4-07/08-webhook-ssrf-allowlist-and-signature")
def t_webhooks():
    base = f"/api/workspaces/{SLUG}/webhooks/"
    for bad in ("http://127.0.0.1:9/x", "http://10.0.0.1/x", "http://169.254.169.254/latest/meta-data/"):
        s, r, _ = alice.req("POST", base, {"url": bad, "issue": True})
        if s == 201:
            alice.req("DELETE", f"{base}{r['id']}/")
        expect(s == 400, f"private target {bad} accepted ({s})")
    port = 18766
    srv = http.server.HTTPServer(("127.0.0.1", port), Capture)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    wid = None
    try:
        s, r, _ = alice.req("POST", base, {"url": f"http://host.docker.internal:{port}/capture", "issue": True,
                                           "project": False, "cycle": False, "module": False, "issue_comment": False})
        expect(s == 201, f"allow-listed host.docker.internal refused ({s} {r}) — A-10 broken")
        wid, secret = r["id"], r.get("secret_key", "")
        issue = QAA["issues"][2]
        alice.req("PATCH", f"/api/workspaces/{SLUG}/projects/{QAA['id']}/issues/{issue}/", {"priority": "urgent"})
        for _ in range(30):
            if Capture.hits:
                break
            time.sleep(1)
        expect(Capture.hits, "no delivery within 30 s")
        headers, body = Capture.hits[0]
        sig = {k.lower(): v for k, v in headers.items()}.get("x-plane-signature", "")
        want = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        expect(secret and hmac.compare_digest(sig, want), "X-Plane-Signature does not verify")
        payload = json.loads(body)
        data = payload.get("data", {})
        for key in ("id", "target_date", "assignees", "state"):
            expect(key in data, f"payload.data lacks {key} (bot / n8n consumers)")
        expect(isinstance(data["state"], dict) and "name" in data["state"], "data.state.name missing")
    finally:
        if wid:
            alice.req("DELETE", f"{base}{wid}/")
        srv.shutdown()
        alice.req("PATCH", f"/api/workspaces/{SLUG}/projects/{QAA['id']}/issues/{QAA['issues'][2]}/", {"priority": "medium"})
    return "private targets refused; host.docker.internal delivers, HMAC verifies, payload shape intact"


@test("L4-10-project-sort-order-persists")
def t_sort_order():
    s, _, _ = alice.req("PATCH", f"/api/workspaces/{SLUG}/projects/{QAG['id']}/user-properties/", {"sort_order": 4242})
    expect(s in (200, 204), f"patch {s}")
    s, r, _ = alice.req("GET", f"/api/workspaces/{SLUG}/projects/")
    got = next(p["sort_order"] for p in r if p["id"] == QAG["id"])
    expect(got == 4242, f"sort_order {got}")
    return "user-properties sort_order persisted"


@test("L4-11-sidebar-preferences-per-user")
def t_sidebar():
    # the app's path: one bulk PATCH with [{key, is_pinned, sort_order}] (use-navigation-preferences)
    path = f"/api/workspaces/{SLUG}/sidebar-preferences/"

    def pinned(client):
        _, prefs, _ = client.req("GET", path)
        items = prefs if isinstance(prefs, list) else [dict(v, key=k) for k, v in (prefs or {}).items()]
        return {i["key"]: i.get("is_pinned") for i in items if isinstance(i, dict) and "key" in i}

    bob_before = pinned(bob)
    # Upstream quirk (verified 2026-09-17): the PATCH only updates rows that already exist, and
    # rows are created by the first GET — a PATCH before any GET answers 200 and changes nothing.
    # The app always loads preferences first, so do the same.
    pinned(alice)
    s, r, _ = alice.req("PATCH", path, [{"key": "archives", "is_pinned": True, "sort_order": 7}])
    expect(s in (200, 204), f"bulk patch {s} {r}")
    try:
        expect(pinned(alice).get("archives") is True, f"alice archives not pinned: {pinned(alice)}")
        expect(pinned(bob) == bob_before, "bob's preferences changed with alice's")
    finally:
        alice.req("PATCH", path, [{"key": "archives", "is_pinned": False, "sort_order": 7}])
    return "alice's pin does not touch bob (bulk endpoint, as the app calls it)"


@test("L4-12-session-rolling")
def t_rolling():
    def expiry():
        _, _, h = alice.req("GET", "/api/users/me/")
        cookies = [v for k, v in h.items() if k.lower() == "set-cookie" and v.startswith("session-id=")]
        expect(cookies, "no session cookie refresh on an authenticated request")
        part = next(p for p in cookies[0].split(";") if p.strip().lower().startswith("expires="))
        return time.mktime(time.strptime(part.split("=", 1)[1].strip(), "%a, %d %b %Y %H:%M:%S GMT"))
    first = expiry()
    time.sleep(2)
    second = expiry()
    expect(second > first, f"expiry did not move ({first} → {second})")
    days = (second - time.time()) / 86400
    expect(85 <= days <= 91, f"cookie lifetime {days:.1f} days")
    return f"expiry rolls forward, ~{days:.0f} days (A-11)"


@test("L4-09-api-key-rate-limit")
def t_rate():
    codes = [bob_key.req("GET", f"/api/v1/workspaces/{SLUG}/projects/")[0] for _ in range(65)]
    first_429 = next((i + 1 for i, c in enumerate(codes) if c == 429), None)
    expect(first_429 is not None and first_429 <= 62, f"no 429 within 65 calls ({sorted(set(codes))})")
    return f"429 from call {first_429} (60/minute)"


if __name__ == "__main__":
    for t in (t_attachment, t_pages, t_favorites, t_pin_lifecycle, t_search, t_views, t_notify, t_webhooks, t_sort_order, t_sidebar, t_rolling, t_rate):
        t()
    print(f"L4 api: {sum(results)}/{len(results)} passed")
    raise SystemExit(0 if all(results) else 1)
