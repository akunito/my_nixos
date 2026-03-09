#!/usr/bin/env python3
"""Restricted Google Calendar MCP server for OpenClaw.

Code-level RBAC — the same pattern as gmail-restricted-mcp:
- READ: list calendars, list events, get event details
- WRITE: create event (rate limited: 10/hour)
- UPDATE: update event time/title (rate limited: 5/hour)
- DELETE: delete event (rate limited: 3/hour)
- NOT IMPLEMENTED: ACL management, calendar creation/deletion, settings, freebusy

OAuth scope: calendar + calendar.events (needed for create/update/delete).
Uses Google's official API client with an existing OAuth token (reused from n8n).
Rate-limited with persistent state — survives process restarts.
"""
import os, json, time, fcntl
from pathlib import Path
from datetime import datetime, timezone
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

CREDENTIALS_PATH = os.environ["CALENDAR_CREDENTIALS_PATH"]
CALENDAR_ACCOUNT = os.environ["CALENDAR_ACCOUNT"]
CALENDAR_TIMEZONE = os.environ.get("CALENDAR_TIMEZONE", "Europe/Madrid")

# --- Input length validation (anti-payload-abuse) ---
MAX_BODY_LENGTH = 50_000  # 50KB
def _validate_body_length(arguments: dict, fields: list[str]) -> str | None:
    for f in fields:
        if f in arguments and len(str(arguments[f])) > MAX_BODY_LENGTH:
            return f"ERROR: {f} too long ({len(str(arguments[f]))} > {MAX_BODY_LENGTH} chars)"
    return None

# Blocked operations — not implemented, listed for audit clarity
# calendar_create, calendar_delete, acl_manage, settings_modify, freebusy_query

# --- Persistent rate limiter (file-backed, survives process restarts) ---
RATE_LIMITS = {
    "create_event":  {"max": 10, "window": 3600},
    "update_event":  {"max": 5,  "window": 3600},
    "delete_event":  {"max": 3,  "window": 3600},
}
_RATE_FILE = Path(os.environ.get("HOME", "/home/node")) / ".openclaw/mcp/.ratelimit-calendar-restricted.json"

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
        # Fail-CLOSED permanently: deny if rate state is unreadable
        return f"RATE LIMITED: {op} denied — rate state file corrupted ({type(e).__name__}). Manual fix: delete {_RATE_FILE}"
    return None

server = Server("calendar-restricted")

_TOKEN_CACHE = Path("/tmp/calendar_mcp_token_refreshed.json")

def _get_service():
    """Build Google Calendar API service from stored OAuth credentials.
    Credentials volume is mounted :ro to prevent overwrite on container compromise.
    Token refresh writes to /tmp (tmpfs) — survives within session, cleared on restart.
    On restart, falls back to the :ro original and re-refreshes.
    """
    token_path = Path(CREDENTIALS_PATH) / "calendar_mcp_token.json"
    # Use cached refreshed token if available (written by previous refresh)
    source = _TOKEN_CACHE if _TOKEN_CACHE.exists() else token_path
    creds = Credentials.from_authorized_user_file(str(source))
    if creds.expired and creds.refresh_token:
        from google.auth.transport.requests import Request
        creds.refresh(Request())
        # Write refreshed token to tmpfs (writable), not :ro volume
        _TOKEN_CACHE.write_text(creds.to_json())
    return build("calendar", "v3", credentials=creds)

