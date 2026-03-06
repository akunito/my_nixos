#!/usr/bin/env python3
"""OpenClaw API Proxy — HTTP server that wraps external APIs with access control.
Tokens stay in environment variables, never exposed to the LLM.
Rate-limited write operations. Read-only by default.

Runs as a sidecar; agents call via web_fetch http://127.0.0.1:18795/plane/...

Services: Plane, Jellyseerr, GitHub, Miniflux, Prometheus, LeftyWorkout
"""
import os, json, re, time, fcntl, urllib.request, urllib.parse, sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.error import HTTPError, URLError

LISTEN_PORT = int(os.environ.get("API_PROXY_PORT", "18795"))

# --- Plane config ---
PLANE_API_URL = os.environ.get("PLANE_API_URL", "https://plane.akunito.com")
PLANE_API_TOKEN = os.environ.get("PLANE_OPENCLAW_TOKEN", "")
PLANE_WORKSPACE = os.environ.get("PLANE_WORKSPACE_SLUG", "akuworkspace")

# --- Jellyseerr config ---
JELLYSEERR_URL = os.environ.get("JELLYSEERR_URL", "")
JELLYSEERR_KEY = os.environ.get("JELLYSEERR_OPENCLAW_KEY", "")

# --- GitHub config ---
GITHUB_TOKEN = os.environ.get("GITHUB_OPENCLAW_TOKEN", "")
GITHUB_ALLOWED_OWNERS = os.environ.get("GITHUB_ALLOWED_OWNERS", "akunito").split(",")

# --- Miniflux config ---
MINIFLUX_URL = os.environ.get("MINIFLUX_URL", "https://miniflux.local.akunito.com")
MINIFLUX_KEY = os.environ.get("MINIFLUX_OPENCLAW_KEY", "")

# --- Prometheus config ---
# Prometheus is behind nginx basic auth; use PROMETHEUS_URL with embedded credentials
# e.g. https://user:pass@prometheus.local.akunito.com
PROMETHEUS_URL = os.environ.get("PROMETHEUS_URL", "")

# --- LeftyWorkout config ---
LEFTYWORKOUT_DB_URL = os.environ.get("LEFTYWORKOUT_DB_URL", "")

# --- Input validation ---
_UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
MAX_BODY_LENGTH = 50_000

def _validate_uuid(val, name):
    if not val or not _UUID_RE.match(val):
        raise ValueError(f"Invalid {name}: must be UUID format")

# --- Persistent rate limiter ---
RATE_LIMITS = {
    "plane_create_work_item":         {"max": 10, "window": 3600},
    "plane_create_comment":           {"max": 30, "window": 3600},
    "jellyseerr_request":             {"max": 5,  "window": 3600},
}
_RATE_FILE = Path(os.environ.get("HOME", "/home/node")) / ".openclaw/mcp/.ratelimit-api-proxy.json"

def _check_rate(op):
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
                return f"RATE LIMITED: {op} exceeded {cfg['max']}/{cfg['window']}s. Retry in {remaining}s."
            timestamps.append(now)
            data[op] = timestamps
            f.seek(0); f.truncate()
            f.write(json.dumps(data))
    except (json.JSONDecodeError, OSError) as e:
        return f"RATE LIMITED: rate state corrupted ({type(e).__name__}). Delete {_RATE_FILE}"
    return None

# --- Custom DNS: route *.local.* through Docker host gateway (nginx) ---
# Inside Docker, 172.17.0.1 is the host. The host's nginx reverse-proxies
# all *.local.akunito.com services. Container can't reach 192.168.8.x directly
# (only the host can via WireGuard), so we override DNS for these domains.
DOCKER_HOST_GW = os.environ.get("DOCKER_HOST_GW", "100.64.0.6")
_LOCAL_DOMAIN_SUFFIX = os.environ.get("LOCAL_DOMAIN_SUFFIX", ".local.akunito.com")

import socket
_original_getaddrinfo = socket.getaddrinfo
def _patched_getaddrinfo(host, port, *args, **kwargs):
    if isinstance(host, str) and host.endswith(_LOCAL_DOMAIN_SUFFIX):
        return _original_getaddrinfo(DOCKER_HOST_GW, port, *args, **kwargs)
    return _original_getaddrinfo(host, port, *args, **kwargs)
socket.getaddrinfo = _patched_getaddrinfo

# --- HTTP helpers ---
def _fetch(url, method="GET", body=None, headers=None, timeout=30):
    data = json.dumps(body).encode() if body else None
    hdrs = {"Content-Type": "application/json"}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())

def _plane_v1(path):
    return f"{PLANE_API_URL}/api/v1/workspaces/{PLANE_WORKSPACE}/{path}"

