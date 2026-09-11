#!/usr/bin/env python3
"""Infra Alerts Telegram bot (AINF-368).

One daemon on VPS_PROD, next to Prometheus and Alertmanager. Three halves:

  1. HTTP relay on the Tailscale interface ONLY (no auth: identity is the
     source Tailscale IP, resolved to a peer with `tailscale status`):
       POST /deploy   {"text": "<html>"}     -> posts into the 🚀 Deploys topic
       GET  /alerts?node=<name>             -> active alerts for that node
                                               (Alertmanager proxy, JSON)
       GET  /health
     Secrets-free nodes (LAPTOP_A, DESK_A, YOGA) announce their deploys through
     this; nodes that hold the bot token talk to Telegram directly and only use
     /alerts here.

  2. Group commands via long polling, answered in the topic they were asked in:
       /status                 one led line per node
       /status <node> [full]   details; "full" lists every container/unit
       /alerts                 active alerts by node (🔴 critical 🟡 warning)
       /deploys                last generation change per node
       /help
     Data: Prometheus instant queries + Alertmanager API. Read-only.

  3. Sunday digest into 📋 Weekly: node leds + every active warning.

  4. /restart <node> docker-rootless|docker-rootful — the ONLY write action.
     Admin user ids only, inline ✅/❌ confirmation (2 min), then
     `sudo -n infra-restart <target>` locally or over BatchMode ssh for nodes
     listed in RESTART_SSH_TARGETS. system/app/infra-restart.nix owns the
     sudoers rule and the allow-list.

Config comes from the environment (infra-bot.nix). `infra-bot --selftest`
prints every handler's output without touching Telegram.
"""
import datetime as dt
import json
import logging
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zoneinfo
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from tgcommon import Telegram, esc  # shared with plane-bot (system/app/tgcommon.py)

log = logging.getLogger("infra-bot")

TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")
THREAD_DEPLOYS = os.environ.get("THREAD_DEPLOYS", "")
THREAD_ALERTS = os.environ.get("THREAD_ALERTS", "")
THREAD_WEEKLY = os.environ.get("THREAD_WEEKLY", "")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8765"))
ALERTMANAGER_URL = os.environ.get("ALERTMANAGER_URL", "http://127.0.0.1:9093")
PROMETHEUS_URL = os.environ.get("PROMETHEUS_URL", "http://127.0.0.1:9090")
STATE_DIR = os.environ.get("STATE_DIR", "/var/lib/infra-bot")
TZ = zoneinfo.ZoneInfo(os.environ.get("TZ", "Europe/Warsaw"))
# tailscale hostname -> node label used by Prometheus/Alertmanager
NODE_MAP = json.loads(os.environ.get("NODE_MAP", "{}"))
# the NAS sleeps on a timer: "down" inside this window is 💤, not 🔴
SLEEP_NODE = os.environ.get("SLEEP_NODE", "nas")
SLEEP_FROM, SLEEP_TO = (os.environ.get("SLEEP_WINDOW", "23:00-16:05").split("-") + ["16:05"])[:2]
DIGEST_DAY = int(os.environ.get("DIGEST_WEEKDAY", "6"))  # Monday=0 .. Sunday=6
DIGEST_HOUR = int(os.environ.get("DIGEST_HOUR", "10"))
ADMIN_USER_IDS = {x.strip() for x in os.environ.get("ADMIN_USER_IDS", "").split(",") if x.strip()}
RESTART_SSH_TARGETS = json.loads(os.environ.get("RESTART_SSH_TARGETS", "{}"))
LOCAL_NODE = os.environ.get("LOCAL_NODE", "vps")
RESTART_TARGETS = ("docker-rootless", "docker-rootful")
CONFIRM_TTL = 120
BOT_NAME = ""
TG = Telegram(TOKEN)

REAL_FS = 'fstype!~"tmpfs|overlay|squashfs|devtmpfs|efivarfs|ramfs|fuse.*|nsfs|autofs|zfs"'


