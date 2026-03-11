#!/usr/bin/env python3
"""GitHub MCP server for OpenClaw.
Exposes: read repos/code/issues/PRs, create issues, add comments.
Blocks: push code, delete repos, close issues, admin operations.
Rate-limited: create_issue (5/hour), create_comment (20/hour).
Rate state persists to disk — survives process restarts.
"""
import os, json, re, time, fcntl, urllib.request, urllib.parse
from pathlib import Path
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

TOKEN = os.environ["GITHUB_OPENCLAW_TOKEN"]
API = "https://api.github.com"
ALLOWED_OWNERS = os.environ.get("GITHUB_ALLOWED_OWNERS", "akunito").split(",")
ALLOWED_METHODS = {"GET", "POST"}

# --- Input length validation (anti-payload-abuse) ---
MAX_BODY_LENGTH = 50_000  # 50KB
def _validate_body_length(arguments: dict, fields: list[str]) -> str | None:
    for f in fields:
        if f in arguments and len(str(arguments[f])) > MAX_BODY_LENGTH:
            return f"ERROR: {f} too long ({len(str(arguments[f]))} > {MAX_BODY_LENGTH} chars)"
    return None

# --- Input validation (anti-path-traversal) ---
_SAFE_NAME = re.compile(r'^[a-zA-Z0-9._-]+$')
def _validate_name(val: str, name: str):
    if not val or not _SAFE_NAME.match(val) or len(val) > 100:
        raise ValueError(f"Invalid {name}: only alphanumeric, dots, hyphens, underscores")

# --- Persistent rate limiter (file-backed, survives process restarts) ---
RATE_LIMITS = {
    "create_issue":   {"max": 5,  "window": 3600},
    "create_comment": {"max": 20, "window": 3600},
}
_RATE_FILE = Path(os.environ.get("HOME", "/home/node")) / ".openclaw/mcp/.ratelimit-github.json"

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

server = Server("github")

def _gh(method: str, path: str, body: dict | None = None) -> dict:
    if method not in ALLOWED_METHODS:
        raise ValueError(f"Method {method} not allowed (only GET, POST)")
    url = f"{API}{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {TOKEN}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())

def _validate_owner(owner: str):
    if owner not in ALLOWED_OWNERS:
        raise ValueError(f"Owner '{owner}' not in allowlist: {ALLOWED_OWNERS}")

@server.list_tools()
async def list_tools():
    return [
        Tool(name="list_repos", description="List user's repositories",
             inputSchema={"type": "object", "properties": {
                 "sort": {"type": "string", "enum": ["updated","pushed","created"], "default": "updated"},
                 "per_page": {"type": "integer", "default": 30}
             }}),
        Tool(name="get_repo", description="Get repository details",
             inputSchema={"type": "object", "properties": {
                 "owner": {"type": "string"}, "repo": {"type": "string"}
             }, "required": ["owner", "repo"]}),
        Tool(name="read_file", description="Read a file from a repository",
             inputSchema={"type": "object", "properties": {
                 "owner": {"type": "string"}, "repo": {"type": "string"},
                 "path": {"type": "string"}, "ref": {"type": "string", "default": "main"}
             }, "required": ["owner", "repo", "path"]}),
        Tool(name="list_issues", description="List issues for a repository",
             inputSchema={"type": "object", "properties": {
                 "owner": {"type": "string"}, "repo": {"type": "string"},
                 "state": {"type": "string", "enum": ["open","closed","all"], "default": "open"},
                 "per_page": {"type": "integer", "default": 30}
             }, "required": ["owner", "repo"]}),
        Tool(name="list_pulls", description="List pull requests",
             inputSchema={"type": "object", "properties": {
                 "owner": {"type": "string"}, "repo": {"type": "string"},
                 "state": {"type": "string", "enum": ["open","closed","all"], "default": "open"}
             }, "required": ["owner", "repo"]}),
        Tool(name="list_commits", description="List recent commits on a branch",
             inputSchema={"type": "object", "properties": {
                 "owner": {"type": "string"}, "repo": {"type": "string"},
                 "sha": {"type": "string", "default": "main"},
                 "per_page": {"type": "integer", "default": 20}
             }, "required": ["owner", "repo"]}),
        Tool(name="search_code", description="Search code across repositories",
             inputSchema={"type": "object", "properties": {
                 "query": {"type": "string"}, "per_page": {"type": "integer", "default": 10}
             }, "required": ["query"]}),
        Tool(name="create_issue", description="Create a new issue",
             inputSchema={"type": "object", "properties": {
                 "owner": {"type": "string"}, "repo": {"type": "string"},
                 "title": {"type": "string"}, "body": {"type": "string"},
                 "labels": {"type": "array", "items": {"type": "string"}}
             }, "required": ["owner", "repo", "title"]}),
        Tool(name="create_comment", description="Add a comment to an issue or PR",
             inputSchema={"type": "object", "properties": {
                 "owner": {"type": "string"}, "repo": {"type": "string"},
                 "issue_number": {"type": "integer"}, "body": {"type": "string"}
             }, "required": ["owner", "repo", "issue_number", "body"]}),
    ]

