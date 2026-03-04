import re

PLACEHOLDER_RE = re.compile(r'\{\{WIKILINK:(.+?)\}\}')
PLANE_BASE = "https://plane.akunito.com"
WORKSPACE = "akuworkspace"


def resolve_wikilinks(html: str, page_map: dict) -> str:
    """Replace {{WIKILINK:target|display}} with actual Plane page links.

    page_map: dict mapping source_name -> {"page_id": str, "project": str}
    """
    def replacer(match):
        content = match.group(1)
        if "|" in content:
            target, display = content.split("|", 1)
        else:
            target = content
            display = target.split("/")[-1]

        # Try exact match on last path segment
        lookup_name = target.split("/")[-1]
        entry = page_map.get(lookup_name)

        if entry:
            page_id = entry["page_id"]
            url = f"{PLANE_BASE}/{WORKSPACE}/pages/{page_id}"
            return f'<a href="{url}">{display}</a>'
        else:
            return f'<em>[Link: {display}]</em>'

    return PLACEHOLDER_RE.sub(replacer, html)


def has_unresolved_links(html: str) -> bool:
    return bool(PLACEHOLDER_RE.search(html))