def telegram(method, timeout=20, **params):
    return TG.call(method, timeout=timeout, **params)


def send(text, thread=None, reply_to=None, reply_markup=None):
    """HTML message into the group; thread = forum topic id ('' = General)."""
    return TG.send(CHAT_ID, text, thread, reply_to, reply_markup)


def edit(message_id, text, reply_markup=None):
    return TG.edit(CHAT_ID, message_id, text, reply_markup)


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
# Prometheus / Alertmanager
# ----------------------------------------------------------------------------
def http_json(url, timeout=10):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return json.load(r)


def promq(expr):
    """Instant query -> list of (labels, float)."""
    q = urllib.parse.urlencode({"query": expr})
    res = http_json(f"{PROMETHEUS_URL}/api/v1/query?{q}")
    if res.get("status") != "success":
        raise RuntimeError(f"prometheus: {res}")
    out = []
    for r in res["data"]["result"]:
        try:
            out.append((r["metric"], float(r["value"][1])))
        except (KeyError, ValueError):
            pass
    return out


def prom_by(expr, key="node"):
    """Instant query -> {label value: float} (first sample per key)."""
    d = {}
    for m, v in promq(expr):
        d.setdefault(m.get(key, ""), v)
    return d


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
# Status model
# ----------------------------------------------------------------------------
def in_sleep_window(now=None):
    now = now or dt.datetime.now(TZ)
    t = now.strftime("%H:%M")
    return t >= SLEEP_FROM or t < SLEEP_TO


def age(seconds):
    s = int(seconds)
    if s < 0:
        return "?"
    if s < 3600:
        return f"{s // 60}m"
    if s < 86400:
        return f"{s // 3600}h"
    return f"{s // 86400}d"


def led_of(items):
    """Worst led among strings starting with an emoji led."""
    order = {"🔴": 3, "🟡": 2, "🟢": 1}
    worst = "🟢"
    for it in items:
        for k in order:
            if it.startswith(k) and order[k] > order[worst]:
                worst = k
    return worst


def nodes():
    """All nodes Prometheus knows, with role and reachability."""
    up = {}
    for m, v in promq('max by (node, role) (up{job=~".*_node|snmp_.*"})'):
        n = m.get("node")
        if n:
            up[n] = {"role": m.get("role", "roaming"), "up": v == 1}
    return up


def node_facts(node):
    """Everything /status shows for one node; every key optional."""
    f = {}
    q = lambda e: prom_by(e).get(node)  # noqa: E731
    f["boot"] = q(f'node_boot_time_seconds{{node="{node}"}}')
    f["load"] = q(f'node_load1{{node="{node}"}}')
    f["cpus"] = q(f'count by (node) (node_cpu_seconds_total{{node="{node}",mode="idle"}})')
    f["mem"] = q(f'(1 - node_memory_MemAvailable_bytes{{node="{node}"}} / node_memory_MemTotal_bytes{{node="{node}"}}) * 100')
    f["disks"] = {m["mountpoint"]: v for m, v in promq(
        f'(1 - node_filesystem_avail_bytes{{node="{node}",{REAL_FS}}} / node_filesystem_size_bytes{{node="{node}",{REAL_FS}}}) * 100')}
    f["pools"] = {m["pool"]: v for m, v in promq(f'nas_zfs_pool_allocated_bytes{{node="{node}"}} / nas_zfs_pool_size_bytes{{node="{node}"}} * 100')}
    f["pool_health"] = {m["pool"]: v for m, v in promq(f'nas_zfs_pool_healthy{{node="{node}"}}')}
    f["docker"] = {m["mode"]: v for m, v in promq(f'host_docker_daemon_up{{node="{node}"}}')}
    f["containers"] = sorted({m["name"] for m, _ in promq(f'container_last_seen{{node="{node}",name!=""}} > time() - 60')})
    f["containers_gone"] = sorted({m["name"] for m, _ in promq(f'container_last_seen{{node="{node}",name!=""}} <= time() - 60')} - set(f["containers"]))
    failed = {m["name"] for m, _ in promq(f'node_systemd_unit_state{{node="{node}",state="failed"}} == 1')}
    failed |= {m["name"] + (" (user)" if m.get("scope") == "user" else "") for m, _ in promq(f'host_systemd_unit_failed{{node="{node}"}} == 1')}
    f["failed"] = sorted(failed)
    f["updated"] = q(f'nixos_last_update_system_timestamp{{node="{node}"}}')
    f["tailscale"] = q(f'tailscale_backend_running{{node="{node}"}}')
    # pfSense via SNMP
    f["pf_cpu"] = q(f'avg by (node) (hrProcessorLoad{{node="{node}"}})')
    f["pf_mem"] = q(f'(1 - memAvailReal{{node="{node}"}} / memTotalReal{{node="{node}"}}) * 100')
    f["pf_disk"] = q(f'hrStorageUsed{{node="{node}",hrStorageDescr="/"}} / hrStorageSize{{node="{node}",hrStorageDescr="/"}} * 100')
    f["pf_ifaces_down"] = [m.get("ifDescr", "?") for m, _ in promq(
        f'ifOperStatus{{node="{node}"}} == 2 and on(ifIndex) ifAdminStatus{{node="{node}"}} == 1')]
    return f


