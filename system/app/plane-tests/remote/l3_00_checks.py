# L3-00 dev safety — in-app checks. Piped into `manage.py shell` inside
# plane-dev-aio. Prints one "PASS|FAIL <id> <detail>" line per check; the
# wrapper (l3_00_dev_safety.sh) turns any FAIL into a non-zero exit.
#
# Env: PT_DROP_WORKSPACES (slugs that must not exist), PT_MAILPIT (host).
import json
import os
import time
import urllib.parse
import urllib.request
import uuid

from django.apps import apps
from django.core.mail import EmailMultiAlternatives, get_connection

from plane.db.models import APIToken, Webhook, Workspace
from plane.license.models import InstanceConfiguration
from plane.license.utils.instance_value import get_email_configuration

MAILPIT = os.environ.get("PT_MAILPIT", "plane-dev-mailpit")
results = []


def check(cid, ok, detail=""):
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'} {cid} {detail}".rstrip())


def config(key):
    row = InstanceConfiguration.objects.filter(key=key).first()
    return row.value if row else None


# S01 no webhooks at all (a capture receiver will be allow-listed here when L4 exists)
hooks = list(Webhook.all_objects.values_list("url", "is_active"))
check("S01-webhooks", not hooks, f"{len(hooks)} webhook(s): {hooks}" if hooks else "none")

# S02 no API tokens except the QA users' (seed-qa.sh); S10 cross-checks against prod
foreign = APIToken.objects.exclude(user__email__endswith="@plane-tests.invalid").count()
check("S02-api-tokens", foreign == 0, f"{foreign} non-QA token(s), {APIToken.objects.count()} total")

# S04 email config rows point at the sink
host, port = config("EMAIL_HOST"), config("EMAIL_PORT")
check("S04-email-rows", host == MAILPIT and port == "1025", f"EMAIL_HOST={host} EMAIL_PORT={port}")

# S05 the resolved email configuration Plane really uses
cfg = get_email_configuration()
check("S05-email-resolved", cfg[0] == MAILPIT and str(cfg[3]) == "1025", f"host={cfg[0]} port={cfg[3]}")

# S06 dev-only auth expectations
check(
    "S06-auth-flags",
    config("ENABLE_EMAIL_PASSWORD") == "1" and config("ENABLE_SIGNUP") == "0" and config("ENABLE_MAGIC_LINK_LOGIN") == "0",
    f"password={config('ENABLE_EMAIL_PASSWORD')} signup={config('ENABLE_SIGNUP')} magic={config('ENABLE_MAGIC_LINK_LOGIN')}",
)

# S07 workspaces that must not be on dev
drop = os.environ.get("PT_DROP_WORKSPACES", "").split()
left = list(Workspace.all_objects.filter(slug__in=drop).values_list("slug", flat=True))
check("S07-dropped-workspaces", not left, f"present: {left}" if left else f"absent: {drop}")

# S08 no third-party sync integrations that could call out
counts = {}
for name in ("WorkspaceIntegration", "GithubRepositorySync", "GithubIssueSync", "SlackProjectSync", "Importer"):
    try:
        counts[name] = apps.get_model("db", name).objects.count()
    except LookupError:
        pass
check("S08-integrations", not any(counts.values()), json.dumps(counts))


# S09 live mail path: send through Plane's own configuration, find it in mailpit.
# Never probe through a real relay — an unsanitized dev would deliver it.
def probe_mail():
    if cfg[0] != MAILPIT:
        return False, f"not attempted: email resolves to {cfg[0]}, not the sink"
    subject = f"plane-tests L3-00 probe {uuid.uuid4()}"
    h, user, pwd, p, tls, ssl, sender = cfg
    conn = get_connection(host=h, port=int(p), username=user, password=pwd, use_tls=tls == "1", use_ssl=ssl == "1")
    EmailMultiAlternatives(subject, "probe", sender, ["probe@plane-tests.invalid"], connection=conn).send()
    query = urllib.parse.quote(f'subject:"{subject}"')
    for _ in range(10):
        with urllib.request.urlopen(f"http://{MAILPIT}:8025/api/v1/search?query={query}", timeout=5) as r:
            if json.load(r).get("messages_count", 0):
                return True, "probe delivered to mailpit"
        time.sleep(1)
    return False, "probe sent but not found in mailpit"


try:
    ok, detail = probe_mail()
except Exception as exc:  # noqa: BLE001 — any failure here is a FAIL, reported verbatim
    ok, detail = False, f"{type(exc).__name__}: {exc}"
check("S09-mail-lands-in-sink", ok, detail)

print(f"SUMMARY {sum(results)}/{len(results)} passed")
