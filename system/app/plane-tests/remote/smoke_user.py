# qa-smoke user for the read-only L7 smoke (APLANE-11). Piped into `manage.py shell`.
#
# PT_ACTION=add     idempotent: Guest in akuworkspace + secret project "QA Smoke" (QSMK) with
#                   no work items (no webhook traffic). Unusable password, no Pocket ID account.
# PT_ACTION=remove  hard-deletes the project, the memberships, sessions and the user.
# PT_ACTION=mint    prints "SESSION <key>" for one smoke run (web cookie `session-id`).
# PT_ACTION=revoke  deletes every session of qa-smoke.
#
# The project is created through Plane's own view (default states, identifier, member
# rows) with qa-smoke temporarily workspace admin, then both roles drop to Guest.
import json
import os

from django.contrib.auth import BACKEND_SESSION_KEY, HASH_SESSION_KEY, SESSION_KEY
from django.test import Client

from plane.db.models import Issue, Profile, Project, ProjectMember, Session, User, Workspace, WorkspaceMember
from plane.db.models.session import SessionStore

EMAIL = "qa-smoke@plane-tests.invalid"
SLUG = "akuworkspace"
PROJECT_NAME, IDENT = "QA Smoke", "QSMK"
GUEST, ADMIN = 5, 20
action = os.environ["PT_ACTION"]
ws = Workspace.objects.get(slug=SLUG)


def sessions(user):
    return Session.objects.filter(user_id=str(user.id))


if action == "add":
    user, created = User.objects.get_or_create(
        email=EMAIL,
        defaults=dict(username="qa-smoke", display_name="qa-smoke", first_name="QA", last_name="Smoke",
                      is_password_autoset=True, is_email_verified=True),
    )
    if created:
        user.set_unusable_password()
        user.save()
    profile, _ = Profile.objects.get_or_create(user=user)
    profile.is_onboarded, profile.is_tour_completed, profile.last_workspace_id = True, True, ws.id
    for field in ("onboarding_step", "mobile_onboarding_step", "product_tour"):
        value = getattr(profile, field, None)
        if isinstance(value, dict):
            setattr(profile, field, {k: True for k in value})
    profile.save()
    # No notification mail for this user, ever.
    from plane.db.models import UserNotificationPreference

    UserNotificationPreference.objects.filter(user=user).update(
        property_change=False, state_change=False, comment=False, mention=False, issue_completed=False)

    wm, _ = WorkspaceMember.objects.get_or_create(workspace=ws, member=user, defaults={"role": GUEST})
    project = Project.objects.filter(workspace=ws, identifier=IDENT).first()
    if not project:
        WorkspaceMember.objects.filter(pk=wm.pk).update(role=ADMIN, is_active=True)
        try:
            client = Client()
            client.force_login(user)
            resp = client.post(f"/api/workspaces/{SLUG}/projects/",
                               data=json.dumps({"name": PROJECT_NAME, "identifier": IDENT, "network": 0}),
                               content_type="application/json", HTTP_HOST="localhost")
            if resp.status_code != 201:
                raise SystemExit(f"FATAL project create -> {resp.status_code}: {resp.content[:300]!r}")
            project = Project.objects.get(workspace=ws, identifier=IDENT)
        finally:
            sessions(user).delete()
    WorkspaceMember.objects.filter(pk=wm.pk).update(role=GUEST, is_active=True)
    ProjectMember.objects.filter(project=project, member=user).update(role=GUEST, is_active=True)
    print(f"OK user={user.id} project={project.id} ws_role={WorkspaceMember.objects.get(pk=wm.pk).role} "
          f"project_role={ProjectMember.objects.get(project=project, member=user).role} "
          f"items={Issue.all_objects.filter(project=project).count()}")

elif action == "remove":
    user = User.objects.filter(email=EMAIL).first()
    Project.all_objects.filter(workspace=ws, identifier=IDENT).delete()
    if user:
        sessions(user).delete()
        WorkspaceMember.all_objects.filter(member=user).delete()
        user.delete()
    print("OK removed")

elif action == "mint":
    user = User.objects.get(email=EMAIL)
    store = SessionStore()
    store[SESSION_KEY] = str(user.pk)
    store[BACKEND_SESSION_KEY] = "django.contrib.auth.backends.ModelBackend"
    store[HASH_SESSION_KEY] = user.get_session_auth_hash()
    store.set_expiry(900)
    store.create()
    print(f"SESSION {store.session_key}")

elif action == "revoke":
    user = User.objects.filter(email=EMAIL).first()
    n = sessions(user).delete()[0] if user else 0
    print(f"OK revoked {n}")

else:
    raise SystemExit(f"unknown PT_ACTION {action}")
