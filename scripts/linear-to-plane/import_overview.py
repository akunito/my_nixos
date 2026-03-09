#!/usr/bin/env python3
"""Import Linear project overview page into Plane."""

import markdown as md

from config import (
    read_linear_token, read_plane_token,
    LINEAR_DELAY_SECONDS, PLANE_DELAY_SECONDS,
    PLANE_BASE_URL, WORKSPACE_SLUG, LW_PROJECT_ID,
)
from linear_client import LinearClient
from plane_client import PlaneClient


def main():
    linear = LinearClient(read_linear_token(), LINEAR_DELAY_SECONDS)
    plane = PlaneClient(PLANE_BASE_URL, WORKSPACE_SLUG, read_plane_token(), PLANE_DELAY_SECONDS)

    print("Fetching project overview from Linear...")
    data = linear._query("""
        query($projectId: String!) {
            project(id: $projectId) {
                name
                content
                startDate
                state
                progress
                projectUpdates {
                    nodes {
                        body
                        createdAt
                        user { name }
                    }
                }
            }
        }
    """, {"projectId": "91bbda47-5659-4ceb-9d7c-a51978c29854"})

    proj = data["project"]
    content = proj.get("content", "") or ""
    updates = proj.get("projectUpdates", {}).get("nodes", [])

    progress_pct = (proj.get("progress", 0) or 0) * 100
    start_date = proj.get("startDate", "N/A")

    # Build full markdown
    parts = []
    parts.append(f"*Migrated from Linear project overview. Start: {start_date} | Progress: {progress_pct:.0f}%*")
    parts.append("")
    parts.append(content)

    if updates:
        parts.append("")
        parts.append("---")
        parts.append("# Project Updates")
        for u in sorted(updates, key=lambda x: x.get("createdAt", "")):
            date = u.get("createdAt", "")[:10]
            author = (u.get("user") or {}).get("name", "Unknown")
            body = u.get("body", "")
            parts.append("")
            parts.append(f"## {date} - {author}")
            parts.append(body)

    full_md = "\n".join(parts)

    # Convert to HTML
    html = md.markdown(full_md, extensions=["tables", "fenced_code", "nl2br"])

    print("Creating page in Plane...")
    result = plane.create_page(LW_PROJECT_ID, "Lefty Workout App — Project Overview", html)
    print(f"Created page: {result['id']}")
    print("Done!")


if __name__ == "__main__":
    main()
