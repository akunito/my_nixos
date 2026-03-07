#!/usr/bin/env python3
"""Jellyseerr + Jellyfin MCP server for OpenClaw.
Exposes: search, trending, discover, request media, watch history (Jellyfin).
Blocks: user management, settings, admin operations.
Rate-limited: request_media (20/hour). Rate state persists to disk.
"""
import os, json, time, fcntl, urllib.request, urllib.parse
from pathlib import Path
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

# --- Jellyseerr config ---
BASE_URL = os.environ["JELLYSEERR_URL"]
API_KEY = os.environ["JELLYSEERR_API_KEY"]
ALLOWED_PATH_PREFIXES = ("/search", "/media", "/trending", "/discover", "/request", "/tv", "/movie")
BLOCKED_PATH_PREFIXES = ("/user", "/admin", "/settings", "/auth", "/notification")

# --- Jellyfin config (optional — watch history) ---
JELLYFIN_URL = os.environ.get("JELLYFIN_URL", "")
JELLYFIN_KEY = os.environ.get("JELLYFIN_API_KEY", "")
JELLYFIN_USER_ID = os.environ.get("JELLYFIN_USER_ID", "")

# --- Persistent rate limiter (file-backed, survives process restarts) ---
RATE_LIMITS = {"request_media": {"max": 20, "window": 3600}}
_RATE_FILE = Path(os.environ.get("RATE_LIMIT_DIR", "/tmp")) / ".ratelimit-jellyseerr.json"

def _check_rate(op: str) -> str | None:
    if op not in RATE_LIMITS:
        return None
    cfg = RATE_LIMITS[op]
    now = time.time()
    _RATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    try:
        with open(_RATE_FILE, "a+") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.seek(0)
            data = json.loads(f.read() or "{}")
            timestamps = [t for t in data.get(op, []) if now - t < cfg["window"]]
            if len(timestamps) >= cfg["max"]:
                remaining = int(cfg["window"] - (now - timestamps[0]))
                return f"RATE LIMITED: {op} exceeded {cfg['max']}/{cfg['window']}s. Try again in {remaining}s."
            timestamps.append(now)
            data[op] = timestamps
            f.seek(0); f.truncate()
            f.write(json.dumps(data))
    except (json.JSONDecodeError, OSError) as e:
        # Corrupted or missing state — reset and allow the request
        try:
            _RATE_FILE.parent.mkdir(parents=True, exist_ok=True)
            with open(_RATE_FILE, "w") as f:
                json.dump({op: [now]}, f)
        except OSError:
            pass  # write failed — allow anyway, rate limiting is best-effort
    return None

server = Server("jellyseerr")

def _api(method: str, path: str, body: dict | None = None) -> dict:
    """Call Jellyseerr API."""
    path_base = path.split("?")[0]
    if any(path_base.startswith(b) for b in BLOCKED_PATH_PREFIXES):
        raise ValueError(f"Blocked path: {path_base}")
    if not any(path_base.startswith(a) for a in ALLOWED_PATH_PREFIXES):
        raise ValueError(f"Path not in allowlist: {path_base}")
    url = f"{BASE_URL}/api/v1{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "X-Api-Key": API_KEY, "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def _jellyfin_api(path: str) -> dict:
    """Call Jellyfin API (read-only)."""
    if not JELLYFIN_URL or not JELLYFIN_KEY:
        raise ValueError("Jellyfin not configured (JELLYFIN_URL / JELLYFIN_API_KEY missing)")
    sep = "&" if "?" in path else "?"
    url = f"{JELLYFIN_URL}{path}{sep}api_key={JELLYFIN_KEY}"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def _search_tmdb_id(title: str, media_type: str) -> tuple[int | None, str | None]:
    """Search Jellyseerr for a title and return (tmdb_id, matched_name) or (None, None)."""
    q = urllib.parse.quote(title)
    results = _api("GET", f"/search?query={q}&page=1&language=en")
    for r in results.get("results", []):
        if r.get("mediaType") == media_type:
            name = r.get("name") or r.get("title") or ""
            return r.get("id"), name
    return None, None


def _get_tv_seasons(tmdb_id: int) -> list[int]:
    """Fetch all season numbers (excluding specials/season 0) for a TV show."""
    details = _api("GET", f"/tv/{tmdb_id}")
    return [s["seasonNumber"] for s in details.get("seasons", []) if s.get("seasonNumber", 0) > 0]


