#!/usr/bin/env python3
"""AkuCraft chat bot - status announcements + commands, on Telegram and Discord.

Runs as systemd service akucraft-status-bot on VPS_PROD (akucraft-status-bot.nix).
Stdlib only. Talks to the rootless-docker Minecraft container(s) via the
docker CLI (DOCKER_HOST set by the unit) and to Telegram via the Bot API.

Features:
  - announces server ONLINE/OFFLINE (health transitions)
  - announces player joins/leaves (RCON `list` diff)
  - announces deaths and advancements (docker log tailing)
  - auto-stops a server empty for IDLE_STOP_MINUTES and announces it
  - commands: /start /stop /status /players /map /connect /vpn /help

Transports (each optional, enabled by its own env vars):
  - Telegram: long-polls getUpdates; commands honored only in TG_CHAT.
  - Discord announcements: POSTs to DISCORD_WEBHOOK (no bot account needed).
  - Discord commands: gateway (outbound WebSocket, no public endpoint) via
    discord.py, slash commands registered to DISCORD_GUILD and answered only
    in DISCORD_CHANNEL.
Announcements fan out to every configured transport; command replies go back
to whichever transport asked.
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
DISCORD_WEBHOOK = os.environ.get("DISCORD_WEBHOOK", "")
DISCORD_TOKEN = os.environ.get("DISCORD_TOKEN", "")
DISCORD_GUILD = int(os.environ.get("DISCORD_GUILD") or 0)
DISCORD_CHANNEL = int(os.environ.get("DISCORD_CHANNEL") or 0)
# Auto-role: grant these roles to members who join through one of our invites.
# Patidifusos is a general-purpose server, so joins through other invites must
# be left alone - hence attribution by invite code rather than "everyone".
DISCORD_JOIN_ROLES = [int(r) for r in os.environ.get("DISCORD_JOIN_ROLES", "").split(",") if r.strip()]
DISCORD_INVITE_CODES = {c for c in os.environ.get("DISCORD_INVITE_CODES", "").split(",") if c}
STATE_DIR = os.environ.get("STATE_DIRECTORY", "/var/lib/akucraft-status")
IDLE_STOP_MIN = int(os.environ.get("IDLE_STOP_MINUTES", "45"))
GROUP_LINK = os.environ.get("TG_GROUP_LINK", "")

SERVERS = {
    # Addresses are given as raw IP:port on purpose: the friendly hostname only
    # resolves on the home LAN (pfSense) and on tailnet clients using MagicDNS,
    # so anyone with a different resolver gets NXDOMAIN. The IP always works.
    "survival": {
        "label": "Survival",
        "container": "minecraft",
        "dir": "/home/akunito/.homelab/minecraft",
        "address": "100.64.0.6:25565",
    },
    # Creative was decommissioned 2026-08-14 (unused since 2026-08-06, last
    # container exit 7 days before that). Its world is kept on disk at
    # ~/.homelab/minecraft-creative and in the restic backups, so it can be
    # brought back by restoring this entry and its compose file.
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
3. Instance: Minecraft 1.21.1 + Fabric Loader 0.19.3, with these 9 mods.
   The exact versions matter - a mismatch kicks you when you join:
   fabric-api 0.116.15, supplementaries 3.8.2, moonlight 3.1.1,
   flan 1.12.7, lithium 0.15.4, shield-expansion 1.4.1,
   enchanting-infuser 21.1.4, puzzles-lib 21.1.52,
   forge-config-api-port 21.1.6
   (ask for the download links, or check your invite email.)
4. Add the server in Multiplayer -> Add Server (address = IP and port,
   copy it exactly):
   Survival: 100.64.0.6:25565
5. First join: /auth register <password> <password>
   Later joins: /auth login <password>

6. Skins (optional). We play offline, so by default everyone is Steve.
   The server handles skins for us - you install nothing, and everyone
   sees your skin normally.
   - Your own custom skin, no Minecraft account needed:
     register for free at https://ely.by, upload your skin there, then
     in game: /skin set ely.by <your-ely-username>
     Tip: use the same name on ely.by as your player name and the skin
     is applied automatically every time you join.
   - Copy the skin of an existing Minecraft account:
     /skin set mojang <that-account-name>
   - From an image URL:
     /skin set web classic "<url>"   (quotes required; use slim for
     the Alex-model body shape)
   - Undo with /skin clear

7. Live map + finding each other (optional, recommended).
   Website map, works in any browser with the VPN on:
     http://100.64.0.6:8100
   To also see everyone on your in-game minimap, add these client mods
   (client-side only - they change nothing on the server, and versions
   do not have to match anyone else's):
     Xaero's Minimap, Xaero's World Map, Map Link, Cloth Config, Mod Menu
   Then in game: Mod Menu -> Map Link -> General -> Server Entries -> add
     Web Map Type: Squaremap
     Server IP:    100.64.0.6:25565
     Web map link: http://100.64.0.6:8100"""

