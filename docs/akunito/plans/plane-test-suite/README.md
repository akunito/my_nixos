---
id: plans.plane-test-suite
summary: "Plane fork regression suite — audit, interview decisions (2026-09-17), architecture, deploy gate, phases"
tags: [plane, testing, plan, vps, regression, playwright, vitest]
related_files: [docs/akunito/infrastructure/services/plane-customizations.md, .claude/commands/plane-upgrade.md]
date: 2026-09-17
status: draft
---

# Plan: Plane fork regression suite

**Status:** P1–P9 done (P7–P9 2026-09-22). **`plane-deploy` on the VPS is now the only way Plane changes**, and since P8 **prod runs our own image built from the fork** (`plane-aku/aio-community:6547899b9`) — nothing is patched at container start and no code is bind-mounted. Fork specs in `plane-up` `apps/web/tests/{unit,e2e}`; runner `run.sh unit|build|e2e` on the VPS (L1 140 tests / 8 files, **L2 352 backend tests**, L4 12/12, E2E 200 passed / 20 skipped, ~13 min; VR baselines live on the runner). Typecheck baseline **2** (was 27). All nine phases done; the suite is now the standing safety net and `/plane-security-review` the standing upstream duty. Epic **APLANE-7** (phases APLANE-8…16, follow-ups APLANE-17…20). Test catalogue: [`catalog.md`](catalog.md).

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
| F5 | Dev ≠ prod: dev lacked Fix 2b + `WEBHOOK_ALLOWED_HOSTS`, data from 2026-06-25. *(Correction 2026-09-17: the frontend bundle was already identical — "27 commits" was only a stale compose comment)* | P1 refresh + P2 + L3-15 drift ✅ |
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
| **M Manual** | real Android + passkey/PWA checks (Diego, only when frontend changes). **No iPhone exists** — the WebKit half is covered by Playwright and VR only, never on a real device | prod | — |

**Placement:** L0/L1/L2/L5/VR specs live **in the fork** (they move with the code); `plane-deploy`,
L3/L4/L7, seeds and the Telegram reporter live in dotfiles (`system/app/plane-tests/`, nix-packaged).

## 4. `plane-deploy` flow

```
plane-deploy [--ref REF] [--dev-only] [--config-only] [--rollback prod|dev] [--no-test-check] [--yes]
  0. rule check: fork code changed without tests → stop (--no-test-check overrides, logged + reported)
  1. L0 build gate + L1 unit from a clean checkout of REF        (L2 joins in P8)
  2. bundle → dev (previous kept), L3-00 → L3 → L4 → L5 + VR      any red → dev restored, STOP, Telegram
  3. bundle → prod (previous kept)
  4. L7 smoke                                                     red → ROLLBACK, Telegram
  5. Telegram green; record the deployed commit in <stack>/.deployed-ref
  6. print the manual checks Diego still owns
```

