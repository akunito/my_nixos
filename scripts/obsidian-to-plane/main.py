#!/usr/bin/env python3
"""Obsidian vault to Plane migration script."""

import argparse
import os
import sys

from config import (
    VAULT_PATH, IAKU_PROJECT_ID, AWN_PROJECT_ID,
    API_DELAY_SECONDS, CLASSIFICATION_FILE,
    read_plane_token, PLANE_BASE_URL, WORKSPACE_SLUG,
    get_nextcloud_share_url,
)
from classifier import generate_classification, load_classification, scan_vault
from converter import ObsidianConverter, convert_excalidraw
from image_resolver import ImageResolver
from link_resolver import resolve_wikilinks
from kanban_parser import parse_kanban, item_to_work_item_data
from plane_client import PlaneClient
from state_store import (
    load_state, save_state, is_already_migrated,
    record_page, record_work_item, record_failure, record_skip,
    build_page_map,
)


def cmd_classify(args):
    """Generate classification review file."""
    print("Scanning vault and classifying files...")
    generate_classification()
    print(f"\nReview the file at: {CLASSIFICATION_FILE}")
    print("Edit 'skip', 'project', 'category', 'page_name' fields as needed.")
    print("Then run: python main.py --migrate")


def cmd_test_sample(args):
    """Migrate a small sample of files for testing."""
    n = args.test_sample
    token = read_plane_token()
    client = PlaneClient(PLANE_BASE_URL, WORKSPACE_SLUG, token, API_DELAY_SECONDS)
    resolver = ImageResolver()
    converter = ObsidianConverter(resolver)
    state = load_state()

    # If classification exists, use it; otherwise scan
    if os.path.exists(CLASSIFICATION_FILE):
        entries = load_classification()
    else:
        entries = [e for e in scan_vault() if not e.get("skip")]

    # Pick representative samples
    sample = entries[:n]
    print(f"Testing with {len(sample)} files...")

    for entry in sample:
        _migrate_entry(entry, client, converter, state)

    print(f"\nTest complete. Created {len(state['created_pages'])} pages.")
    print("Check Plane UI to verify rendering.")


def cmd_migrate(args):
    """Run full migration pass 1 (create pages)."""
    if not os.path.exists(CLASSIFICATION_FILE):
        print("Classification file not found. Run --classify-only first.")
        sys.exit(1)

    token = read_plane_token()
    client = PlaneClient(PLANE_BASE_URL, WORKSPACE_SLUG, token, API_DELAY_SECONDS)
    resolver = ImageResolver()
    converter = ObsidianConverter(resolver)
    state = load_state()

    entries = load_classification()
    total = len(entries)
    print(f"Migrating {total} files...")

    for i, entry in enumerate(entries, 1):
        rel_path = entry["path"]
        if is_already_migrated(state, rel_path):
            continue

        print(f"  [{i}/{total}] {entry['page_name']}")
        _migrate_entry(entry, client, converter, state)

    state["phase"] = "pass1_done"
    save_state(state)

    created = len(state["created_pages"])
    failed = len(state["failed"])
    print(f"\nPass 1 complete: {created} pages created, {failed} failures.")


def _migrate_entry(entry: dict, client: PlaneClient, converter: ObsidianConverter, state: dict):
    """Migrate a single file entry."""
    rel_path = entry["path"]
    filepath = os.path.join(VAULT_PATH, rel_path)
    page_name = entry["page_name"]
    project_id = entry.get("project_id")

    if not project_id:
        project_id = IAKU_PROJECT_ID if entry["project"] == "IAKU" else AWN_PROJECT_ID

    try:
        with open(filepath, encoding="utf-8", errors="replace") as f:
            content = f.read()

        # Handle Excalidraw files
        if ".excalidraw" in rel_path.lower():
            nc_url = get_nextcloud_share_url(rel_path)
            html = convert_excalidraw(content, entry["filename"], nc_url)
            has_links = False
        else:
            html, has_links = converter.convert(content)

        # Create page
        result = client.create_page(project_id, page_name, html)
        page_id = result["id"]

        record_page(state, rel_path, entry["filename"].rsplit(".md", 1)[0],
                     entry["project"], page_id, entry["category"], has_links)

    except Exception as e:
        print(f"    FAILED: {e}")
        record_failure(state, rel_path, str(e))


def cmd_resolve_links(args):
    """Pass 2: resolve wikilink placeholders in created pages."""
    token = read_plane_token()
    client = PlaneClient(PLANE_BASE_URL, WORKSPACE_SLUG, token, API_DELAY_SECONDS)
    state = load_state()
    page_map = build_page_map(state)

    pages_with_links = [p for p in state["created_pages"]
                        if p.get("has_unresolved_links") and p["status"] == "created"]

    if not pages_with_links:
        print("No pages with unresolved links.")
        return

    print(f"Resolving links in {len(pages_with_links)} pages...")
    resolved = 0

    for i, page in enumerate(pages_with_links, 1):
        project_id = IAKU_PROJECT_ID if page["project"] == "IAKU" else AWN_PROJECT_ID
        page_id = page["page_id"]

        try:
            # Fetch current page content
            result = client._request("GET", f"projects/{project_id}/pages/{page_id}/")
            current_html = result.get("description_html", "")

            if "{{WIKILINK:" not in current_html:
                page["status"] = "links_resolved"
                page["has_unresolved_links"] = False
                continue

            updated_html = resolve_wikilinks(current_html, page_map)
            client.update_page(project_id, page_id, updated_html)

            page["status"] = "links_resolved"
            page["has_unresolved_links"] = False
            resolved += 1

            if i % 10 == 0:
                print(f"  [{i}/{len(pages_with_links)}] resolved...")
                save_state(state)

        except Exception as e:
            print(f"  Failed to resolve links for {page['source_name']}: {e}")

    save_state(state)
    print(f"Resolved links in {resolved} pages.")


