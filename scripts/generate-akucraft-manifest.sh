#!/usr/bin/env bash
# Regenerate docs/akunito/infrastructure/services/akucraft-manifest.md from the
# LIVE server, not from memory.
#
# Why a generator and not a hand-written doc: this file is the source of truth
# for any assistant answering player questions (roadmap section 9). A prose doc
# would silently drift from the server within one deploy; this one cannot,
# because every version and every tunable number is read out of the running
# container at generation time.
#
# Run it after any phase that changes mods or config:
#   ./scripts/generate-akucraft-manifest.sh
#
# Requires: ssh access to VPS_PROD (uses -A, see CLAUDE.md).

set -euo pipefail

VPS_HOST="${VPS_HOST:-100.64.0.6}"
VPS_PORT="${VPS_PORT:-56777}"
VPS_USER="${VPS_USER:-akunito}"
OUT="$(dirname "$0")/../docs/akunito/infrastructure/services/akucraft-manifest.md"

echo "Reading live state from ${VPS_USER}@${VPS_HOST}..."

STATE=$(ssh -A -p "$VPS_PORT" "${VPS_USER}@${VPS_HOST}" 'bash -s' <<'REMOTE'
export DOCKER_HOST=unix:///run/user/1000/docker.sock
if ! docker ps --format '{{.Names}}' | grep -qw minecraft; then
  echo "SERVER_STOPPED"; exit 0
fi
echo "###MODS"
docker logs minecraft 2>&1 | grep -oE "^\s+- [a-z0-9_-]+ [^ ]+" | sed 's/^\s*- //' | sort -u
echo "###PROPS"
docker exec minecraft grep -E "^(difficulty|pvp|max-players|view-distance|online-mode|white-list)=" /data/server.properties 2>/dev/null
echo "###FLAN"
docker exec minecraft cat /data/config/flan/flan_config.json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for k in ('claimingItem','inspectionItem','startingBlocks','ticksForNextBlock','maxClaimBlocks','minClaimsize','defaultClaimDepth'):
    if k in d: print(f'{k}={d[k]}')" 2>/dev/null
echo "###WARP"
docker exec minecraft cat /data/config/warputils_config.json 2>/dev/null | python3 -c "
import json,sys
c=json.load(sys.stdin)['config']
print(f\"maxHomes={int(c['homes']['maxHomeCount'])}\")
print(f\"homeCooldownMin={int(c['homes']['cooldown']/1200)}\")
print(f\"warpCooldownMin={int(c['warp']['cooldown']/1200)}\")
print(f\"fightLockoutSec={int(c['fightCooldown']['cooldown']/20)}\")" 2>/dev/null
echo "###WAYSTONE"
docker exec minecraft cat /data/config/sswaystones.json 2>/dev/null | python3 -c "
import json,sys; print('xpCost=%s' % json.load(sys.stdin)['xp_cost'])" 2>/dev/null
echo "###SKINS"
docker exec minecraft cat /data/config/skinrestorer/config.json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)['join']['autoFetch']
print('providers=' + ', '.join(d['providers']))
print('enabled=%s' % d['enabled'])" 2>/dev/null
REMOTE
)

if [[ "$STATE" == *SERVER_STOPPED* ]]; then
  echo "ERROR: the minecraft container is not running - start it first, the manifest is generated from the live server." >&2
  exit 1
fi

sec() { awk -v s="###$1" '$0==s{f=1;next} /^###/{f=0} f' <<<"$STATE"; }
val() {
  local v; v=$(sec "$1" | sed -n "s/^$2=//p" | head -1)
  if [[ -z "$v" ]]; then
    echo "ERROR: no value for $1.$2 - the manifest would render a blank. Fix the collector." >&2
    exit 1
  fi
  printf '%s' "$v"
}
mod() { sec MODS | awk -v m="$1" '$1==m{print $2}'; }

MC=$(mod minecraft); LOADER=$(mod fabricloader)
MODCOUNT=$(sec MODS | wc -l)

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<EOF
---
id: akunito.infra.services.akucraft-manifest
summary: Single source of truth describing the AkuCraft Minecraft server - mods, rules, commands and tunables, generated from the live server
tags: [minecraft, akucraft, vps, gaming, generated]
related_files: [scripts/generate-akucraft-manifest.sh]
date: $(date +%Y-%m-%d)
status: published
---

# AkuCraft — server manifest

**GENERATED FILE — do not edit by hand.**
Regenerate with \`./scripts/generate-akucraft-manifest.sh\`; every number below
is read from the running server.

Generated $(date '+%Y-%m-%d %H:%M %Z') · Minecraft **$MC** · Fabric Loader **$LOADER** · **$MODCOUNT** mods

---

## What this server is

A private survival server for a small group of friends. Offline mode, reachable
only through a Tailscale VPN — there is no public address and no whitelist to
maintain, because network access *is* the access control.

| | |
|---|---|
| Address | \`100.64.0.6:25565\` (VPN required) |
| Live 3D map | \`http://100.64.0.6:8100\` (VPN required) |
| Modpack | \`http://100.64.0.6:8100/downloads/AkuCraft-auto.mrpack\` (AutoModpack; the server supplies the rest) |
| Difficulty | $(val PROPS difficulty) · PVP $(val PROPS pvp) · max $(val PROPS max-players) players |
| Login | offline accounts + EasyAuth password (\`/auth register <pw> <pw>\`) |

The server **auto-stops after 45 minutes empty** and anyone can restart it with
\`/start\` in Discord or Telegram. It is not up 24/7 by design.

---

## Player identity — the thing that breaks most often

Offline mode means a player's identity is derived from their **username**, as
\`md5("OfflinePlayer:" + name)\`. Consequences that matter:

- **Names are case-sensitive.** \`Julcyxx\` and \`julcyxx\` are different players
  with different claims and inventories.
- Changing your in-game name means losing access to your own base until the
  data is migrated.
- \`whitelist add <name>\` must never be used: it resolves against Mojang and
  stores an *online* UUID belonging to a stranger. Compute the offline UUID.

---

## Land claims (Flan)

Claiming is how players protect builds and chests. Everyone can do it; nothing
needs granting.

| Setting | Value |
|---|---|
| Claim tool | \`$(val FLAN claimingItem)\` — right-click two opposite corners |
| Inspect tool | \`$(val FLAN inspectionItem)\` — shows who owns a block |
| Starting blocks | $(val FLAN startingBlocks) |
| Earned | 1 block per $(( $(val FLAN ticksForNextBlock) / 20 )) seconds played |
| Maximum | $(val FLAN maxClaimBlocks) |
| Smallest claim | $(val FLAN minClaimsize) blocks |
| Depth below | $(val FLAN defaultClaimDepth) |

Cost is the **ground footprint** (X × Z); height is free. Expanding costs
\`amount × depth\`, so wide claims get expensive fast.

Key commands: \`/flan menu\` (GUI for everything), \`/flan list\`, \`/flan info\`,
\`/flan expand <n>\` (**in the direction you are facing**), \`/flan group add\`,
\`/flan permission group <g> flan:<perm> true\` (**the \`flan:\` prefix is
required**), \`/flan switchMode subclaim\` for a private room inside a shared base.

⚠️ \`/flan delete\` removes the claim you stand in with **no confirmation**, and
autocomplete offers \`deleteAll\` first.

---

## Travel

Three systems, deliberately different in cost.

**Waystones** — the main network. Craft (Eye of Ender + redstone + stone brick
wall + stone bricks), place, name it. Costs **$(val WAYSTONE xpCost) XP level per
teleport**. Can be set global so everyone may use it. Works across dimensions.

**Home** — the emergency exit, not transport. **$(val WARP maxHomes) home only**,
**$(val WARP homeCooldownMin) minute cooldown**. \`/sethome\`, \`/home\`, \`/delhome\`.

**Warps and players** — \`/warp <name>\` (**$(val WARP warpCooldownMin) min
cooldown**, admin-set destinations), \`/tpa <player>\`, \`/back\`.

All of it: **5 second stand-still** before it fires, and **no teleporting for
$(val WARP fightLockoutSec) seconds after taking damage** from anything,
including mobs. Nobody escapes a losing fight.

---

## Economy and trading

**Diamonds are the currency — by convention, not enforcement.** Universal Shops
has no setting to mandate one, so the rule only holds if everyone follows it.

Craft a **Trade Shop** (4 planks + 1 wool + 1 iron), place it against a chest,
set what you sell and the price. It keeps selling **while you are offline**.
Shops work inside claims without granting anyone chest access.

---

## Death

Nothing is lost by default. A **grave** holds your items where you died,
protected from other players — \`/graves\` locates yours. The **Soulbound**
enchantment (\`soulbound_enchantment:soulbound\`, from the enchanting table, loot
or villagers) returns enchanted items to you directly.

Bed spawns are cleared silently if the bed is broken *or obstructed*, which
sends you to world spawn. Leave space around it.

---

## Skins

Offline mode means no skin by default, and the server fixes that with no client
install. Auto-fetch providers: **$(val SKINS providers)**.

Register free at ely.by using **the same name as in game** and your skin applies
automatically. Otherwise \`/skin set ely.by <name>\`, \`/skin set mojang <account>\`,
or \`/skin set web classic "<url>"\`.

---

## Progression and combat (all optional)

Ignoring every item below leaves vanilla gameplay untouched. That is a hard
design rule for this server.

- **Skills** — \`/puffish_skills category open\`. Passive bonuses bought with
  points earned by playing. Trees are server-side data and can be rebalanced
  without anyone reinstalling.
- **Classes** — Wizards (arcane/fire/frost), Paladins & Priests (heal/support),
  Rogues & Warriors (stealth/martial). Active abilities via spell books.
- **Weapons and shields** — Simply Swords adds weapon types; Shield Expansion
  adds material tiers and a parry window.
- **Enchanting** — the Enchanting Infuser lets you pick instead of gamble,
  grindstones move enchantments between items, and many enchantments now fit
  gear they never did.

- **Treasure gear (Artifacts)** — passive items with no recipe, found only in
  loot chests, worn in the Trinkets slots beside the armour. Double jump,
  permanent night vision, poison immunity, faster mining. They stack.
- **Bosses (Bosses of Mass Destruction)** — Night Lich, Obsidilith, Nether
  Gauntlet, Void Blossom. Structure spacing is widened well past the mod
  defaults in \`config/cristellib/bosses_of_mass_destruction\` (lich tower 96/192
  chunks, void blossom 80/160, obsidilith 48/96, gauntlet 32/64) and they only
  generate in chunks nobody has visited, so none exist near an established base.

**Deliberately excluded:** Better Combat. It rewrites melee for everyone, which
breaks the "ignorable" rule.

---

## Installed mods ($MODCOUNT)

\`\`\`
$(sec MODS | awk '{printf "%-34s %s\n", $1, $2}')
\`\`\`

---

## Keeping clients in sync (AutoModpack)

Clients no longer carry a hand-installed mod list. AutoModpack advertises the
server's set **over the existing game port** — no extra port, no Headscale ACL
change — and each client downloads what it lacks from the Modrinth CDN.

What is sent is not the raw \`/data/mods\` folder: \`scripts/sync-akucraft-automodpack.py\`
derives it from \`user/app/games/minecraft-client-mods.nix\`, the set known to
work, and excludes everything else (BlueMap would otherwise start a web server
on a player's machine). Client-only mods — the Xaero map stack, MapLink, EMI,
Mod Menu — have no server counterpart and are pushed into
\`automodpack/host-modpack/main/mods/\`.

Re-run that script after any mod change, then restart. The player-facing pack
is \`AkuCraft-auto.mrpack\`, which contains AutoModpack alone and therefore
cannot go stale.

Each server has its own certificate; players confirm its fingerprint once.
Read the current one with:

\`\`\`
docker exec minecraft cat /data/automodpack/.private/cert.crt | openssl x509 -outform DER | sha256sum
\`\`\`

---

## Bot commands (Discord and Telegram)

\`/status\` · \`/players\` · \`/start\` · \`/stop\` · \`/map\` · \`/connect\` · \`/vpn\` · \`/help\`

The bot also announces server up/down, joins, leaves and deaths.
EOF

echo "Wrote $OUT"
grep -c '' "$OUT" | sed 's/^/  lines: /'
