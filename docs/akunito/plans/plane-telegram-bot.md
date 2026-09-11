# Plan: Plane Telegram bot (AINF-380)

Status: **F1 deployed 2026-09-11** · service doc: `../infrastructure/services/plane-telegram-bot.md`

## Decisions (interview 2026-09-11)

| Topic | Decision |
|---|---|
| Bot | New dedicated `@aku_plane_bot`; Telegram helpers shared with infra-bot (`tgcommon.py`) |
| Groups | `PLANE My Tasks` (Diego's projects + those shared with Komi) and `PLANE Home` (IRIN, HOME with Aga). Komi-only projects nowhere. LW stays with the LiftCraft bot |
| Identity / authorship | Alias → Plane token per person; writes always with the caller's token. `komi` read-only alias |
| Language | English everywhere |
| Active states | Todo, In Progress, In Review by name |
| `/status` forms | topic = project · General = summary · `<proj> all` by person · `all [user]` by project · `all all` group summary |
| Events (F2) | assignment, created, Done/Cancelled, comments; n8n tickets always (`external_source=n8n`) |
| Delivery | in the project topic, mentioning the assignee |
| Ingest | polling first (mirror), Plane webhook in F3 |
| Digests | due-today reminder + Sunday summary |
| Testing | unit tests gate the nix build; real tests in the final groups with Diego only until ready; Aga joins afterwards |
| Tracking | AINF-380 |

## Phases

- **F1 (done)** — module, secrets, mirror sync, `/status` all forms, `/show`, `/new` + `+` capture, `/whoami`, 47 tests incl. leak matrix, n8n `external_source`.
- **F2** — notifications from `sync_items` diffs + activities/comments; echo rule; 60 s aggregation; edit-in-place on state change; inline state buttons (Pending nonce/TTL from tgcommon); reply = comment; `/assign` `/prio` `/due`; due-today 08:00; Sunday digest. Tests: notification leak matrix (an IRIN event never lands in My Tasks), echo/n8n cases, aggregation.
- **F3** — Plane webhook with HMAC, `WEBHOOK_ALLOWED_IPS` in plane-aio compose (+ plane-customizations.md), Kuma monitor on the bot; polling stays as reconciliation. infra-bot migrated onto `tgcommon.py` (verify with its `--selftest`).
- **Later** — Aga: her Telegram id into `planeBotUsers`, add her to PLANE Home. LiftCraft integration. `/ask` over LiteLLM.

## Facts found along the way

- Plane v1 `work-items/` list ignores every filter; `expand=state,assignees` works; `work-items/PROJ-N/` and `work-items/search/` are workspace-level; `activities/` per item returns `{field, old_value, new_value, actor}` — the same shape as the webhook's `activity`, so F2 logic is transport-independent.
- Webhook events: project, issue, cycle, module, issue_comment only; one delivery per changed field; Plane deactivates a webhook after 5 failed retries.
- Diego's token: 12 projects, **not JLE** (404) — JLE removed from the group; Aga's token: AGA, APORT, HOME, IRIN; AINF → 403 as expected.
- Bot API cannot list forum topics; the bot created them itself and the ids are in secrets.
