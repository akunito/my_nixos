#!/usr/bin/env python3
"""Copy the published #mc-guides forum posts into the /ask assistant's store.

Publishing a guide and teaching the bot about it are two different acts. The
bot only reads GUIDE_DIR, which `save_guide()` writes when somebody runs
/guide or /share; every guide written by hand in Discord was therefore
invisible to /ask. This pulls them across so the assistant can quote what the
server has already documented.

Idempotent: filenames are slugs of the title, so re-running updates in place
rather than duplicating. Safe to run after every new guide.

  DISCORD_TOKEN=... ./scripts/import-akucraft-guides.py [--dry-run] [--no-prune]
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

FORUM = os.environ.get("ASK_GUIDES_CHANNEL", "1538121365859733526")
GUIDE_DIR = os.environ.get("GUIDE_DIR", "/var/lib/akucraft-status/guides")
UA = "akucraft-guide-import/1.0"
DRY = "--dry-run" in sys.argv
PRUNE = "--no-prune" not in sys.argv

# A trilingual card stores the same guide three times. The model gains nothing
# from the repeats and they would eat the whole per-question character budget,
# so keep the English copy and drop the rest.
OTHER_LANG = re.compile(r"^\s*(?:\U0001F1EA\U0001F1F8|\U0001F1F5\U0001F1F1|\U0001F1E9\U0001F1EA)")
EN_LABEL = re.compile(r"^\s*\U0001F1EC\U0001F1E7\s*\*\*[^*]*\*\*\s*\n+")


def token():
    if os.environ.get("DISCORD_TOKEN"):
        return os.environ["DISCORD_TOKEN"]
    out = subprocess.run(["systemctl", "show", "akucraft-status-bot",
                          "-p", "Environment", "--value"],
                         capture_output=True, text=True).stdout
    for part in out.split():
        if part.startswith("DISCORD_TOKEN="):
            return part.split("=", 1)[1]
    sys.exit("no DISCORD_TOKEN in env or in the akucraft-status-bot unit")


TOKEN = token()


def api(path):
    req = urllib.request.Request(
        f"https://discord.com/api/v10/{path}",
        headers={"Authorization": f"Bot {TOKEN}", "User-Agent": UA})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            # 429 is normal here: one call per thread plus one per message page.
            if e.code == 429:
                time.sleep(float(json.loads(e.read()).get("retry_after", 2)) + 0.5)
                continue
            raise
    sys.exit(f"gave up on {path} after rate limits")


def threads():
    """Every guide post, open or archived."""
    seen = {}
    guild = api(f"channels/{FORUM}")["guild_id"]
    for t in api(f"guilds/{guild}/threads/active")["threads"]:
        if t["parent_id"] == FORUM:
            seen[t["id"]] = t
    before = None
    while True:
        page = api(f"channels/{FORUM}/threads/archived/public?limit=100"
                   + (f"&before={before}" if before else ""))
        for t in page.get("threads", []):
            seen.setdefault(t["id"], t)
        if not page.get("has_more"):
            break
        before = page["threads"][-1]["thread_metadata"]["archive_timestamp"]
    return list(seen.values())


def body_of(thread_id):
    """Every message oldest-first, joined. Guides over 2000 chars are split."""
    msgs, after = [], 0
    while True:
        page = api(f"channels/{thread_id}/messages?limit=100&after={after}")
        if not page:
            break
        page.sort(key=lambda m: int(m["id"]))
        msgs += page
        after = page[-1]["id"]
        if len(page) < 100:
            break
    parts, author = [], ""
    for m in msgs:
        # Renaming a forum post leaves a CHANNEL_NAME_CHANGE notice (type 4)
        # whose content is the new title, and Discord refuses to delete system
        # messages. Without this the title gets appended to the guide body and
        # there is no way to take it back out. 0 = normal, 19 = reply.
        if m.get("type") not in (0, 19):
            continue
        text = m.get("content", "").strip()
        if not text or OTHER_LANG.match(text):
            continue
        author = author or m["author"].get("username", "")
        parts.append(EN_LABEL.sub("", text))
    return "\n\n".join(parts), author


def main():
    tagnames = {t["id"]: t["name"] for t in api(f"channels/{FORUM}").get("available_tags", [])}
    if not DRY:
        os.makedirs(GUIDE_DIR, exist_ok=True)
    written, keep = 0, set()
    for t in sorted(threads(), key=lambda t: int(t["id"])):
        body, author = body_of(t["id"])
        if not body:
            print(f"  SKIP (vacio)  {t['name']!r}")
            continue
        title = t["name"]
        slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:60] or "guide"
        meta = {
            "title": title,
            "author": author or "the server",
            "url": f"https://discord.com/channels/{t['guild_id']}/{t['id']}",
            "at": t.get("thread_metadata", {}).get("create_timestamp", "")[:10],
            "tags": [tagnames.get(x, x) for x in t.get("applied_tags", [])],
        }
        print(f"  {len(body):5d}  {meta['tags']}  {title}")
        keep.add(f"{slug}.md")
        if not DRY:
            with open(os.path.join(GUIDE_DIR, f"{slug}.md"), "w") as f:
                f.write(json.dumps(meta) + "\n" + body)
        written += 1
    print(f"{'would write' if DRY else 'wrote'} {written} guides to {GUIDE_DIR}")

    # Renaming a thread changes its slug, so without this the store keeps the
    # copy under the old name and /ask answers from both. Guarded on having
    # imported something: a Discord outage returning an empty list must not be
    # read as "every guide was deleted".
    if not PRUNE or not written:
        return
    for name in sorted(set(os.listdir(GUIDE_DIR)) - keep):
        if not name.endswith(".md"):
            continue
        print(f"  stale, removing: {name}")
        if not DRY:
            os.remove(os.path.join(GUIDE_DIR, name))


if __name__ == "__main__":
    main()