@server.call_tool()
async def call_tool(name: str, arguments: dict):
    o = arguments.get("owner", ""); r = arguments.get("repo", "")
    # Validate names to prevent path traversal via crafted owner/repo
    try:
        if o: _validate_name(o, "owner")
        if r: _validate_name(r, "repo")
    except ValueError as e:
        return [TextContent(type="text", text=f"ERROR: {e}")]
    if name not in ("list_repos", "search_code") and o:
        _validate_owner(o)
    match name:
        case "list_repos":
            qs = urllib.parse.urlencode({k: v for k, v in arguments.items()})
            r_ = _gh("GET", f"/user/repos?{qs}")
        case "get_repo":
            r_ = _gh("GET", f"/repos/{o}/{r}")
        case "read_file":
            ref = arguments.get("ref", "main")
            r_ = _gh("GET", f"/repos/{o}/{r}/contents/{arguments['path']}?ref={ref}")
        case "list_issues":
            s = arguments.get("state", "open"); pp = arguments.get("per_page", 30)
            r_ = _gh("GET", f"/repos/{o}/{r}/issues?state={s}&per_page={pp}")
        case "list_pulls":
            s = arguments.get("state", "open")
            r_ = _gh("GET", f"/repos/{o}/{r}/pulls?state={s}")
        case "list_commits":
            sha = arguments.get("sha", "main"); pp = arguments.get("per_page", 20)
            r_ = _gh("GET", f"/repos/{o}/{r}/commits?sha={sha}&per_page={pp}")
        case "search_code":
            # Strip user:/org:/repo: qualifiers from LLM-provided query to enforce owner allowlist.
            # Without this, the LLM (via prompt injection) could append "user:victimorg" and
            # GitHub would OR it with the enforced filter, searching outside the allowlist.
            q = re.sub(r'\b(user|org|repo):\S+', '', arguments["query"]).strip()
            owner_filter = " ".join(f"user:{ow}" for ow in ALLOWED_OWNERS)
            q_safe = urllib.parse.quote(f"{q} {owner_filter}")
            r_ = _gh("GET", f"/search/code?q={q_safe}&per_page={arguments.get('per_page',10)}")
        case "create_issue":
            if err := _check_rate("create_issue"):
                return [TextContent(type="text", text=err)]
            if err := _validate_body_length(arguments, ["title", "body"]):
                return [TextContent(type="text", text=err)]
            body = {"title": arguments["title"]}
            if "body" in arguments: body["body"] = arguments["body"]
            if "labels" in arguments: body["labels"] = arguments["labels"]
            r_ = _gh("POST", f"/repos/{o}/{r}/issues", body)
        case "create_comment":
            if err := _check_rate("create_comment"):
                return [TextContent(type="text", text=err)]
            if err := _validate_body_length(arguments, ["body"]):
                return [TextContent(type="text", text=err)]
            r_ = _gh("POST", f"/repos/{o}/{r}/issues/{arguments['issue_number']}/comments",
                      {"body": arguments["body"]})
        case _:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]
    return [TextContent(type="text", text=json.dumps(r_, indent=2, default=str))]

async def main():
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
