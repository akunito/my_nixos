# QA seed (APLANE-10). Piped into `manage.py shell` inside plane-dev-aio.
#
# Idempotent: hard-deletes the qa / qa-2 workspaces and every *@plane-tests.invalid
# user, then rebuilds them. Users, workspace members and profiles are created with
# the ORM (that is what Plane itself does on signup / invite accept); everything
# else goes through Plane's own API views with a logged-in Django test client, so
# default states, project members, activities and sort orders are created exactly
# as the web app would — and no API-key rate limit applies.
#
# Env: PT_QA_PASSWORD (password for every QA user).
# Output: "TOKEN <user> <token>" lines (captured by seed-qa.sh, never shown) and a
# "MANIFEST <json>" line describing what exists, for tests to read.
import json
import os
from datetime import date, timedelta

from django.core.cache import cache
from django.test import Client

from plane.db.models import (
    APIToken,
    Profile,
    User,
    Workspace,
    WorkspaceMember,
)

DOMAIN = "plane-tests.invalid"
PASSWORD = os.environ["PT_QA_PASSWORD"]
ANCHOR = date(2026, 10, 1)  # every date in the seed is relative to this, never to today
ADMIN, MEMBER, GUEST = 20, 15, 5

# ---------------------------------------------------------------- reset
Workspace.all_objects.filter(slug__in=["qa", "qa-2"]).delete()
User.objects.filter(email__endswith=f"@{DOMAIN}").delete()
# Bot users the upstream workspace_seed task leaves behind for workspaces that no longer exist
for bot in User.objects.filter(is_bot=True, username__startswith="bot_user_"):
    if not Workspace.all_objects.filter(id=bot.username[len("bot_user_"):]).exists():
        bot.delete()


def api(client, method, path, payload=None, expect=(200, 201, 204)):
    resp = getattr(client, method)(path, data=json.dumps(payload) if payload is not None else None,
                                   content_type="application/json", HTTP_HOST="localhost")
    if resp.status_code not in expect:
        raise SystemExit(f"FATAL {method.upper()} {path} -> {resp.status_code}: {resp.content[:400]!r}")
    return resp.json() if resp.content else None


# ---------------------------------------------------------------- users
def make_user(handle, first, last):
    user = User.objects.create(
        email=f"{handle}@{DOMAIN}",
        username=handle,
        display_name=handle,
        first_name=first,
        last_name=last,
        is_password_autoset=False,
        is_email_verified=True,
    )
    user.set_password(PASSWORD)
    user.save()
    profile = Profile.objects.create(user=user, is_onboarded=True, is_tour_completed=True)
    for field in ("onboarding_step", "mobile_onboarding_step", "product_tour"):
        value = getattr(profile, field, None)
        if isinstance(value, dict):
            setattr(profile, field, {k: True for k in value})
    profile.save()
    return user


users = {
    "alice": make_user("qa-alice", "Alice", "QA"),  # workspace admin qa + qa-2, admin of every QA project
    "bob": make_user("qa-bob", "Bob", "QA"),  # member; in Alpha + Beta, NOT in Gamma (no-access cases)
    "carol": make_user("qa-carol", "Carol", "QA"),  # member; Alpha only; never touches preferences
    "guest": make_user("qa-guest", "Gus", "QA"),  # workspace guest; guest on Alpha
}

alice = Client()
alice.force_login(users["alice"])
bob = Client()
bob.force_login(users["bob"])

# ---------------------------------------------------------------- workspaces
# Same rows WorkSpaceViewSet.create writes (workspace + admin member), but NOT its
# `workspace_seed` celery task, which adds an async sample project, issues, pages
# and a bot member — noise in every cross-project view the tests look at.
for slug, wname in (("qa", "QA"), ("qa-2", "QA Two")):
    w = Workspace.objects.create(name=wname, slug=slug, owner=users["alice"], organization_size="2-10")
    WorkspaceMember.objects.create(workspace=w, member=users["alice"], role=ADMIN)
ws = Workspace.objects.get(slug="qa")
for key, role in (("bob", MEMBER), ("carol", MEMBER), ("guest", GUEST)):
    WorkspaceMember.objects.create(workspace=ws, member=users[key], role=role)
for u in users.values():
    Profile.objects.filter(user=u).update(last_workspace_id=ws.id)

# ---------------------------------------------------------------- projects
PROJECTS = [
    # (slug, name, identifier, extra members)
    ("qa", "QA Alpha", "QAA", [("bob", MEMBER), ("carol", MEMBER), ("guest", GUEST)]),
    ("qa", "QA Beta", "QAB", [("bob", MEMBER)]),
    ("qa", "QA Gamma", "QAG", []),
    ("qa-2", "QA Two", "QTW", []),
]
STATE_PATTERN = ["backlog", "unstarted", "started", "completed", "cancelled", "started",
                 "unstarted", "backlog", "started", "unstarted", "completed", "started"]
PRIORITY_PATTERN = ["urgent", "high", "medium", "low", "none", "high",
                    "high", "medium", "none", "urgent", "low", "medium"]  # deliberate ties
manifest = {"anchor": ANCHOR.isoformat(), "password_env": "PT_QA_PASSWORD", "users": {}, "workspaces": {}}
for key, u in users.items():
    manifest["users"][key] = {"email": u.email, "id": str(u.id)}

