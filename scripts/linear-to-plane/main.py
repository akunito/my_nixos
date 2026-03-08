#!/usr/bin/env python3
"""Linear → Plane migration script for Liftcraft (LW) project.

Usage:
    cd scripts/linear-to-plane && nix-shell --run "python main.py --inventory"
    cd scripts/linear-to-plane && nix-shell --run "python main.py --export"
    cd scripts/linear-to-plane && nix-shell --run "python main.py --import-all"
    cd scripts/linear-to-plane && nix-shell --run "python main.py --verify"
"""

import argparse
import json
import sys

import markdown as md

from config import (
    LINEAR_PROJECT_NAME,
    LINEAR_DELAY_SECONDS,
    PLANE_BASE_URL,
    PLANE_DELAY_SECONDS,
    WORKSPACE_SLUG,
    LW_PROJECT_ID,
    EXPORT_FILE,
    read_linear_token,
    read_plane_token,
    map_linear_state,
    map_linear_priority,
    map_linear_user,
)
from linear_client import LinearClient
from plane_client import PlaneClient
from state_store import (
    load_state, save_state,
    is_label_migrated, record_label,
    is_issue_migrated, record_issue,
    is_comment_migrated, record_comment,
    is_page_migrated, record_page,
    record_failure,
)


# =============================================================================
# Helpers
# =============================================================================

def md_to_html(text: str) -> str:
    """Convert Markdown to HTML. Returns empty string for None/empty input."""
    if not text:
        return ""
    return md.markdown(text, extensions=["tables", "fenced_code", "nl2br"])


def topological_sort_issues(issues: list) -> list:
    """Sort issues so parents come before children.

    Issues without parents come first, then issues whose parents
    are already in the sorted list.
    """
    id_set = {i["id"] for i in issues}
    issue_by_id = {i["id"]: i for i in issues}

    # Separate roots from children
    roots = []
    children = []
    for issue in issues:
        parent = issue.get("parent")
        if not parent or parent.get("id") not in id_set:
            roots.append(issue)
        else:
            children.append(issue)

    sorted_ids = set()
    result = []

    for issue in roots:
        result.append(issue)
        sorted_ids.add(issue["id"])

    # Iteratively add children whose parents are already sorted
    remaining = children
    max_passes = len(remaining) + 1
    for _ in range(max_passes):
        if not remaining:
            break
        still_remaining = []
        for issue in remaining:
            parent_id = issue["parent"]["id"]
            if parent_id in sorted_ids:
                result.append(issue)
                sorted_ids.add(issue["id"])
            else:
                still_remaining.append(issue)
        if len(still_remaining) == len(remaining):
            # No progress — add remaining as-is (orphan parents outside project)
            result.extend(still_remaining)
            break
        remaining = still_remaining

    return result


def get_linear_client() -> LinearClient:
    return LinearClient(read_linear_token(), LINEAR_DELAY_SECONDS)


def get_plane_client() -> PlaneClient:
    return PlaneClient(PLANE_BASE_URL, WORKSPACE_SLUG, read_plane_token(), PLANE_DELAY_SECONDS)


def load_export() -> dict:
    """Load the Linear export JSON."""
    try:
        with open(EXPORT_FILE) as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"Export file not found: {EXPORT_FILE}")
        print("Run --export first.")
        sys.exit(1)


# =============================================================================
# Phase 0: Inventory
# =============================================================================

