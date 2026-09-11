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
| `/assign PROJ-12 <alias|me|none>` | anywhere (project must be in the chat) | adds the person (or clears), answers with the card |
| `/prio PROJ-12 <urgent|high|medium|low|none>` | anywhere | priority |
| `/due PROJ-12 <YYYY-MM-DD|MM-DD|today|tomorrow|fri|+3d|none>` | anywhere | target date (weekday = next one, never today) |
| `/state PROJ-12 <todo|progress|review|done|cancel>`, `/done PROJ-12` | anywhere | state by name in that project |
| **buttons under a card** | — | `▶ In Progress` / `☐ Todo` / `✅ Done` / `👤 Me`; closed cards show `↩ Todo` |
| **reply to a bot message about a ticket** | — | adds a Plane comment as you (`💬 added to PROJ-12`) |
| `/whoami`, `/help` | anywhere | id + mapping; usage |

Every write uses the caller's token (a read-only alias or an unregistered Telegram id is refused), refreshes the mirror
immediately (so the sync does not echo it back) and answers with the updated card. Button callbacks carry the item id;
the chat's table is still checked (`Not available here` in the wrong chat).

**Scheduled** (thread `run_scheduler`, once per day via `meta` keys): 08:00 due-today/overdue per project topic with
assignee mentions; Sunday 18:00 weekly digest in General (closed this week + group summary).

Active = `planeBotActiveStates` by **name** (`In Progress, In Review, Todo`; Hold - Important and Backlog excluded).
Order: state (as listed) → priority (urgent…none) → due date. 20 per project then `+N more`; long replies are split.
Users are aliases (`diego`, `aga`, `komi`), case-insensitive, `@` tolerated.

## Sync

The v1 list endpoint ignores every filter (`assignees`, `state`, `state__group`, `updated_at__gt`) and AINF alone has
370+ items, so `/status` reads the mirror. Incremental sync walks `?order_by=-updated_at&fields=…` until the stored
cursor (every `planeBotPollSeconds`); a full walk every `planeBotFullSyncMinutes` marks vanished items deleted.
`sync_items` returns `(previous_row, new_item)` pairs — the hook for F2 notifications.

## Notifications (F2a)

Source = mirror diffs (`sync_items` returns `(previous_row, new_item)`), so no webhook is needed; a new comment bumps the
item's `updated_at` (verified), so comments ride the same path. `notify.py`:

| Event | Delivery |
|---|---|
| created | 🆕 card in the project's topic (skipped if the bot's own `/new` reply is already the card) |
| assigned | new message mentioning the assignee (`tg://user?id=`), replying to the card; self-assignment silent |
| Done / Cancelled | ✅ / 🚫: the card is **edited in place** (silent); a short line if there was no card |
| priority / due / name / other state | card edited in place; nothing if there is no card |
| comment | 💬 quoted (HTML stripped, 300 chars) as a reply to the card |

**Audience** of a chat for a project = configured users **with a Telegram id** who are members of the project.
**Echo rule:** nothing posts when the actor is the only listener — except `external_source=n8n` items, which always post.
So in *My Tasks* your own web edits are silent while n8n's monthly ticket is not; in *Home*, Aga's actions reach you and
yours reach her once her Telegram id is filled in. Deletions are silent. The first sync of a project (no cursor yet)
and the schema-migration full sync never notify. Cards live in the `posts` table (`item, chat → message_id`).

## Webhook (F3) — instant events, polling kept as reconciliation

Plane workspace webhook `plane-bot` (id `f4e8922a…`, created 2026-09-11 from the Django shell, events **issue** +
**issue_comment**) posts to `http://host.docker.internal:8766/plane`; the bot listens on **127.0.0.1:8766**
(`planeBotWebhookPort`) and verifies `X-Plane-Signature` = HMAC-SHA256(`planeBotWebhookSecret`, body). `webhook.py`
normalises the expanded payload (`state`/`assignees` are objects, timestamps are UTC `Z`) into the REST shape, upserts the
mirror and feeds the **same** notifier the poller uses — one scope, one echo rule. Comments are quoted straight from the
payload; `seen_comments` stops the poller from repeating them. Timestamps are stored canonical UTC so the two sources
never disagree about "changed". Off unless the secret is set; `planeBotWebhookDebug` dumps accepted payloads to
`/var/lib/plane-bot/webhook-samples/`.

Why it needed a Plane customisation: the rootless container reaches host loopback as `host.docker.internal` (10.0.2.2),
which Plane's SSRF guard blocks; `WEBHOOK_ALLOWED_HOSTS` is the escape hatch, but the AIO image ships it **empty in
`/app/plane.env`** and loads services from there, overriding the compose environment. `start-override.sh` **Fix 2b**
rewrites it (plane-customizations.md **A-10**). Plane writes every delivery to `WebhookLog` (status 400 "Access to
private/internal networks is not allowed" was the tell) and deactivates a webhook after 5 failed deliveries — the
receiver answers 200 to anything with a valid signature.

## Testing

- **Unit tests run in the nix `checkPhase`** (107): parser, scope resolver, renderer, sync, notifications (echo rule, assignment, closing, comments), write commands, button callbacks, reply=comment, scheduled reports, webhook receiver (signature, normaliser, dedupe, participle verbs, UTC timestamps), and the **leak matrices** — commands and notifications
  (`tests/test_leak.py`: every chat × every command form × every requester × every thread asserts no foreign identifier,
  project block or ticket title in any reply; ORB is in the mirror and in no chat). A failing test fails the build, so
  `install.sh` cannot deploy a scope regression. Run locally: `cd system/app/plane-bot/tests && PYTHONPATH=..:../.. python3 -m unittest`.
- Standalone build: `nix build --impure --expr 'let f = builtins.getFlake (toString ./.); pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux; in pkgs.callPackage ./system/app/plane-bot/package.nix {}'`.
- `plane-bot-cli simulate --chat ID "@due"` / `"@weekly"` render the scheduled reports; `"a:d:<item hex>"` runs a button.
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

Aga's Telegram id + join PLANE Home; turn `planeBotWebhookDebug` off once the samples have served; LiftCraft integration
later. Done: F1–F3, infra-bot on tgcommon.py.