VPN_TEXT = """VPN (Tailscale) setup:

The servers are reachable only through our private VPN. Your access key
gives your device access to the Minecraft servers and NOTHING else.

1. Install Tailscale: https://tailscale.com/download
2. Ask Diego here in the group for your personal invite key.
3. In a terminal (Windows: PowerShell):
   tailscale login --login-server https://headscale.akunito.com --auth-key <YOUR-KEY>
   (macOS app: /Applications/Tailscale.app/Contents/MacOS/Tailscale login ...)
4. Done - check with /status that the server is up, then join with
   100.64.0.6:25565

Note: always use the IP and port above. Hostnames like akucraft.local...
only resolve on some networks, so the IP is the reliable way in."""

MAP_TEXT = """Live map of the survival world:

   http://100.64.0.6:8100

Open it in any browser (phone works too) with the VPN on. It shows the
whole explored world and everyone who is online right now, live.

Want the same player positions on your in-game minimap? Add these 5
mods to your instance's "mods" folder. They are CLIENT-SIDE ONLY: they
change nothing on the server, nobody else has to install them, and the
versions do not have to match anyone.

   Xaero's Minimap    https://modrinth.com/mod/xaeros-minimap
   Xaero's World Map  https://modrinth.com/mod/xaeros-world-map
   Map Link           https://modrinth.com/mod/maplink
   Cloth Config       https://modrinth.com/mod/cloth-config
   Mod Menu           https://modrinth.com/mod/modmenu

Then in game, open Mod Menu -> Map Link -> General -> Server Entries,
add one entry and fill it in exactly like this:

   Web Map Type:  Squaremap
   Server IP:     100.64.0.6:25565
   Web map link:  http://100.64.0.6:8100

Everyone online then appears on your minimap as a head icon with the
distance to them."""

HELP_TEXT = """AkuCraft bot commands:
/status - servers status + who is online
/players - who is playing right now
/start - boot the server if it is stopped
/stop - stop the server (refuses if players online)
/map - live web map + minimap mods to see each other
/connect - how to join the servers
/vpn - how to set up the VPN (Tailscale)
/help - this message

I also announce: servers going on/offline, joins/leaves, deaths,
advancements, and I auto-stop servers left empty for a while."""


def log(msg):
    print(msg, flush=True)


def post(label, req_or_url, data, timeout=15, attempts=3):
    """POST with retries. A dropped announcement is invisible to users, so a
    transient hiccup (Discord returned 403 mid permission-edit on 2026-08-07,
    Telegram flakes on network blips) must not silently lose the message."""
    for attempt in range(1, attempts + 1):
        try:
            urllib.request.urlopen(req_or_url, data, timeout=timeout).read()
            return True
        except Exception as e:  # noqa: BLE001 - chat outages must never crash us
            if attempt == attempts:
                log(f"{label} failed after {attempts} attempts: {e}")
                return False
            log(f"{label} attempt {attempt} failed ({e}), retrying")
            time.sleep(2 * attempt)
    return False


def send(text):
    """Post to the Telegram group."""
    data = urllib.parse.urlencode({"chat_id": CHAT, "text": text}).encode()
    post("telegram sendMessage", API + "/sendMessage", data)