def cmd_inventory(args):
    """Query Linear and show what will be migrated."""
    linear = get_linear_client()

    print("Fetching teams...")
    teams = linear.get_teams()
    for t in teams:
        print(f"  Team: {t['name']} (key={t['key']}, id={t['id']})")

    print(f"\nSearching for project '{LINEAR_PROJECT_NAME}'...")
    project = linear.get_project_by_name(LINEAR_PROJECT_NAME)
    if not project:
        print("  Project NOT FOUND!")
        return

    project_id = project["id"]
    print(f"  Found: {project['name']} (id={project_id}, progress={project.get('progress', 'N/A')})")

    # Get team ID from project
    project_teams = project.get("teams", {}).get("nodes", [])
    if not project_teams:
        print("  WARNING: No teams associated with project")
        return
    team_id = project_teams[0]["id"]
    team_name = project_teams[0]["name"]
    print(f"  Team: {team_name} (id={team_id})")

    print("\nFetching issues...")
    issues = linear.get_issues(project_id)
    print(f"  Issues: {len(issues)}")

    # Count by state
    state_counts = {}
    for issue in issues:
        state_name = issue["state"]["name"]
        state_counts[state_name] = state_counts.get(state_name, 0) + 1
    for state, count in sorted(state_counts.items()):
        print(f"    {state}: {count}")

    # Count with comments
    issues_with_children = sum(1 for i in issues if i.get("children", {}).get("nodes"))
    issues_with_parent = sum(1 for i in issues if i.get("parent"))
    issues_with_attachments = sum(1 for i in issues
                                  if i.get("attachments", {}).get("nodes"))
    print(f"  With children: {issues_with_children}")
    print(f"  With parent: {issues_with_parent}")
    print(f"  With attachments: {issues_with_attachments}")

    print("\nFetching workflow states...")
    states = linear.get_workflow_states(team_id)
    for s in states:
        print(f"  {s['name']} (type={s['type']})")

    print("\nFetching labels...")
    labels = linear.get_labels(team_id)
    print(f"  Labels: {len(labels)}")
    for label in labels:
        print(f"    {label['name']} (color={label['color']})")

    print("\nFetching documents...")
    docs = linear.get_documents(project_id)
    print(f"  Documents: {len(docs)}")
    for doc in docs:
        print(f"    {doc['title']}")

    print("\nFetching milestones...")
    milestones = linear.get_project_milestones(project_id)
    print(f"  Milestones: {len(milestones)}")
    for m in milestones:
        print(f"    {m['name']} (target={m.get('targetDate', 'N/A')})")

    print("\nFetching cycles...")
    cycles = linear.get_cycles(team_id)
    print(f"  Cycles: {len(cycles)}")
    for c in cycles:
        issue_count = len(c.get("issues", {}).get("nodes", []))
        cycle_name = c.get('name') or f"Cycle #{c['number']}"
        print(f"    {cycle_name} ({issue_count} issues)")

    print("\nFetching users...")
    users = linear.get_users()
    for u in users:
        print(f"  {u['name']} ({u['email']}, active={u['active']})")


# =============================================================================
# Phase 1: Export
# =============================================================================

def cmd_export(args):
    """Export all Linear data to a local JSON file."""
    linear = get_linear_client()

    print(f"Finding project '{LINEAR_PROJECT_NAME}'...")
    project = linear.get_project_by_name(LINEAR_PROJECT_NAME)
    if not project:
        print("Project not found!")
        sys.exit(1)

    project_id = project["id"]
    project_teams = project.get("teams", {}).get("nodes", [])
    team_id = project_teams[0]["id"] if project_teams else None

    export_data = {
        "project": project,
        "team_id": team_id,
        "issues": [],
        "comments": {},  # issue_id → [comments]
        "documents": [],
        "labels": [],
        "workflow_states": [],
        "milestones": [],
        "cycles": [],
        "users": [],
    }

    print("Exporting issues...")
    issues = linear.get_issues(project_id)
    export_data["issues"] = issues
    print(f"  {len(issues)} issues")

    print("Exporting comments for each issue...")
    for i, issue in enumerate(issues, 1):
        comments = linear.get_issue_comments(issue["id"])
        if comments:
            export_data["comments"][issue["id"]] = comments
        if i % 20 == 0:
            print(f"  [{i}/{len(issues)}] comments fetched...")
    total_comments = sum(len(v) for v in export_data["comments"].values())
    print(f"  {total_comments} comments total")

    if team_id:
        print("Exporting workflow states...")
        export_data["workflow_states"] = linear.get_workflow_states(team_id)

        print("Exporting labels...")
        export_data["labels"] = linear.get_labels(team_id)
        print(f"  {len(export_data['labels'])} labels")

        print("Exporting cycles...")
        export_data["cycles"] = linear.get_cycles(team_id)
        print(f"  {len(export_data['cycles'])} cycles")

    print("Exporting documents...")
    export_data["documents"] = linear.get_documents(project_id)
    print(f"  {len(export_data['documents'])} documents")

    print("Exporting milestones...")
    export_data["milestones"] = linear.get_project_milestones(project_id)
    print(f"  {len(export_data['milestones'])} milestones")

    print("Exporting users...")
    export_data["users"] = linear.get_users()

    with open(EXPORT_FILE, "w") as f:
        json.dump(export_data, f, indent=2, default=str)
    print(f"\nExport saved to {EXPORT_FILE}")

    state = load_state()
    state["phase"] = "exported"
    save_state(state)


# =============================================================================
# Phase 2: Import
# =============================================================================

