---
id: plans.plane-test-suite
summary: "Plane fork regression suite — audit, interview decisions (2026-09-17), architecture, deploy gate, phases"
tags: [plane, testing, plan, vps, regression, playwright, vitest]
related_files: [docs/akunito/infrastructure/services/plane-customizations.md, .claude/commands/plane-upgrade.md]
date: 2026-09-17
status: draft
---

# Plan: Plane fork regression suite

**Status:** PLAN AGREED 2026-09-17 (audit + interview), nothing built yet. Epic **APLANE-7** (phases APLANE-8…16, follow-ups APLANE-17…20). Test catalogue: [`catalog.md`](catalog.md).

**Goal:** every customisation of our Plane (frontend fork, backend patches, instance config) has an
automated test, and the **whole suite runs on every deploy** through a single `plane-deploy`
command that blocks and rolls back on failure.

## 1. Decisions (interview 2026-09-17)

| Topic | Decision |
|---|---|
| **Upstream** | **No more upstream upgrades.** The fork is our product. Upstream is only *read* for security fixes and ideas, which we port ourselves |
| **Build** | **Own images built from the fork** (api + web + AIO assembly) on the VPS. `sed` patches and bind-mounts become normal commits with tests |
| Scope | Fork frontend + backend patches + instance config. **Out:** plane-bot, n8n flows, Pocket ID/CF Access perimeter, MCP |
| Dev | Keep the cloned real data and users for Diego's manual testing **plus** a seeded QA workspace with fictitious users for automated tests |
| Dev side effects | **Neutralised:** n8n webhook off, email → local sink (mailpit). A safety test runs first and aborts if dev can reach anything real |
| Test login | **Password login enabled on dev only**, QA users with passwords. Prod stays Pocket-ID-only |
| Prod | **Read-only** smoke after every deploy, authenticated as `qa-smoke` (Guest in an empty QA project, session minted via Django shell) |
| Runner | **VPS** (always on, loopback access to dev + prod) — build, unit, E2E |
| On failure | Dev red → **no promotion**. Prod smoke red → **automatic rollback** to the previous images + Telegram |
| Report | **Telegram infra-bot** (one line green; failures + rollback status red) |
| Run size | **Full suite on every deploy**, no nightly run |
| Visual regression | **Yes**, ~15 key screens, fixed QA data, tolerance; baselines re-approved on intentional UI changes |
| Rule | **No change to the fork without its tests in the same commit** — `plane-deploy` warns/blocks when code changed and tests didn't |
| Deploy path | **`plane-deploy` is the only way** to change Plane (no hand rsync/compose) — added to CLAUDE.md like `install.sh` |

### Feature changes decided before pinning behaviour in tests

| Item | Decision |
|---|---|
| Multi-sort scope (was one global set) | **Per view / per project** secondary rules |
| Pins store a label at pin time (stale title, 404 after identifier change) | **Fix:** resolve by UUID at render time (live name + identifier) |
| Pinned entity **deleted** | Pin **disappears automatically**, sidebar + backend (`UserFavorite`), every device |
| Pinned entity **archived** | Pin stays, opens the archived item |
| User **loses access** to the project | Pin **hidden, not deleted**; returns when access returns |

## 2. Audit findings (what the original request was missing)

| # | Finding | Handled by |
|---|---|---|
| F1 | Dev = prod-DB clone with the **n8n webhook active** (real Google Calendar), real SMTP relay, real users | P1 + L3-00 |
| F2 | Login can't be automated (Pocket ID passkeys) | Dev password login (P3) |
| F3 | Writes on prod would notify Aga (Telegram), calendar, email | Prod read-only (L7) |
| F4 | Deploys are hand rsync/compose — nothing to hook tests onto | `plane-deploy` (P7) |
| F5 | Dev ≠ prod: frontend 27 vs 29 commits, dev lacks Fix 2b, data from 2026-06-25 | P2 + L3-15 drift |
| F6 | Session lifetime (90 d rolling) is a customisation missing from the register | A-11, L3-05 |
| F7 | Register says prod mounts `web-override-fork`; it mounts `web-override-v141` | doc fix |
| F8 | Fork removed the "More" sidebar buttons — undocumented; projects past the limit reachable only via the pin dialog | L5-15 |
| F9 | Global Board/Calendar only show loaded pages; states of unloaded projects → "No status" | L1-19/20, L5-53 |
| F10 | API keys throttled at 60 req/min — the suite itself would 429 | session auth in E2E, paced API tier |
| F11 | `apps/web` has no test infra; upstream only has backend pytest | P5 |
| F12 | iOS crash class is WebKit-only | Playwright WebKit project |
| F13 | DESK (current fork build host) not always reachable | runner on VPS |
| F14 | Removing upstream upgrades makes `/plane-upgrade` obsolete; security review needs its own procedure | P9 |

**Accepted risk (out of scope):** plane-bot and the n8n calendar sync depend on the webhook payload
shape. Moving to our own image can change it without any test noticing — check them by hand after P8.

## 3. Architecture

| Layer | What | Target | Writes? |
|---|---|---|---|
| **L0 Build gate** | build, typecheck (no new errors), bundle checks | — | no |
| **L1 Unit (web)** | vitest — pure logic of every fork feature | — | no |
| **L2 Backend** | pytest for our backend code (API-key auth, notifications, favourites cleanup, config) | test DB | test DB |
| **L3 Config contract** | instance flags, env, settings, routes, served build, drift | dev + prod | no |
| **L4 API functional** | attachments, favourites, views perms, notifications, webhooks SSRF | dev QA | yes |
| **L5 E2E** | Playwright: Chromium desktop, Chromium Android, WebKit iPhone, 767/768 | dev QA | yes |
| **VR Visual** | ~15 screenshot baselines | dev QA | no |
| **L7 Prod smoke** | L3 + login page + read-only crawl as `qa-smoke` | prod | **no** |
| **M Manual** | real iPhone/Android/passkey/PWA checks (Diego, only when frontend changes) | prod | — |