def pct_led(v, warn=85, crit=95):
    return "🔴" if v >= crit else "🟡" if v >= warn else "🟢"


def node_alert_leds(alerts):
    """Unmuted, uninhibited alerts -> (critical count, warning count)."""
    live = [a for a in alerts if not a["muted"] and not a["inhibited"]]
    return sum(a["severity"] == "critical" for a in live), sum(a["severity"] != "critical" for a in live)


def summary_line(node, info, alerts, now):
    """One line for /status and the digest."""
    crit, warn = node_alert_leds(alerts)
    if not info["up"]:
        if node == SLEEP_NODE and in_sleep_window(now):
            return f"💤 <b>{esc(node)}</b> · asleep ({SLEEP_FROM}–{SLEEP_TO})"
        if info["role"] == "always_on":
            return f"🔴 <b>{esc(node)}</b> · DOWN"
        return f"⚪ <b>{esc(node)}</b> · offline"
    f = node_facts(node)
    parts = []
    if f["boot"]:
        parts.append(f"up {age(time.time() - f['boot'])}")
    if f["load"] is not None:
        parts.append(f"load {f['load']:.1f}" + (f"/{int(f['cpus'])}" if f["cpus"] else ""))
    if f["mem"] is not None:
        parts.append(f"{pct_led(f['mem'], 90, 97)} mem {f['mem']:.0f}%")
    if f["pf_cpu"] is not None:
        parts.append(f"cpu {f['pf_cpu']:.0f}%")
    if f["pf_mem"] is not None:
        parts.append(f"{pct_led(f['pf_mem'], 90, 97)} mem {f['pf_mem']:.0f}%")
    if f["pf_disk"] is not None:
        parts.append(f"{pct_led(f['pf_disk'])} disk {f['pf_disk']:.0f}%")
    if f["disks"]:
        worst_m, worst_v = max(f["disks"].items(), key=lambda kv: kv[1])
        parts.append(f"{pct_led(worst_v)} disk {worst_v:.0f}%" + ("" if worst_m == "/" else f" {esc(worst_m)}"))
    for p, v in f["pools"].items():
        healthy = f["pool_health"].get(p, 1) == 1
        parts.append(f"{'🔴' if not healthy else pct_led(v, 80, 90)} {esc(p)} {v:.0f}%")
    for mode, v in f["docker"].items():
        if v != 1:
            parts.append(f"🔴 docker {esc(mode)} down")
    if f["containers"]:
        parts.append(f"{len(f['containers'])} ctr" + (f" (🟡 {len(f['containers_gone'])} stopped)" if f["containers_gone"] else ""))
    if f["failed"]:
        parts.append(f"🔴 {len(f['failed'])} failed unit" + ("s" if len(f["failed"]) > 1 else ""))
    if f["pf_ifaces_down"]:
        parts.append(f"🔴 iface down: {esc(', '.join(f['pf_ifaces_down']))}")
    if f["tailscale"] == 0:
        parts.append("🔴 tailscale down")
    if f["updated"]:
        parts.append(f"updated {age(time.time() - f['updated'])} ago")
    if crit:
        parts.append(f"🔴 {crit} critical")
    if warn:
        parts.append(f"🟡 {warn} warning" + ("s" if warn > 1 else ""))
    led = "🔴" if crit or any(p.startswith("🔴") for p in parts) else led_of(parts)
    return f"{led} <b>{esc(node)}</b> · " + " · ".join(parts)


