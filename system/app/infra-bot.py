#!/usr/bin/env python3
"""Infra Alerts Telegram bot (AINF-368).

One daemon on VPS_PROD, next to Prometheus and Alertmanager. Two halves:

  1. HTTP relay on the Tailscale interface ONLY (no auth: identity is the
     source Tailscale IP, resolved to a peer with `tailscale status`):
       POST /deploy   {"text": "<html>"}     -> posts into the 🚀 Deploys topic
       GET  /alerts?node=<name>             -> active alerts for that node
                                               (Alertmanager proxy, JSON)
       GET  /health
     Secrets-free nodes (LAPTOP_A, DESK_A, YOGA) announce their deploys through
     this; nodes that hold the bot token talk to Telegram directly and only use
     /alerts here.

  2. Telegram commands (/status, /alerts, /deploys, /help) via long polling
     and the Sunday warning digest — phase F3, see run_commands().

Everything is read-only. Config comes from the environment (infra-bot.nix).
"""
import json
import logging
import os
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

log = logging.getLogger("infra-bot")

TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")
THREAD_DEPLOYS = os.environ.get("THREAD_DEPLOYS", "")
THREAD_ALERTS = os.environ.get("THREAD_ALERTS", "")
THREAD_WEEKLY = os.environ.get("THREAD_WEEKLY", "")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8765"))
ALERTMANAGER_URL = os.environ.get("ALERTMANAGER_URL", "http://127.0.0.1:9093")
PROMETHEUS_URL = os.environ.get("PROMETHEUS_URL", "http://127.0.0.1:9090")
# tailscale hostname -> node label used by Prometheus/Alertmanager
NODE_MAP = json.loads(os.environ.get("NODE_MAP", "{}"))
TELEGRAM_API = "https://api.telegram.org"
MAX_TEXT = 4000


# ----------------------------------------------------------------------------
# Telegram
# ----------------------------------------------------------------------------
def telegram(method, **params):
    data = urllib.parse.urlencode({k: v for k, v in params.items() if v not in ("", None)}).encode()
    req = urllib.request.Request(f"{TELEGRAM_API}/bot{TOKEN}/{method}", data=data)
    with urllib.request.urlopen(req, timeout=20) as r:
        body = json.load(r)
    if not body.get("ok"):
        raise RuntimeError(f"telegram {method}: {body}")
    return body["result"]


def send(text, thread=None):
    """HTML message into the group; thread = forum topic id ('' = General)."""
    return telegram(
        "sendMessage",
        chat_id=CHAT_ID,
        message_thread_id=thread,
        parse_mode="HTML",
        disable_web_page_preview="true",
        text=text[:MAX_TEXT],
    )


# ----------------------------------------------------------------------------
# Tailscale identity
# ----------------------------------------------------------------------------
def tailscale_status():
    out = subprocess.run(["tailscale", "status", "--json"], capture_output=True, text=True, timeout=10)
    if out.returncode != 0:
        raise RuntimeError(f"tailscale status: {out.stderr.strip()}")
    return json.loads(out.stdout)


def self_ipv4():
    st = tailscale_status()
    for ip in st["Self"]["TailscaleIPs"]:
        if ":" not in ip:
            return ip
    raise RuntimeError("no tailscale IPv4")


def peer_hostname(ip):
    """Tailscale IP -> first label of the Headscale DNS name, or None if it is
    not a tailnet peer (the relay refuses those)."""
    st = tailscale_status()
    nodes = list(st.get("Peer", {}).values()) + [st["Self"]]
    for p in nodes:
        if ip in p.get("TailscaleIPs", []):
            dns = p.get("DNSName") or p.get("HostName") or ""
            return dns.split(".")[0] or None
    return None


# ----------------------------------------------------------------------------
# Alertmanager / Prometheus helpers
# ----------------------------------------------------------------------------
def http_json(url, timeout=10):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return json.load(r)


