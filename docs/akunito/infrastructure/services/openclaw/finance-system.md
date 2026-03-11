---
id: infrastructure.services.openclaw.finance
summary: "Vaultkeeper finance system: Revolut import, multi-currency budgeting, salary-cycle reports"
tags: [openclaw, vaultkeeper, finance, revolut, budget, sqlite, matrix]
related_files: [templates/openclaw/workspace/skills/finance/SKILL.md, templates/openclaw/workspace/skills/finance/PROCEDURES.md, templates/openclaw/workspace/VAULTKEEPER_IDENTITY.md, templates/openclaw/workspace/VAULTKEEPER_SOUL.md, templates/openclaw/finance-market-data.py, templates/openclaw/sanitize-csv.py, system/app/openclaw.nix]
date: 2026-03-11
status: published
---

# Vaultkeeper Finance System

## Overview

Vaultkeeper is a privacy-first financial analyst agent running on OpenClaw. It processes Revolut multi-currency exports, classifies transactions, tracks budgets against salary-cycle periods, and generates consolidated monthly reports.

**Key properties:**
- Agent: `vaultkeeper` (routed via Matrix room `!ivCwPDzzvEUuIvPAYR:akunito.com`)
- Database: SQLite at `/home/node/.openclaw/finance-data/vaultkeeper.db` (WAL mode)
- Base currency: PLN (configurable)
- Salary cycle day: 7 (reports cut Feb 7 → Mar 6, not calendar month)
- Web access: DENIED (`deny: ["group:web"]`) — all external data via host-side services

## Architecture

```
User (Matrix/Element) → @vaultkeeperbot → OpenClaw Gateway → Vaultkeeper agent
                                                                    ↓
Host-side services (systemd timers) ──────────────────→ vaultkeeper.db (SQLite)
  - finance-market-data.py (ECB rates, crypto prices)
  - sanitize-csv.py (CSV injection defense)
```

**Data flow:**
1. User sends Revolut Excel/CSV to Vaultkeeper via Matrix (primary) or drops in filesystem (secondary)
2. Vaultkeeper parses, classifies, deduplicates, imports to SQLite
3. Host-side timers populate exchange rates and asset prices
4. Vaultkeeper generates cycle reports on-demand or via cron

## Database Schema (8 tables)

| Table | Purpose | Key fields |
|-------|---------|------------|
| `transactions` | Core ledger | date, amount, currency, amount_base, tx_type, category, dedup_hash |
| `exchange_rates` | Monthly fiat rates | PK(month, from_currency, to_currency), rate, source |
| `settings` | Configuration | base_currency=PLN, cycle_day=7, tracked_currencies=EUR,GBP,USD |
| `budget_targets` | Monthly limits per category | category, monthly_limit, alert_threshold |
| `monthly_summaries` | Cycle-end aggregates | income, expenses, savings_rate, net_worth, top_categories |
| `account_balances` | Per-account balance snapshots | month, account_type, account_name, balance_base |
| `asset_prices` | Crypto/stock prices | PK(date, asset_type, symbol), price_base, source |
| `holdings` | Current crypto/stock positions | UNIQUE(asset_type, symbol), quantity, source |

## Transaction Classification

### tx_type (determines what counts in totals)

| tx_type | In spending? | In income? | Detection |
|---------|-------------|------------|-----------|
| `expense` | YES | no | Card payments, ATM, subscriptions |
| `income` | no | YES | Salary, refunds, rewards |
| `exchange` | no | no | "Exchanged to/from" |
| `internal_transfer` | no | no | Pocket moves, Revolut Bank UAB, pocket withdrawals |
| `top_up` | no | no | Bank→Revolut transfers |
| `investment` | no | no | Stock/crypto trades |
| `unknown` | no | no | Ambiguous — flagged for review |

### Category mapping

Groceries, Dining, Transport, Housing, Health, Entertainment, Shopping, Subscriptions, Travel, Savings, Income, Other.

Detection via regex on transaction descriptions (see SKILL.md for full patterns).

## Exchange Rates

**Sources (precedence):** manual > ecb > revolut_inferred

**Host-side service:** `finance-market-data.py`
- ECB rates: 1st of month 07:00 (previous month)
- Crypto prices: daily 06:00 (CoinGecko)
- Backfill: `--backfill 2019-01 2026-03` for historical rates

**Amount conversion:** `amount_base = amount * rate` where rate is from `exchange_rates` table for the transaction's calendar month. PLN transactions have `amount_base = amount` (rate=1.0).

## Salary Cycle Reporting

