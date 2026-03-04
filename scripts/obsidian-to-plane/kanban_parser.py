import re
from config import KANBAN_STATE_MAP, AWN_STATES

COLOR_RE = re.compile(r'~=\{(\w+)\}(.*?)=~', re.DOTALL)
WIKILINK_RE = re.compile(r'\[\[([^\]]+?)\]\]')


def parse_kanban(filepath: str) -> list[dict]:
    """Parse Kanban Work.md into a list of work item dicts."""
    with open(filepath) as f:
        lines = f.readlines()

    items = []
    current_column = None
    current_item = None
    in_frontmatter = False

    for line in lines:
        stripped = line.rstrip()

        # Skip frontmatter
        if stripped == "---":
            in_frontmatter = not in_frontmatter
            continue
        if in_frontmatter:
            continue

        # Skip kanban settings
        if stripped.startswith("%%"):
            continue

        # Detect column headers
        if stripped.startswith("## "):
            if current_item:
                items.append(current_item)
                current_item = None
            current_column = stripped[3:].strip()
            continue

        # Skip non-kanban content
        if current_column is None:
            continue

        # Detect task items
        if stripped.startswith("- [ ] ") or stripped.startswith("- [x] "):
            if current_item:
                items.append(current_item)

            is_done = stripped.startswith("- [x] ")
            raw_title = stripped[6:].strip()

            # Clean title: remove color syntax
            title = COLOR_RE.sub(r'\2', raw_title).strip()

            # If title is a wikilink, extract the text
            wl_match = WIKILINK_RE.match(title)
            if wl_match:
                title = wl_match.group(1).split("/")[-1]

            # Remove strikethrough
            title = title.replace("~~", "").strip()

            current_item = {
                "title": title,
                "column": current_column,
                "is_done": is_done,
                "description_lines": [],
                "raw_title": raw_title,
            }
        elif current_item and (stripped.startswith("\t") or stripped.startswith("    ")):
            # Indented content = description
            current_item["description_lines"].append(stripped.strip())
        elif stripped == "" and current_item:
            # Empty line within item
            pass
        elif stripped.startswith("**") and current_item is None:
            # Section labels like **Complete** - skip
            pass

    if current_item:
        items.append(current_item)

    return items


def item_to_work_item_data(item: dict) -> dict:
    """Convert a parsed kanban item to Plane work item creation data."""
    column = item["column"]
    state_name = KANBAN_STATE_MAP.get(column, "Backlog")
    state_id = AWN_STATES.get(state_name, AWN_STATES["Backlog"])

    # Override state for done items
    if item["is_done"] or column == "Done":
        state_id = AWN_STATES["Done"]
    if column == "Deprecated":
        state_id = AWN_STATES["Cancelled"]

    # Build description HTML
    desc_lines = item.get("description_lines", [])
    desc_html = ""
    if desc_lines:
        # Clean wikilinks and color syntax in description
        cleaned = []
        for line in desc_lines:
            line = COLOR_RE.sub(r'\2', line)
            line = WIKILINK_RE.sub(r'\1', line)
            if line.strip():
                cleaned.append(line)
        if cleaned:
            desc_html = "<p>" + "<br/>".join(cleaned) + "</p>"

    priority = "urgent" if column == "Important" else "none"

    data = {
        "state": state_id,
        "priority": priority,
        "external_source": "obsidian-migration",
    }
    if desc_html:
        data["description_html"] = desc_html

    return data