def cmd_import_labels(args):
    """Import labels from export into Plane."""
    data = load_export()
    plane = get_plane_client()
    state = load_state()

    labels = data.get("labels", [])
    if not labels:
        print("No labels to import.")
        return

    # Fetch existing Plane labels to avoid duplicates
    existing = plane.list_labels(LW_PROJECT_ID)
    existing_names = {l["name"].lower(): l["id"] for l in existing}

    print(f"Importing {len(labels)} labels...")
    created = 0
    for label in labels:
        linear_id = label["id"]
        name = label["name"]
        color = label.get("color", "#6b7280")

        if is_label_migrated(state, linear_id):
            continue

        # Check if label already exists in Plane by name
        if name.lower() in existing_names:
            plane_id = existing_names[name.lower()]
            record_label(state, linear_id, plane_id, name)
            print(f"  Mapped existing: {name}")
            continue

        try:
            result = plane.create_label(LW_PROJECT_ID, name, color)
            record_label(state, linear_id, result["id"], name)
            existing_names[name.lower()] = result["id"]
            created += 1
            print(f"  Created: {name}")
        except Exception as e:
            print(f"  FAILED ({name}): {e}")
            record_failure(state, "label", linear_id, str(e))

    print(f"\nLabels: {created} created, {len(labels) - created} mapped/skipped")


def cmd_import_issues(args):
    """Import issues from export into Plane as work items."""
    data = load_export()
    plane = get_plane_client()
    state = load_state()

    issues = data.get("issues", [])
    if not issues:
        print("No issues to import.")
        return

    # Topological sort for parent-child ordering
    sorted_issues = topological_sort_issues(issues)
    print(f"Importing {len(sorted_issues)} issues (topologically sorted)...")

    created = 0
    for i, issue in enumerate(sorted_issues, 1):
        linear_id = issue["id"]
        identifier = issue.get("identifier", "")
        title = issue["title"]

        if is_issue_migrated(state, linear_id):
            continue

        # Map state
        state_name = issue["state"]["name"]
        state_type = issue["state"]["type"]
        plane_state_id = map_linear_state(state_name, state_type)

        # Map priority
        plane_priority = map_linear_priority(issue.get("priority", 0))

        # Map assignee
        assignee_ids = []
        assignee = issue.get("assignee")
        if assignee and assignee.get("email"):
            plane_user = map_linear_user(assignee["email"])
            if plane_user:
                assignee_ids.append(plane_user)

        # Map labels
        label_ids = []
        for label_node in issue.get("labels", {}).get("nodes", []):
            plane_label_id = state.get("label_map", {}).get(label_node["id"])
            if plane_label_id:
                label_ids.append(plane_label_id)

        # Convert description
        description_html = md_to_html(issue.get("description"))

        # Prepend original metadata
        meta = f'<p><em>Migrated from Linear: {identifier}</em></p>'
        if description_html:
            description_html = meta + description_html
        else:
            description_html = meta

        # Build work item data
        work_item_data = {
            "state": plane_state_id,
            "priority": plane_priority,
            "description_html": description_html,
        }

        if assignee_ids:
            work_item_data["assignees"] = assignee_ids

        if label_ids:
            work_item_data["labels"] = label_ids

        if issue.get("dueDate"):
            work_item_data["target_date"] = issue["dueDate"]

        if issue.get("estimate"):
            work_item_data["estimate_point"] = issue["estimate"]

        # Parent link (if parent was already imported)
        parent = issue.get("parent")
        if parent and parent.get("id") in state.get("issue_map", {}):
            work_item_data["parent"] = state["issue_map"][parent["id"]]

        # Truncate title if over 255 chars (Plane limit)
        if len(title) > 255:
            title = title[:252] + "..."

        try:
            result = plane.create_work_item(LW_PROJECT_ID, title, **work_item_data)
            record_issue(state, linear_id, identifier, result["id"], title)
            created += 1
            if i % 10 == 0 or i == len(sorted_issues):
                print(f"  [{i}/{len(sorted_issues)}] {title[:60]}")
        except Exception as e:
            print(f"  FAILED [{i}] ({title[:50]}): {e}")
            record_failure(state, "issue", linear_id, str(e))

    # Second pass: fix parent links for issues whose parents were imported after them
    print("\nChecking parent-child links...")
    fixed = 0
    for issue in sorted_issues:
        parent = issue.get("parent")
        if not parent:
            continue
        parent_linear_id = parent.get("id")
        child_linear_id = issue["id"]
        if parent_linear_id not in state["issue_map"]:
            continue
        if child_linear_id not in state["issue_map"]:
            continue

        plane_parent_id = state["issue_map"][parent_linear_id]
        plane_child_id = state["issue_map"][child_linear_id]

        try:
            plane.update_work_item(LW_PROJECT_ID, plane_child_id, parent=plane_parent_id)
            fixed += 1
        except Exception:
            pass  # Already set during creation or API ignores duplicate

    print(f"\nIssues: {created} created, {fixed} parent links verified")