def cmd_status(args):
    now = dt.datetime.now(TZ)
    info = nodes()
    if not info:
        return "Prometheus reports no nodes."
    alerts = active_alerts()
    by_node = {}
    for a in alerts:
        by_node.setdefault(a["node"], []).append(a)
    if args:
        node = args[0].lower()
        if node not in info:
            return f"Unknown node <b>{esc(node)}</b>. Known: {esc(', '.join(sorted(info)))}"
        return status_detail(node, info[node], by_node.get(node, []), "full" in args[1:], now)
    order = sorted(info, key=lambda n: (info[n]["role"] != "always_on", n))
    lines = [summary_line(n, info[n], by_node.get(n, []), now) for n in order]
    return "\n".join(lines)


def status_detail(node, info, alerts, full, now):
    head = summary_line(node, info, alerts, now)
    if not info["up"]:
        seen = prom_by(f'max_over_time(timestamp(up{{node="{node}",job=~".*_node|snmp_.*"}} == 1)[7d:5m])')
        last = seen.get(node)
        return head + (f"\nlast seen {age(time.time() - last)} ago" if last else "")
    f = node_facts(node)
    out = [head]
    if f["disks"]:
        ds = sorted(f["disks"].items(), key=lambda kv: -kv[1])
        shown = ds if full else [d for d in ds if d[1] >= 85] or ds[:1]
        out.append("<b>Disks</b> " + " · ".join(f"{pct_led(v)} {esc(m)} {v:.0f}%" for m, v in shown)
                   + ("" if full or len(shown) == len(ds) else f" (+{len(ds) - len(shown)} ok)"))
    if f["pools"]:
        out.append("<b>ZFS</b> " + " · ".join(
            f"{'🔴' if f['pool_health'].get(p, 1) != 1 else pct_led(v, 80, 90)} {esc(p)} {v:.0f}%"
            + ("" if f["pool_health"].get(p, 1) == 1 else " DEGRADED") for p, v in f["pools"].items()))
    if f["docker"]:
        out.append("<b>Docker</b> " + " · ".join(f"{'🟢' if v == 1 else '🔴'} {esc(m)}" for m, v in f["docker"].items()))
    if f["containers"] or f["containers_gone"]:
        if full:
            out.append("<b>Containers</b>\n" + "\n".join([f"🟢 {esc(c)}" for c in f["containers"]] + [f"🔴 {esc(c)}" for c in f["containers_gone"]]))
        else:
            out.append(f"<b>Containers</b> {len(f['containers'])} running"
                       + (f", not running: {esc(', '.join(f['containers_gone']))}" if f["containers_gone"] else " 🟢")
                       + f"  (<code>/status {esc(node)} full</code> lists them)")
    if f["failed"]:
        out.append("<b>Failed units</b> " + " · ".join(f"🔴 {esc(u)}" for u in f["failed"]))
    elif f["docker"] or full:
        out.append("🟢 no failed units")
    live = [a for a in alerts if not a["muted"] and not a["inhibited"]]
    if live:
        out.append("<b>Alerts</b>\n" + "\n".join(
            f"{'🔴' if a['severity'] == 'critical' else '🟡'} {esc(a['alertname'])} — {esc(a['summary'])}" for a in live))
    else:
        out.append("🟢 no active alerts")
    if f["updated"]:
        out.append(f"Last update: {dt.datetime.fromtimestamp(f['updated'], TZ).strftime('%Y-%m-%d %H:%M')} ({age(time.time() - f['updated'])} ago)")
    return "\n".join(out)