def send_discord(text):
    """Post to the Discord channel via webhook (no bot account required)."""
    if not DISCORD_WEBHOOK:
        return
    # The User-Agent is REQUIRED: Discord/Cloudflare answers 403 Forbidden to
    # urllib's default "Python-urllib/x.y" UA (verified 2026-08-07 - curl
    # worked while the daemon silently failed). Format per Discord API docs.
    req = urllib.request.Request(DISCORD_WEBHOOK, headers={
        "Content-Type": "application/json",
        "User-Agent": "DiscordBot (https://akunito.com, 1.0)",
    })
    post("discord webhook", req, json.dumps({"content": text}).encode())


def announce(text):
    """Fan an announcement out to every configured chat transport."""
    send(text)
    send_discord(text)


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
                            announce(f"\U0001F7E2 AkuCraft {srv['label']} is ONLINE - connect: {srv['address']}")
                            st.idle_since = None
                            st.suppress_offline = False
                        elif prev and not st.suppress_offline:
                            announce(f"\U0001F534 AkuCraft {srv['label']} went OFFLINE")
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
                            announce(f"\U0001F3AE {', '.join(sorted(joined))} joined {srv['label']} ({n} online)")
                        if left:
                            announce(f"\U0001F44B {', '.join(sorted(left))} left {srv['label']} ({n} online)")
                    st.players = players

                    # Auto-stop when empty
                    if players:
                        st.idle_since = None
                    elif st.idle_since is None:
                        st.idle_since = time.time()
                    elif time.time() - st.idle_since > IDLE_STOP_MIN * 60:
                        st.suppress_offline = True
                        st.idle_since = None
                        announce(f"⏸ AkuCraft {srv['label']} was empty for {IDLE_STOP_MIN} min - "
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
                    announce(f"\U0001F3C6 [{srv['label']}] {a.group(1)} got {a.group(2)}")
                    continue
                first = msg.split(" ", 1)[0]
                with LOCK:
                    known = first in STATES[name].players
                if known and any(k in msg for k in DEATH_KEYWORDS):
                    announce(f"\U0001F480 [{srv['label']}] {msg}")
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
        return "No such server."
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
        return "No such server."
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
    if cmd == "map":
        return MAP_TEXT
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


DISCORD_COMMANDS = [
    ("status", "Servers status + who is online", False),
    ("players", "Who is playing right now", False),
    ("start", "Boot a stopped server", True),
    ("stop", "Stop a server (refuses if players online)", True),
    ("map", "Live web map + minimap mods to see each other", False),
    ("connect", "How to join the servers", False),
    ("vpn", "How to set up the VPN (Tailscale)", False),
    ("help", "List commands", False),
]


def pick_invite(before, after):
    """Which invite code was just used? None if it cannot be attributed.

    Discord gives no 'joined via' field, so we diff invite use-counts. If two
    people join between refreshes, or the invite vanished (single-use/expired),
    attribution is ambiguous and we deliberately grant nothing rather than
    guess - a wrong role on a general-purpose server is worse than none.
    """
    used = [c for c, u in after.items() if u > before.get(c, 0)]
    return used[0] if len(used) == 1 else None


def build_discord_client(with_members=True):
    """Build the gateway client + slash command tree (no connection yet)."""
    import asyncio

    import discord
    from discord import app_commands

    intents = discord.Intents.default()  # message content intent NOT needed
    if DISCORD_JOIN_ROLES and with_members:
        # Privileged "Server Members" intent - required for on_member_join.
        # Toggle it in the Developer Portal (self-serve under 100 servers).
        intents.members = True
    client = discord.Client(intents=intents)
    tree = app_commands.CommandTree(client)
    guild = discord.Object(id=DISCORD_GUILD)

    def make_handler(name, takes_arg):
        async def handler(interaction, server: str = ""):
            if DISCORD_CHANNEL and interaction.channel_id != DISCORD_CHANNEL:
                await interaction.response.send_message(
                    "Use me in the AkuCraft channel.", ephemeral=True)
                return
            # /start and /stop shell out to docker compose and can exceed
            # Discord's 3s response deadline - defer, then follow up.
            await interaction.response.defer(thinking=True)
            text = "/" + name + (f" {server}" if server else "")
            reply = await asyncio.get_running_loop().run_in_executor(
                None, handle, text)
            await interaction.followup.send(reply or "Unknown command.")

        if not takes_arg:
            async def noarg(interaction):
                await handler(interaction)
            return noarg
        return handler

    for name, description, takes_arg in DISCORD_COMMANDS:
        cmd = app_commands.Command(
            name=name, description=description, callback=make_handler(name, takes_arg))
        tree.add_command(cmd, guild=guild)

    invite_uses = {}

    async def snapshot_invites(g):
        try:
            return {i.code: (i.uses or 0) for i in await g.invites()}
        except discord.Forbidden:
            log("discord: cannot read invites (bot needs Manage Server) "
                "- auto-role disabled")
        except Exception as e:  # noqa: BLE001
            log(f"discord: invite snapshot failed: {e}")
        return {}

    @client.event
    async def on_ready():  # noqa: D401
        await tree.sync(guild=guild)
        if DISCORD_JOIN_ROLES:
            g = client.get_guild(DISCORD_GUILD)
            if g:
                invite_uses.update(await snapshot_invites(g))
                log(f"discord: tracking {len(invite_uses)} invites for auto-role")
        log(f"discord gateway ready as {client.user}")

    @client.event
    async def on_invite_create(invite):
        # Keep the baseline current, otherwise a brand-new invite's first use
        # looks like "count appeared from nowhere" and stays unattributed.
        if invite.guild and invite.guild.id == DISCORD_GUILD:
            invite_uses[invite.code] = invite.uses or 0

    @client.event
    async def on_member_join(member):
        if not DISCORD_JOIN_ROLES or member.guild.id != DISCORD_GUILD:
            return
        before = dict(invite_uses)
        after = await snapshot_invites(member.guild)
        if after:
            invite_uses.clear()
            invite_uses.update(after)
        code = pick_invite(before, after)
        if code is None:
            log(f"discord: could not attribute an invite for {member} "
                f"- no roles granted")
            return
        if code not in DISCORD_INVITE_CODES:
            log(f"discord: {member} joined via '{code}' (not an AkuCraft "
                f"invite) - no roles granted")
            return
        roles = [r for r in (member.guild.get_role(i) for i in DISCORD_JOIN_ROLES) if r]
        try:
            await member.add_roles(*roles, reason=f"Joined via AkuCraft invite {code}")
        except discord.Forbidden:
            log(f"discord: FORBIDDEN adding roles to {member} - the bot needs "
                f"Manage Roles AND its own role must sit above them")
            return
        except Exception as e:  # noqa: BLE001
            log(f"discord: adding roles to {member} failed: {e}")
            return
        names = ", ".join(r.name for r in roles)
        log(f"discord: granted {names} to {member} (invite {code})")
        send_discord(f"\U0001F44B Welcome {member.mention}! Gave you {names}. "
                     f"Type /connect for how to join the Minecraft servers.")

    return client, tree


def discord_gateway():
    """Serve slash commands over the Discord gateway (outbound WebSocket).

    Runs in its own thread with its own event loop: client.run() would try to
    install signal handlers, which only works on the main thread.
    """
    import asyncio

    import discord

    # If the privileged Server Members intent is not enabled in the Developer
    # Portal, discord.py refuses to connect AT ALL. Slash commands matter more
    # than auto-role, so fall back to a members-less client instead of leaving
    # the bot offline in a reconnect loop.
    with_members = True
    while True:
        client, _tree = build_discord_client(with_members)
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(client.start(DISCORD_TOKEN))
        except discord.errors.PrivilegedIntentsRequired:
            log("discord: SERVER MEMBERS intent is not enabled in the Developer "
                "Portal - auto-role on join is DISABLED; reconnecting with "
                "commands only")
            with_members = False
        except Exception as e:  # noqa: BLE001
            log(f"discord gateway: {e}")
        finally:
            try:
                loop.run_until_complete(client.close())
            except Exception:  # noqa: BLE001
                pass
            loop.close()
        time.sleep(5 if not with_members else 30)


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    threading.Thread(target=monitor, daemon=True).start()
    for name in SERVERS:
        threading.Thread(target=tail_logs, args=(name,), daemon=True).start()
    if DISCORD_TOKEN and DISCORD_GUILD:
        threading.Thread(target=discord_gateway, daemon=True).start()
    log("akucraft bot up")
    poll()


if __name__ == "__main__":
    main()