def cmd_import_comments(args):
    """Import comments for all migrated issues."""
    data = load_export()
    plane = get_plane_client()
    state = load_state()

    comments_by_issue = data.get("comments", {})
    if not comments_by_issue:
        print("No comments to import.")
        return

    total = sum(len(v) for v in comments_by_issue.values())
    print(f"Importing {total} comments across {len(comments_by_issue)} issues...")

    created = 0
    for linear_issue_id, comments in comments_by_issue.items():
        plane_issue_id = state.get("issue_map", {}).get(linear_issue_id)
        if not plane_issue_id:
            continue

        # Sort by creation date
        sorted_comments = sorted(comments, key=lambda c: c.get("createdAt", ""))

        for comment in sorted_comments:
            linear_comment_id = comment["id"]
            if is_comment_migrated(state, linear_comment_id):
                continue

            # Build comment HTML with attribution
            user = comment.get("user") or {}
            author = user.get("name", "Unknown")
            date = comment.get("createdAt", "")[:10]
            body_html = md_to_html(comment.get("body", ""))

            attribution = f'<p><em>Originally by {author} on {date}</em></p>'
            full_html = attribution + body_html

            try:
                result = plane.create_comment(LW_PROJECT_ID, plane_issue_id, full_html)
                record_comment(state, linear_comment_id, result["id"], linear_issue_id)
                created += 1
            except Exception as e:
                print(f"  FAILED comment {linear_comment_id}: {e}")
                record_failure(state, "comment", linear_comment_id, str(e))

    print(f"\nComments: {created} created")


def cmd_import_docs(args):
    """Import Linear documents as Plane pages."""
    data = load_export()
    plane = get_plane_client()
    state = load_state()

    docs = data.get("documents", [])
    if not docs:
        print("No documents to import.")
        return

    print(f"Importing {len(docs)} documents as pages...")
    created = 0
    for doc in docs:
        linear_doc_id = doc["id"]
        title = doc["title"]

        if is_page_migrated(state, linear_doc_id):
            continue

        # Convert content
        content_html = md_to_html(doc.get("content", ""))

        # Add metadata header
        author = doc.get("creator", {}).get("name", "Unknown")
        date = doc.get("createdAt", "")[:10]
        meta = f'<p><em>Migrated from Linear document. Author: {author}, Created: {date}</em></p><hr/>'
        full_html = meta + content_html

        try:
            result = plane.create_page(LW_PROJECT_ID, title, full_html)
            record_page(state, linear_doc_id, result["id"], title)
            created += 1
            print(f"  Created page: {title}")
        except Exception as e:
            print(f"  FAILED ({title}): {e}")
            record_failure(state, "document", linear_doc_id, str(e))

    print(f"\nDocuments: {created} pages created")


def cmd_import_attachments(args):
    """Import attachments as work item links."""
    data = load_export()
    plane = get_plane_client()
    state = load_state()

    issues = data.get("issues", [])
    total_attachments = 0
    created = 0

    for issue in issues:
        attachments = issue.get("attachments", {}).get("nodes", [])
        if not attachments:
            continue

        plane_issue_id = state.get("issue_map", {}).get(issue["id"])
        if not plane_issue_id:
            continue

        for att in attachments:
            total_attachments += 1
            url = att.get("url", "")
            title = att.get("title", "Attachment")
            if len(title) > 255:
                title = title[:252] + "..."
            if not url:
                continue

            try:
                plane.create_work_item_link(LW_PROJECT_ID, plane_issue_id, url, title)
                created += 1
            except Exception as e:
                print(f"  FAILED attachment ({title}): {e}")
                record_failure(state, "attachment", att.get("id", ""), str(e))

    print(f"Attachments: {created}/{total_attachments} linked")