def _plane_internal(path):
    return f"{PLANE_API_URL}/api/workspaces/{PLANE_WORKSPACE}/{path}"

def _plane_headers():
    return {"X-Api-Key": PLANE_API_TOKEN}


class ProxyHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Suppress default access logs to avoid leaking paths
        pass

    def _send_json(self, data, status=200):
        body = json.dumps(data, indent=2, default=str).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error(self, msg, status=400):
        self._send_json({"error": msg}, status)

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        if length > MAX_BODY_LENGTH:
            return None
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length))

    def _parse_path(self):
        parsed = urllib.parse.urlparse(self.path)
        return parsed.path.strip("/"), dict(urllib.parse.parse_qsl(parsed.query))

    def do_GET(self):
        path, params = self._parse_path()
        try:
            result = self._route_get(path, params)
            self._send_json(result)
        except ValueError as e:
            self._send_error(str(e))
        except HTTPError as e:
            self._send_error(f"Upstream: {e.code} {e.reason}", e.code)
        except URLError as e:
            self._send_error(f"Upstream unreachable: {e.reason}", 502)
        except Exception as e:
            self._send_error(f"Internal error: {type(e).__name__}: {e}", 500)

    def do_POST(self):
        path, params = self._parse_path()
        body = self._read_body()
        if body is None:
            self._send_error("Body too large")
            return
        try:
            result = self._route_post(path, params, body)
            self._send_json(result)
        except ValueError as e:
            self._send_error(str(e))
        except HTTPError as e:
            self._send_error(f"Upstream: {e.code} {e.reason}", e.code)
        except URLError as e:
            self._send_error(f"Upstream unreachable: {e.reason}", 502)
        except Exception as e:
            self._send_error(f"Internal error: {type(e).__name__}: {e}", 500)

    # ========================================================================
    # GET routes
    # ========================================================================
    def _route_get(self, path, params):
        parts = path.split("/")

        # --- Health ---
        if path == "health":
            return {"status": "ok", "services": {
                "plane": bool(PLANE_API_TOKEN),
                "jellyseerr": bool(JELLYSEERR_KEY),
                "github": bool(GITHUB_TOKEN),
                "miniflux": bool(MINIFLUX_KEY),
                "prometheus": bool(PROMETHEUS_URL),
                "leftyworkout": bool(LEFTYWORKOUT_DB_URL),
            }}

        # --- Plane ---
        if parts[0] == "plane":
            if not PLANE_API_TOKEN:
                raise ValueError("Plane not configured")
            return self._plane_get(parts[1:], params)

        # --- Jellyseerr ---
        if parts[0] == "jellyseerr":
            if not JELLYSEERR_KEY:
                raise ValueError("Jellyseerr not configured")
            return self._jellyseerr_get(parts[1:], params)

        # --- GitHub ---
        if parts[0] == "github":
            if not GITHUB_TOKEN:
                raise ValueError("GitHub not configured")
            return self._github_get(parts[1:], params)

        # --- Miniflux ---
        if parts[0] == "miniflux":
            if not MINIFLUX_KEY:
                raise ValueError("Miniflux not configured")
            return self._miniflux_get(parts[1:], params)

        # --- Prometheus ---
        if parts[0] == "prometheus":
            return self._prometheus_get(parts[1:], params)

        # --- LeftyWorkout ---
        if parts[0] == "leftyworkout":
            if not LEFTYWORKOUT_DB_URL:
                raise ValueError("LeftyWorkout not configured")
            return self._leftyworkout_get(parts[1:], params)

        raise ValueError(f"Unknown route: {path}")

    # --- Plane GET ---
    def _plane_get(self, parts, params):
        h = _plane_headers()
        if len(parts) == 0 or parts[0] == "projects":
            return _fetch(_plane_v1("projects/"), headers=h)
        if parts[0] == "search":
            q = urllib.parse.quote(params.get("q", ""))
            return _fetch(_plane_v1(f"search/?search={q}&type=work_item"), headers=h)
        if parts[0] == "project" and len(parts) >= 2:
            pid = parts[1]
            _validate_uuid(pid, "project_id")
            if len(parts) == 2 or parts[2] == "items":
                expand = params.get("expand", "state")
                return _fetch(_plane_v1(f"projects/{pid}/work-items/?expand={expand}"), headers=h)
            if parts[2] == "item" and len(parts) >= 4:
                wid = parts[3]
                _validate_uuid(wid, "work_item_id")
                if len(parts) == 4:
                    return _fetch(_plane_v1(f"projects/{pid}/work-items/{wid}/?expand=state"), headers=h)
                if parts[4] == "comments":
                    return _fetch(_plane_v1(f"projects/{pid}/work-items/{wid}/comments/"), headers=h)
            if parts[2] == "states":
                return _fetch(_plane_v1(f"projects/{pid}/states/"), headers=h)
            if parts[2] == "labels":
                return _fetch(_plane_v1(f"projects/{pid}/labels/"), headers=h)
            if parts[2] == "cycles":
                return _fetch(_plane_v1(f"projects/{pid}/cycles/"), headers=h)
            if parts[2] == "modules":
                return _fetch(_plane_v1(f"projects/{pid}/modules/"), headers=h)
            if parts[2] == "page" and len(parts) >= 4:
                page_id = parts[3]
                _validate_uuid(page_id, "page_id")
                return _fetch(_plane_internal(f"projects/{pid}/pages/{page_id}/"), headers=h)
        raise ValueError(f"Unknown Plane route: /plane/{'/'.join(parts)}")

    # --- Jellyseerr GET ---
    def _jellyseerr_get(self, parts, params):
        h = {"X-Api-Key": JELLYSEERR_KEY}
        if parts[0] == "search":
            q = urllib.parse.quote(params.get("q", ""))
            return _fetch(f"{JELLYSEERR_URL}/api/v1/search?query={q}", headers=h)
        if parts[0] == "requests":
            return _fetch(f"{JELLYSEERR_URL}/api/v1/request?take=20&sort=added", headers=h)
        raise ValueError(f"Unknown Jellyseerr route: /jellyseerr/{'/'.join(parts)}")

    # --- GitHub GET ---
    def _github_get(self, parts, params):
        h = {"Authorization": f"Bearer {GITHUB_TOKEN}", "Accept": "application/vnd.github+json"}
        if parts[0] == "repos":
            owner = parts[1] if len(parts) > 1 else "akunito"
            if owner not in GITHUB_ALLOWED_OWNERS:
                raise ValueError(f"Owner {owner} not in allowed list")
            if len(parts) >= 3:
                repo = parts[2]
                if len(parts) == 3:
                    return _fetch(f"https://api.github.com/repos/{owner}/{repo}", headers=h)
                if parts[3] == "issues":
                    return _fetch(f"https://api.github.com/repos/{owner}/{repo}/issues?per_page=20", headers=h)
            return _fetch(f"https://api.github.com/users/{owner}/repos?per_page=30", headers=h)
        raise ValueError(f"Unknown GitHub route: /github/{'/'.join(parts)}")

    # --- Miniflux GET ---
    def _miniflux_get(self, parts, params):
        h = {"X-Auth-Token": MINIFLUX_KEY}
        if parts[0] == "entries":
            status = params.get("status", "unread")
            limit = min(int(params.get("limit", "20")), 50)
            return _fetch(f"{MINIFLUX_URL}/v1/entries?status={status}&limit={limit}", headers=h)
        if parts[0] == "feeds":
            return _fetch(f"{MINIFLUX_URL}/v1/feeds", headers=h)
        raise ValueError(f"Unknown Miniflux route: /miniflux/{'/'.join(parts)}")

    # --- Prometheus GET (read-only) ---
    _SAFE_PROMQL_RE = re.compile(r'^[a-zA-Z0-9_:{}()\[\]",=~!<>+\-*/\s.@^$|]+$')

    def _prometheus_get(self, parts, params):
        if not parts:
            raise ValueError("Specify: query, query_range, targets, alerts, series")
        if parts[0] == "query":
            q = params.get("q", "")
            if not q or not self._SAFE_PROMQL_RE.match(q):
                raise ValueError("Invalid or missing PromQL query")
            url = f"{PROMETHEUS_URL}/api/v1/query?query={urllib.parse.quote(q)}"
            if "time" in params:
                url += f"&time={urllib.parse.quote(params['time'])}"
            return _fetch(url, timeout=15)
        if parts[0] == "query_range":
            q = params.get("q", "")
            if not q or not self._SAFE_PROMQL_RE.match(q):
                raise ValueError("Invalid or missing PromQL query")
            start = params.get("start", "")
            end = params.get("end", "")
            step = params.get("step", "60s")
            if not start or not end:
                raise ValueError("start and end are required for range queries")
            url = (f"{PROMETHEUS_URL}/api/v1/query_range?"
                   f"query={urllib.parse.quote(q)}&start={urllib.parse.quote(start)}"
                   f"&end={urllib.parse.quote(end)}&step={urllib.parse.quote(step)}")
            return _fetch(url, timeout=30)
        if parts[0] == "targets":
            return _fetch(f"{PROMETHEUS_URL}/api/v1/targets", timeout=10)
        if parts[0] == "alerts":
            return _fetch(f"{PROMETHEUS_URL}/api/v1/alerts", timeout=10)
        if parts[0] == "series":
            match = params.get("match", "")
            if not match:
                raise ValueError("match parameter required (e.g. match=up)")
            return _fetch(f"{PROMETHEUS_URL}/api/v1/series?match[]={urllib.parse.quote(match)}", timeout=10)
        raise ValueError(f"Unknown Prometheus route: /prometheus/{'/'.join(parts)}")

    # --- LeftyWorkout GET (read-only, predefined queries) ---
    _LW_QUERIES = {
        "workouts": """SELECT w.id, w.name, w.performed_at, w.duration_minutes,
                       COUNT(we.id) as exercise_count
                       FROM workouts w LEFT JOIN workout_exercises we ON we.workout_id = w.id
                       GROUP BY w.id ORDER BY w.performed_at DESC LIMIT 20""",
        "exercises": """SELECT id, name, muscle_group, equipment
                       FROM exercises ORDER BY name LIMIT 100""",
        "stats": """SELECT COUNT(DISTINCT w.id) as total_workouts,
                    COUNT(DISTINCT DATE(w.performed_at)) as total_days,
                    ROUND(AVG(w.duration_minutes)::numeric, 1) as avg_duration,
                    MAX(w.performed_at) as last_workout
                    FROM workouts w""",
        "recent_sets": """SELECT w.performed_at, e.name as exercise, ws.sets, ws.reps, ws.weight_kg
                         FROM workout_sets ws
                         JOIN workout_exercises we ON ws.workout_exercise_id = we.id
                         JOIN workouts w ON we.workout_id = w.id
                         JOIN exercises e ON we.exercise_id = e.id
                         ORDER BY w.performed_at DESC, we.position LIMIT 50""",
    }

    def _leftyworkout_get(self, parts, params):
        if not parts:
            return {"available_queries": list(self._LW_QUERIES.keys())}
        query_name = parts[0]
        if query_name not in self._LW_QUERIES:
            raise ValueError(f"Unknown query: {query_name}. Available: {list(self._LW_QUERIES.keys())}")
        try:
            import psycopg2
            import psycopg2.extras
        except ImportError:
            raise ValueError("psycopg2 not installed in mcp-packages")
        conn = psycopg2.connect(LEFTYWORKOUT_DB_URL)
        try:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(self._LW_QUERIES[query_name])
                rows = cur.fetchall()
                return {"query": query_name, "count": len(rows), "results": rows}
        finally:
            conn.close()

    # ========================================================================
    # POST routes
    # ========================================================================
    def _route_post(self, path, params, body):
        parts = path.split("/")
        if parts[0] == "plane":
            if not PLANE_API_TOKEN:
                raise ValueError("Plane not configured")
            return self._plane_post(parts[1:], body)
        if parts[0] == "jellyseerr":
            if not JELLYSEERR_KEY:
                raise ValueError("Jellyseerr not configured")
            return self._jellyseerr_post(parts[1:], body)
        raise ValueError(f"Unknown POST route: {path}")

    def _plane_post(self, parts, body):
        h = _plane_headers()
        # POST /plane/project/{pid}/items — create work item
        if parts[0] == "project" and len(parts) >= 3 and parts[2] == "items":
            pid = parts[1]
            _validate_uuid(pid, "project_id")
            if err := _check_rate("plane_create_work_item"):
                raise ValueError(err)
            if not body.get("name"):
                raise ValueError("name is required")
            return _fetch(_plane_v1(f"projects/{pid}/work-items/"), method="POST", body=body, headers=h)
        # POST /plane/project/{pid}/item/{wid}/comments — create comment
        if parts[0] == "project" and len(parts) >= 5 and parts[2] == "item" and parts[4] == "comments":
            pid = parts[1]
            wid = parts[3]
            _validate_uuid(pid, "project_id")
            _validate_uuid(wid, "work_item_id")
            if err := _check_rate("plane_create_comment"):
                raise ValueError(err)
            if not body.get("comment_html"):
                raise ValueError("comment_html is required")
            return _fetch(_plane_v1(f"projects/{pid}/work-items/{wid}/comments/"),
                          method="POST", body=body, headers=h)
        raise ValueError(f"Unknown Plane POST: /plane/{'/'.join(parts)}")

    def _jellyseerr_post(self, parts, body):
        h = {"X-Api-Key": JELLYSEERR_KEY}
        if parts[0] == "request":
            if err := _check_rate("jellyseerr_request"):
                raise ValueError(err)
            return _fetch(f"{JELLYSEERR_URL}/api/v1/request", method="POST", body=body, headers=h)
        raise ValueError(f"Unknown Jellyseerr POST: /jellyseerr/{'/'.join(parts)}")


if __name__ == "__main__":
    print(f"API Proxy listening on 127.0.0.1:{LISTEN_PORT}")
    server = HTTPServer(("127.0.0.1", LISTEN_PORT), ProxyHandler)
    server.serve_forever()