@server.list_tools()
async def list_tools():
    return [
        Tool(name="search_media", description="Search movies and TV shows by title. ALWAYS use this before request_media to get the correct TMDB ID.",
             inputSchema={"type": "object", "properties": {
                 "query": {"type": "string", "description": "Title to search for"}
             }, "required": ["query"]}),
        Tool(name="get_requests", description="List media requests",
             inputSchema={"type": "object", "properties": {
                 "take": {"type": "integer", "default": 20},
                 "skip": {"type": "integer", "default": 0},
                 "filter": {"type": "string", "enum": ["all","approved","pending","available","unavailable"]}
             }}),
        Tool(name="get_request", description="Get details of a specific request",
             inputSchema={"type": "object", "properties": {
                 "request_id": {"type": "integer"}
             }, "required": ["request_id"]}),
        Tool(name="get_media", description="Get media item details",
             inputSchema={"type": "object", "properties": {
                 "media_id": {"type": "integer"}
             }, "required": ["media_id"]}),
        Tool(name="get_trending", description="Get trending movies or TV shows",
             inputSchema={"type": "object", "properties": {
                 "type": {"type": "string", "enum": ["movie", "tv"]},
                 "page": {"type": "integer", "default": 1}
             }, "required": ["type"]}),
        Tool(name="get_discover", description="Discover movies or TV by genre/year",
             inputSchema={"type": "object", "properties": {
                 "type": {"type": "string", "enum": ["movie", "tv"]},
                 "page": {"type": "integer", "default": 1},
                 "genre": {"type": "string"}, "year": {"type": "integer"}
             }, "required": ["type"]}),
        Tool(name="request_media",
             description="Request a movie or TV show. Provide 'title' to auto-search for the correct TMDB ID (recommended). For TV shows, seasons are auto-populated if not specified.",
             inputSchema={"type": "object", "properties": {
                 "media_type": {"type": "string", "enum": ["movie", "tv"]},
                 "title": {"type": "string", "description": "Title to search for. The tool will find the correct TMDB ID automatically. ALWAYS provide this."},
                 "media_id": {"type": "integer", "description": "TMDB ID. Only use if you got this from search_media results. Do NOT guess or memorize IDs."},
                 "seasons": {"type": "array", "items": {"type": "integer"}, "description": "Season numbers to request. Auto-populated for TV if omitted."}
             }, "required": ["media_type"]}),
        Tool(name="get_watch_history",
             description="Get Aku's watch history from Jellyfin — movies and TV shows that have been watched. Use type to filter by 'Movie' or 'Series'.",
             inputSchema={"type": "object", "properties": {
                 "type": {"type": "string", "enum": ["Movie", "Series", "Movie,Series"], "default": "Movie,Series", "description": "Media type to filter: Movie, Series, or both"},
                 "limit": {"type": "integer", "default": 20, "description": "Number of results (max 50)"}
             }}),
        Tool(name="get_library_recent",
             description="Get recently added media to the Jellyfin library (not necessarily watched).",
             inputSchema={"type": "object", "properties": {
                 "limit": {"type": "integer", "default": 20, "description": "Number of results (max 50)"}
             }}),
    ]