def cmd_import_all(args):
    """Run all import phases in order."""
    print("=" * 60)
    print("Phase 1: Labels")
    print("=" * 60)
    cmd_import_labels(args)

    print("\n" + "=" * 60)
    print("Phase 2: Issues")
    print("=" * 60)
    cmd_import_issues(args)

    print("\n" + "=" * 60)
    print("Phase 3: Comments")
    print("=" * 60)
    cmd_import_comments(args)

    print("\n" + "=" * 60)
    print("Phase 4: Attachments")
    print("=" * 60)
    cmd_import_attachments(args)

    print("\n" + "=" * 60)
    print("Phase 5: Documents → Pages")
    print("=" * 60)
    cmd_import_docs(args)

    state = load_state()
    state["phase"] = "imported"
    save_state(state)
    print("\nAll import phases complete!")


# =============================================================================
# Phase 3: Verify
# =============================================================================

def cmd_verify(args):
    """Compare counts between Linear export and Plane."""
    data = load_export()
    state = load_state()

    linear_issues = len(data.get("issues", []))
    linear_comments = sum(len(v) for v in data.get("comments", {}).values())
    linear_labels = len(data.get("labels", []))
    linear_docs = len(data.get("documents", []))

    plane_issues = len(state.get("created_work_items", []))
    plane_comments = len(state.get("created_comments", []))
    plane_labels = len(state.get("created_labels", []))
    plane_pages = len(state.get("created_pages", []))
    failed = len(state.get("failed", []))

    print("Verification Report")
    print("=" * 50)
    print(f"{'Item':<20} {'Linear':>10} {'Plane':>10} {'Match':>10}")
    print("-" * 50)
    print(f"{'Issues':<20} {linear_issues:>10} {plane_issues:>10} {'OK' if linear_issues == plane_issues else 'MISMATCH':>10}")
    print(f"{'Comments':<20} {linear_comments:>10} {plane_comments:>10} {'OK' if linear_comments == plane_comments else 'MISMATCH':>10}")
    print(f"{'Labels':<20} {linear_labels:>10} {plane_labels:>10} {'OK' if linear_labels == plane_labels else 'MISMATCH':>10}")
    print(f"{'Documents→Pages':<20} {linear_docs:>10} {plane_pages:>10} {'OK' if linear_docs == plane_pages else 'MISMATCH':>10}")
    print("-" * 50)
    print(f"{'Failed items':<20} {failed:>10}")

    if failed:
        print("\nFailed items:")
        for f in state["failed"][:20]:
            print(f"  [{f['type']}] {f['id']}: {f['error'][:80]}")
        if len(state["failed"]) > 20:
            print(f"  ... and {len(state['failed']) - 20} more")


# =============================================================================
# Retry & Status
# =============================================================================

def cmd_retry_failed(args):
    """Retry failed items."""
    data = load_export()
    plane = get_plane_client()
    state = load_state()

    failed = state.get("failed", [])
    if not failed:
        print("No failed items to retry.")
        return

    # Group by type
    by_type = {}
    for f in failed:
        by_type.setdefault(f["type"], []).append(f)

    # Clear failed list (will re-add any that still fail)
    state["failed"] = []
    save_state(state)

    # Rebuild lookup data
    issue_by_id = {i["id"]: i for i in data.get("issues", [])}
    label_by_id = {l["id"]: l for l in data.get("labels", [])}
    doc_by_id = {d["id"]: d for d in data.get("documents", [])}

    retried = 0
    still_failed = 0

    for item_type, items in by_type.items():
        print(f"\nRetrying {len(items)} {item_type}(s)...")
        for item in items:
            item_id = item["id"]
            try:
                if item_type == "label" and item_id in label_by_id:
                    label = label_by_id[item_id]
                    if not is_label_migrated(state, item_id):
                        result = plane.create_label(LW_PROJECT_ID, label["name"], label.get("color", "#6b7280"))
                        record_label(state, item_id, result["id"], label["name"])
                        retried += 1

                elif item_type == "issue" and item_id in issue_by_id:
                    if not is_issue_migrated(state, item_id):
                        # Re-run through the same logic (simplified)
                        issue = issue_by_id[item_id]
                        plane_state_id = map_linear_state(issue["state"]["name"], issue["state"]["type"])
                        plane_priority = map_linear_priority(issue.get("priority", 0))
                        description_html = md_to_html(issue.get("description"))
                        meta = f'<p><em>Migrated from Linear: {issue.get("identifier", "")}</em></p>'
                        work_item_data = {
                            "state": plane_state_id,
                            "priority": plane_priority,
                            "description_html": meta + (description_html or ""),
                        }
                        result = plane.create_work_item(LW_PROJECT_ID, issue["title"], **work_item_data)
                        record_issue(state, item_id, issue.get("identifier", ""), result["id"], issue["title"])
                        retried += 1

                elif item_type == "document" and item_id in doc_by_id:
                    if not is_page_migrated(state, item_id):
                        doc = doc_by_id[item_id]
                        content_html = md_to_html(doc.get("content", ""))
                        author = doc.get("creator", {}).get("name", "Unknown")
                        date = doc.get("createdAt", "")[:10]
                        meta = f'<p><em>Migrated from Linear. Author: {author}, Created: {date}</em></p><hr/>'
                        result = plane.create_page(LW_PROJECT_ID, doc["title"], meta + content_html)
                        record_page(state, item_id, result["id"], doc["title"])
                        retried += 1

                elif item_type == "comment":
                    if not is_comment_migrated(state, item_id):
                        # Find the comment in export data
                        for issue_id, comments in data.get("comments", {}).items():
                            for c in comments:
                                if c["id"] == item_id:
                                    plane_issue_id = state.get("issue_map", {}).get(issue_id)
                                    if plane_issue_id:
                                        author = c.get("user", {}).get("name", "Unknown")
                                        date = c.get("createdAt", "")[:10]
                                        body_html = md_to_html(c.get("body", ""))
                                        full_html = f'<p><em>Originally by {author} on {date}</em></p>' + body_html
                                        result = plane.create_comment(LW_PROJECT_ID, plane_issue_id, full_html)
                                        record_comment(state, item_id, result["id"], issue_id)
                                        retried += 1
                                    break
                            else:
                                continue
                            break

                else:
                    print(f"  Skipping unknown type: {item_type} ({item_id})")

            except Exception as e:
                print(f"  Still failing [{item_type}] {item_id}: {e}")
                record_failure(state, item_type, item_id, str(e))
                still_failed += 1

    print(f"\nRetried: {retried}, still failed: {still_failed}")


