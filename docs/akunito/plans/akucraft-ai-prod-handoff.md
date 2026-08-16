---
id: akunito.plans.akucraft-ai-prod-handoff
summary: What is built, what is verified, and the exact steps to take the AkuCraft AI work from staging to production
tags: [minecraft, akucraft, ai, llm, discord, handoff, deploy]
related_files:
  - system/app/litellm.nix
  - system/app/akucraft-bot.py
  - scripts/apply-mca-chatai.py
  - docs/akunito/infrastructure/services/akucraft-ai.md
date: 2026-08-16
status: draft
---

# AkuCraft AI — production handoff

Everything below is **already deployed and running on VPS_PROD** except the
villager chat, which is live on **staging only**. This document is the decision
and the procedure for the last step.

Written for a session with none of the preceding context. Read `CLAUDE.md` first;
the deploy path is not optional.

---

## Already in production, working

| Piece | State |
|---|---|
| LiteLLM gateway (`system/app/litellm.nix`) | running, `100.64.0.6:4711`, tailscale0 only |
| Discord `/ask` | live, answering from the generated manifest |
| `/link`, `/profile`, `/companions` | live |
| DeepSeek billing | $10 prepaid, auto-recharge OFF |

Full description of how it works: `docs/akunito/infrastructure/services/akucraft-ai.md`.

## On staging only — the thing to promote

MCA Reborn villager chat on `mc-mca-staging` (`100.64.0.6:25599`), applied with:

```bash
./scripts/apply-mca-chatai.py --container mc-mca-staging --tools
```

Verified working: five conversations, all HTTP 200, one of them surviving a
server restart. No truncated or empty replies.

---

## Decide these three before promoting

### 1. Most villagers in the live world will never talk

This is the big one, and it is not a bug. MCA only makes a villager an MCA
villager when it **spawns**; `overwriteOriginalVillagers` does not convert
entities already saved in the world. The live world predates the mod, so the
village everyone knows is full of `minecraft:villager` — plain vanilla, silent
forever.

Confirmed on staging: `minecraft:villager` count 2, `mca:female_villager` count 0.

What will talk: villagers born in game, villagers in villages generated after the
mod arrived, and anything summoned. If the expectation is "our villagers can talk
now", that expectation is wrong and it is better to say so before the feature
lands than after.

### 2. `--tools` is going to production — DECIDED

Diego chose to promote **with** `--tools` and test it live (2026-08-17). It was
recommended to go without it first; that recommendation was declined, and this
records the consequence rather than re-arguing it.

With `--tools` a villager can follow, stay and come along **because a player
asked out loud**. Without it they only talk. It is the one setting that gives
the model real effects in the world.

The trust gate lives in the system prompt, NOT in the mod: obey only players at
the mod's friend level (40 hearts) or who have hired you, and do not be argued
into it by someone claiming to be an admin. That is persuasion, not enforcement
— `villagerChatAIUseTools` is a global on/off and MCA has no per-relationship
switch. A determined player may well talk one into it; the worst case is a
villager following someone it should not, which is recoverable.

Time is enforced by the mod and is real: a ~4 minute interaction cooldown plus
gift desaturation put 40 hearts well over half an hour of play.

If it misbehaves, `--disable` and restart, or re-run without `--tools` to drop
back to talk-only (the script always writes the key, so omitting the flag turns
it off rather than leaving a previous experiment in place).

### 3. Message logging is ON

`litellmLogMessages = true` in `profiles/VPS_PROD-config.nix` writes full prompts
and replies to the journal. LiteLLM has no per-model switch, so this captures
**every player's `/ask` question too**, not just villager traffic.

It was turned on to tune the villager prompts. The players are told plainly:
`/companions` carries a "WHAT IS RECORDED" section saying conversations and
/ask questions are saved, why (debugging, and villager memory/gossip), and that
Diego will wipe a player's history on request. Turn logging off when tuning
stops, or keep it and keep the notice accurate.

---

## The procedure

