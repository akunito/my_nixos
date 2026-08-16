#!/usr/bin/env python3
"""Point MCA Reborn's villager chat at our own LiteLLM gateway.

The MCA config lives at <data-dir>/config/mca.json, which is INSIDE the server's
data directory and therefore outside this repo. Staging in particular is
declared throwaway - "meant to be thrown away and re-restored" from a production
backup - so hand-editing that file loses the settings the next time anyone
re-restores. This script exists so reapplying is one command instead of
remembering nine keys.

Idempotent: run it as often as you like. It backs up the file first and prints
what it changed, with the token redacted.

    ./scripts/apply-mca-chatai.py --data-dir ~/.homelab/backups/mca-staging
    ./scripts/apply-mca-chatai.py --data-dir ... --disable     # turn it back off

The server must be RESTARTED afterwards: MCA reads this config at startup.

Deliberately left alone:
  villagerChatAIUseTools          - lets the model ACT in the world. Off until
                                    everything else is proven.
  villagerChatAIFuseSystemPrompt  - undocumented in the mod's wiki and its
                                    source is not vendored here. Changing a flag
                                    nobody can explain is how you get a bug you
                                    cannot debug.
  villagerChatAIContextPermissionLevel - this is the permission level needed to
                                    EDIT the chat context in game, not a privacy
                                    dial. Leave it at the mod's default.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time

# Kept short and concrete. Villagers talk to whoever walks up to them, children
# included, and whatever the model says is what the player hears - there is no
# second pair of eyes between the two.
SYSTEM_PROMPT = (
    "You are a villager in a private Minecraft server played by one family and "
    "their friends, including children. Keep every reply friendly and suitable "
    "for a child: no sexual content, no graphic violence beyond ordinary "
    "Minecraft combat, no slurs, no real-world politics or religion. "
    "Stay in character as a villager living in this world. You are an AI "
    "playing this villager, and if someone sincerely asks whether you are real, "
    "say plainly that you are not. "
    "Never claim to perform actions in the world - you can only talk. "
    "Keep replies to one or two short sentences: the player is standing in "
    "front of you waiting, and long speeches break the game."
)

KEYS_ON = {
    "enableVillagerChatAI": True,
    "villagerChatAIModel": "akucraft-villager",
    "villagerChatAIUseLongTermMemory": True,
    "villagerChatAIUseSharedLongTermMemory": True,
    "villagerChatAISystemPrompt": SYSTEM_PROMPT,
    "villagerChatAIUseTools": False,
}


def secret(name, repo):
    """Read one attribute out of the git-crypt secrets file."""
    path = os.path.join(repo, "secrets", "domains.nix")
    out = subprocess.run(
        ["nix", "eval", "--impure", "--raw", "--expr",
         f'(import {path}).{name} or ""'],
        capture_output=True, text=True)
    return out.stdout.strip()


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", required=True,
                    help="server data dir (the one mounted as /data)")
    ap.add_argument("--host", default="100.64.0.6", help="LiteLLM host")
    ap.add_argument("--port", default="4711", help="LiteLLM port")
    ap.add_argument("--disable", action="store_true",
                    help="turn villager chat AI back off, leaving the rest")
    args = ap.parse_args()

    cfg = os.path.join(os.path.expanduser(args.data_dir), "config", "mca.json")
    if not os.path.exists(cfg):
        sys.exit(f"no MCA config at {cfg} - has the server ever started?")

    with open(cfg) as f:
        data = json.load(f)

    if args.disable:
        wanted = {"enableVillagerChatAI": False}
    else:
        token = secret("litellmMasterKey", repo)
        if not token:
            sys.exit("litellmMasterKey is empty - is git-crypt unlocked?")
        wanted = dict(KEYS_ON)
        # MCA wants the FULL chat/completions path, not a base URL, and sends
        # the token as a bearer. Verified against the mod's own docs:
        #   /mca chatAI <model> "<url>" "<token>"
        wanted["villagerChatAIEndpoint"] = \
            f"http://{args.host}:{args.port}/v1/chat/completions"
        wanted["villagerChatAIToken"] = token

    changed = {k: (data.get(k), v) for k, v in wanted.items() if data.get(k) != v}
    if not changed:
        print("already applied - nothing to do")
        return

    backup = f"{cfg}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(cfg, backup)
    data.update(wanted)
    tmp = cfg + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, cfg)

    print(f"backup: {backup}")
    for k, (old, new) in changed.items():
        redact = lambda v: "<token>" if k == "villagerChatAIToken" and v else v
        print(f"  {k}: {redact(old)!r} -> {redact(new)!r}")
    print("\nRestart the server for MCA to pick this up.")


if __name__ == "__main__":
    main()
