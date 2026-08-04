#!/usr/bin/env python3
"""AkuCraft Telegram bot - status announcements + group commands.

Runs as systemd service akucraft-status-bot on VPS_PROD (akucraft-status-bot.nix).
Stdlib only. Talks to the two rootless-docker Minecraft containers via the
docker CLI (DOCKER_HOST set by the unit) and to Telegram via the Bot API.

Features:
  - announces server ONLINE/OFFLINE (health transitions)
  - announces player joins/leaves (RCON `list` diff)
  - announces deaths and advancements (docker log tailing)
  - auto-stops a server empty for IDLE_STOP_MINUTES and announces it
  - group commands: /start /stop /status /players /connect /vpn /help
    (only honored in the configured group chat)
"""

import json
import os
import re
import subprocess
import threading
import time
import urllib.parse
import urllib.request

TOKEN = os.environ["TG_TOKEN"]
CHAT = int(os.environ["TG_CHAT"])
API = "https://api.telegram.org/bot" + TOKEN
STATE_DIR = os.environ.get("STATE_DIRECTORY", "/var/lib/akucraft-status")
IDLE_STOP_MIN = int(os.environ.get("IDLE_STOP_MINUTES", "45"))
GROUP_LINK = os.environ.get("TG_GROUP_LINK", "")

SERVERS = {
    "survival": {
        "label": "Survival",
        "container": "minecraft",
        "dir": "/home/akunito/.homelab/minecraft",
        "address": "akucraft.local.akunito.com",
    },
    "creative": {
        "label": "Creative",
        "container": "minecraft-creative",
        "dir": "/home/akunito/.homelab/minecraft-creative",
        "address": "akucraft.local.akunito.com:25566",
    },
}

DEATH_KEYWORDS = (
    "was slain by", "was shot by", "drowned", "fell from a high place",
    "fell off", "blew up", "was blown up by", "burned to death",
    "tried to swim in lava", "hit the ground too hard", "starved to death",
    "suffocated in a wall", "was killed by", "went up in flames",
    "walked into fire", "was struck by lightning", "froze to death",
    "was skewered by", "was squashed by", "withered away",
    "was pricked to death", "walked into a cactus", "was impaled",
    "was squished too much", "was poked to death", "was stung to death",
    "was obliterated by", "left the confines of this world",
    "didn't want to live in the same world as", "experienced kinetic energy",
    "went off with a bang", "was doomed to fall", "died",
)

CONNECT_TEXT = """How to join AkuCraft:

1. You need the VPN active (see /vpn).
2. Launcher: FreeSM Launcher (no paid account needed):
   https://github.com/FreesmTeam/FreesmLauncher/releases
   Add an OFFLINE account with your player name.
3. Instance: Minecraft 1.21.1 + Fabric Loader 0.19.3, with these 5 mods:
   fabric-api 0.116.15, supplementaries 3.8.2, moonlight 3.1.1,
   flan 1.12.7, lithium 0.15.4 (ask for the download links or check
   your invite email - exact versions matter).
4. Servers:
   Survival: akucraft.local.akunito.com
   Creative: akucraft.local.akunito.com:25566
5. First join: /auth register <password> <password>
   Later joins: /auth login <password>"""

VPN_TEXT = """VPN (Tailscale) setup:

The servers are reachable only through our private VPN. Your access key
gives your device access to the Minecraft servers and NOTHING else.

1. Install Tailscale: https://tailscale.com/download
2. Ask Diego here in the group for your personal invite key.
3. In a terminal (Windows: PowerShell):
   tailscale login --login-server https://headscale.akunito.com --auth-key <YOUR-KEY>
   (macOS app: /Applications/Tailscale.app/Contents/MacOS/Tailscale login ...)
4. Done - check with /status that a server is up, then join!"""

HELP_TEXT = """AkuCraft bot commands:
/status - servers status + who is online
/players - who is playing right now
/start [survival|creative] - boot a stopped server
/stop [survival|creative] - stop a server (refuses if players online)
/connect - how to join the servers
/vpn - how to set up the VPN (Tailscale)
/help - this message

I also announce: servers going on/offline, joins/leaves, deaths,
advancements, and I auto-stop servers left empty for a while."""


def log(msg):
    print(msg, flush=True)


def send(text):
    try:
        data = urllib.parse.urlencode({"chat_id": CHAT, "text": text}).encode()
        urllib.request.urlopen(API + "/sendMessage", data, timeout=15).read()
    except Exception as e:  # noqa: BLE001 - never crash on telegram hiccups
        log(f"sendMessage failed: {e}")