for slug, name, ident, members in PROJECTS:
    proj = api(alice, "post", f"/api/workspaces/{slug}/projects/", {"name": name, "identifier": ident, "network": 2})
    pid = proj["id"]
    base = f"/api/workspaces/{slug}/projects/{pid}"
    if members:
        api(alice, "post", f"{base}/members/",
            {"members": [{"member_id": str(users[k].id), "role": r} for k, r in members]})
    member_keys = ["alice"] + [k for k, r in members if r != GUEST]

    states = api(alice, "get", f"{base}/states/")
    by_group = {}
    for s in sorted(states, key=lambda s: s.get("sequence", 0)):
        by_group.setdefault(s["group"], s["id"])

    labels = [api(alice, "post", f"{base}/issue-labels/", {"name": n, "color": c})["id"]
              for n, c in (("bug", "#EF4444"), ("docs", "#3B82F6"), ("zeta", "#10B981"))]

    count = 12 if slug == "qa" else 3
    issues = []
    for i in range(count):
        assignee_cycle = [["alice"], member_keys[1:2], [], member_keys[:2], member_keys[-1:], ["alice"]]
        target = None if i % 4 == 3 else ANCHOR + timedelta(days=i * 3 - 6)
        start = None if i % 3 else (target or ANCHOR) - timedelta(days=2)  # never after target
        payload = {
            "name": f"{ident} case {i + 1:02d} — {PRIORITY_PATTERN[i]} / {STATE_PATTERN[i]}",
            "state_id": by_group[STATE_PATTERN[i]],
            "priority": PRIORITY_PATTERN[i],
            "assignee_ids": [str(users[k].id) for k in dict.fromkeys(assignee_cycle[i % 6])],
            "label_ids": [labels[j] for j in range(3) if (i >> j) & 1],  # 0..7 → every label combination
            "target_date": target.isoformat() if target else None,
            "start_date": start.isoformat() if start else None,
            "description_html": f"<p>Seeded QA item {i + 1} of {ident}.</p>",
        }
        issues.append(api(alice, "post", f"{base}/issues/", payload))
    ids = [x["id"] for x in issues]

    info = {"id": pid, "identifier": ident, "issues": ids, "labels": labels, "states": by_group}
    if slug == "qa":
        cycle = api(alice, "post", f"{base}/cycles/",
                    {"name": f"{ident} sprint", "start_date": (ANCHOR - timedelta(days=7)).isoformat(),
                     "end_date": (ANCHOR + timedelta(days=7)).isoformat(), "project_id": pid})
        api(alice, "post", f"{base}/cycles/{cycle['id']}/cycle-issues/", {"issues": ids[:6]})
        module = api(alice, "post", f"{base}/modules/", {"name": f"{ident} module", "project_id": pid})
        api(alice, "post", f"{base}/modules/{module['id']}/issues/", {"issues": ids[4:9]})
        api(alice, "post", f"{base}/issues/{ids[0]}/comments/", {"comment_html": "<p>First QA comment.</p>"})
        # archived: case 11 is 'completed' → archivable
        api(alice, "post", f"{base}/issues/{ids[10]}/archive/", {})
        info.update(cycle=cycle["id"], module=module["id"], archived_issue=ids[10])

    if ident == "QAA":
        # one project view per layout (layout matrix L5-30)
        info["views"] = {}
        for layout in ("list", "kanban", "calendar", "spreadsheet", "gantt_chart"):
            v = api(alice, "post", f"{base}/views/",
                    {"name": f"QAA {layout}", "display_filters": {"layout": layout}, "filters": {}})
            info["views"][layout] = v["id"]
        info["pages"] = {}
        for pname in ("QA page to pin", "QA page to delete", "QA page to archive"):
            info["pages"][pname] = api(alice, "post", f"{base}/pages/",
                                       {"name": pname, "description_html": f"<p>{pname}</p>"})["id"]
        api(bob, "post", f"{base}/issues/{ids[1]}/comments/", {"comment_html": "<p>Bob was here.</p>"})

    manifest["workspaces"].setdefault(slug, {"projects": {}})["projects"][ident] = info

# ---------------------------------------------------------------- workspace (global) views
gv = {}
for name, layout, owner in (("QA Table", "spreadsheet", alice), ("QA Board", "kanban", alice),
                            ("QA Calendar", "calendar", alice), ("QA Locked", "spreadsheet", alice),
                            ("QA Bob view", "kanban", bob)):
    view = api(owner, "post", "/api/workspaces/qa/views/",
               {"name": name, "display_filters": {"layout": layout}, "filters": {}})
    gv[name] = view["id"]
from plane.db.models import IssueView  # noqa: E402

IssueView.objects.filter(id=gv["QA Locked"]).update(is_locked=True)
manifest["workspaces"]["qa"]["views"] = gv

# ---------------------------------------------------------------- API tokens (L4)
for key in ("alice", "bob"):
    token = APIToken.objects.create(user=users[key], workspace=ws, label=f"plane-tests {key}", user_type=0)
    print(f"TOKEN {key} {token.token}")

cache.clear()
print("MANIFEST " + json.dumps(manifest, sort_keys=True))
