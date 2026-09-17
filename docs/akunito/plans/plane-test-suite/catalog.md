---
id: plans.plane-test-suite.catalog
summary: "Plane fork regression suite — full test catalogue by layer, mapped to register IDs A-xx/B-xx, with combination matrices"
tags: [plane, testing, plan, catalog, playwright, vitest]
related_files: [docs/akunito/plans/plane-test-suite/README.md, docs/akunito/infrastructure/services/plane-customizations.md]
date: 2026-09-17
status: draft
---

# Plane test catalogue

Decisions, architecture, `plane-deploy` flow and phases: [`README.md`](README.md). IDs in brackets = register
rows in `plane-customizations.md`. `×` = full combination matrix (one test per cell).

**Viewports (V):** `D` desktop Chromium 1440×900 · `A` Android Chromium 412×915 · `I` iPhone WebKit 390×844 ·
`B-` 767px · `B+` 768px (breakpoint pair, used only where behaviour flips at 768).

## L0 — Build gate

| ID | Test |
|---|---|
| L0-01 | `pnpm install --frozen-lockfile` + `turbo build --filter=web` succeed |
| L0-02 | `check:types` error count ≤ baseline (27); list new errors on increase |
| L0-03 | Every `requestIdleCallback` in `build/client/assets` is guarded (APLANE-1 class) |
| L0-04 | Bundle contains `with Pocket ID` and not `with Gitea` [B-32] |
| L0-05 | No unresolved free identifiers from fork files (grep minified output for fork symbol names) |
| L0-06 | Lint/format on fork-touched files only (upstream noise excluded) |

## L1 — Unit (vitest, `apps/web/tests/unit`)

| ID | Unit | Cases |
|---|---|---|
| L1-01 | `multiSortStore` load [B-28] — **per view key** (decision) | two views keep independent rules · project vs global view keys don't collide · migration of the old global key · empty storage · valid 1/2 keys · >2 keys truncated to 2 · invalid JSON · non-array JSON · `window` undefined |
| L1-02 | `multiSortStore.setSecondaryOrderBy` | persists · truncates to 2 · storage throws (quota) → state still updates |
| L1-03 | `getSortDescriptor` | every `TIssueOrderByOptions` key returns a descriptor or an explicit, listed `null` |
| L1-04 | Single-key parity | for every key K: `issuesSortWithMultipleOrderBy(ids,[K])` ≡ `issuesSortWithOrderBy(ids,K)` |
| L1-05 | Multi-sort matrix [B-27] | primary × secondary-1 × secondary-2 over {created, updated, start, target, priority, state, project} × asc/desc, fixture with deliberate ties so each next key is observable |
| L1-06 | Empty values | null `target_date`/`start_date`/labels/assignees/modules/cycle sort **last** in both directions |
| L1-07 | Unknown/EE-only key in the chain | ignored, falls back to remaining keys; all-unknown → single-key path |
| L1-08 | Project sort [B-31] | case-insensitive · missing `projectMap` · project missing from map · archived store path |
| L1-09 | `reapplyMultiSort` | flat ids · grouped · grouped+sub-grouped · empty `groupedIssueIds` |
| L1-10 | `reOrderFavorite` math [B-01] | above/below middle · above top (dest+GAP) · below bottom (dest−GAP) · single favourite · moved item excluded from neighbours · destination sequence `0` · 50 repeated midpoint moves keep strict order (float precision) |
| L1-11 | `fetchFavorite` dedupe [B-01] | refetch twice → no duplicate ids |
| L1-12 | `useResponsiveIssueLayout` [B-13] | widths {0, 320, 767, 768, 1440} × layouts {list, kanban, calendar, spreadsheet, gantt, undefined}; width 0 (SSR/unknown) never overrides |
| L1-13 | `getWorkspaceItemState` [B-02] | no pref → views+analytics pinned, archives not · stored `is_pinned:false` for views stays false · stored true for archives respected |
| L1-14 | Order-by editor logic [B-27/B-30/B-31] | addable excludes used bases and `sort_order` · max 2 secondary hides adders · move bounds (first up / last down no-op) · flip toggles `-` · remove middle rule · `-state__name` forced on project pages · `project__name` only when layout allow-list has it |
| L1-15b ✅ | Pins resolved by UUID (`usePinnedEntities`) | live title after rename · live identifier after project identifier change · deleted (404) → favourite dropped server-side · archived → kept, archived route · 401/403 → hidden, never deleted · 5xx → kept with the last known label |
| L1-15 ✅ | Pinned list derivation [B-08] | split pages/tickets · sort by sequence desc · `parent` excluded · other entity types ignored |
| L1-16 ✅ | Ticket permalink [B-10] | built from the live identifier + sequence, never the stored label |
| L1-17 ✅ | Page pin open | missing `project_id` or `entity_identifier` → not resolved, never fetched · no workspace → nothing fetched |
| L1-18 | Manage dialog search [B-09] | results filtered by already-pinned ids · capped at 8 · stale response after query change ignored (`active` flag) · search error → empty |
| L1-19 | Global Board grouping [B-18] | 5 state-group columns in order · order within column preserved · unknown state → "No status" column shown only when non-empty · Load-more label `n/total` · hidden when no next page |
| L1-20 | Global Calendar grouping [B-19] | bucket by `YYYY-MM-DD` · no `target_date` excluded · date near midnight in Europe/Madrid vs UTC lands on the right day |
| L1-21 | Drawer auto-close [B-33] | mobile+open+path change → close · same path → nothing · desktop → nothing · already collapsed → nothing |
| L1-22 | Project reorder detection [B-04] | move first→last · last→first · middle swap · no-op drop sends no API call |
| L1-23 | OAuth config [B-32] | gitea option text `… with Pocket ID` · onClick URL `/auth/gitea/` with and without `next_path` |
| L1-24 | Constants contract | `ISSUE_ORDER_BY_OPTIONS` has state + project · `my_issues` has spreadsheet/list/kanban/calendar entries · `GLOBAL_VIEW_LAYOUTS` = [spreadsheet, kanban, calendar] [B-22] · `ISSUE_ORDERBY_KEY` covers every order-by key |
| L1-25 | `favorites-menu` filter [B-11] | page/issue excluded, project/view/cycle/module/folder kept |