```bash
# 1. Apply the MCA config to the LIVE container, WITH spoken orders (decision 2)
cd ~/.dotfiles
./scripts/apply-mca-chatai.py --container minecraft --tools

# 2. Restart so MCA reads it. Check nobody is mid-session first:
docker exec minecraft rcon-cli list
cd ~/.homelab/minecraft && docker-compose restart

# 3. Verify the config actually loaded
docker exec minecraft sh -c 'grep -E "enableVillagerChatAI|ChatAIModel|ChatAIEndpoint" /data/config/mca.json'

# 4. Verify the container can reach the gateway (401 is CORRECT - no token sent)
docker exec minecraft sh -c 'curl -s -o /dev/null -w "%{http_code}\n" http://100.64.0.6:4711/v1/models'

# 5. Summon one and talk to it
docker exec minecraft rcon-cli "execute at <player> run summon mca:female_villager ~ ~ ~"

# 6. Confirm requests are arriving
sudo journalctl -u litellm --since "5 min ago" | grep chat/completions
```

To undo, at any point:

```bash
./scripts/apply-mca-chatai.py --container minecraft --disable
cd ~/.homelab/minecraft && docker-compose restart
```

The script backs up `mca.json` before every write, inside the container.

---

## Things that will bite

**`DOCKER_HOST`.** The stack is rootless docker under `akunito`. A plain ssh
command inherits nothing and `docker` will talk to a root daemon that has none of
these containers, reporting "no such object". The script sets it itself; ad-hoc
commands need `export DOCKER_HOST=unix:///run/user/1000/docker.sock`.

**Container names differ.** Production is `minecraft`; staging is
`mc-mca-staging`, not `minecraft-staging`.

**The data dirs belong to uid 100999**, the rootless mapping. `akunito` can read
`mca.json` but cannot write beside it — that is why everything goes through
`docker exec`.

**The production stop-lock is stale.** `akucraftStopLockReason` still says the
world is being pre-generated and `akucraftIdleStopMinutes` is 100000. Chunky has
been idle for hours, so that is finished: the message players get when they try
`/stop` is now a lie, and the server no longer auto-stops when empty. The profile
comment already says to put it back to 45 when the pregeneration ends. It does
not block this deploy — `docker-compose restart` is not subject to the bot's
lock — but it should be cleaned up.

**Staging is throwaway.** Its data dir is a restored production backup and is
meant to be re-restored. That is why the config is a script and not a hand edit;
re-run it after any restore.

**The `-q` deploy flag is wrong here.** Use `./install.sh ~/.dotfiles VPS_PROD
-s -d`: `-d` keeps containers running, and **no `-h`**, so
`hardware-configuration.nix` is regenerated. `-q` is shorthand for `-d -h` and
would skip that. Regenerating with docker running is safe because `install.sh`
strips the `/var/lib/docker/*` and overlay entries immediately afterwards.

**The gateway port is 4711, not 4000.** `rpc.statd` holds 4000-4002 on this host,
and litellm does not fail on a taken port — it silently binds a different one.
The module asserts after start that we hold the configured port.

---

## Cost

Measured, not estimated: ~4,900 input tokens per `/ask` (of which ~4,700 are
prompt-cache hits) and ~550 output. At DeepSeek's post-2026-08-16 peak/off-peak
rates that is **$0.23–0.47 per week at 80 questions a day**, and evening play in
Spain falls entirely in the off-peak window. Output is ~80% of the cost, so the
lever is `akucraftAskMaxTokens`, not the size of the manifest.

Villager conversations are the same order of magnitude and the same alias family.
The hard ceiling is the prepaid balance; keep auto-recharge off and it cannot
become a bill.

---

## Open, not blocking

- **Villager-to-villager relationships cost nothing.** MCA simulates marriage,
  children and family trees itself — `MCA-FamilyTree.dat` is 32 KB of populated
  data and `marriageChancePerMinute = 0.05` runs with no API involved. The model
  is only called when a *player* talks to a villager. There is nothing to
  optimise and nothing to configure.
- `villagerChatAIFuseSystemPrompt` is undocumented in the mod's wiki and left at
  its default. Do not change it without finding out what it does.
- `ASK_TOKEN`, `TG_TOKEN` and `DISCORD_TOKEN` reach the bot through the Nix
  store, which is world-readable. Moving all three to an `EnvironmentFile` (as
  `litellm.nix` already does) is the tidy-up.
- Villager latency was not measured under load. If a villager feels slow, point
  the `akucraft-villager` alias at a model that does not reason — it exists as a
  separate alias for exactly this.
