#!/usr/bin/env python3
"""Leftyworkout read-only MCP server for OpenClaw.
All queries are PREDEFINED and PARAMETERIZED — no raw SQL from the LLM.
Defense layers:
  1. Code: All SQL is hardcoded with %s parameterized placeholders (no injection surface)
  2. PG role: openclaw_reader has SELECT-only grants (DB-level enforcement)
  3. Connection: readonly=True, statement_timeout=5s (kills slow/DoS queries)
  4. Code: fetchmany(500) row cap
custom_query was REMOVED to eliminate the SQL injection/DoS surface entirely.
If a new query pattern is needed, add a named tool with hardcoded SQL + parameterized inputs.
"""
import os, json, psycopg2, psycopg2.extras
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

DB_URL = os.environ["LEFTYWORKOUT_DB_URL"]
STATEMENT_TIMEOUT_MS = 5000  # 5 seconds — kills slow queries server-side

server = Server("leftyworkout-readonly")

def _query(sql: str, params: tuple = ()) -> list[dict]:
    """Execute a predefined, parameterized query. All SQL is hardcoded in tool handlers."""
    with psycopg2.connect(DB_URL) as conn:
        conn.set_session(readonly=True)
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            # statement_timeout: PostgreSQL kills the query server-side after 5s.
            # This is the primary defense against DoS (pg_sleep, cartesian joins,
            # resource-exhaustion queries). String matching is defense-in-depth only.
            cur.execute(f"SET statement_timeout = {STATEMENT_TIMEOUT_MS}")
            cur.execute(sql, params)
            rows = cur.fetchmany(500)
            return [dict(row) for row in rows]

@server.list_tools()
async def list_tools():
    return [
        Tool(name="list_workouts", description="List recent workouts",
             inputSchema={"type": "object", "properties": {
                 "limit": {"type": "integer", "default": 20},
                 "offset": {"type": "integer", "default": 0}
             }}),
        Tool(name="get_workout", description="Get full workout details with exercises and sets",
             inputSchema={"type": "object", "properties": {
                 "workout_id": {"type": "integer"}
             }, "required": ["workout_id"]}),
        Tool(name="list_exercises", description="List all exercise definitions",
             inputSchema={"type": "object", "properties": {}}),
        Tool(name="exercise_history", description="Get history for a specific exercise",
             inputSchema={"type": "object", "properties": {
                 "exercise_name": {"type": "string"}, "limit": {"type": "integer", "default": 50}
             }, "required": ["exercise_name"]}),
        Tool(name="workout_stats", description="Get aggregate workout stats",
             inputSchema={"type": "object", "properties": {
                 "days": {"type": "integer", "default": 30}
             }}),
        Tool(name="query_tables", description="List database tables and columns",
             inputSchema={"type": "object", "properties": {}}),
        # custom_query REMOVED — raw SQL is an injection surface even with statement_timeout.
        # Replaced by predefined parameterized tools above. If a new query pattern is needed,
        # add a new named tool with hardcoded SQL + parameterized inputs.
        Tool(name="exercise_volume", description="Get total volume (weight × reps) per exercise over time",
             inputSchema={"type": "object", "properties": {
                 "exercise_name": {"type": "string"},
                 "days": {"type": "integer", "default": 90}
             }, "required": ["exercise_name"]}),
        Tool(name="personal_records", description="Get personal records (max weight per exercise)",
             inputSchema={"type": "object", "properties": {
                 "exercise_name": {"type": "string",
                     "description": "Exercise name (optional — omit for all exercises)"}
             }}),
    ]

@server.call_tool()
async def call_tool(name: str, arguments: dict):
    match name:
        case "list_workouts":
            r = _query("SELECT * FROM workouts ORDER BY created_at DESC LIMIT %s OFFSET %s",
                       (arguments.get("limit", 20), arguments.get("offset", 0)))
        case "get_workout":
            r = _query("""
                SELECT w.*, json_agg(json_build_object(
                    'exercise', e.name, 'sets', es.sets_data
                )) as exercises
                FROM workouts w
                LEFT JOIN workout_exercises we ON we.workout_id = w.id
                LEFT JOIN exercises e ON e.id = we.exercise_id
                LEFT JOIN LATERAL (
                    SELECT json_agg(json_build_object('reps', s.reps, 'weight', s.weight)) as sets_data
                    FROM sets s WHERE s.workout_exercise_id = we.id
                ) es ON true
                WHERE w.id = %s GROUP BY w.id
            """, (arguments["workout_id"],))
        case "list_exercises":
            r = _query("SELECT * FROM exercises ORDER BY name")
        case "exercise_history":
            r = _query("""
                SELECT w.created_at, s.reps, s.weight
                FROM sets s
                JOIN workout_exercises we ON we.id = s.workout_exercise_id
                JOIN exercises e ON e.id = we.exercise_id
                JOIN workouts w ON w.id = we.workout_id
                WHERE e.name ILIKE %s
                ORDER BY w.created_at DESC LIMIT %s
            """, (f"%{arguments['exercise_name']}%", arguments.get("limit", 50)))
        case "workout_stats":
            days = arguments.get("days", 30)
            r = _query("""
                SELECT count(*) as total_workouts,
                       avg(EXTRACT(EPOCH FROM (updated_at - created_at))/60)::int as avg_duration_min
                FROM workouts WHERE created_at > NOW() - INTERVAL '%s days'
            """, (days,))
        case "query_tables":
            r = _query("""
                SELECT table_name, column_name, data_type
                FROM information_schema.columns
                WHERE table_schema = 'public'
                ORDER BY table_name, ordinal_position
            """)
        # custom_query REMOVED — raw SQL surface eliminated. See "Architectural Recommendations" below.
        case "exercise_volume":
            name_pattern = f"%{arguments['exercise_name']}%"
            days = arguments.get("days", 90)
            r = _query("""
                SELECT e.name, w.created_at::date as date,
                       SUM(s.weight * s.reps) as total_volume,
                       COUNT(s.id) as total_sets
                FROM sets s
                JOIN workout_exercises we ON we.id = s.workout_exercise_id
                JOIN exercises e ON e.id = we.exercise_id
                JOIN workouts w ON w.id = we.workout_id
                WHERE e.name ILIKE %s AND w.created_at > NOW() - INTERVAL '%s days'
                GROUP BY e.name, w.created_at::date
                ORDER BY date DESC
            """, (name_pattern, days))
        case "personal_records":
            if "exercise_name" in arguments and arguments["exercise_name"]:
                r = _query("""
                    SELECT e.name, MAX(s.weight) as max_weight,
                           MAX(s.reps) as max_reps,
                           MAX(s.weight * s.reps) as max_volume_single_set
                    FROM sets s
                    JOIN workout_exercises we ON we.id = s.workout_exercise_id
                    JOIN exercises e ON e.id = we.exercise_id
                    WHERE e.name ILIKE %s
                    GROUP BY e.name
                """, (f"%{arguments['exercise_name']}%",))
            else:
                r = _query("""
                    SELECT e.name, MAX(s.weight) as max_weight,
                           MAX(s.reps) as max_reps
                    FROM sets s
                    JOIN workout_exercises we ON we.id = s.workout_exercise_id
                    JOIN exercises e ON e.id = we.exercise_id
                    GROUP BY e.name ORDER BY e.name
                """)
        case _:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]
    return [TextContent(type="text", text=json.dumps(r, indent=2, default=str))]

async def main():
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
