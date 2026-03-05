#!/usr/bin/env python3
"""Restricted Plane MCP server for OpenClaw.
Only exposes read + create + comment operations.
Blocks: delete, update state, admin APIs.
Rate-limited: create_work_item (10/hour), create_work_item_comment (30/hour).
Rate state persists to disk — survives process restarts (MCP subprocess crashes/respawns).
"""
import os, json, re, time, fcntl, urllib.request, urllib.parse
from pathlib import Path
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

API_URL = os.environ["PLANE_API_URL"]
API_TOKEN = os.environ["PLANE_API_TOKEN"]
WORKSPACE = os.environ["PLANE_WORKSPACE_SLUG"]

# --- Input length validation (anti-payload-abuse) ---
MAX_BODY_LENGTH = 50_000  # 50KB — prevents resource exhaustion via massive payloads within rate limits
def _validate_body_length(arguments: dict, fields: list[str]) -> str | None:
    for f in fields:
        if f in arguments and len(str(arguments[f])) > MAX_BODY_LENGTH:
            return f"ERROR: {f} too long ({len(str(arguments[f]))} > {MAX_BODY_LENGTH} chars)"
    return None

# --- Input validation (anti-path-traversal) ---
_UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
def _validate_uuid(val: str, name: str):
    if not val or not _UUID_RE.match(val):
        raise ValueError(f"Invalid {name}: must be UUID format")

# --- Persistent rate limiter (file-backed, survives process restarts) ---
# MCP servers are spawned as subprocesses and can be killed/restarted at any time.
# In-memory rate state would reset to zero on restart, allowing spam loops to continue.
# This writes rate timestamps to a JSON file on the persistent volume.
RATE_LIMITS = {
    "create_work_item":         {"max": 10, "window": 3600},
    "create_work_item_comment": {"max": 30, "window": 3600},
}
_RATE_FILE = Path(os.environ.get("HOME", "/home/node")) / ".openclaw/mcp/.ratelimit-plane-restricted.json"

def _check_rate(op: str) -> str | None:
    if op not in RATE_LIMITS:
        return None
    cfg = RATE_LIMITS[op]
    now = time.time()
    _RATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    # File-locked read-modify-write
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
            # Atomic write: truncate + rewrite under lock
            f.seek(0); f.truncate()
            f.write(json.dumps(data))
    except (json.JSONDecodeError, OSError) as e:
        # Fail-CLOSED permanently: deny the operation if rate state is unreadable.
        # Do NOT auto-reset the file — an attacker could corrupt it, get one denied call,
        # then a clean slate with zero rate history. Stay broken until manual fix.
        return f"RATE LIMITED: {op} denied — rate state file corrupted ({type(e).__name__}). Manual fix: delete {_RATE_FILE}"
    return None

server = Server("plane-restricted")

def _api(method: str, path: str, body: dict | None = None) -> dict:
    if method not in ("GET", "POST"):
        raise ValueError(f"Method {method} not allowed (only GET, POST)")
    url = f"{API_URL}{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "X-Api-Key": API_TOKEN, "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())

def _v1(path: str) -> str:
    return f"/api/v1/workspaces/{WORKSPACE}/{path}"

def _internal(path: str) -> str:
    return f"/api/workspaces/{WORKSPACE}/{path}"