def cmd_alerts(args):
    alerts = active_alerts()
    if not alerts:
        return "🟢 no active alerts"
    by_node = {}
    for a in alerts:
        by_node.setdefault(a["node"] or "-", []).append(a)
    out = []
    for node in sorted(by_node):
        out.append(f"<b>{esc(node)}</b>")
        for a in sorted(by_node[node], key=lambda a: (a["severity"] != "critical", a["alertname"])):
            led = "🔴" if a["severity"] == "critical" else "🟡"
            tag = " (muted)" if a["muted"] else " (inhibited)" if a["inhibited"] else ""
            out.append(f"{led} {esc(a['alertname'])}{tag} — {esc(a['summary'])}")
    return "\n".join(out)


def cmd_deploys(args):
    ts = prom_by("nixos_last_update_system_timestamp")
    if not ts:
        return "no update timestamps in Prometheus"
    now = time.time()
    out = []
    for node, t in sorted(ts.items(), key=lambda kv: -kv[1]):
        stale = now - t > 14 * 86400
        out.append(f"{'🟡' if stale else '🟢'} <b>{esc(node)}</b> · {dt.datetime.fromtimestamp(t, TZ).strftime('%a %Y-%m-%d %H:%M')} ({age(now - t)} ago)")
    return "<b>Last generation change per node</b>\n" + "\n".join(out)


def cmd_help(args):
    return ("<b>Infra Alerts bot</b> — read-only\n"
            "/status — one line per node\n"
            "/status &lt;node&gt; [full] — details (full = every container)\n"
            "/alerts — active alerts by node\n"
            "/deploys — last generation change per node\n"
            "/restart &lt;node&gt; docker-rootless|docker-rootful — admins only, asks to confirm\n"
            "Alerts: 🔴 critical → 🚨 Alerts topic once + 🟢 resolved · 🟡 warnings → Sunday digest in 📋 Weekly")


# ----------------------------------------------------------------------------
# /restart — confirm, then run infra-restart locally or over ssh
# ----------------------------------------------------------------------------
PENDING = {}  # nonce -> {node, target, user, created, message_id}


def restart_nodes():
    return [LOCAL_NODE] + sorted(RESTART_SSH_TARGETS)


def run_restart(node, target, check=False):
    """Returns (ok, output). Never raises."""
    args = ["sudo", "-n", "infra-restart", target] + (["--check"] if check else [])
    if node != LOCAL_NODE:
        host = RESTART_SSH_TARGETS.get(node)
        if not host:
            return False, f"no ssh target configured for {node}"
        args = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=accept-new", host] + args
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return False, "timed out after 120s"
    text = (out.stdout + out.stderr).strip()
    return out.returncode == 0, text or f"exit {out.returncode}"