def cmd_status(args):
    """Show migration progress."""
    state = load_state()

    print(f"Phase: {state.get('phase', 'new')}")
    print(f"Labels: {len(state.get('created_labels', []))} (mapped: {len(state.get('label_map', {}))})")
    print(f"Issues: {len(state.get('created_work_items', []))}")
    print(f"Comments: {len(state.get('created_comments', []))}")
    print(f"Pages: {len(state.get('created_pages', []))}")
    print(f"Failed: {len(state.get('failed', []))}")
    print(f"Skipped: {len(state.get('skipped', []))}")

    failed = state.get("failed", [])
    if failed:
        print("\nRecent failures:")
        for f in failed[:10]:
            print(f"  [{f['type']}] {f['id']}: {f['error'][:80]}")
        if len(failed) > 10:
            print(f"  ... and {len(failed) - 10} more")


# =============================================================================
# CLI
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Migrate Linear 'Lefty Workout App' project to Plane 'Liftcraft' (LW)"
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--inventory", action="store_true",
                       help="Phase 0: Query Linear, show counts and structure")
    group.add_argument("--export", action="store_true",
                       help="Phase 1: Export all Linear data to linear_export.json")
    group.add_argument("--import-all", action="store_true",
                       help="Phase 2: Import everything (labels → issues → comments → docs)")
    group.add_argument("--import-labels", action="store_true",
                       help="Import only labels")
    group.add_argument("--import-issues", action="store_true",
                       help="Import only issues")
    group.add_argument("--import-comments", action="store_true",
                       help="Import only comments")
    group.add_argument("--import-docs", action="store_true",
                       help="Import only documents as Plane pages")
    group.add_argument("--import-attachments", action="store_true",
                       help="Import only attachments as work item links")
    group.add_argument("--verify", action="store_true",
                       help="Phase 3: Compare counts between Linear and Plane")
    group.add_argument("--retry-failed", action="store_true",
                       help="Retry previously failed items")
    group.add_argument("--status", action="store_true",
                       help="Show migration progress")

    args = parser.parse_args()

    if args.inventory:
        cmd_inventory(args)
    elif args.export:
        cmd_export(args)
    elif args.import_all:
        cmd_import_all(args)
    elif args.import_labels:
        cmd_import_labels(args)
    elif args.import_issues:
        cmd_import_issues(args)
    elif args.import_comments:
        cmd_import_comments(args)
    elif args.import_docs:
        cmd_import_docs(args)
    elif args.import_attachments:
        cmd_import_attachments(args)
    elif args.verify:
        cmd_verify(args)
    elif args.retry_failed:
        cmd_retry_failed(args)
    elif args.status:
        cmd_status(args)


if __name__ == "__main__":
    main()
