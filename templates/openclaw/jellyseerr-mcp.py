#!/usr/bin/env python3
"""Jellyseerr MCP server for OpenClaw.
Exposes: search, trending, discover, request media, watch history.
Blocks: user management, settings, admin operations.
Rate-limited: request_media (5/hour). Rate state persists to disk.
"""
import os, json, time, fcntl, urllib.request, urllib.parse
from pathlib import Path
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

BASE_URL = os.environ["JELLYSEERR_URL"]
API_KEY = os.environ["JELLYSEERR_API_KEY"]
ALLOWED_PATH_PREFIXES = ("/search", "/media", "/trending", "/discover", "/request")
BLOCKED_PATH_PREFIXES = ("/user", "/admin", "/settings", "/auth", "/notification")

# --- Persistent rate limiter (file-backed, survives process restarts) ---
RATE_LIMITS = {"request_media": {"max": 5, "window": 3600}}
_RATE_FILE = Path(os.environ.get("HOME", "/home/node")) / ".openclaw/mcp/.ratelimit-jellyseerr.json"

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
        # Fail-CLOSED permanently: deny if rate state is unreadable (no auto-reset — see plane-restricted-mcp)
        return f"RATE LIMITED: {op} denied — rate state file corrupted ({type(e).__name__}). Manual fix: delete {_RATE_FILE}"
    return None

server = Server("jellyseerr")

def _api(method: str, path: str, body: dict | None = None) -> dict:
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

@server.list_tools()
async def list_tools():
    return [
        Tool(name="search_media", description="Search movies and TV shows",
             inputSchema={"type": "object", "properties": {
                 "query": {"type": "string"}
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
        Tool(name="request_media", description="Request a movie or TV show",
             inputSchema={"type": "object", "properties": {
                 "media_type": {"type": "string", "enum": ["movie", "tv"]},
                 "media_id": {"type": "integer"},
                 "seasons": {"type": "array", "items": {"type": "integer"}}
             }, "required": ["media_type", "media_id"]}),
        Tool(name="get_watch_history", description="Get recently watched/added media",
             inputSchema={"type": "object", "properties": {
                 "take": {"type": "integer", "default": 20}
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
            mid = arguments["media_id"]
            if not isinstance(mid, int) or mid < 0:
                return [TextContent(type="text", text="ERROR: media_id must be a positive integer")]
            body = {"mediaType": arguments["media_type"], "mediaId": mid}
            if "seasons" in arguments: body["seasons"] = arguments["seasons"]
            r = _api("POST", "/request", body)
        case "get_watch_history":
            r = _api("GET", f"/media?take={arguments.get('take', 20)}&sort=added&filter=available")
        case _:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]
    return [TextContent(type="text", text=json.dumps(r, indent=2, default=str))]

async def main():
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