@server.call_tool()
async def call_tool(name: str, arguments: dict):
    match name:
        case "search_media":
            q = urllib.parse.quote(arguments["query"])
            r = _api("GET", f"/search?query={q}&page=1&language=en")
        case "get_requests":
            qs = urllib.parse.urlencode({k: v for k, v in arguments.items()})
            r = _api("GET", f"/request?{qs}")
        case "get_request":
            rid = arguments['request_id']
            if not isinstance(rid, int) or rid < 0:
                return [TextContent(type="text", text="ERROR: request_id must be a positive integer")]
            r = _api("GET", f"/request/{rid}")
        case "get_media":
            mid = arguments['media_id']
            if not isinstance(mid, int) or mid < 0:
                return [TextContent(type="text", text="ERROR: media_id must be a positive integer")]
            r = _api("GET", f"/media/{mid}")
        case "get_trending":
            r = _api("GET", f"/trending/{arguments['type']}?page={arguments.get('page',1)}")
        case "get_discover":
            t = arguments.pop("type")
            qs = urllib.parse.urlencode({k: v for k, v in arguments.items() if v})
            r = _api("GET", f"/discover/{t}?{qs}")
        case "request_media":
            if err := _check_rate("request_media"):
                return [TextContent(type="text", text=err)]

            media_type = arguments["media_type"]
            title = arguments.get("title")
            mid = arguments.get("media_id")

            # Resolve TMDB ID from title (preferred) or validate provided ID
            if title and not mid:
                mid, matched = _search_tmdb_id(title, media_type)
                if not mid:
                    return [TextContent(type="text", text=f"ERROR: No {media_type} found matching '{title}'. Try a different search term.")]
                info = f"Matched '{title}' → '{matched}' (TMDB {mid})"
            elif title and mid:
                # Validate: search and check if the ID matches
                found_id, matched = _search_tmdb_id(title, media_type)
                if found_id and found_id != mid:
                    info = f"WARNING: Title '{title}' maps to TMDB {found_id} ('{matched}'), not {mid}. Using correct ID {found_id}."
                    mid = found_id
                else:
                    info = f"Confirmed '{title}' = TMDB {mid}"
            elif mid:
                info = f"Using provided TMDB {mid} (no title verification)"
            else:
                return [TextContent(type="text", text="ERROR: Provide 'title' or 'media_id'. Title is strongly preferred.")]

            if not isinstance(mid, int) or mid < 0:
                return [TextContent(type="text", text="ERROR: media_id must be a positive integer")]

            body = {"mediaType": media_type, "mediaId": mid}

            # Auto-populate seasons for TV requests
            if media_type == "tv":
                seasons = arguments.get("seasons")
                if not seasons:
                    seasons = _get_tv_seasons(mid)
                    if not seasons:
                        return [TextContent(type="text", text=f"ERROR: Could not fetch seasons for TMDB {mid}. The show may not have aired yet.")]
                    info += f" | Auto-selected seasons: {seasons}"
                body["seasons"] = seasons

            r = _api("POST", "/request", body)
            # Prepend resolution info to help the agent understand what happened
            return [TextContent(type="text", text=f"{info}\n\n{json.dumps(r, indent=2, default=str)}")]

        case "get_watch_history":
            if not JELLYFIN_USER_ID:
                return [TextContent(type="text", text="ERROR: JELLYFIN_USER_ID not configured")]
            item_type = arguments.get("type", "Movie,Series")
            limit = min(int(arguments.get("limit", 20)), 50)
            r = _jellyfin_api(
                f"/Users/{JELLYFIN_USER_ID}/Items"
                f"?IsPlayed=true&IncludeItemTypes={item_type}"
                f"&SortBy=DatePlayed&SortOrder=Descending&Limit={limit}&Recursive=true"
                f"&Fields=DateLastMediaAdded,Overview,Genres,CommunityRating"
            )
            # Simplify response for the LLM
            items = []
            for i in r.get("Items", []):
                items.append({
                    "name": i.get("Name"),
                    "year": i.get("ProductionYear"),
                    "type": i.get("Type"),
                    "genres": i.get("Genres", []),
                    "rating": i.get("CommunityRating"),
                    "overview": (i.get("Overview") or "")[:200],
                })
            r = {"totalWatched": r.get("TotalRecordCount"), "showing": len(items), "items": items}

        case "get_library_recent":
            if not JELLYFIN_USER_ID:
                return [TextContent(type="text", text="ERROR: JELLYFIN_USER_ID not configured")]
            limit = min(int(arguments.get("limit", 20)), 50)
            r = _jellyfin_api(
                f"/Users/{JELLYFIN_USER_ID}/Items/Latest?Limit={limit}"
                f"&IncludeItemTypes=Movie,Series&Fields=Overview,Genres,CommunityRating"
            )
            # Simplify response
            items = []
            for i in (r if isinstance(r, list) else r.get("Items", [])):
                items.append({
                    "name": i.get("Name"),
                    "year": i.get("ProductionYear"),
                    "type": i.get("Type"),
                    "genres": i.get("Genres", []),
                    "rating": i.get("CommunityRating"),
                })
            r = {"count": len(items), "items": items}

        case _:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]
    return [TextContent(type="text", text=json.dumps(r, indent=2, default=str))]

async def main():
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
