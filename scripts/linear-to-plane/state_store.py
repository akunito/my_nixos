"""JSON-based resumable state tracking for Linear→Plane migration."""

import json
import os
from config import STATE_FILE


def load_state() -> dict:
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return _empty_state()


def _empty_state() -> dict:
    return {
        "phase": "new",
        "label_map": {},       # linear_label_id → plane_label_id
        "issue_map": {},       # linear_issue_id → plane_issue_id
        "identifier_map": {},  # linear_identifier (e.g. "AKP-42") → plane_issue_id
        "created_work_items": [],
        "created_pages": [],
        "created_comments": [],
        "created_labels": [],
        "failed": [],
        "skipped": [],
    }


def save_state(state: dict):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


# =============================================================================
# Labels
# =============================================================================
def is_label_migrated(state: dict, linear_label_id: str) -> bool:
    return linear_label_id in state["label_map"]


def record_label(state: dict, linear_label_id: str, plane_label_id: str, name: str):
    state["label_map"][linear_label_id] = plane_label_id
    state["created_labels"].append({
        "linear_id": linear_label_id,
        "plane_id": plane_label_id,
        "name": name,
    })
    save_state(state)


# =============================================================================
# Issues
# =============================================================================
def is_issue_migrated(state: dict, linear_issue_id: str) -> bool:
    return linear_issue_id in state["issue_map"]


def record_issue(state: dict, linear_issue_id: str, linear_identifier: str,
                 plane_issue_id: str, title: str):
    state["issue_map"][linear_issue_id] = plane_issue_id
    state["identifier_map"][linear_identifier] = plane_issue_id
    state["created_work_items"].append({
        "linear_id": linear_issue_id,
        "linear_identifier": linear_identifier,
        "plane_id": plane_issue_id,
        "title": title,
    })
    save_state(state)


# =============================================================================
# Comments
# =============================================================================
def is_comment_migrated(state: dict, linear_comment_id: str) -> bool:
    return any(c["linear_id"] == linear_comment_id for c in state["created_comments"])


def record_comment(state: dict, linear_comment_id: str, plane_comment_id: str,
                   linear_issue_id: str):
    state["created_comments"].append({
        "linear_id": linear_comment_id,
        "plane_id": plane_comment_id,
        "linear_issue_id": linear_issue_id,
    })
    save_state(state)


# =============================================================================
# Pages (Documents)
# =============================================================================
def is_page_migrated(state: dict, linear_doc_id: str) -> bool:
    return any(p["linear_id"] == linear_doc_id for p in state["created_pages"])


def record_page(state: dict, linear_doc_id: str, plane_page_id: str, title: str):
    state["created_pages"].append({
        "linear_id": linear_doc_id,
        "plane_id": plane_page_id,
        "title": title,
    })
    save_state(state)


# =============================================================================
# Failures & Skips
# =============================================================================
def record_failure(state: dict, item_type: str, item_id: str, error: str):
    state["failed"].append({
        "type": item_type,
        "id": item_id,
        "error": error,
    })
    save_state(state)


def record_skip(state: dict, item_type: str, item_id: str, reason: str):
    state["skipped"].append({
        "type": item_type,
        "id": item_id,
        "reason": reason,
    })
    save_state(state)