@server.list_tools()
async def list_tools():
    return [
        Tool(name="list_calendars",
             description="List all accessible Google calendars",
             inputSchema={"type": "object", "properties": {}}),
        Tool(name="list_events",
             description="List calendar events within a date range",
             inputSchema={"type": "object", "properties": {
                 "calendar_id": {"type": "string", "default": "primary",
                                 "description": "Calendar ID (default: primary)"},
                 "time_min": {"type": "string",
                              "description": "Start of range (RFC3339, e.g. 2026-03-10T00:00:00+01:00)"},
                 "time_max": {"type": "string",
                              "description": "End of range (RFC3339, e.g. 2026-03-11T00:00:00+01:00)"},
                 "max_results": {"type": "integer", "default": 20,
                                 "description": "Max events to return (1-50)"},
                 "query": {"type": "string", "default": "",
                           "description": "Free-text search within events"}
             }, "required": ["time_min", "time_max"]}),
        Tool(name="get_event",
             description="Get full details of a specific calendar event",
             inputSchema={"type": "object", "properties": {
                 "calendar_id": {"type": "string", "default": "primary",
                                 "description": "Calendar ID (default: primary)"},
                 "event_id": {"type": "string",
                              "description": "Event ID to retrieve"}
             }, "required": ["event_id"]}),
        Tool(name="create_event",
             description="Create a new calendar event (rate limited: 10/hour)",
             inputSchema={"type": "object", "properties": {
                 "calendar_id": {"type": "string", "default": "primary",
                                 "description": "Calendar ID (default: primary)"},
                 "summary": {"type": "string",
                             "description": "Event title"},
                 "start": {"type": "string",
                           "description": "Start time (RFC3339, e.g. 2026-03-10T14:00:00+01:00)"},
                 "end": {"type": "string",
                         "description": "End time (RFC3339, e.g. 2026-03-10T15:00:00+01:00)"},
                 "description": {"type": "string", "default": "",
                                 "description": "Event description (optional)"},
                 "location": {"type": "string", "default": "",
                              "description": "Event location (optional)"}
             }, "required": ["summary", "start", "end"]}),
        Tool(name="update_event",
             description="Update an existing event's time, title, or description (rate limited: 5/hour)",
             inputSchema={"type": "object", "properties": {
                 "calendar_id": {"type": "string", "default": "primary",
                                 "description": "Calendar ID (default: primary)"},
                 "event_id": {"type": "string",
                              "description": "Event ID to update"},
                 "summary": {"type": "string",
                             "description": "New title (optional)"},
                 "start": {"type": "string",
                           "description": "New start time (RFC3339, optional)"},
                 "end": {"type": "string",
                         "description": "New end time (RFC3339, optional)"},
                 "description": {"type": "string",
                                 "description": "New description (optional)"},
                 "location": {"type": "string",
                              "description": "New location (optional)"}
             }, "required": ["event_id"]}),
        Tool(name="delete_event",
             description="Delete a calendar event (rate limited: 3/hour)",
             inputSchema={"type": "object", "properties": {
                 "calendar_id": {"type": "string", "default": "primary",
                                 "description": "Calendar ID (default: primary)"},
                 "event_id": {"type": "string",
                              "description": "Event ID to delete"}
             }, "required": ["event_id"]}),
    ]