def run(cmd, timeout=30, cwd=None):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd)
        return p.returncode, p.stdout.strip()
    except Exception as e:  # noqa: BLE001
        return 1, str(e)


def health(container):
    rc, out = run(["docker", "inspect", "-f", "{{.State.Health.Status}}", container], 15)
    return out if rc == 0 else "absent"


def rcon(container, command):
    rc, out = run(["docker", "exec", container, "rcon-cli", command], 20)
    return out if rc == 0 else ""


def online_players(container):
    out = rcon(container, "list")
    m = re.search(r"players online:\s*(.*)$", out)
    if not m or not m.group(1).strip():
        return set()
    return {p.strip() for p in m.group(1).split(",") if p.strip()}


def compose(server, action):
    return run(["docker-compose", "-f", server["dir"] + "/docker-compose.yml", action] +
               (["-d"] if action == "up" else []), 180, cwd=server["dir"])


class State:
    """Per-server runtime + persisted (across restarts) online state."""

    def __init__(self, name):
        self.name = name
        self.file = os.path.join(STATE_DIR, SERVERS[name]["container"] + ".state")
        try:
            self.online = open(self.file).read().strip() == "online"
        except OSError:
            self.online = None  # unknown: don't announce on first observation
        self.players = set()
        self.idle_since = None
        self.suppress_offline = False  # set by /stop and auto-stop

    def persist(self, online):
        self.online = online
        with open(self.file, "w") as f:
            f.write("online" if online else "offline")


STATES = {name: State(name) for name in SERVERS}
LOCK = threading.Lock()


def monitor():
    while True:
        for name, srv in SERVERS.items():
            st = STATES[name]
            try:
                is_online = health(srv["container"]) == "healthy"
                with LOCK:
                    prev = st.online
                    if is_online != prev:
                        if is_online:
                            send(f"\U0001F7E2 AkuCraft {srv['label']} is ONLINE - connect: {srv['address']}")
                            st.idle_since = None
                            st.suppress_offline = False
                        elif prev and not st.suppress_offline:
                            send(f"\U0001F534 AkuCraft {srv['label']} went OFFLINE")
                        st.persist(is_online)
                    if not is_online:
                        st.players = set()
                        continue

                players = online_players(srv["container"])
                with LOCK:
                    if st.players != players and st.online:
                        joined = players - st.players
                        left = st.players - players
                        n = len(players)
                        if joined:
                            send(f"\U0001F3AE {', '.join(sorted(joined))} joined {srv['label']} ({n} online)")
                        if left:
                            send(f"\U0001F44B {', '.join(sorted(left))} left {srv['label']} ({n} online)")
                    st.players = players

                    # Auto-stop when empty
                    if players:
                        st.idle_since = None
                    elif st.idle_since is None:
                        st.idle_since = time.time()
                    elif time.time() - st.idle_since > IDLE_STOP_MIN * 60:
                        st.suppress_offline = True
                        st.idle_since = None
                        send(f"⏸ AkuCraft {srv['label']} was empty for {IDLE_STOP_MIN} min - "
                             f"stopping it to save resources. Use /start {name} to boot it again.")
                        compose(srv, "stop")
                        st.persist(False)
            except Exception as e:  # noqa: BLE001
                log(f"monitor {name}: {e}")
        time.sleep(45)