## L2 — Backend (pytest in the fork)

Until P8 (own images) L2-01…03 guard the `sed` patches; after P8 they are deleted and the
patches are ordinary code covered by L2-04…11.

| ID | Test |
|---|---|
| L2-01 | *(pre-P8)* anchor counts on the image: `USE_MINIO 0` =1 · `MINIO_ENDPOINT_SSL=0` =1 · `WEBHOOK_ALLOWED_HOSTS=` =1 · session import =1 · `authentication_classes` =2 · subscriber line =1 |
| L2-02 | *(pre-P8)* `start-override.sh` dry run → "All patches applied and verified", exit 0 |
| L2-03 | *(pre-P8)* each FATAL branch fires with its anchor removed (6 cases) |
| L2-04 | OIDC adapter (Pocket ID via gitea slot): token/userinfo/authorize URLs · claim mapping (`sub`, `email`, `given_name`/`name`, `family_name`, `picture`) · missing optional claims |
| L2-09 | Favourites cleanup: deleting a page / work item removes its `UserFavorite` rows for every user · archiving does not |
| L2-10 | Favourites API filters out entities the requester can no longer access (row kept) |
| L2-11 | Storage settings: presigned URL host/scheme from config (ex Fix 1/2) · webhook allow-list from config (ex Fix 2b) |
| L2-05 | pytest [A-04] internal `/api/`: valid key 200 · invalid key 401 · no key/no session 401 · session auth still 200 · key of user not in workspace 403 · `/api/v1/` unaffected |
| L2-06 | pytest [A-09] assignee not subscribed gets notified · actor excluded when self-assigning · subscriber+assignee gets exactly one · unassigned subscriber still notified · removed assignee stops being notified |
| L2-07 | Create with assignees → no notification (current behaviour, pinned; change it deliberately or not at all) |
| L2-08 | Upstream contract suite `apps/api/plane/tests/contract` stays green (inherited coverage for everything we didn't write) |

## L3 — Config contract (read-only; dev and prod)

| ID | Test |
|---|---|
| L3-00 | **Dev safety (runs first, dev only):** no active webhook outside the capture receiver · `EMAIL_HOST` = mailpit · no outbound route to n8n/SMTP2GO from the dev container → otherwise ABORT |
| L3-01 | Container `healthy`; *(pre-P8)* log has `All patches applied and verified` since last start; deployed image digests = recorded ones |
| L3-02 | `/api/instances/` — **prod:** gitea on; email-password, magic-link, signup, intercom off [A-07/A-08] · **dev:** gitea on, email-password **on**, signup/magic/intercom off |
| L3-03 | `instance_configurations` raw rows match (guards a stale 2 h Redis cache hiding a DB change) |
| L3-04 | Process env of api/worker/beat: `USE_MINIO=1`, `MINIO_ENDPOINT_SSL=1`, `WEBHOOK_ALLOWED_HOSTS=host.docker.internal` [A-02/A-03/A-10] |
| L3-05 | Django settings: `SESSION_COOKIE_AGE=7776000`, `SESSION_SAVE_EVERY_REQUEST=True` [A-11 new] |
| L3-06 | `/auth/gitea/` redirects to `auth.akunito.com/authorize` with the correct `redirect_uri` for each host: public, `.local`, dev [A-01] |
| L3-07 | Public host: `/god-mode*` and `/api/instances/admins*` are behind CF Access · bare `/api/instances/` is NOT (login needs it) |
| L3-08 | Caddy routes [A-06]: `/uploads/` → MinIO · `/god-mode/` index 200 · SPA deep links (`/akuworkspace/browse/X-1/`, `/akuworkspace/projects/<id>/issues/`) return `index.html` 200 · `/api/` and `/auth/` reach the API |
| L3-09 | Mount points: `/app/web` source dir = expected; served `index.html` sha = deployed build sha |
| L3-10 | Served assets: every `requestIdleCallback` guarded; no service worker registration (or kill-switch) [C-02] |
| L3-11 | Email config rows (`EMAIL_HOST=host.docker.internal`, port 25, from) on prod |
| L3-12 | Webhooks: expected set present + active; last `WebhookLog` per webhook 2xx; none auto-deactivated |
| L3-13 | `API_KEY_RATE_LIMIT` value recorded (alert on change) |
| L3-14 | Migrations: latest applied = latest in image |
| L3-15 | Drift dev↔prod: image digests · compose env keys · Caddyfile sha · deployed commit (only the documented dev-only differences allowed: password login, mail sink, webhooks) |

## L4 — API functional (dev, QA workspace, 2 test users)

| ID | Test |
|---|---|
| L4-01 | Attachment upload: presigned URL is `https://` + public host, PUT works, GET via `/uploads/` 200 [A-02/A-03] |
| L4-02 | Pages API on internal `/api/` with API key: list/create/read/delete [A-04] |
| L4-03 | Favorites: create page + issue favourites · update `sequence` · delete · second device sees them [B-08/B-09] |
| L4-03b ✅ | Pin lifecycle **backend contract**: rename never touches the favourite's stored label · archived work item readable with `archived_at`, favourite kept · deleted work item 404 with its favourite **left behind** (the frontend drops it) · archiving a **page** deletes its favourite server-side (upstream deviation) |
| L4-04 | Workspace search returns `page` and `issue` result shapes the dialog relies on (`project__identifier`, `sequence_id`, `project_ids`) |
| L4-05 | Views perms: owner updates · non-owner update rejected · admin deletes · non-owner member delete rejected [B-26] |
| L4-06 | A-09 end-to-end: user B assigns user A (unsubscribed) → A has in-app notification; B has none |
| L4-07 | Webhook SSRF: `host.docker.internal` target delivers · `127.0.0.1`, `10.0.0.1`, `169.254.169.254` still rejected (Fix 2b didn't open everything) |
| L4-08 | Webhook HMAC: capture receiver verifies `X-Plane-Signature`; payload keeps `data.target_date`, `data.assignees[].email`, `data.state.name` (cheap guard for the out-of-scope bot/n8n consumers) |
| L4-09 | Rate limit: 61st call/min with one key → 429 (documents D11) |
| L4-10 | Project `sort_order` update persists (backend of B-04) |
| L4-11 | Sidebar preferences are per-user: A pins, B reloads, A's pins intact (A-05, now upstream) |
| L4-12 | Session: request extends cookie expiry (rolling) [A-11] |

## L5 — E2E browser (Playwright; dev QA workspace)

Every E2E test also asserts: **no error boundary** ("Looks like something went wrong"), **no
uncaught console error**, and on `A`/`I` **no horizontal overflow** (`scrollWidth ≤ clientWidth`).

### Auth & shell
| ID | Test | V |
|---|---|---|
| L5-01 | Login page: "Sign in with Pocket ID" + fingerprint icon; click → redirect to Pocket ID [B-32]; **prod (L7):** no password/magic-link form [A-07] | D A I |
| L5-02 | Route crawl: home, projects, each project's issues/cycles/modules/views/pages/intake, analytics, archives, notifications, profile, settings, browse permalink | D A I |
| L5-04 | Switch `qa` ↔ `qa-2`: sidebar, Pins, favourites and multi-sort rules belong to the active workspace only | D I |
| L5-03 | Read-only crawl of the **real** copied `akuworkspace` on dev: every project × layout {list, kanban, calendar, spreadsheet} + every saved view; only asserts no error boundary / console error | D I |

### Sidebar & navigation [B-01…B-11, B-15, B-33]
| ID | Test | V |
|---|---|---|
| L5-10 | Views + Analytics visible for a user with no stored prefs; archives hidden | D A |
| L5-11 | Header icons: hidden until hover on D; always visible on A/I; at B-/B+ flip | D A I B- B+ |
| L5-12 | Workspace pin icon → dialog scoped to Workspace (no Personal/Projects); toggle pin persists after reload | D I |
| L5-13 | Projects pin icon → project list: click opens project + closes dialog; drag reorder persists after reload (A: touch drag → M if flaky) | D A |
| L5-14 | Project name click → Work Items; chevron → expand only — × navigation mode {Accordion, Tabbed} | D A |
| L5-15 | Limited projects count on: projects beyond the limit reachable via the pin dialog (D6) | D A |
| L5-16 | Favourites drag reorder → reload → order held, no duplicates | D |
| L5-17 | Pins: empty state CTA · pin page + ticket via search · reorder up/down · remove · collapse state survives reload · pinned page shows once (not in Favorites) | D A I |
| L5-18 | Pinned ticket tap → `/browse/ID-SEQ/` loads (no 404); pinned page opens page | D A I |
| L5-18b ✅ | Pin stored with a wrong label → sidebar shows the live title · rename ticket + page → pin follows · archive ticket → pin kept, opens the archived route · delete ticket + page → pins gone and the favourites removed server-side. Lost access is covered by L1-15b (the hook), not here: it needs a second user's session mid-test | D A I |
| L5-19 | Drawer: open → scrim visible → tap outside closes · navigate via project link, Pins ticket, Pins page, workspace item → drawer closes · chevron/pin/"+" keep it open · D sidebar never collapses on navigation | A I D |

### Project-level layouts [B-12…B-17]
| ID | Test | V |
|---|---|---|
| L5-30 | Saved layout {list, kanban, calendar, spreadsheet, gantt} × context {project, cycle, module, project view} → rendered = saved on D; spreadsheet/gantt render List on A/I | D A I |
| L5-31 | After visiting on A/I, API still returns the original saved layout (not mutated) | A |
| L5-32 | Switcher highlight + Display options match the rendered layout | A I |
| L5-33 | Display: popper on D/B+, bottom sheet with handle + Done on A/I/B-; tap-out and Esc close | D A I B- B+ |
| L5-34 | Sheet height unchanged when switching Board ↔ Calendar inside it | A I |
| L5-35 | Peek overview: properties below content on A/I, side panel 400px on D; archived item properties not editable | D A I |

### Global views [B-18…B-26]
| ID | Test | V |
|---|---|---|
| L5-50 | View {All, Assigned, Created, Subscribed, custom saved, custom locked} × layout {Table, Board, Calendar} renders | D A I |
| L5-51 | Selector offers exactly Table/Board/Calendar; on A/I it's inside Display with labels; hidden on locked views | D A I |
| L5-52 | Table on A/I renders cross-project List with rows from ≥3 projects | A I |
| L5-53 | Board: 5 state-group columns, cards from ≥3 projects in the right column, no "No status" column, counts = loaded, Load more appends, read-only (no drag, no quick-add), tap card → peek | D A I |
| L5-54 | Calendar: dated items on correct day (month + week), weekends toggle, undated absent, tap → peek, read-only | D I |
| L5-55 | Header stays one line at 320/360/390/412; breadcrumb truncates and stays tappable (switch view) | A I |
| L5-56 | "⋯" menu reachable on A/I with Add view (mobile only), Edit/Delete; Add view button on D header only | D A I |
| L5-57 | Owner vs non-owner: edit hidden/refused for non-owner | D |

### Sorting [B-27…B-31]
| ID | Test | V |
|---|---|---|
| L5-70 | Order-by list: project page has State, no Project; global view has State + Project | D |
| L5-71 | Add rule 2 and 3, reorder, flip, remove; rendered order matches the expected order computed from API data | D A |
| L5-72 | Multi-sort × layout {list, spreadsheet, kanban column, global list, global board column} | D |
| L5-73 | Rules survive reload per view; view X rules ≠ view Y rules; project page and global view independent | D |
| L5-74 | Changing rules re-sorts without refetch (no new list request) | D |

## VR — Visual regression (Playwright screenshots, fixed QA data, frozen clock)

| ID | Screen | V |
|---|---|---|
| VR-01 | Login page | D I |
| VR-02 | Sidebar expanded with Pins populated | D |
| VR-03 | Mobile drawer open with scrim | I |
| VR-04 | Workspace / Projects pin dialogs | D I |
| VR-05 | Manage pinned dialog with search results | D I |
| VR-06 | Display bottom sheet (project page + global view) | I |
| VR-07 | Order-by with 3 rules | D |
| VR-08 | Global Board | D I |
| VR-09 | Global Calendar (month) | D |
| VR-10 | Global Table → mobile List | I |
| VR-11 | Global view header on 320 px | A |
| VR-12 | Peek overview mobile | I |
| VR-13 | Project work items List on phone (from Spreadsheet) | I |

Out of scope by decision (2026-09-17): plane-bot, n8n flows, Pocket ID/CF Access perimeter, MCP.

## L7 — Prod smoke (read-only, after every prod deploy)

L3-01…L3-15 (minus L3-00) · L5-01 on D and I · L5-02 crawl as `qa-smoke` (read-only Guest) on D and I ·
deployed image digests = promoted build. Any failure → **automatic rollback** + Telegram.

## M — Manual (Diego, real devices, only on T1/T3)

| ID | Check |
|---|---|
| M-00 | Only when the deploy changed the frontend; `plane-deploy` prints this list |
| M-01 | Real iPhone Safari: Work Items in every layout, Display sheet, drawer close |
| M-02 | Real Android: touch drag in the projects dialog and favourites |
| M-03 | Real Pocket ID passkey login end-to-end on phone + desktop |
| M-04 | Installed PWA opens the new build (no stale cache) |

## Size

~27 unit groups (≈320 cases with matrices) · 11 backend · 16 config · 13 API · ~42 E2E scenarios
(≈370 runs across viewports/combinations) · 13 visual (≈17 shots) · 5 manual.