@server.call_tool()
async def call_tool(name: str, arguments: dict):
    svc = _get_service()

    match name:
        case "list_calendars":
            result = svc.calendarList().list().execute()
            calendars = []
            for cal in result.get("items", []):
                calendars.append({
                    "id": cal["id"],
                    "summary": cal.get("summary", ""),
                    "primary": cal.get("primary", False),
                    "accessRole": cal.get("accessRole", ""),
                    "timeZone": cal.get("timeZone", ""),
                })
            r = {"count": len(calendars), "calendars": calendars}

        case "list_events":
            cal_id = arguments.get("calendar_id", "primary")
            max_r = min(arguments.get("max_results", 20), 50)
            query = arguments.get("query", "")
            kwargs = {
                "calendarId": cal_id,
                "timeMin": arguments["time_min"],
                "timeMax": arguments["time_max"],
                "maxResults": max_r,
                "singleEvents": True,
                "orderBy": "startTime",
                "timeZone": CALENDAR_TIMEZONE,
            }
            if query:
                kwargs["q"] = query
            result = svc.events().list(**kwargs).execute()
            events = []
            for ev in result.get("items", []):
                events.append({
                    "id": ev["id"],
                    "summary": ev.get("summary", "(no title)"),
                    "start": ev.get("start", {}).get("dateTime", ev.get("start", {}).get("date", "")),
                    "end": ev.get("end", {}).get("dateTime", ev.get("end", {}).get("date", "")),
                    "location": ev.get("location", ""),
                    "status": ev.get("status", ""),
                    "htmlLink": ev.get("htmlLink", ""),
                })
            r = {"count": len(events), "events": events}

        case "get_event":
            cal_id = arguments.get("calendar_id", "primary")
            event = svc.events().get(
                calendarId=cal_id, eventId=arguments["event_id"]
            ).execute()
            # Truncate description to prevent context overflow
            desc = event.get("description", "")
            if len(desc) > 4000:
                desc = desc[:4000] + "\n... [truncated]"
            r = {
                "id": event["id"],
                "summary": event.get("summary", "(no title)"),
                "start": event.get("start", {}),
                "end": event.get("end", {}),
                "description": desc,
                "location": event.get("location", ""),
                "status": event.get("status", ""),
                "creator": event.get("creator", {}),
                "organizer": event.get("organizer", {}),
                "attendees": [
                    {"email": a.get("email", ""), "responseStatus": a.get("responseStatus", "")}
                    for a in event.get("attendees", [])
                ],
                "htmlLink": event.get("htmlLink", ""),
                "recurrence": event.get("recurrence", []),
            }

        case "create_event":
            if err := _check_rate("create_event"):
                return [TextContent(type="text", text=err)]
            if err := _validate_body_length(arguments, ["summary", "description"]):
                return [TextContent(type="text", text=err)]
            cal_id = arguments.get("calendar_id", "primary")
            body = {
                "summary": arguments["summary"],
                "start": {"dateTime": arguments["start"], "timeZone": CALENDAR_TIMEZONE},
                "end": {"dateTime": arguments["end"], "timeZone": CALENDAR_TIMEZONE},
            }
            if arguments.get("description"):
                body["description"] = arguments["description"]
            if arguments.get("location"):
                body["location"] = arguments["location"]
            event = svc.events().insert(calendarId=cal_id, body=body).execute()
            r = {
                "status": "event_created",
                "event_id": event["id"],
                "summary": event.get("summary", ""),
                "start": event.get("start", {}),
                "end": event.get("end", {}),
                "htmlLink": event.get("htmlLink", ""),
            }

        case "update_event":
            if err := _check_rate("update_event"):
                return [TextContent(type="text", text=err)]
            if err := _validate_body_length(arguments, ["summary", "description"]):
                return [TextContent(type="text", text=err)]
            cal_id = arguments.get("calendar_id", "primary")
            # Fetch current event to merge updates
            event = svc.events().get(
                calendarId=cal_id, eventId=arguments["event_id"]
            ).execute()
            if "summary" in arguments:
                event["summary"] = arguments["summary"]
            if "start" in arguments:
                event["start"] = {"dateTime": arguments["start"], "timeZone": CALENDAR_TIMEZONE}
            if "end" in arguments:
                event["end"] = {"dateTime": arguments["end"], "timeZone": CALENDAR_TIMEZONE}
            if "description" in arguments:
                event["description"] = arguments["description"]
            if "location" in arguments:
                event["location"] = arguments["location"]
            updated = svc.events().update(
                calendarId=cal_id, eventId=arguments["event_id"], body=event
            ).execute()
            r = {
                "status": "event_updated",
                "event_id": updated["id"],
                "summary": updated.get("summary", ""),
                "start": updated.get("start", {}),
                "end": updated.get("end", {}),
                "htmlLink": updated.get("htmlLink", ""),
            }

        case "delete_event":
            if err := _check_rate("delete_event"):
                return [TextContent(type="text", text=err)]
            cal_id = arguments.get("calendar_id", "primary")
            svc.events().delete(
                calendarId=cal_id, eventId=arguments["event_id"]
            ).execute()
            r = {
                "status": "event_deleted",
                "event_id": arguments["event_id"],
                "note": "Event has been permanently deleted.",
            }

        case _:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]

    return [TextContent(type="text", text=json.dumps(r, indent=2, default=str))]

async def main():
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