def active_alerts(node=None):
    """Compact list of active Alertmanager alerts, optionally for one node."""
    params = [("active", "true"), ("silenced", "false")]
    if node:
        params.append(("filter", f'node="{node}"'))
    alerts = http_json(f"{ALERTMANAGER_URL}/api/v2/alerts?" + urllib.parse.urlencode(params))
    out = []
    for a in alerts:
        st = a.get("status", {})
        out.append({
            "alertname": a["labels"].get("alertname"),
            "severity": a["labels"].get("severity", "warning"),
            "node": a["labels"].get("node") or a["labels"].get("instance"),
            "summary": a.get("annotations", {}).get("summary", ""),
            "state": st.get("state"),
            "muted": bool(st.get("mutedBy")),
            "inhibited": bool(st.get("inhibitedBy")),
            "since": a.get("startsAt"),
        })
    return out


# ----------------------------------------------------------------------------
# HTTP relay (Tailscale interface only)
# ----------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    server_version = "infra-bot/1"

    def log_message(self, fmt, *args):  # route through logging
        log.info("%s %s", self.client_address[0], fmt % args)

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _caller(self):
        ip = self.client_address[0]
        try:
            host = peer_hostname(ip)
        except Exception as e:  # tailscale hiccup: refuse rather than guess
            log.warning("identity lookup failed for %s: %s", ip, e)
            host = None
        return ip, host

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(url.query)
        if url.path == "/health":
            return self._json(200, {"ok": True})
        if url.path == "/alerts":
            ip, host = self._caller()
            if not host:
                return self._json(403, {"error": "not a tailnet peer"})
            node = (q.get("node") or [None])[0]
            try:
                return self._json(200, {"node": node, "alerts": active_alerts(node)})
            except Exception as e:
                log.warning("alertmanager query failed: %s", e)
                return self._json(502, {"error": f"alertmanager: {e}"})
        return self._json(404, {"error": "unknown path"})

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        ip, host = self._caller()
        if not host:
            return self._json(403, {"error": "not a tailnet peer"})
        try:
            n = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(min(n, 65536)) or b"{}")
        except Exception:
            return self._json(400, {"error": "bad json"})
        if url.path == "/deploy":
            text = str(payload.get("text", "")).strip()
            if not text:
                return self._json(400, {"error": "text required"})
            # The caller formats the message; we only vouch for who sent it.
            node = NODE_MAP.get(host, host)
            claimed = payload.get("hostname")
            if claimed and claimed != host:
                log.warning("deploy relay: %s (%s) claims to be %s", host, ip, claimed)
                text = f"⚠️ <i>relayed by {host}, message claims {claimed}</i>\n" + text
            try:
                send(text, THREAD_DEPLOYS)
            except Exception as e:
                log.error("telegram send failed: %s", e)
                return self._json(502, {"error": f"telegram: {e}"})
            log.info("deploy announced for %s (%s)", node, ip)
            return self._json(200, {"ok": True, "node": node})
        return self._json(404, {"error": "unknown path"})


def run_relay():
    # tailscaled may still be coming up at boot; the unit has After= but the IP
    # can lag, so retry instead of dying.
    for attempt in range(30):
        try:
            ip = self_ipv4()
            break
        except Exception as e:
            log.warning("waiting for tailscale ip (%s)", e)
            time.sleep(5)
    else:
        log.error("no tailscale IPv4 after 150s, relay disabled")
        return
    srv = ThreadingHTTPServer((ip, LISTEN_PORT), Handler)
    srv.daemon_threads = True
    log.info("relay listening on %s:%d", ip, LISTEN_PORT)
    srv.serve_forever()


# ----------------------------------------------------------------------------
# Telegram commands + weekly digest (F3)
# ----------------------------------------------------------------------------
def run_commands():
    log.info("command handling not enabled yet (F3)")
    while True:
        time.sleep(3600)


# ----------------------------------------------------------------------------
def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stdout)
    if not TOKEN or not CHAT_ID:
        log.error("TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID missing")
        sys.exit(1)
    if "--selftest" in sys.argv:
        print(json.dumps(active_alerts(), indent=1))
        print("self ip:", self_ipv4())
        return
    t = threading.Thread(target=run_relay, name="relay", daemon=True)
    t.start()
    run_commands()


if __name__ == "__main__":
    main()