def tail_logs(name):
    srv = SERVERS[name]
    info = re.compile(r"\[Server thread/INFO\]: (.*)$")
    adv = re.compile(r"^(\S+) has (?:made the advancement|completed the challenge|reached the goal) (.+)$")
    while True:
        if health(srv["container"]) == "absent":
            time.sleep(30)
            continue
        try:
            proc = subprocess.Popen(
                ["docker", "logs", "-f", "--tail", "0", srv["container"]],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in proc.stdout:
                m = info.search(line)
                if not m:
                    continue
                msg = m.group(1).strip()
                if msg.startswith("<"):  # chat line, never parse
                    continue
                a = adv.match(msg)
                if a:
                    send(f"\U0001F3C6 [{srv['label']}] {a.group(1)} got {a.group(2)}")
                    continue
                first = msg.split(" ", 1)[0]
                with LOCK:
                    known = first in STATES[name].players
                if known and any(k in msg for k in DEATH_KEYWORDS):
                    send(f"\U0001F480 [{srv['label']}] {msg}")
            proc.wait()
        except Exception as e:  # noqa: BLE001
            log(f"tail {name}: {e}")
        time.sleep(15)


def pick_targets(arg):
    if arg in SERVERS:
        return [arg]
    if not arg:
        return list(SERVERS)
    return []


def cmd_start(arg):
    targets = pick_targets(arg)
    if not targets:
        return "Usage: /start [survival|creative]"
    replies = []
    for name in targets:
        srv = SERVERS[name]
        h = health(srv["container"])
        if h == "healthy":
            replies.append(f"\U0001F7E2 {srv['label']} is already running.")
        elif h == "starting":
            replies.append(f"\U0001F7E1 {srv['label']} is already starting...")
        else:
            compose(srv, "up")
            replies.append(f"\U0001F680 Starting {srv['label']} - I'll announce when it's ready (~1 min).")
    return "\n".join(replies)


def cmd_stop(arg):
    targets = pick_targets(arg)
    if not targets:
        return "Usage: /stop [survival|creative]"
    replies = []
    for name in targets:
        srv = SERVERS[name]
        if health(srv["container"]) != "healthy":
            replies.append(f"\U0001F534 {srv['label']} is not running.")
            continue
        players = online_players(srv["container"])
        if players:
            replies.append(f"\U0001F465 {srv['label']}: {len(players)} player(s) online "
                           f"({', '.join(sorted(players))}) - not stopping.")
            continue
        with LOCK:
            STATES[name].suppress_offline = True
            STATES[name].persist(False)
        compose(srv, "stop")
        replies.append(f"⏹ {srv['label']} stopped. /start {name} boots it again.")
    return "\n".join(replies)


def cmd_status():
    lines = []
    for name, srv in SERVERS.items():
        h = health(srv["container"])
        if h == "healthy":
            players = online_players(srv["container"])
            who = f" - online: {', '.join(sorted(players))}" if players else " - nobody on"
            lines.append(f"\U0001F7E2 {srv['label']}: UP ({srv['address']}){who}")
        elif h == "starting":
            lines.append(f"\U0001F7E1 {srv['label']}: starting...")
        else:
            lines.append(f"\U0001F534 {srv['label']}: offline - /start {name}")
    return "\n".join(lines)


def cmd_players():
    lines = []
    for name, srv in SERVERS.items():
        if health(srv["container"]) == "healthy":
            players = online_players(srv["container"])
            lines.append(f"{srv['label']}: " +
                         (", ".join(sorted(players)) if players else "nobody"))
    return "\n".join(lines) if lines else "No server is running. /start boots one."


def handle(text):
    parts = text.split()
    cmd = parts[0].split("@")[0].lstrip("/").lower()
    arg = parts[1].lower() if len(parts) > 1 else ""
    if cmd == "start":
        return cmd_start(arg)
    if cmd == "stop":
        return cmd_stop(arg)
    if cmd == "status":
        return cmd_status()
    if cmd == "players":
        return cmd_players()
    if cmd == "connect":
        return CONNECT_TEXT
    if cmd == "vpn":
        return VPN_TEXT
    if cmd == "help":
        return HELP_TEXT
    return None


def poll():
    offset_file = os.path.join(STATE_DIR, "offset")
    try:
        offset = int(open(offset_file).read().strip())
    except (OSError, ValueError):
        offset = 0
    while True:
        try:
            qs = urllib.parse.urlencode({
                "timeout": 50, "offset": offset,
                "allowed_updates": json.dumps(["message"]),
            })
            with urllib.request.urlopen(API + f"/getUpdates?{qs}", timeout=70) as r:
                updates = json.load(r).get("result", [])
            for u in updates:
                offset = u["update_id"] + 1
                msg = u.get("message") or {}
                text = msg.get("text", "")
                if not text.startswith("/"):
                    continue
                if msg.get("chat", {}).get("id") != CHAT:
                    continue  # only the AkuCraft group may command the bot
                reply = handle(text)
                if reply:
                    send(reply)
            with open(offset_file, "w") as f:
                f.write(str(offset))
        except Exception as e:  # noqa: BLE001
            log(f"poll: {e}")
            time.sleep(10)


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    threading.Thread(target=monitor, daemon=True).start()
    for name in SERVERS:
        threading.Thread(target=tail_logs, args=(name,), daemon=True).start()
    log("akucraft bot up")
    poll()


if __name__ == "__main__":
    main()
