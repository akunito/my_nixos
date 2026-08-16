---
id: akunito.plans.akucraft-ai-handoff
summary: Handoff for building the AkuCraft AI work - villager conversations in MCA and a per-player Discord support assistant with usage limits
tags: [minecraft, akucraft, ai, llm, discord, plan, handoff]
related_files:
  - system/app/akucraft-bot.py
  - system/app/akucraft-status-bot.nix
  - scripts/generate-akucraft-manifest.sh
  - docs/akunito/infrastructure/services/akucraft-manifest.md
date: 2026-08-16
status: draft
---

# AkuCraft AI — handoff

Two separate pieces that happen to want the same backend:

1. **Villager conversations** — MCA Reborn talking to players in game.
2. **A Discord support assistant** — players ask questions about the server and
   get answers, each in their own private conversation, with usage limits.

This document is written for a session that has none of the preceding context.
Read `CLAUDE.md` first for the repo rules; the deploy path in particular is not
optional.

---

## What already exists (do not rebuild these)

| Thing | Where | Note |
|---|---|---|
| The bot daemon | `system/app/akucraft-bot.py` (741 lines) | Telegram polling **and** a Discord gateway client with slash commands, in one process |
| Its service | `system/app/akucraft-status-bot.nix` | runs as `akunito` on VPS_PROD, `StateDirectory=akucraft-status` |
| Server manifest | `docs/akunito/infrastructure/services/akucraft-manifest.md` | **generated from the live server**; written specifically to be the context an assistant answers from |
| Manifest generator | `scripts/generate-akucraft-manifest.sh` | re-run after any mod or config change |
| Secrets | `secrets/domains.nix` (git-crypt) | naming convention: `akucraftDiscordBotToken`, `perplexityApiKey`, … |

The bot already does the hard Discord parts: gateway client, `CommandTree`,
role-gated commands, and **ephemeral replies** — see `/invite` around line 575.
Copy that shape.

There is **no LLM gateway anywhere in the infrastructure yet**. `userAiPkgsEnable`
installs lmstudio and ollama-rocm, but that is for desktops with an AMD GPU, not
for the VPS.

---

## Hardware reality — read before choosing a backend

VPS_PROD has **no GPU** (`/dev/dri/card0` only), 12 cores, and about 8 GiB of RAM
free with everything running. During world pregeneration the Minecraft server
alone takes 5-7 cores and 6 GiB.

CPU inference there would be a small quantised model answering in tens of
seconds. That is unusable for a villager you are standing in front of, and poor
for support. **Plan for a hosted model reached over the network**, and treat a
local model as a later experiment on DESK (which has an RX 9070 XT but is not
always on).

---

## Piece 1 — Villager conversations (MCA)

### No new mod is needed

MCA Reborn 7.7.32 is already on both servers and already contains all of this;
the feature needs 7.5.13+. It is switched **off** deliberately and has been since
MCA was installed.

Config lives at `/data/config/mca.json` in the `minecraft` container (and the
staging one). Relevant keys, with their current values:

```
enableVillagerChatAI              = false      <- the master switch
villagerChatAIEndpoint            = https://api.conczin.net/v1/mca/chat
villagerChatAIToken               = ""
villagerChatAIModel               = "default"
villagerChatAISystemPrompt        = ""
villagerChatAIUseTools            = false
villagerChatAIContextPermissionLevel = 3
villagerChatAIUseLongTermMemory   = false
villagerChatAIUseSharedLongTermMemory = false
villagerChatAIIncludeSessionInformation = false
player2Url                        = http://127.0.0.1:4315/
inworldAIToken, elevenlabs*       = "" (voice; out of scope)
```

### Backend options

`/mca chatAI <model>` accepts `mistral`, `openai`, `groq`, `horde`, `player2`,
and a custom endpoint can be supplied.

- **The default endpoint** is the mod author's own service. It is rate-limited
  per hour and the limit is raised by a Patreon pledge tied to an email verified
  with `/mca verify`. Fine for a demo, not something to build on.
- **`player2`** expects a local app on `127.0.0.1:4315`. Nothing listens there,
  and it would have to run on the *server*, not a player's machine.
- **Our own endpoint** is the one to aim for, so that villagers and the Discord
  assistant share one gateway, one set of keys, and one budget.

### Things to be careful about

- `villagerChatAIUseTools` lets the model *act* in the game. Leave it off until
  everything else is proven.
- `villagerChatAIContextPermissionLevel` controls how much server state is fed
  into the prompt. Understand what it includes before raising it.
- The long-term memory options store dialogue on the server, so they are a
  privacy decision as much as a technical one — the group is family and friends.
- Villagers say whatever the model says, to whoever talks to them, including
  children. `villagerChatAISystemPrompt` is the lever; write it deliberately.

---