- `cycle_day = 7` → Cycle 2026-02 = Feb 7 → Mar 6
- Transactions stay ISO date-based in DB
- Reporting queries use cycle boundaries: `WHERE date >= '2026-02-07' AND date <= '2026-03-06'`
- Exchange rates stay calendar-month-based (transaction on Mar 3 uses March rate)
- Revolut exports are calendar-month-based → one cycle spans TWO CSV exports

## Report Structure

Output: `finance/reports/YYYY-MM.md` + `finance/summary-latest.md` (in workspace)

1. **Net Worth Snapshot** — all accounts + balances in base currency
2. **Income & Spending** — totals, savings rate, by-category with budget % used
3. **Movements** — exchanges, internal transfers, top-ups (excluded from totals)

## Initial Bootstrap (2026-03-10)

### What was done

1. **Database created** with full schema (8 tables + settings)
2. **5,104 transactions imported** from `account-statement_2019-01-30_2026-03-10_en_b392a1.csv`
   - Currencies: PLN (3,118), EUR (1,819), USD (163), GBP (4)
   - Products: Current (4,217), Savings/Pocket (812), Investments (75)
   - 52 non-COMPLETED transactions skipped, 0 errors
3. **Classification applied**: expense (2,159), internal_transfer (2,164), exchange (420), top_up (221), investment (72), income (68), unknown (0)
4. **ECB rates backfilled**: 258 rates from 2019-01 to 2026-03 for EUR/PLN, GBP/PLN, USD/PLN
5. **amount_base populated**: 1,980 non-PLN transactions converted (6 remaining with NULL — March 2026 rates not yet published)
6. **Budget targets set**: 10 categories, 13,750 PLN/cycle total
7. **First report generated**: Cycle 2026-02 (Feb 7 → Mar 6)

### Import script location

- `/home/akunito/.openclaw/finance-data/revolut-import.py` (on VPS, inside container volume)
- `/home/akunito/.openclaw/finance-data/generate-report.py` (report generator)
- Source CSV: `/home/akunito/.openclaw/finance-imports/revolut-import.csv`

### Post-bootstrap refinement (2026-03-11)

**Income reclassification (281 transactions):**
- 137 salary deposits (`Top-up by 2268`) → `income/Salary`
- 68 shop refunds (Allegro, Amazon, etc.) → `refund/Refund` (were falsely `income`)
- 37 Walutomat exchanges → `exchange/Exchange`
- 27 self-transfers (Diego Rueda Galán) → `internal_transfer/Savings`
- 4 family transfers (sister, mother) → `income/Family`
- 3 eBay sales → `income/Sales`
- Monthly salary now tracked: avg ~10,800 PLN/month

**Category reclassification (1,127 transactions):**
- 42 rent payments identified: -1,250 PLN (Nov'23–Mar'25), -900 PLN (Dec'23–Sep'24), -750 PLN (Jun'21–Apr'22)
- 16 partner food transfers: -160 EUR (Aug'22–Jul'23)
- 73 Aplazame → Installments
- 48+ merchant patterns mapped to: Groceries, Transport, Sports & Entertainment, Dining, Health, Travel, Telecom, Subscriptions, Shopping, Cash, Investment
- "Other" reduced from 1,500 → 373 (long-tail merchants, 1–4 occurrences each)

**New category distribution (expenses):**
| Category | Count | Total PLN |
|----------|-------|-----------|
| Revolut Misc | 426 | -53,512 |
| Other | 373 | -39,038 |
| Shopping | 339 | -75,923 |
| Groceries | 306 | -25,157 |
| Transport | 135 | -4,680 |
| Dining | 93 | -4,275 |
| Sports & Entertainment | 77 | -1,163 |
| Installments | 73 | -5,245 |
| Telecom | 52 | -1,882 |
| Rent | 42 | -42,400 |
| Travel | 41 | -20,073 |
| Cash | 37 | -5,758 |
| Health | 34 | -5,142 |
| Subscriptions | 17 | -1,950 |

### Remaining known issues

1. **Revolut Misc (426 tx)** — small variable-amount charges to "Revolut Bank UAB" with no description detail. Likely card payments where merchant resolved to Revolut's name. Cannot be further classified without Revolut app details.
2. **Other (373 tx)** — long-tail merchants with 1–4 occurrences each. Not cost-effective to classify individually.
3. **6 transactions missing amount_base** — March 2026 ECB rates not yet published.
4. **Balance column from CSV not stored** — future imports should capture Balance for accurate per-row tracking.
5. **Vaultkeeper cron jobs not deployed** — `revolut-analysis` and `budget-pulse` crons need to be added to openclaw.json and activated.

## Vaultkeeper Operating Instructions

### For the user (monthly workflow)