def cmd_restart(args, user=None, thread=None, message_id=None):
    if str(user) not in ADMIN_USER_IDS:
        return "⛔ /restart is limited to admins."
    if len(args) != 2 or args[0].lower() not in restart_nodes() or args[1].lower() not in RESTART_TARGETS:
        return (f"usage: /restart &lt;{esc('|'.join(restart_nodes()))}&gt; &lt;{esc('|'.join(RESTART_TARGETS))}&gt;")
    node, target = args[0].lower(), args[1].lower()
    ok, out = run_restart(node, target, check=True)
    if not ok:
        return f"⛔ {esc(node)} refuses {esc(target)}: <code>{esc(out)}</code>"
    nonce = uuid.uuid4().hex[:12]
    warn = "every container of that daemon restarts" + (" (rootless has no live-restore)" if target == "docker-rootless" else "")
    text = (f"⚠️ Restart <b>{esc(target)}</b> on <b>{esc(node)}</b>?\n<i>{esc(warn)}</i>\n"
            f"<code>{esc(out)}</code>")
    kb = {"inline_keyboard": [[
        {"text": "✅ Restart", "callback_data": f"restart:{nonce}:yes"},
        {"text": "❌ Cancel", "callback_data": f"restart:{nonce}:no"},
    ]]}
    m = send(text, thread, reply_to=message_id, reply_markup=kb)
    PENDING[nonce] = {"node": node, "target": target, "user": str(user), "created": time.time(), "message_id": m["message_id"]}
    return None  # already answered


def handle_callback(cq):
    data = cq.get("data", "")
    user = str(cq.get("from", {}).get("id"))
    cq_id = cq.get("id")
    try:
        _, nonce, answer = data.split(":")
    except ValueError:
        return
    p = PENDING.get(nonce)
    if not p:
        telegram("answerCallbackQuery", callback_query_id=cq_id, text="expired")
        return
    if user != p["user"] and user not in ADMIN_USER_IDS:
        telegram("answerCallbackQuery", callback_query_id=cq_id, text="not yours")
        return
    del PENDING[nonce]
    head = f"<b>{esc(p['target'])}</b> on <b>{esc(p['node'])}</b>"
    if answer != "yes" or time.time() - p["created"] > CONFIRM_TTL:
        telegram("answerCallbackQuery", callback_query_id=cq_id, text="cancelled")
        edit(p["message_id"], f"❌ Restart {head} cancelled" + ("" if answer != "yes" else " (confirmation expired)"))
        return
    telegram("answerCallbackQuery", callback_query_id=cq_id, text="restarting…")
    edit(p["message_id"], f"⏳ Restarting {head} …")

    def work():
        ok, out = run_restart(p["node"], p["target"])
        led = "🟢" if ok else "🔴"
        try:
            edit(p["message_id"], f"{led} Restart {head} {'done' if ok else 'FAILED'}\n<code>{esc(out)}</code>")
        except Exception as e:
            log.error("edit failed: %s", e)
        log.info("restart %s %s by %s: %s", p["node"], p["target"], p["user"], "ok" if ok else "FAILED")

    threading.Thread(target=work, daemon=True).start()


COMMANDS = {"status": cmd_status, "alerts": cmd_alerts, "deploys": cmd_deploys, "help": cmd_help, "start": cmd_help}


def handle_command(text, user=None, thread=None, message_id=None):
    parts = text.strip().split()
    cmd = parts[0][1:].split("@")[0].lower()
    if "@" in parts[0] and BOT_NAME and parts[0].split("@")[1].lower() != BOT_NAME.lower():
        return None
    if cmd == "restart":
        try:
            return cmd_restart(parts[1:], user, thread, message_id)
        except Exception as e:
            log.exception("restart failed")
            return f"⚠️ restart failed: {esc(e)}"
    fn = COMMANDS.get(cmd)
    if not fn:
        return None
    try:
        return fn(parts[1:])
    except Exception as e:
        log.exception("command %s failed", cmd)
        return f"⚠️ {esc(cmd)} failed: {esc(e)}"


