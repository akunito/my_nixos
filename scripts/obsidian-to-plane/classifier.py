import os
import json
from config import (
    VAULT_PATH, IAKU_PROJECT_ID, AWN_PROJECT_ID,
    SKIP_DIRS, SKIP_FILES, MIN_FILE_SIZE_BYTES,
    WORK_KEYWORDS, IT_DOC_CATEGORIES, AWN_CATEGORIES,
    CLASSIFICATION_FILE,
)


def classify_file(rel_path: str, filename: str) -> tuple[str, str, str]:
    """Classify a file into (project_id, category_prefix, page_name).

    Returns (project_id, category, cleaned_name).
    """
    name = filename.rsplit(".md", 1)[0] if filename.endswith(".md") else filename

    # Directory-based routing
    if rel_path.startswith("01 - Documentation/IT Documentation/Source/"):
        category = _get_category(name, IT_DOC_CATEGORIES, "[IT Doc]")
        return IAKU_PROJECT_ID, category, name

    if rel_path.startswith("01 - Documentation/Schenker Documentation/"):
        category = _get_category(name, AWN_CATEGORIES, "[Schenker]")
        return AWN_PROJECT_ID, category, name

    if rel_path.startswith("00 - Kanban/source/"):
        # Check if work-related or infra-related
        if _matches_keywords(name, WORK_KEYWORDS):
            category = _get_category(name, AWN_CATEGORIES, "[Work]")
            return AWN_PROJECT_ID, category, name
        else:
            category = _get_category(name, IT_DOC_CATEGORIES, "[Infra]")
            return IAKU_PROJECT_ID, category, name

    if rel_path.startswith("image/") and filename.endswith(".md"):
        category = _get_category(name, AWN_CATEGORIES, "[Work]")
        return AWN_PROJECT_ID, category, name

    if rel_path.startswith("Excalidraw/"):
        return IAKU_PROJECT_ID, "[Diagram]", name

    if rel_path.startswith("00b - Canvas/"):
        return IAKU_PROJECT_ID, "[Diagram]", name

    # Root-level files: keyword-based
    if _matches_keywords(name, WORK_KEYWORDS):
        category = _get_category(name, AWN_CATEGORIES, "[Work]")
        return AWN_PROJECT_ID, category, name

    # Default to IAKU
    category = _get_category(name, IT_DOC_CATEGORIES, "[General]")
    return IAKU_PROJECT_ID, category, name


def _matches_keywords(text: str, keywords: list) -> bool:
    for kw in keywords:
        if kw.lower() in text.lower():
            return True
    return False


def _get_category(name: str, category_map: dict, default: str) -> str:
    for keyword, category in category_map.items():
        if keyword.lower() in name.lower():
            return category
    return default


def scan_vault() -> list[dict]:
    """Scan the vault and return a list of file entries."""
    entries = []

    for root, dirs, files in os.walk(VAULT_PATH):
        # Skip excluded directories
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]

        for filename in sorted(files):
            if not filename.endswith(".md"):
                continue
            if filename in SKIP_FILES:
                continue

            filepath = os.path.join(root, filename)
            rel_path = os.path.relpath(filepath, VAULT_PATH)

            # Skip kanban boards (already migrated or handled separately)
            if rel_path == "00 - Kanban/Kanban Work.md":
                continue  # handled by kanban_parser
            if rel_path.startswith("01 - Documentation/IT Documentation/") and not rel_path.startswith("01 - Documentation/IT Documentation/Source/"):
                # Root files in IT Documentation (not Source/) - include them
                pass

            # Check file size
            size = os.path.getsize(filepath)
            if size < MIN_FILE_SIZE_BYTES:
                entries.append({
                    "path": rel_path,
                    "filename": filename,
                    "size": size,
                    "skip": True,
                    "skip_reason": f"Too small ({size} bytes)",
                    "project": None,
                    "category": None,
                    "page_name": None,
                })
                continue

            project_id, category, page_name = classify_file(rel_path, filename)
            entries.append({
                "path": rel_path,
                "filename": filename,
                "size": size,
                "skip": False,
                "skip_reason": None,
                "project": "IAKU" if project_id == IAKU_PROJECT_ID else "AWN",
                "project_id": project_id,
                "category": category,
                "page_name": f"{category} {page_name}",
            })

    return entries


def generate_classification(output_path: str = CLASSIFICATION_FILE):
    """Generate classification review JSON file."""
    entries = scan_vault()

    iaku_count = sum(1 for e in entries if e.get("project") == "IAKU")
    awn_count = sum(1 for e in entries if e.get("project") == "AWN")
    skip_count = sum(1 for e in entries if e.get("skip"))

    result = {
        "summary": {
            "total_files": len(entries),
            "iaku_pages": iaku_count,
            "awn_pages": awn_count,
            "skipped": skip_count,
        },
        "files": entries,
    }

    with open(output_path, "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"Classification saved to {output_path}")
    print(f"  Total: {len(entries)}, IAKU: {iaku_count}, AWN: {awn_count}, Skipped: {skip_count}")
    return result


def load_classification(path: str = CLASSIFICATION_FILE) -> list[dict]:
    """Load the reviewed classification file."""
    with open(path) as f:
        data = json.load(f)
    return [e for e in data["files"] if not e.get("skip")]