1. **Export Revolut** (1st-3rd of month): Download CSV/Excel for previous month
2. **Send to Vaultkeeper**: Share file in Vaultkeeper's Matrix room
3. **Review classification**: Ask "show unknowns" — reclassify any flagged items
4. **Check report**: Ask "generate report" or wait for `revolut-analysis` cron (3rd of month)
5. **Budget check**: Ask "budget status" or wait for `budget-pulse` cron (Mondays)

### For Vaultkeeper (processing instructions)

When receiving a Revolut file via Matrix:

1. **Detect format**: Excel (.xlsx) may have multiple sheets; CSV is single-account
2. **Parse columns**: Type, Product, Started Date, Completed Date, Description, Amount, Fee, Currency, State, Balance
3. **Filter**: Only process rows with `State = COMPLETED`
4. **Classify tx_type**: Apply detection rules (see SKILL.md)
5. **Classify category**: Apply keyword regex (see SKILL.md)
6. **Compute dedup_hash**: `SHA256(date|amount|currency|account_name|description|row_index)`
7. **Insert**: `INSERT OR IGNORE` — dedup_hash prevents duplicates
8. **Convert amount_base**: Look up `exchange_rates` for the transaction's calendar month
9. **Report**: Confirm count imported, currencies found, any issues

### Reclassifying transactions

User tells Vaultkeeper:
- "Mark all Revolut Bank UAB transfers as internal_transfer"
- "Mark transaction 2026-02-15 'Schenker' +8500 as income"
- "All transfers from 'EMPLOYER NAME' are salary"

Vaultkeeper updates: `UPDATE transactions SET tx_type='income', category='Income' WHERE ...`

### Querying data

- "What did I spend on groceries this cycle?"
- "Am I over budget on Housing?"
- "Net worth change since last cycle?"
- "Show all unclassified transactions"
- "What's my savings rate?"

## Matrix Routing (CRITICAL)

See [integrations.md](integrations.md#multi-account-agent-routing-critical) for binding rules.

**Key facts:**
- `peer.kind` MUST be `"channel"` (not `"group"`)
- `peer.id` MUST use EXACT case from Matrix (e.g., `!ivCwPDzzvEUuIvPAYR:akunito.com`)
- Use `"accountId"` (not `"account"`) in binding match
- Stale sessions in `agents/*/sessions/sessions.json` must be manually purged after binding changes

## File Locations

### Repository (templates)
| File | Purpose |
|------|---------|
| `templates/openclaw/workspace/skills/finance/SKILL.md` | Full skill specification |
| `templates/openclaw/workspace/skills/finance/PROCEDURES.md` | Step-by-step exec commands for all operations |
| `templates/openclaw/workspace/VAULTKEEPER_IDENTITY.md` | Agent identity & roles |
| `templates/openclaw/workspace/VAULTKEEPER_SOUL.md` | Communication style & boundaries |
| `templates/openclaw/finance-market-data.py` | Host-side market data fetcher |
| `templates/openclaw/sanitize-csv.py` | CSV injection defense |
| `templates/openclaw/openclaw.json.template` | Config template with binding patterns |
| `system/app/openclaw.nix` | Systemd timer definitions |

### VPS (live)
| Path | Purpose |
|------|---------|
| `~/.openclaw/openclaw.json` | Live gateway config (owned by UID 100999) |
| `~/.openclaw/finance-data/vaultkeeper.db` | SQLite database |
| `~/.openclaw/finance-imports/` | CSV import directory (bind-mounted read-only) |
| `~/.openclaw/workspace-vaultkeeper/` | Vaultkeeper workspace (IDENTITY, SOUL, skills, reports) |
| `~/.openclaw/workspace-vaultkeeper/finance/reports/` | Generated cycle reports |
| `~/.openclaw/workspace-vaultkeeper/finance/summary-latest.md` | Aggregate summary (Alfred-readable) |
| `~/.openclaw/finance-data/revolut-import.py` | Bootstrap import script (temp) |
| `~/.openclaw/finance-data/generate-report.py` | Report generator script (temp) |
| `~/.openclaw/finance-imports/revolut-import.csv` | Source CSV (temp) |

### Systemd timers (defined in openclaw.nix)
| Timer | Schedule | Action |
|-------|----------|--------|
| `openclaw-sanitize-csv` | Daily 05:00 | Strip CSV injection patterns |
| `openclaw-finance-market-daily` | Daily 06:00 | Fetch crypto/stock prices |
| `openclaw-finance-market-monthly` | 1st of month 07:00 | Fetch ECB fiat rates |
| `openclaw-gateway-restart` | Daily 04:00 | Clear stale sessions |