def cmd_migrate_kanban(args):
    """Parse Kanban Work.md and create work items in AWN."""
    kanban_path = os.path.join(VAULT_PATH, "00 - Kanban/Kanban Work.md")
    if not os.path.exists(kanban_path):
        print(f"Kanban file not found: {kanban_path}")
        sys.exit(1)

    token = read_plane_token()
    client = PlaneClient(PLANE_BASE_URL, WORKSPACE_SLUG, token, API_DELAY_SECONDS)
    state = load_state()

    print("Parsing Kanban Work.md...")
    items = parse_kanban(kanban_path)
    print(f"Found {len(items)} kanban cards.")

    created = 0
    for item in items:
        title = item["title"]
        if not title or len(title) < 2:
            continue

        # Check if already created
        already = any(w["title"] == title for w in state.get("created_work_items", []))
        if already:
            continue

        data = item_to_work_item_data(item)

        try:
            result = client.create_work_item(AWN_PROJECT_ID, title, **data)
            record_work_item(state, title, item["column"], result["id"])
            created += 1
            print(f"  [{created}] {item['column']}: {title}")
        except Exception as e:
            print(f"  FAILED ({title}): {e}")
            record_failure(state, f"kanban:{title}", str(e))

    print(f"\nCreated {created} work items in AWN.")


def cmd_retry_failed(args):
    """Retry previously failed items."""
    state = load_state()
    failed = state.get("failed", [])
    if not failed:
        print("No failed items to retry.")
        return

    token = read_plane_token()
    client = PlaneClient(PLANE_BASE_URL, WORKSPACE_SLUG, token, API_DELAY_SECONDS)
    resolver = ImageResolver()
    converter = ObsidianConverter(resolver)

    # Re-classify and retry page failures
    page_failures = [f for f in failed if not f["source_path"].startswith("kanban:")]
    print(f"Retrying {len(page_failures)} failed pages...")

    # Remove from failed list and re-attempt
    state["failed"] = [f for f in failed if f["source_path"].startswith("kanban:")]
    save_state(state)

    entries = scan_vault()
    entry_map = {e["path"]: e for e in entries}

    for failure in page_failures:
        path = failure["source_path"]
        entry = entry_map.get(path)
        if entry and not entry.get("skip"):
            print(f"  Retrying: {path}")
            _migrate_entry(entry, client, converter, state)


def cmd_status(args):
    """Show migration progress."""
    state = load_state()
    pages = state.get("created_pages", [])
    items = state.get("created_work_items", [])
    failed = state.get("failed", [])
    skipped = state.get("skipped", [])

    iaku_pages = sum(1 for p in pages if p["project"] == "IAKU")
    awn_pages = sum(1 for p in pages if p["project"] == "AWN")
    resolved = sum(1 for p in pages if p["status"] == "links_resolved")
    unresolved = sum(1 for p in pages if p.get("has_unresolved_links"))

    print(f"Phase: {state.get('phase', 'new')}")
    print(f"Pages created: {len(pages)} (IAKU: {iaku_pages}, AWN: {awn_pages})")
    print(f"Links resolved: {resolved}, Unresolved: {unresolved}")
    print(f"Work items: {len(items)}")
    print(f"Failed: {len(failed)}")
    print(f"Skipped: {len(skipped)}")

    if failed:
        print("\nFailed items:")
        for f in failed[:10]:
            print(f"  - {f['source_path']}: {f['error'][:80]}")
        if len(failed) > 10:
            print(f"  ... and {len(failed) - 10} more")


def main():
    parser = argparse.ArgumentParser(description="Migrate Obsidian vault to Plane pages")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--classify-only", action="store_true", help="Generate classification review file")
    group.add_argument("--test-sample", type=int, metavar="N", help="Migrate N sample files for testing")
    group.add_argument("--migrate", action="store_true", help="Run full migration (pass 1)")
    group.add_argument("--resolve-links", action="store_true", help="Resolve wikilinks (pass 2)")
    group.add_argument("--migrate-kanban", action="store_true", help="Create work items from Kanban Work.md")
    group.add_argument("--retry-failed", action="store_true", help="Retry previously failed items")
    group.add_argument("--status", action="store_true", help="Show migration progress")

    parser.add_argument("--nextcloud-share-token", help="Nextcloud public share token for images")

    args = parser.parse_args()

    # Set share token if provided
    if args.nextcloud_share_token:
        import config
        config.NEXTCLOUD_SHARE_TOKEN = args.nextcloud_share_token
        os.environ["NEXTCLOUD_SHARE_TOKEN"] = args.nextcloud_share_token

    if args.classify_only:
        cmd_classify(args)
    elif args.test_sample:
        cmd_test_sample(args)
    elif args.migrate:
        cmd_migrate(args)
    elif args.resolve_links:
        cmd_resolve_links(args)
    elif args.migrate_kanban:
        cmd_migrate_kanban(args)
    elif args.retry_failed:
        cmd_retry_failed(args)
    elif args.status:
        cmd_status(args)


if __name__ == "__main__":
    main()