# ----------------------------------------------------------------------------
# Weekly digest
# ----------------------------------------------------------------------------
def digest_text():
    now = dt.datetime.now(TZ)
    info = nodes()
    alerts = active_alerts()
    by_node = {}
    for a in alerts:
        by_node.setdefault(a["node"], []).append(a)
    order = sorted(info, key=lambda n: (info[n]["role"] != "always_on", n))
    lines = [f"📋 <b>Weekly infra digest</b> · {now.strftime('%a %Y-%m-%d')}"]
    lines += [summary_line(n, info[n], by_node.get(n, []), now) for n in order]
    warns = [a for a in alerts if a["severity"] != "critical" and not a["inhibited"]]
    if warns:
        lines.append(f"\n<b>Active warnings ({len(warns)})</b>")
        for a in sorted(warns, key=lambda a: (a["node"] or "", a["alertname"])):
            lines.append(f"🟡 {esc(a['node'])} · {esc(a['alertname'])} — {esc(a['summary'])}" + (" (muted)" if a["muted"] else ""))
    else:
        lines.append("\n🟢 no active warnings")
    crits = [a for a in alerts if a["severity"] == "critical" and not a["inhibited"] and not a["muted"]]
    if crits:
        lines.append(f"\n<b>Still-firing criticals ({len(crits)})</b>")
        lines += [f"🔴 {esc(a['node'])} · {esc(a['alertname'])} — {esc(a['summary'])}" for a in crits]
    return "\n".join(lines)


def run_digest():
    marker = os.path.join(STATE_DIR, "digest_last")
    while True:
        now = dt.datetime.now(TZ)
        stamp = now.strftime("%Y-%m-%d")
        try:
            last = open(marker).read().strip()
        except OSError:
            last = ""
        if now.weekday() == DIGEST_DAY and now.hour >= DIGEST_HOUR and last != stamp:
            try:
                send(digest_text(), THREAD_WEEKLY)
                with open(marker, "w") as fh:
                    fh.write(stamp)
                log.info("weekly digest posted")
            except Exception as e:
                log.error("digest failed: %s", e)
        time.sleep(300)


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
                text = f"⚠️ <i>relayed by {esc(host)}, message claims {esc(claimed)}</i>\n" + text
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
# Telegram long polling
# ----------------------------------------------------------------------------
def run_commands():
    global BOT_NAME
    try:
        BOT_NAME = TG.me().get("username", "")
        TG.set_commands([
            ("status", "Node leds, or /status <node> [full]"),
            ("alerts", "Active alerts by node"),
            ("deploys", "Last generation change per node"),
            ("help", "What this bot does"),
        ] + ([("restart", "Restart docker-rootless/rootful on a node (admins)")] if ADMIN_USER_IDS else []))
    except Exception as e:
        log.warning("getMe/setMyCommands failed: %s", e)

    def on_callback(cq):
        if str(cq.get("message", {}).get("chat", {}).get("id")) == str(CHAT_ID):
            handle_callback(cq)

    def on_message(m):
        text = m.get("text") or ""
        if str(m.get("chat", {}).get("id")) != str(CHAT_ID) or not text.startswith("/"):
            return
        reply = handle_command(text, m.get("from", {}).get("id"), m.get("message_thread_id"), m.get("message_id"))
        if reply is None:
            return
        try:
            send(reply, m.get("message_thread_id"), reply_to=m.get("message_id"))
        except Exception as e:
            log.error("reply failed: %s", e)

    # tgcommon.poll persists the offset, waits out 409 (another consumer) and
    # never lets one bad update kill the loop — the same contract as before.
    TG.poll(os.path.join(STATE_DIR, "offset"), on_message, on_callback)


# ----------------------------------------------------------------------------
def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stdout)
    if "--selftest" in sys.argv:
        for name, fn in (("status", cmd_status), ("status nas", lambda a: cmd_status(["nas"])),
                         ("status vps full", lambda a: cmd_status(["vps", "full"])), ("alerts", cmd_alerts),
                         ("deploys", cmd_deploys), ("digest", lambda a: digest_text())):
            print(f"===== /{name}\n{fn([])}\n")
        return
    if not TOKEN or not CHAT_ID:
        log.error("TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID missing")
        sys.exit(1)
    os.makedirs(STATE_DIR, exist_ok=True)
    threading.Thread(target=run_relay, name="relay", daemon=True).start()
    threading.Thread(target=run_digest, name="digest", daemon=True).start()
    run_commands()


if __name__ == "__main__":
    main()