**Placement:** L0/L1/L2/L5/VR specs live **in the fork** (they move with the code); `plane-deploy`,
L3/L4/L7, seeds and the Telegram reporter live in dotfiles (`system/app/plane-tests/`, nix-packaged).

## 4. `plane-deploy` flow

```
plane-deploy [--ref <commit>]
  0. rule check: fork code changed without tests → stop (override flag, logged)
  1. build images from the fork @ref (api, web, AIO)            → L0
  2. L1 + L2 inside the build
  3. deploy to dev (compose, tagged by commit)
  4. L3-00 dev safety → L3 → L4 → L5 → VR on dev                  any red → STOP, Telegram
  5. snapshot prod (image tags, compose, pg_dump)
  6. deploy to prod
  7. L7 smoke                                                     red → ROLLBACK to 5, Telegram
  8. Telegram green; record deployed commit + image digests
  9. frontend changed → list the M checks for Diego
```

Instance-config changes (god-mode/shell) also go through `plane-deploy --config-only` (runs L3 + L7).

## 5. Phases

| Phase | Content | Exit criterion |
|---|---|---|
| **P1** (APLANE-8) | `plane-dev-refresh`: full prod → dev copy minus log tables, **always followed by sanitize** (§6); mailpit sink; L3-00 safety test | Re-runnable in < 2 min; L3-00 green right after it |
| **P2** (APLANE-9) | Re-align dev code with prod (29-commit bundle, Fix 2b); drift test | L3-15 green |
| **P3** (APLANE-10) | `qa` workspace seed (fictitious users with passwords, idempotent reset) on dev; `qa-smoke` Guest on prod | Seed re-runnable after every refresh |
| **P4** (APLANE-11) | L3 + L7 against the **current** system (sed-based) | Green on dev + prod |
| **P5** (APLANE-12) | vitest + Playwright + VR in the fork; L1, L4, L5 for the **current** features | Full suite green on dev |
| **P6** (APLANE-13) | Feature changes: multi-sort per view; pins by UUID + deleted/archived/no-access — each with its tests | Suite green |
| **P7** (APLANE-14) | `plane-deploy` (dev → gate → prod → smoke → rollback → Telegram); CLAUDE.md rule | One real frontend deploy through it |
| **P8** (APLANE-15) | Own images from the fork: port Fix 1/2/2b/3/4, Caddyfile, OIDC adapter, session env into code; L2 pytest | Same suite green on the new images, dev then prod |
| **P9** (APLANE-16) | Replace `/plane-upgrade` with a security-review procedure; update `plane-customizations.md` (A-11, F7, F8, decisions) | Docs + skill merged |

P4–P5 come **before** P8 on purpose: the suite is the safety net for the image migration, the
riskiest change in this plan.

## 6. Dev data: real copy + separate QA workspace (decided 2026-09-17)

Measured on prod 2026-09-17: database **557 MB**, of which **516 MB (93 %) is `api_activity_logs`**
(92 735 API request log rows). Everything real is small: 1 040 work items, **632 pages = 5 MB**,
537 comments, 29 attachments, MinIO **7 MB**.

**So nothing needs to be skipped.** Dropping 95 % of the pages would save ~5 MB and cost FK surgery
(page versions, project links, favourites, descriptions). Skipping the *log* tables is what pays:

| Step | What |
|---|---|
| Copy | `pg_dump` prod with `--exclude-table-data` for `api_activity_logs`, `webhook_logs` and the session table (prod sessions must not be valid on dev) → restore into an emptied dev DB; `mc mirror` uploads |
| Sanitize (same script, never skippable) | deactivate every webhook · `EMAIL_HOST` → mailpit · `ENABLE_EMAIL_PASSWORD=1` · delete `api_tokens` (prod tokens would otherwise work on dev) · bust the `/api/instances/` cache · then run L3-00, which aborts if anything real is still reachable |
| QA seed | `qa` workspace with fictitious users/projects/states/items/views/pages; automated tests only ever touch `qa` |

**Why both and not only dummy data:** tests and visual baselines need deterministic data that doesn't
change when you work (`qa`); the real copy is for your manual testing and catches what fixtures
never have (836 items and 628 pages in `akuworkspace`). Cheap extra test: **L5-03**, a read-only crawl
over the real `akuworkspace` on dev (every project × layout, desktop + iPhone) that only asserts no
error boundary / console error.

## 7. Follow-ups to review later (tracked in Plane)

| Ticket | Item | Why |
|---|---|---|
| APLANE-17 | Check plane-bot + n8n calendar sync by hand after P8 | Out of scope for the suite; own images can change the webhook payload |
| APLANE-18 | Prod `api_activity_logs` = 516 MB and growing | No retention; 93 % of the DB is request logs |
| APLANE-19 | Komi's workspace data is copied to dev | Confirm it's acceptable (dev is Tailscale-only) or exclude the `komi` workspace from the copy |
| APLANE-20 | Pocket ID / CF Access perimeter untested | Excluded by decision; `/god-mode*` + `/api/instances/admins*` coverage is still only a manual check |
| APLANE-16 | Register gaps: A-11 session, mount name, removed "More" buttons | Update `plane-customizations.md` (part of P9, don't lose it if P9 slips) |
