# Plane Telegram bot — `@aku_plane_bot` (AINF-380)

One Telegram **forum group per audience**; each group only ever sees its own Plane projects.

| Group | Chat | Topics (project → topic id) | People |
|---|---|---|---|
| **PLANE My Tasks** | `-1003913059286` | AINF 4 · APER 5 · AWORK 6 · ALEA 7 · ZEN 8 · APLANE 9 · LEH 10 · APORT 11 · FIN 13 | Diego |
| **PLANE Home** | `-1004485770269` | IRIN 4 · HOME 5 | Diego, Aga |

Komi-only projects (INF, ORB, N8N, ISG, JLE — Diego is not a member of JLE) are in no group on purpose.
LW/LiftCraft stays with its own bot for now.

## Pieces

| Piece | Where | Flag |
|---|---|---|
| Daemon | `system/app/plane-bot/plane_bot.py`, package `plane-bot/package.nix`, module `system/app/plane-bot.nix` | `planeBotEnable` (VPS only) |
| Shared Telegram helpers | `system/app/tgcommon.py` (to be adopted by infra-bot) | — |
| Config | `secrets/domains.nix`: `planeBotToken`, `planeBotChats`, `planeBotUsers` | `planeBotSyncAlias`, `planeBotPublicUrl`, `planeBotActiveStates`, `planeBotPollSeconds`, `planeBotFullSyncMinutes` in the profile |
| State | `/var/lib/plane-bot/` — `mirror.sqlite` (projects, states, members, items, cursors) + Telegram `offset` | — |

## Scope model (the whole point)

- `planeBotChats` = `chat id → { PROJECT = "topic id" }`. **This table is the only scope.** A chat can list, create in and
  (later) hear about the projects in its row and nothing else. The bot never derives a project from user text except by
  looking the identifier up *in that row*; a foreign project answers `Unknown project here.` with the same wording whether
  it exists or not.
- `planeBotUsers` = `alias → { telegramId, email, token }`. Every write to Plane goes with the **caller's** token, so Plane's
  permissions apply on top. `token = ""` makes a read-only alias (`komi`: listable, assignable, cannot act).
  `telegramId = ""` = not on Telegram yet (fill it from `/whoami` once the person writes in a group).
- The mirror is filled with `planeBotSyncAlias`'s token (Diego), who must be a member of every project in the table.
- Unknown chats and DMs are ignored silently. Plain text is ignored unless it starts with `+` inside a project topic.

## Commands

| Form | Where | Returns |
|---|---|---|
| `/status` | project topic | my active tickets in that project |
| `/status` | General | summary: per project, my counts |
| `/status <proj> [user]` | anywhere | a user's active tickets in `<proj>` |
| `/status <proj> all` | anywhere | everyone's active tickets in `<proj>`, grouped by person + Unassigned |
| `/status all [user]` | anywhere | a user across every project of the group, grouped by project |
| `/status all all` | anywhere | group summary: counts per project and person |
| `/show PROJ-12` | anywhere | one ticket |
| `/new [PROJ] title`, `+ title` | topic (or `PROJ` given) | creates in **Todo** as the caller |
| `/whoami`, `/help` | anywhere | id + mapping; usage |

Active = `planeBotActiveStates` by **name** (`In Progress, In Review, Todo`; Hold - Important and Backlog excluded).
Order: state (as listed) → priority (urgent…none) → due date. 20 per project then `+N more`; long replies are split.
Users are aliases (`diego`, `aga`, `komi`), case-insensitive, `@` tolerated.

## Sync

The v1 list endpoint ignores every filter (`assignees`, `state`, `state__group`, `updated_at__gt`) and AINF alone has
370+ items, so `/status` reads the mirror. Incremental sync walks `?order_by=-updated_at&fields=…` until the stored
cursor (every `planeBotPollSeconds`); a full walk every `planeBotFullSyncMinutes` marks vanished items deleted.
`sync_items` returns `(previous_row, new_item)` pairs — the hook for F2 notifications.

## Testing

- **Unit tests run in the nix `checkPhase`**: parser, scope resolver, renderer, sync, and the **leak matrix**
  (`tests/test_leak.py`: every chat × every command form × every requester × every thread asserts no foreign identifier,
  project block or ticket title in any reply; ORB is in the mirror and in no chat). A failing test fails the build, so
  `install.sh` cannot deploy a scope regression. Run locally: `cd system/app/plane-bot/tests && PYTHONPATH=..:../.. python3 -m unittest`.
- Standalone build: `nix build --impure --expr 'let f = builtins.getFlake (toString ./.); pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux; in pkgs.callPackage ./system/app/plane-bot/package.nix {}'`.
- On the VPS, against the real mirror, without Telegram:
  `sudo -u akunito env $(sudo cat /etc/secrets/plane-bot.env | xargs) $(systemctl show plane-bot -p Environment --value) plane-bot simulate --chat -1004485770269 --thread 5 --user 451343717 "/status HOME all"`
  (`plane-bot sync --full` forces a full walk).

## Gotchas

- Only **one** `getUpdates` consumer per bot token: stop `plane-bot.service` before polling the token by hand (409 otherwise).
- Privacy mode is **off** (BotFather `/setprivacy`) so `+ title` works: the bot receives every group message; it only
  reacts to `/commands` and `+`.
- Topics were created by the bot (`createForumTopic`); the Bot API cannot list topics, so ids live in secrets.
- Plane URL: the bot talks to `planeApiUrl` (`plane.local.akunito.com`, Tailscale); the public one is behind Cloudflare Access
  and answers 302. Ticket links use `planeBotPublicUrl`.
- n8n's monthly ticket now carries `external_source: "n8n"` + a per-month `external_id` (workflow `1ffpYTGrMcQ02viz`), the
  marker F2 uses to notify n8n-created tickets even though the actor is Diego's own token.

## Roadmap

F2 notifications (assignment / created / done-cancelled / comments via activities + comments polling; echo rule: post
only when someone other than the actor is in the chat, or `external_source=n8n`; 60 s aggregation per ticket; edit the
original message on state change), inline state buttons, reply-to-notification = comment, `/assign` `/prio` `/due`,
due-today reminder 08:00, Sunday digest. F3: Plane webhook (`WEBHOOK_ALLOWED_IPS` in plane-aio's env — Plane blocks
private, loopback and 100.64/10 targets — documented in plane-customizations.md) + Kuma monitor; infra-bot onto tgcommon.
