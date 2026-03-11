import json
import os
from config import STATE_FILE


def load_state() -> dict:
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return {
        "phase": "new",
        "created_pages": [],
        "created_work_items": [],
        "failed": [],
        "skipped": [],
    }


def save_state(state: dict):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


def is_already_migrated(state: dict, source_path: str) -> bool:
    for entry in state["created_pages"]:
        if entry["source_path"] == source_path:
            return True
    return False


def record_page(state: dict, source_path: str, source_name: str, project: str,
                page_id: str, category: str, has_links: bool):
    state["created_pages"].append({
        "source_path": source_path,
        "source_name": source_name,
        "project": project,
        "page_id": page_id,
        "category": category,
        "has_unresolved_links": has_links,
        "status": "created",
    })
    save_state(state)


def record_work_item(state: dict, title: str, column: str, item_id: str):
    state["created_work_items"].append({
        "title": title,
        "column": column,
        "work_item_id": item_id,
    })
    save_state(state)


def record_failure(state: dict, source_path: str, error: str):
    state["failed"].append({
        "source_path": source_path,
        "error": error,
    })
    save_state(state)


def record_skip(state: dict, source_path: str, reason: str):
    state["skipped"].append({
        "source_path": source_path,
        "reason": reason,
    })
    save_state(state)


def build_page_map(state: dict) -> dict:
    """Build mapping: source_name -> (page_id, project)."""
    page_map = {}
    for entry in state["created_pages"]:
        page_map[entry["source_name"]] = {
            "page_id": entry["page_id"],
            "project": entry["project"],
        }
    return page_map
