# Dev sanitize, part 2 (APLANE-19): hard-delete workspaces that are not kept on
# dev. Piped into `manage.py shell` inside plane-dev-aio; slugs come from the
# PT_DROP_WORKSPACES env var. `all_objects` is a plain Manager, so .delete() is a
# real delete and Django's collector cascades through every related table
# (including soft-deleted rows).
import os

from plane.db.models import Workspace

slugs = os.environ["PT_DROP_WORKSPACES"].split()
qs = Workspace.all_objects.filter(slug__in=slugs)
found = sorted(qs.values_list("slug", flat=True))
if found:
    total, per_model = qs.delete()
    top = sorted(per_model.items(), key=lambda kv: -kv[1])[:6]
    print(f"deleted workspaces {found}: {total} rows; largest: {top}")
else:
    print(f"no workspaces to delete among {slugs}")

left = list(Workspace.all_objects.filter(slug__in=slugs).values_list("slug", flat=True))
if left:
    raise SystemExit(f"FATAL: workspaces still present: {left}")