## Piece 2 — The Discord support assistant

### The requirement

Each player asks privately, without treading on anyone else, with limits that
stop accidental or deliberate overuse.

### Per-player isolation comes free

Discord slash commands support **ephemeral** replies — only the person who ran
the command sees the answer. `/invite` already uses this
(`interaction.response.defer(thinking=True, ephemeral=True)`).

So `/ask <question>` answered ephemerally is isolated by construction. No
threads, no channels per player, nothing to clean up. Conversation history is
keyed by the Discord user id and kept under `STATE_DIR`
(`/var/lib/akucraft-status`), which the service already creates.

### Where the answers come from

`docs/akunito/infrastructure/services/akucraft-manifest.md` is regenerated from
the running server by `scripts/generate-akucraft-manifest.sh`. It already
contains the mod list, the Flan claim numbers, waystone and warp costs, the
death and grave rules, the skin commands, the trading rules and the bot
commands — every number read out of the live container rather than remembered.

That file **is** the context. Feed it whole; it is a few hundred lines. Do not
build a retrieval system for one document.

Live state the manifest cannot have — who is online, whether the server is up —
the bot already knows: `online_players()`, `health()`, `rcon()`.

### Limits — two layers, because they do different jobs

1. **A friendly per-player quota in the bot.** Counter per Discord user id in
   `STATE_DIR`, reset daily. When it runs out, say so plainly and say when it
   comes back. This is what a player actually experiences.
2. **A hard budget at the gateway.** Whatever the bot does wrong, spending is
   capped upstream. A per-key budget in a gateway like LiteLLM does this, and the
   same gateway can serve MCA.

Do not rely on layer 1 alone: a bug in the bot would otherwise be a bill.

Also worth having: a small maximum answer length, a maximum question length, and
a refusal to answer anything that is not about the server — the manifest gives
it no reason to be a general chatbot, but the system prompt should say so.

### Suggested shape

- `/ask <question>` — ephemeral, rate-limited, answers from the manifest
- `/ask` with no argument — show the player their remaining quota
- Admin-only: a command to reload the manifest without restarting the bot

---

## Suggested architecture

```
                    ┌──────────────────────────┐
   MCA villagers ──►│                          │
                    │   one LLM gateway on     │──► hosted model
   Discord /ask ───►│   VPS_PROD (e.g. LiteLLM)│    (keys, budgets,
                    │                          │     per-user limits)
                    └──────────────────────────┘
```

One gateway rather than two integrations: a single place for the keys, a single
place where spending is capped, and a single place to swap the model later —
including for a local one on DESK if that ever becomes practical.

MCA needs its endpoint to speak whatever shape it expects; check whether it is
OpenAI-compatible before assuming, because the default endpoint's path
(`/v1/mca/chat`) is the author's own API and not OpenAI's. If it is not
compatible, a small shim in front of the gateway is the fix — not abandoning the
gateway.

---

## Rules that apply to this work

From `CLAUDE.md`, and they are enforced:

- **Never hardcode credentials.** New secrets go in `secrets/domains.nix`
  (git-crypt) and reach the service through `systemSettings`, like
  `akucraftDiscordBotToken` does.
- **Deploy only through `install.sh`.** Never `nixos-rebuild switch` on the VPS.
  Commit, push, then on the VPS: `git fetch && git reset --hard origin/main &&
  ./install.sh ~/.dotfiles VPS_PROD -s`.
- **Feature flags, not hostname checks.** Add to `lib/defaults.nix` defaulting to
  off, and enable in `profiles/VPS_PROD-config.nix`.
- The bot is one process serving both Telegram and Discord. Do not fork it.

---

## Open questions for whoever picks this up

1. Which hosted model, and what monthly ceiling is acceptable?
2. Is MCA's endpoint OpenAI-compatible, or is a shim needed?
3. Should villager memory persist between sessions? It is a privacy call.
4. Should the support assistant be able to read live server state (who is
   online, is it up) or only the manifest? Live state is more useful and a
   larger surface.
5. Telegram as well as Discord? The bot serves both, but ephemeral replies have
   no Telegram equivalent — a private chat with the bot would be the analogue.

---

## Current state of the server, for context

Two servers: production `100.64.0.6:25565` and staging `100.64.0.6:25599`, both
Minecraft 1.21.1 / Fabric, ~78 mods, managed by
`~/.homelab/minecraft{,-staging}/docker-compose.yml` under rootless docker.

Clients keep themselves in step with AutoModpack; the mod list a client may
receive is an allow-list derived from
`user/app/games/minecraft-client-mods.nix`, so **a mod added to the server
reaches nobody until it is added there too**.

There is separate in-flight work on a second Terralith world - see
`docs/akunito/plans/akucraft-frontier-world.md`. It does not interact with the AI
work, but the server may be restarted often while it is going on.