@server.list_tools()
async def list_tools():
    return [
        Tool(name="list_projects", description="List all projects",
             inputSchema={"type": "object", "properties": {}}),
        Tool(name="search_work_items", description="Search work items",
             inputSchema={"type": "object", "properties": {
                 "query": {"type": "string"}, "project_id": {"type": "string"}
             }, "required": ["query"]}),
        Tool(name="retrieve_work_item", description="Get a work item by ID",
             inputSchema={"type": "object", "properties": {
                 "project_id": {"type": "string"}, "work_item_id": {"type": "string"}
             }, "required": ["project_id", "work_item_id"]}),
        Tool(name="list_work_item_comments", description="List comments on a work item",
             inputSchema={"type": "object", "properties": {
                 "project_id": {"type": "string"}, "work_item_id": {"type": "string"}
             }, "required": ["project_id", "work_item_id"]}),
        Tool(name="create_work_item", description="Create a new work item (ticket)",
             inputSchema={"type": "object", "properties": {
                 "project_id": {"type": "string"}, "name": {"type": "string"},
                 "description_html": {"type": "string"},
                 "priority": {"type": "string", "enum": ["urgent","high","medium","low","none"]},
                 "state_id": {"type": "string"},
                 "label_ids": {"type": "array", "items": {"type": "string"}}
             }, "required": ["project_id", "name"]}),
        Tool(name="create_work_item_comment", description="Add a comment to a work item",
             inputSchema={"type": "object", "properties": {
                 "project_id": {"type": "string"}, "work_item_id": {"type": "string"},
                 "comment_html": {"type": "string"}
             }, "required": ["project_id", "work_item_id", "comment_html"]}),
        Tool(name="retrieve_project_page", description="Get a project page by ID",
             inputSchema={"type": "object", "properties": {
                 "project_id": {"type": "string"}, "page_id": {"type": "string"}
             }, "required": ["project_id", "page_id"]}),
        Tool(name="list_states", description="List workflow states for a project",
             inputSchema={"type": "object", "properties": {
                 "project_id": {"type": "string"}
             }, "required": ["project_id"]}),
        Tool(name="list_labels", description="List labels for a project",
             inputSchema={"type": "object", "properties": {
                 "project_id": {"type": "string"}
             }, "required": ["project_id"]}),
        Tool(name="list_cycles", description="List cycles for a project",
             inputSchema={"type": "object", "properties": {
                 "project_id": {"type": "string"}
             }, "required": ["project_id"]}),
        Tool(name="list_modules", description="List modules for a project",
             inputSchema={"type": "object", "properties": {
                 "project_id": {"type": "string"}
             }, "required": ["project_id"]}),
    ]

@server.call_tool()
async def call_tool(name: str, arguments: dict):
    pid = arguments.get("project_id", "")
    wid = arguments.get("work_item_id", "")
    # Validate UUIDs to prevent path traversal via crafted IDs
    try:
        if pid: _validate_uuid(pid, "project_id")
        if wid: _validate_uuid(wid, "work_item_id")
        if "page_id" in arguments: _validate_uuid(arguments["page_id"], "page_id")
    except ValueError as e:
        return [TextContent(type="text", text=f"ERROR: {e}")]
    match name:
        case "list_projects":
            r = _api("GET", _v1("projects/"))
        case "search_work_items":
            q = urllib.parse.quote(arguments["query"])
            path = _v1(f"search/?search={q}&type=work_item")
            if pid: path = _v1(f"projects/{pid}/work-items/?search={q}")
            r = _api("GET", path)
        case "retrieve_work_item":
            r = _api("GET", _v1(f"projects/{pid}/work-items/{wid}/"))
        case "list_work_item_comments":
            r = _api("GET", _v1(f"projects/{pid}/work-items/{wid}/comments/"))
        case "create_work_item":
            if err := _check_rate("create_work_item"):
                return [TextContent(type="text", text=err)]
            if err := _validate_body_length(arguments, ["name", "description_html"]):
                return [TextContent(type="text", text=err)]
            body = {k: v for k, v in arguments.items() if k != "project_id"}
            r = _api("POST", _v1(f"projects/{pid}/work-items/"), body)
        case "create_work_item_comment":
            if err := _check_rate("create_work_item_comment"):
                return [TextContent(type="text", text=err)]
            if err := _validate_body_length(arguments, ["comment_html"]):
                return [TextContent(type="text", text=err)]
            r = _api("POST", _v1(f"projects/{pid}/work-items/{wid}/comments/"),
                      {"comment_html": arguments["comment_html"]})
        case "retrieve_project_page":
            r = _api("GET", _internal(f"projects/{pid}/pages/{arguments['page_id']}/"))
        case "list_states":
            r = _api("GET", _v1(f"projects/{pid}/states/"))
        case "list_labels":
            r = _api("GET", _v1(f"projects/{pid}/labels/"))
        case "list_cycles":
            r = _api("GET", _v1(f"projects/{pid}/cycles/"))
        case "list_modules":
            r = _api("GET", _v1(f"projects/{pid}/modules/"))
        case _:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]
    return [TextContent(type="text", text=json.dumps(r, indent=2, default=str))]

async def main():
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