**Built 2026-09-22 (P7)** as `system/app/plane-tests/remote/deploy.sh`, installed by
`system/app/plane-tests.nix` (`planeTestsEnable`) as `plane-deploy` + `plane-tests` on the VPS, and
written into CLAUDE.md as an absolute rule. Until P8 it deploys the **frontend bundle only** — the
backend is still the AIO image + `start-override.sh`, so no migration runs and the rollback is a
directory swap (last 3 kept per stack). The swap never restarts the container: hashed assets first,
then `index.html`/`sw.js`, then the sweep, then every asset the shell references is re-fetched and
its content type checked (Caddy's SPA fallback answers a missing asset with index.html and 200).
Telegram goes through the infra-bot relay (`POST /deploy`), identified by tailnet IP — no token on
this path, unlike `infra-notify`, which reads a root-only secret.

Instance-config changes (god-mode/shell) also go through `plane-deploy --config-only` (runs L3 + L7).

## 5. Phases

| Phase | Content | Exit criterion |
|---|---|---|
| **P1** (APLANE-8) ✅ | `plane-dev-refresh`: full prod → dev copy minus log tables, **always followed by sanitize** (§6); mailpit sink; L3-00 safety test | Re-runnable in < 2 min; L3-00 green right after it |
| **P2** (APLANE-9) ✅ | Re-align dev code with prod (29-commit bundle, Fix 2b); drift test | L3-15 green |
| **P3** (APLANE-10) ✅ | `qa` + `qa-2` workspace seed (fictitious users with passwords, idempotent reset) on dev, chained into every refresh | Seed re-runnable after every refresh |
| **P4** (APLANE-11) ✅ | L3 + L7 (API half) against the current system; `qa-smoke` Guest + empty QA Smoke project on prod. Nix packaging moves to P7, where `plane-deploy` consumes it | Green on dev + prod |
| **P5** (APLANE-12) ✅ | vitest + Playwright + VR in the fork; L1, L4, L5 for the **current** features | Full suite green on dev |
| **P6** (APLANE-13) ✅ | Feature changes: multi-sort per view; pins by UUID + deleted/archived/no-access — each with its tests | Suite green |
| **P7** (APLANE-14) ✅ | `plane-deploy` (dev → gate → prod → smoke → rollback → Telegram); CLAUDE.md rule | One real frontend deploy through it |
| **P8** (APLANE-15) ✅ | Own images from the fork: port Fix 1/2/2b/3/4, Caddyfile, OIDC adapter into code; L2 pytest | Same suite green on the new images, dev then prod |
| **P9** (APLANE-16) ✅ | `/plane-security-review` replaces `/plane-upgrade`; register updated (A-11, F7, F8); first review ported three upstream security fixes | Docs + procedure merged |

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
| Sanitize (same script, never skippable) | delete workspaces `komi` + `leftyspace` (not relevant for tests; pg_dump can't filter by workspace) · deactivate every webhook · `EMAIL_HOST` → mailpit · `ENABLE_EMAIL_PASSWORD=1` · delete `api_tokens` (prod tokens would otherwise work on dev) · bust the `/api/instances/` cache · then run L3-00, which aborts if anything real is still reachable |
| QA seed | `qa` workspace with fictitious users/projects/states/items/views/pages + a small `qa-2` workspace (workspace switcher, pins and multi-sort must not leak across workspaces); automated tests only ever touch `qa*` |

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
| APLANE-19 | ~~Komi's workspace data copied to dev~~ | **Decided:** `komi` + `leftyspace` deleted in sanitize; `qa-2` covers multi-workspace |
| APLANE-20 | ~~Pocket ID / CF Access perimeter untested~~ | **Cancelled:** daily use through Pocket ID surfaces any break immediately |
| APLANE-21 | Prod `WEB_URL=http://plane.akunito.com` (not https) | Plane builds email/notification links from it |
| APLANE-16 | Register gaps: A-11 session, mount name, removed "More" buttons | Update `plane-customizations.md` (part of P9, don't lose it if P9 slips) |
| APLANE-23 | L3-15 **D06 compares dev's web bundle against prod's** | Since P6, dev runs a fork build prod does not have, so D06 is red by design while a change is in flight. `plane-deploy` (P7) should compare each side against the bundle built from the ref it deployed, not against the other side |

## 8-000. Manual verification log

The suite cannot log in with a passkey or hold a phone. What Diego confirmed by hand:

| When | Check | Verdict |
|---|---|---|
| 2026-09-23 | **Pocket ID sign-in on prod** after the image cutover (the OIDC adapter now comes from our image, not a bind-mount) | ✅ Works. Server side: `last_login medium=gitea` on the account created 2026-01-30 and the user count unchanged at 6 — it matched the existing account instead of creating a new one, which was the real risk |
| 2026-09-23 | **Android PWA** (drawer, a pinned ticket, the Display sheet) | ✅ "parece ir bien de momento" — provisional, which is why APLANE-25 keeps it In Review until 2026-10-23 |
| — | iPhone PWA | **not possible** — no device. Known gap, carried deliberately |

Nothing else is outstanding, but "green on the first day" is not the same as "green in a
month of real use": **APLANE-25** holds the soak period open until 2026-10-23, listing what
changed and is therefore worth suspecting first (attachments, assignee notifications, the
webhook payload the bot and n8n read, sub-issues, page ordering, anything mobile).

## 8-00. P9: watching upstream instead of upgrading (2026-09-22)

`/plane-upgrade` is retired (the file is a tombstone pointing here) and `/plane-security-review`
replaces it: read upstream, judge each change against **our** deployment, prove it applies by
running upstream's own test against our unpatched code, then cherry-pick it with that test and
ship through `plane-deploy`. Monthly-ish, plus whenever a Plane CVE appears.

**The first run was not a formality.** Upstream's `preview` was 64 commits past `v1.4.2`, six of
them security-relevant. Three had contract tests, and all three **failed against our code**:

| Upstream | What it fixes | Our exposure |
|---|---|---|
| #9382 | webhook HMAC `secret_key` returned on list/retrieve/patch | we run webhooks for the Telegram bot and n8n; any member who could read them saw the signing secret |
| #9387 | page list `order_by` taken raw from the query string | ordering by arbitrary fields, `password` among them |
| #9466 | `SubIssuesEndpoint` not scoped to the URL project | sub-issues readable and re-parentable across projects — and we have Guests |

All three cherry-picked cleanly, carry upstream's tests, and went out through `plane-deploy`.
Still open: the dependabot/Trivy sweeps (#9839, #9806) and the `sanitize-html` bump (#9736),
which need our lockfile checked rather than a cherry-pick.

Two gaps this exposed in our own machinery: `plane-deploy`'s rule check only looked at
`apps/web` and `packages/`, so a backend change could have reached prod untested (apps/api is
ours since P8); and L2 defaulted to `plane/tests/unit`, which would have skipped exactly the
contract tests these fixes ship with.

## 8-0. P8: what our image is (2026-09-22)

Upstream's AIO Dockerfile **does not build from source** — it `FROM`s the six published
`makeplane/plane-*` images and copies their artifacts into one runner. So `build_images.sh`
builds those six from the fork (`plane-aku/plane-*:<sha>`) and assembles the AIO on top with
`PLANE_IMAGE_PREFIX` pointing at them. Upstream's `deployments/cli/community/build.yml` is
unused: its build contexts resolve one directory short.

Every runtime patch is now source in the fork:

| Was | Now |
|---|---|
| Fix 1/2/2b: sed on `start.sh` / `plane.env` at boot | `start.sh` honours `USE_MINIO`, `MINIO_ENDPOINT_SSL`, `WEBHOOK_ALLOWED_HOSTS` (plane.env wins over the container env, which is why they had to be written there) |
| Fix 3: sed adding `APIKeyAuthentication` to the base views | `plane/app/views/base.py`, with L2 tests |
| Fix 4: sed adding assignees to the notification set | `plane/bgtasks/notification_task.py`, with L2 tests |
| Pocket ID adapter bind-mounted over `gitea.py` | the fork's `gitea.py`, with L2 tests on its endpoints and claims |
| Caddyfile bind-mounted per stack | `Caddyfile.aio.ce`, MinIO upstream from `AWS_S3_ENDPOINT_URL` |
| Frontend bundle bind-mounted into `/app/web` | baked into the image by `Dockerfile.web` |

A deploy is now an image swap plus `compose up -d` (~40 s where the API answers 502), and
`--rollback` swaps back to the tag recorded in `<stack>/.previous-image`.

## 8a. P7 findings (2026-09-22)

| # | Finding | Where it lands |
|---|---|---|
| P7-1 | `fork-suite.sh` re-checks the tree out and `git clean -fdx`s it on **every** command, so running `unit` after `build` deleted the bundle that was about to be deployed | the pipeline runs L1 first and builds last; caught by the first real `--dev-only` run |
| P7-2 | Without a tty (systemd-run, a hook) the prod confirmation prompt was simply skipped — an unattended run would have walked into prod | `--yes` is now mandatory when there is no terminal |
| P7-3 | `run.sh` passed arguments to the VPS as one unquoted string, so `-g "QA Locked"` arrived as two words and Playwright found no tests | each argument is `printf '%q'`-quoted now |
| P7-4 | A locked global view rendered nothing once in ~600 test runs and turned a deploy red; it passed 3/3 immediately after | Playwright retries once, and the deploy prints + reports anything that only passed on the retry |
| P7-5 | `infra-notify` needs a root-only secret, but the infra-bot's relay accepts `POST /deploy` from any tailnet peer — including the VPS itself | that is the transport; no token on this path |
| P8-1 | Porting the bind-mounted Caddyfile baked **prod's** container name (`plane-minio`) into the image; dev's is `plane-dev-minio`, so `/uploads` answered 502 there | L3-08 caught it on dev; the upstream is `AWS_S3_ENDPOINT_URL` now |
| P8-2 | Readiness polled `/`, which the proxy serves from static files the moment the container exists — the suite started ~40 s before gunicorn was up and read a 502 as a failure | `plane-deploy` waits on `/api/instances/` |
| P8-3 | Three drift checks were testing the old world: D02 demanded ≥6 mounts (there are 2), D03 hashed a `start-override.sh` neither side has (passing vacuously), D05 rewrote `plane-dev-minio` before comparing | rewritten; D07 is now "both stacks run the same image tag" |
| P8-4 | Upstream's AIO `build.sh` installed `yq` with sudo and never used it, and had a `/bin/bash` shebang — the runner is NixOS with no passwordless sudo and no `/bin/bash` | both fixed in the fork |
| P7-7 | The E2E step checks the tree out again too, so it deleted the built bundle *after* dev went green: the first prod attempt died with "is not a built bundle" on the way to prod (prod untouched — `deploy_bundle` refuses before copying) | the bundle is staged in `~/.cache/plane-tests/bundle` right after the build |
| P7-6 | Running `install.sh` on the VPS re-locked `flake.lock` in its working tree, so nixpkgs jumped to Playwright 1.63 (browsers 1243) under a suite pinned to 1.61.1 (1228). The first prod deploy died 5 min in with "Executable doesn't exist" — a message that says nothing about the cause | the runner now builds the browsers from the dotfiles flake at its **committed** revision, and asserts `@playwright/test` == `playwright-driver.version` in seconds before starting |

## 8b. P6 findings (2026-09-17)

| # | Finding | Where it lands |
|---|---|---|
| P6-1 | Archiving a **page** deletes its favourite server-side; archiving a **work item** keeps it. Upstream deviation, not something the fork chose | Pinned by L4-03b and asserted in L5-18b |
| P6-2 | A deleted work item leaves its favourite behind (`entity_identifier` is not a FK), so removing the pin is the frontend's job — exactly what B-10 now does | L4-03b |
| P6-3 | Only work items in a **completed / cancelled** state group can be archived, and a page must be archived before it can be deleted (400 otherwise) | Both tests create their fixtures accordingly |
| P6-4 | Declaring `currentWorkspaceFavorites` on `IFavoriteStore` removed 25 of the 27 typecheck errors; the 2 that remain are upstream (`filters.tsx` TS2538, `base-list-root.tsx` TS2345) | `TYPE_ERROR_BASELINE=2` |

## 8. P5 findings (2026-09-17)

| # | Finding | Where it lands |
|---|---|---|
| P5-1 | **B-02 broken for every new user**: v1.4.1's first sidebar-preferences GET seeds views/analytics unpinned, so the fork default never applies | APLANE-22; E2E L5-10 marked `test.fail` until fixed |
| P5-2 | v1.4.1 subscribes assignees when assigned — Fix 4 (A-09) only matters for assignees who aren't subscribed | L4-06 tests that case; register note (P9) |
| P5-3 | Upstream PATCH-before-GET quirks: sidebar preferences answer 200 and change nothing; cycle/module user-properties answer 404 | tests do GET first, like the app |
| P5-4 | `usePlatformOS` treats only iOS as mobile: iPhone opens the full work item page, Android the side peek | L5-35 accepts both |
| P5-5 | React #418/#423/#425 recoverable hydration errors on every route (SPA shell) | recorded, not failed |
| P5-6 | a11y gaps: untranslated aria-label `aria_labels.app_sidebar.close_workspace_menu` (fork), unlabeled page-header panel toggle and global layout buttons (upstream) | backlog |
| P5-7 | favourites midpoint reorder collides after 51 consecutive moves into the same gap (float precision) | documented in L1-10 |
| P5-8 | Caddy SPA fallback serves index.html (200) for missing assets | L7-02 checks content type |
| P5-9 | webhooks deleted through the API are soft-deleted | L3-00 S01 ignores them |

Catalogue deviations: L1-15…L1-18 (Pins) move to P6 with the UUID rewrite; L1-22 / L1-25 are covered by
E2E L5-13 / L5-17 (components too coupled to render in isolation); VR ships VR-01/02/03/06/08/09/10/11/13.
