#!/usr/bin/env python3
"""Plane -> OpenProject demo migration (idempotent, resumable).

SOURCE: live Plane workspace, READ-ONLY (only GET requests).
TARGET: disposable OpenProject demo instance.

  nix-shell --run "python migrate.py --dry-run"      # preview, no writes
  nix-shell --run "python migrate.py"                # issues + sample pages
  nix-shell --run "python migrate.py --issues-only"  # skip the wiki test

State is tracked in migration_state.json so reruns skip already-created items.
"""
import argparse
import json
import os
import sys

import config
from plane_reader import PlaneReader
from openproject_client import OpenProjectClient
from converter import html_to_markdown


def load_state():
    if os.path.exists(config.STATE_FILE):
        with open(config.STATE_FILE) as f:
            return json.load(f)
    return {"issues": {}, "pages": {}, "failed": []}


def save_state(state):
    with open(config.STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


def build_state_map(plane, project_id):
    """Plane state UUID -> OpenProject status name (via Plane's `group`)."""
    out = {}
    for st in plane.states(project_id):
        op_name = config.STATE_GROUP_TO_OP_STATUS.get(
            st.get("group", ""), config.OP_STATUS_FALLBACK)
        out[st["id"]] = (st.get("name"), op_name)
    return out


def migrate_issues(plane, op, state, dry_run):
    project_id = config.AINF_PROJECT_ID
    op_proj = op.ensure_project(config.OP_PROJECT_NAME, config.OP_PROJECT_IDENTIFIER)
    op_proj_id = op_proj["identifier"] if isinstance(op_proj, dict) else config.OP_PROJECT_IDENTIFIER

    statuses = op.statuses()
    priorities = op.priorities()
    types = op.types()
    type_href = types.get(config.OP_DEFAULT_TYPE) or next(iter(types.values()))

    state_map = build_state_map(plane, project_id)
    issues = plane.issues(project_id)
    print(f"[issues] {len(issues)} AINF work items found in Plane (read-only)")

    created = skipped = failed = 0
    for it in issues:
        pid = it["id"]
        if pid in state["issues"]:
            skipped += 1
            continue

        subject = it.get("name", "(untitled)")
        _, op_status_name = state_map.get(it.get("state"), (None, config.OP_STATUS_FALLBACK))
        status_href = statuses.get(op_status_name) or statuses.get(config.OP_STATUS_FALLBACK)
        prio_name = config.PRIORITY_TO_OP.get(it.get("priority") or "none", config.OP_PRIORITY_FALLBACK)
        prio_href = priorities.get(prio_name) or priorities.get(config.OP_PRIORITY_FALLBACK)
        desc_md = html_to_markdown(it.get("description_html", ""))

        if dry_run:
            print(f"  + WP «{subject[:60]}»  status={op_status_name} prio={prio_name}")
            created += 1
            continue
        try:
            wp = op.create_work_package(
                op_proj_id, subject, desc_md, type_href, status_href, prio_href)
            state["issues"][pid] = {
                "wp_id": wp["id"],
                "wp_href": wp["_links"]["self"]["href"],
                "plane_parent": it.get("parent"),
            }
            save_state(state)
            created += 1
            print(f"  + WP #{wp['id']} «{subject[:60]}»")
        except Exception as e:
            failed += 1
            state["failed"].append({"issue": pid, "subject": subject, "error": str(e)})
            save_state(state)
            print(f"  ! FAILED «{subject[:60]}»: {e}")

    # second pass: parent/child
    if not dry_run:
        for pid, rec in state["issues"].items():
            parent = rec.get("plane_parent")
            if not parent or parent not in state["issues"] or rec.get("parent_done"):
                continue
            try:
                wp = op._req("GET", f"/work_packages/{rec['wp_id']}").json()
                op.set_parent(rec["wp_id"], state["issues"][parent]["wp_href"], wp["lockVersion"])
                rec["parent_done"] = True
                save_state(state)
            except Exception as e:
                print(f"  ! parent link failed for WP {rec['wp_id']}: {e}")

    print(f"[issues] created={created} skipped={skipped} failed={failed}")


def migrate_pages(plane, op, state, dry_run):
    project_id = config.AINF_PROJECT_ID
    op_proj_id = config.OP_PROJECT_IDENTIFIER
    try:
        pages = plane.pages(project_id)
    except Exception as e:
        print(f"[pages] could not list Plane pages (read-only): {e}")
        return
    sample = pages[: config.SAMPLE_PAGES_COUNT]
    print(f"[pages] sampling {len(sample)}/{len(pages)} AINF pages for wiki-fidelity test")

    created = skipped = failed = 0
    for pg in sample:
        pgid = pg["id"]
        if pgid in state["pages"]:
            skipped += 1
            continue
        title = pg.get("name") or "(untitled page)"
        html = pg.get("description_html")
        if html is None:
            try:
                html = plane.page_detail(project_id, pgid).get("description_html", "")
            except Exception:
                html = ""
        text_md = html_to_markdown(html)

        if dry_run:
            print(f"  ~ wiki «{title[:60]}» ({len(text_md)} md chars)")
            created += 1
            continue
        try:
            wp = op.create_wiki_page(op_proj_id, title, text_md)
            state["pages"][pgid] = {"wiki": wp.get("id") or wp.get("title")}
            save_state(state)
            created += 1
            print(f"  ~ wiki «{title[:60]}»")
        except Exception as e:
            failed += 1
            state["failed"].append({"page": pgid, "title": title, "error": str(e)})
            save_state(state)
            print(f"  ! wiki FAILED «{title[:60]}»: {e}")

    print(f"[pages] created={created} skipped={skipped} failed={failed}")
    if failed and not dry_run:
        print("  NOTE: if wiki creation 404s/405s, this OpenProject version lacks v3 wiki "
              "writes — import the ~25 pages manually to judge fidelity.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="preview only, no writes")
    ap.add_argument("--issues-only", action="store_true", help="skip the wiki/pages test")
    ap.add_argument("--pages-only", action="store_true", help="only the wiki/pages test")
    args = ap.parse_args()

    plane = PlaneReader(config.read_plane_token())
    op = None if args.dry_run else OpenProjectClient(config.OP_BASE_URL, config.read_op_api_key())
    if args.dry_run:
        # dry-run still needs an OP client for lookups only if not previewing; keep it offline.
        class _Stub:
            def ensure_project(self, *a): return {"identifier": config.OP_PROJECT_IDENTIFIER}
            def statuses(self): return {}
            def priorities(self): return {}
            def types(self): return {"Task": "stub"}
        op = _Stub()

    state = load_state()
    print(f"OpenProject target: {config.OP_BASE_URL}  (Plane is read-only)\n")

    if not args.pages_only:
        migrate_issues(plane, op, state, args.dry_run)
    if not args.issues_only and not args.dry_run:
        migrate_pages(plane, op, state, args.dry_run)
    elif args.dry_run and not args.issues_only:
        migrate_pages(plane, op, state, True)

    print("\nDone." + ("" if not args.dry_run else "  (dry-run — nothing written)"))


if __name__ == "__main__":
    sys.exit(main())
