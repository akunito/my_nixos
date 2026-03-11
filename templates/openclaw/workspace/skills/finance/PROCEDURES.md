# Finance Skill — Operational Procedures

**Agent**: Vaultkeeper only
**Tool**: `exec` (Python + sqlite3) — Vaultkeeper has no web access
**Database**: `/home/node/.openclaw/finance-data/vaultkeeper.db`

> Every Python snippet below can be run via the `exec` tool. Always use
> `PRAGMA journal_mode=WAL` on first connect. Always `ROUND(value, 2)` in reports.

---

## 1. Import Revolut CSV (from Matrix file)

When user sends a CSV/Excel file via Matrix:

### Step 1a — Inspect the file
```python
exec python3 -c "
import csv, io, sys

# Read the file content (Matrix delivers it as text or base64)
# Adjust path if saved to disk first
data = open('/home/node/.openclaw/finance-imports/revolut-import.csv').read()
reader = csv.reader(io.StringIO(data))
header = next(reader)
print('Columns:', header)
rows = list(reader)
print(f'Total rows: {len(rows)}')
print('First 3 rows:')
for r in rows[:3]:
    print(r)
print('Last 3 rows:')
for r in rows[-3:]:
    print(r)
"
```

### Step 1b — Run the import script
```python
exec python3 /home/node/.openclaw/finance-data/revolut-import.py \
  --csv /home/node/.openclaw/finance-imports/revolut-import.csv \
  --db /home/node/.openclaw/finance-data/vaultkeeper.db
```

If the import script is not available, use the inline import procedure:

```python
exec python3 -c "
import sqlite3, csv, hashlib, io, re
from datetime import datetime

DB = '/home/node/.openclaw/finance-data/vaultkeeper.db'
CSV_PATH = '/home/node/.openclaw/finance-imports/revolut-import.csv'

db = sqlite3.connect(DB)
db.execute('PRAGMA journal_mode=WAL')

with open(CSV_PATH) as f:
    reader = csv.DictReader(f)
    imported = 0
    skipped = 0
    for i, row in enumerate(reader):
        # Skip incomplete transactions
        if row.get('State', '').strip() != 'Completed':
            skipped += 1
            continue

        date_str = row.get('Started Date', row.get('Date started', '')).strip()
        date = datetime.strptime(date_str[:10], '%Y-%m-%d').strftime('%Y-%m-%d')
        desc = row.get('Description', '').strip()[:60]
        amount = float(row.get('Amount', 0))
        currency = row.get('Currency', 'PLN').strip()
        fee = float(row.get('Fee', 0) or 0)
        product = row.get('Product', 'Current').strip()

        # Account info
        account_type = 'main' if product in ('Current', '') else 'pocket'
        account_name = currency if account_type == 'main' else product

        # Dedup hash
        raw = f'{date}{amount}{currency}{account_name}{desc}{i}'
        dedup = hashlib.sha256(raw.encode()).hexdigest()

        # Check if exists
        if db.execute('SELECT 1 FROM transactions WHERE dedup_hash=?', (dedup,)).fetchone():
            skipped += 1
            continue

        # Classify tx_type
        tx_type = 'expense'
        if re.search(r'Exchanged to|Exchanged from', desc, re.I):
            tx_type = 'exchange'
        elif re.search(r'Top-Up by|Top up from|Google Pay top-up', desc, re.I):
            tx_type = 'top_up'
        elif re.search(r'To pocket|From pocket|Pocket Withdrawal', desc, re.I):
            tx_type = 'internal_transfer'
        elif re.search(r'Transfer to|SWIFT Transfer', desc, re.I):
            tx_type = 'internal_transfer'
        elif desc == 'Top-up by 2268':
            tx_type = 'income'
        elif amount > 0:
            tx_type = 'income'

        if amount > 0 and tx_type == 'expense':
            tx_type = 'income'

        # Category (basic)
        category = 'Other'
        if tx_type == 'income':
            category = 'Salary' if desc == 'Top-up by 2268' else 'Income'
        elif tx_type in ('exchange', 'internal_transfer', 'top_up'):
            category = 'Savings'
        elif tx_type == 'investment':
            category = 'Investment'

        # Base currency conversion (PLN = 1.0, others need rate lookup)
        amount_base = amount if currency == 'PLN' else None
        if currency != 'PLN':
            month = date[:7]
            rate_row = db.execute(
                'SELECT rate FROM exchange_rates WHERE month=? AND from_currency=? AND to_currency=\"PLN\"',
                (month, currency)).fetchone()
            if rate_row:
                amount_base = round(amount * rate_row[0], 2)

        db.execute('''INSERT INTO transactions
            (date, description, amount, currency, amount_base, account_type, account_name,
             tx_type, category, raw_description, raw_category, source_file, row_index, dedup_hash)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
            (date, desc, amount, currency, amount_base, account_type, account_name,
             tx_type, category, desc, row.get('Category'), CSV_PATH, i, dedup))
        imported += 1

    db.commit()
    print(f'Imported: {imported}, Skipped (dupes/incomplete): {skipped}')
db.close()
"
```

---

## 2. Generate Monthly Cycle Report

Generate a report for a specific salary cycle (cycle_day=7, so cycle 2026-02 = Feb 7 → Mar 6).

```python
exec python3 -c "
import sqlite3, json
from datetime import datetime, timedelta
from calendar import monthrange

DB = '/home/node/.openclaw/finance-data/vaultkeeper.db'
CYCLE = '2026-02'  # <-- CHANGE THIS to the target cycle

db = sqlite3.connect(DB)
db.execute('PRAGMA journal_mode=WAL')
db.row_factory = sqlite3.Row

# Cycle boundaries
year, month = map(int, CYCLE.split('-'))
cycle_day = int(db.execute(\"SELECT value FROM settings WHERE key='cycle_day'\").fetchone()[0])
start = f'{year}-{month:02d}-{cycle_day:02d}'
# Next month
if month == 12:
    end_year, end_month = year + 1, 1
else:
    end_year, end_month = year, month + 1
end = f'{end_year}-{end_month:02d}-{cycle_day - 1:02d}'

print(f'# Financial Report — Cycle {CYCLE} ({start} → {end})')
print()

# Income
inc = db.execute('''SELECT ROUND(SUM(COALESCE(amount_base, amount)), 2) as total
    FROM transactions WHERE date >= ? AND date <= ? AND tx_type = 'income' ''', (start, end)).fetchone()
income_total = inc['total'] or 0
print(f'## Income: {income_total:,.2f} PLN')

inc_detail = db.execute('''SELECT category, ROUND(SUM(COALESCE(amount_base, amount)), 2) as total
    FROM transactions WHERE date >= ? AND date <= ? AND tx_type = 'income'
    GROUP BY category ORDER BY total DESC''', (start, end)).fetchall()
for r in inc_detail:
    print(f'  {r[\"category\"]}: {r[\"total\"]:,.2f} PLN')

# Expenses
exp = db.execute('''SELECT ROUND(SUM(ABS(COALESCE(amount_base, amount))), 2) as total
    FROM transactions WHERE date >= ? AND date <= ? AND tx_type = 'expense' ''', (start, end)).fetchone()
expense_total = exp['total'] or 0
print(f'\n## Expenses: {expense_total:,.2f} PLN')

# By category
cats = db.execute('''SELECT category, ROUND(SUM(ABS(COALESCE(amount_base, amount))), 2) as total, COUNT(1) as cnt
    FROM transactions WHERE date >= ? AND date <= ? AND tx_type = 'expense'
    GROUP BY category ORDER BY total DESC''', (start, end)).fetchall()

# Get budget targets
budgets = {}
for b in db.execute('SELECT category, monthly_limit FROM budget_targets').fetchall():
    budgets[b['category']] = b['monthly_limit']

print(f'| Category | Amount (PLN) | Budget | % Used | Count |')
print(f'|----------|-------------|--------|--------|-------|')
for c in cats:
    bgt = budgets.get(c['category'], '-')
    pct = f'{c[\"total\"]/bgt*100:.0f}%' if isinstance(bgt, (int, float)) and bgt > 0 else '-'
    bgt_str = f'{bgt:,.0f}' if isinstance(bgt, (int, float)) else '-'
    print(f'| {c[\"category\"]} | {c[\"total\"]:,.2f} | {bgt_str} | {pct} | {c[\"cnt\"]} |')

# Savings rate
if income_total > 0:
    savings_rate = (income_total - expense_total) / income_total * 100
    print(f'\n## Savings Rate: {savings_rate:.1f}%')
else:
    print('\n## Savings Rate: N/A (no income)')

# Spending by currency
print('\n## Spending by Currency')
curr = db.execute('''SELECT currency, ROUND(SUM(ABS(amount)), 2) as total, COUNT(1) as cnt
    FROM transactions WHERE date >= ? AND date <= ? AND tx_type = 'expense'
    GROUP BY currency ORDER BY total DESC''', (start, end)).fetchall()
for c in curr:
    print(f'  {c[\"currency\"]}: {c[\"total\"]:,.2f} ({c[\"cnt\"]} tx)')

db.close()
"
```

---

## 3. Check Budget / Spending Pace

Quick mid-cycle budget check (e.g., for Monday pulse):

```python
exec python3 -c "
import sqlite3
from datetime import datetime, date

DB = '/home/node/.openclaw/finance-data/vaultkeeper.db'
db = sqlite3.connect(DB)
db.execute('PRAGMA journal_mode=WAL')
db.row_factory = sqlite3.Row

today = date.today()
cycle_day = int(db.execute(\"SELECT value FROM settings WHERE key='cycle_day'\").fetchone()[0])

# Current cycle start
if today.day >= cycle_day:
    start = today.replace(day=cycle_day)
else:
    m = today.month - 1 if today.month > 1 else 12
    y = today.year if today.month > 1 else today.year - 1
    start = date(y, m, cycle_day)

# Days into cycle
days_in = (today - start).days
days_total = 30  # approximate

print(f'Budget Pulse — Day {days_in}/{days_total} of cycle')
print(f'Cycle start: {start}')
print()

cats = db.execute('''
    SELECT t.category,
           ROUND(SUM(ABS(COALESCE(t.amount_base, t.amount))), 2) as spent,
           b.monthly_limit as budget
    FROM transactions t
    LEFT JOIN budget_targets b ON t.category = b.category
    WHERE t.date >= ? AND t.tx_type = 'expense'
    GROUP BY t.category
    ORDER BY spent DESC
''', (start.isoformat(),)).fetchall()

print(f'| Category | Spent | Budget | Pace |')
print(f'|----------|-------|--------|------|')
for c in cats:
    budget = c['budget']
    if budget and budget > 0:
        expected_pct = days_in / days_total * 100
        actual_pct = c['spent'] / budget * 100
        pace = 'ON TRACK' if actual_pct <= expected_pct * 1.1 else 'OVER PACE'
        if actual_pct > 100:
            pace = 'OVER BUDGET'
        print(f'| {c[\"category\"]} | {c[\"spent\"]:,.0f} | {budget:,.0f} | {actual_pct:.0f}% ({pace}) |')
    else:
        print(f'| {c[\"category\"]} | {c[\"spent\"]:,.0f} | - | - |')

db.close()
"
```

---

## 4. Reclassify Transactions

### Single transaction by ID
```python
exec python3 -c "
import sqlite3
db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.execute('PRAGMA journal_mode=WAL')

TX_ID = 123       # <-- CHANGE
NEW_TYPE = 'expense'     # <-- CHANGE (income, expense, internal_transfer, exchange, etc.)
NEW_CAT = 'Dining'       # <-- CHANGE

db.execute('UPDATE transactions SET tx_type=?, category=? WHERE id=?', (NEW_TYPE, NEW_CAT, TX_ID))
db.commit()
print(f'Updated transaction {TX_ID} -> tx_type={NEW_TYPE}, category={NEW_CAT}')
db.close()
"
```

### Bulk reclassify by description pattern
```python
exec python3 -c "
import sqlite3
db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.execute('PRAGMA journal_mode=WAL')

PATTERN = 'Żabka'         # <-- CHANGE (exact match)
NEW_CAT = 'Groceries'     # <-- CHANGE
NEW_TYPE = None            # <-- Set to change tx_type too, or None to keep

if NEW_TYPE:
    cnt = db.execute('UPDATE transactions SET category=?, tx_type=? WHERE description=?',
                     (NEW_CAT, NEW_TYPE, PATTERN)).rowcount
else:
    cnt = db.execute('UPDATE transactions SET category=? WHERE description=?',
                     (NEW_CAT, PATTERN)).rowcount
db.commit()
print(f'Reclassified {cnt} transactions matching \"{PATTERN}\" -> category={NEW_CAT}')
db.close()
"
```

### Find unclassified / Other transactions
```python
exec python3 -c "
import sqlite3
db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.row_factory = sqlite3.Row

rows = db.execute('''
    SELECT description, count(1) as cnt, ROUND(SUM(amount), 2) as total
    FROM transactions
    WHERE category = 'Other' AND tx_type = 'expense'
    GROUP BY description ORDER BY cnt DESC LIMIT 20
''').fetchall()

print('Top unclassified expense merchants:')
for r in rows:
    print(f'  [{r[\"cnt\"]:>3}x] total={r[\"total\"]:>10.2f} | {r[\"description\"]}')
db.close()
"
```

---

## 5. Query Transactions

### Search by description
```python
exec python3 -c "
import sqlite3
db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.row_factory = sqlite3.Row

SEARCH = '%allegro%'  # <-- CHANGE (SQL LIKE pattern)

rows = db.execute('''
    SELECT date, description, amount, currency, tx_type, category
    FROM transactions WHERE description LIKE ? ORDER BY date DESC LIMIT 20
''', (SEARCH,)).fetchall()

for r in rows:
    print(f'{r[\"date\"]} | {r[\"amount\"]:>10.2f} {r[\"currency\"]} | {r[\"tx_type\"]:>18} | {r[\"category\"]:>15} | {r[\"description\"]}')
print(f'Showing {len(rows)} results')
db.close()
"
```

### Spending summary for current cycle
```python
exec python3 -c "
import sqlite3
from datetime import date

db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.row_factory = sqlite3.Row

today = date.today()
cycle_day = int(db.execute(\"SELECT value FROM settings WHERE key='cycle_day'\").fetchone()[0])

if today.day >= cycle_day:
    start = today.replace(day=cycle_day)
else:
    m = today.month - 1 if today.month > 1 else 12
    y = today.year if today.month > 1 else today.year - 1
    start = date(y, m, cycle_day)

total = db.execute('''
    SELECT ROUND(SUM(ABS(COALESCE(amount_base, amount))), 2)
    FROM transactions WHERE date >= ? AND tx_type = 'expense'
''', (start.isoformat(),)).fetchone()[0] or 0

income = db.execute('''
    SELECT ROUND(SUM(COALESCE(amount_base, amount)), 2)
    FROM transactions WHERE date >= ? AND tx_type = 'income'
''', (start.isoformat(),)).fetchone()[0] or 0

print(f'Current cycle (from {start}):')
print(f'  Income:   {income:>12,.2f} PLN')
print(f'  Expenses: {total:>12,.2f} PLN')
print(f'  Net:      {income - total:>12,.2f} PLN')
db.close()
"
```

### Transaction type distribution
```python
exec python3 -c "
import sqlite3
db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.row_factory = sqlite3.Row

rows = db.execute('''
    SELECT tx_type, count(1) as cnt, ROUND(SUM(amount), 2) as total
    FROM transactions GROUP BY tx_type ORDER BY cnt DESC
''').fetchall()

for r in rows:
    print(f'  {r[\"tx_type\"]:>20}: {r[\"cnt\"]:>5} tx, total: {r[\"total\"]:>12,.2f}')
db.close()
"
```

---

## 6. Manage Budget Targets

### View current budgets
```python
exec python3 -c "
import sqlite3
db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.row_factory = sqlite3.Row

rows = db.execute('SELECT * FROM budget_targets ORDER BY monthly_limit DESC').fetchall()
for r in rows:
    print(f'  {r[\"category\"]:>20}: {r[\"monthly_limit\"]:>8,.0f} {r[\"currency\"]} (alert at {r[\"alert_threshold\"]*100:.0f}%)')
db.close()
"
```

### Set / update a budget
```python
exec python3 -c "
import sqlite3
db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.execute('PRAGMA journal_mode=WAL')

CATEGORY = 'Dining'     # <-- CHANGE
LIMIT = 500.0           # <-- CHANGE (monthly limit in PLN)
THRESHOLD = 0.8         # <-- CHANGE (alert at 80%)

db.execute('''INSERT OR REPLACE INTO budget_targets (category, monthly_limit, currency, alert_threshold)
    VALUES (?, ?, 'PLN', ?)''', (CATEGORY, LIMIT, THRESHOLD))
db.commit()
print(f'Budget set: {CATEGORY} = {LIMIT} PLN (alert at {THRESHOLD*100:.0f}%)')
db.close()
"
```

---

## 7. Exchange Rates

### View rates for a month
```python
exec python3 -c "
import sqlite3
db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.row_factory = sqlite3.Row

MONTH = '2026-02'  # <-- CHANGE

rows = db.execute('SELECT * FROM exchange_rates WHERE month=? ORDER BY from_currency', (MONTH,)).fetchall()
for r in rows:
    print(f'  {r[\"month\"]} | {r[\"from_currency\"]}/{r[\"to_currency\"]} = {r[\"rate\"]:.4f} (source: {r[\"source\"]})')
db.close()
"
```

### Set manual rate
```python
exec python3 -c "
import sqlite3
db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.execute('PRAGMA journal_mode=WAL')

MONTH = '2026-03'       # <-- CHANGE
FROM_CUR = 'EUR'        # <-- CHANGE
TO_CUR = 'PLN'
RATE = 4.30             # <-- CHANGE (1 EUR = 4.30 PLN)

db.execute('''INSERT OR REPLACE INTO exchange_rates (month, from_currency, to_currency, rate, source)
    VALUES (?, ?, ?, ?, 'manual')''', (MONTH, FROM_CUR, TO_CUR, RATE))
db.commit()
print(f'Rate set: {MONTH} {FROM_CUR}/{TO_CUR} = {RATE} (manual)')
db.close()
"
```

### Recalculate amount_base for all transactions missing it
```python
exec python3 -c "
import sqlite3
db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.execute('PRAGMA journal_mode=WAL')

# Get all rates
rates = {}
for r in db.execute('SELECT month, from_currency, rate FROM exchange_rates WHERE to_currency=\"PLN\"').fetchall():
    rates[(r[0], r[1])] = r[2]

# Update NULL amount_base
rows = db.execute('SELECT id, date, amount, currency FROM transactions WHERE amount_base IS NULL AND currency != \"PLN\"').fetchall()
updated = 0
for r in rows:
    month = r[1][:7]
    key = (month, r[2])
    if key in rates:
        base = round(r[3] * rates[key], 2)
        db.execute('UPDATE transactions SET amount_base=? WHERE id=?', (base, r[0]))
        updated += 1

db.commit()
print(f'Updated {updated}/{len(rows)} transactions with base amounts')
db.close()
"
```

---

## 8. Holdings & Net Worth

### View current holdings
```python
exec python3 -c "
import sqlite3
db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.row_factory = sqlite3.Row

rows = db.execute('SELECT * FROM holdings ORDER BY asset_type, symbol').fetchall()
for r in rows:
    print(f'  {r[\"asset_type\"]:>6} | {r[\"symbol\"]:>5} | qty: {r[\"quantity\"]} | avg price: {r[\"avg_buy_price\"]} | source: {r[\"source\"]} | updated: {r[\"updated_at\"]}')
db.close()
"
```

### Add/update manual holding
```python
exec python3 -c "
import sqlite3
from datetime import datetime

db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.execute('PRAGMA journal_mode=WAL')

ASSET_TYPE = 'crypto'   # <-- CHANGE (crypto, stock)
SYMBOL = 'BTC'          # <-- CHANGE
QUANTITY = 0.15          # <-- CHANGE
AVG_PRICE = None        # <-- CHANGE or None

db.execute('''INSERT INTO holdings (asset_type, symbol, quantity, avg_buy_price, source, updated_at)
    VALUES (?, ?, ?, ?, 'manual', ?)
    ON CONFLICT(asset_type, symbol) DO UPDATE SET
        quantity=excluded.quantity, avg_buy_price=excluded.avg_buy_price,
        source='manual', updated_at=excluded.updated_at''',
    (ASSET_TYPE, SYMBOL, QUANTITY, AVG_PRICE, datetime.now().isoformat()))
db.commit()
print(f'Holding set: {QUANTITY} {SYMBOL} ({ASSET_TYPE})')
db.close()
"
```

---

## 9. Database Health Check

```python
exec python3 -c "
import sqlite3
db = sqlite3.connect('/home/node/.openclaw/finance-data/vaultkeeper.db')
db.row_factory = sqlite3.Row

print('=== DATABASE HEALTH ===')
tx_count = db.execute('SELECT count(1) FROM transactions').fetchone()[0]
print(f'Total transactions: {tx_count}')

null_base = db.execute('SELECT count(1) FROM transactions WHERE amount_base IS NULL AND currency != \"PLN\"').fetchone()[0]
print(f'Missing amount_base (non-PLN): {null_base}')

unknown = db.execute('SELECT count(1) FROM transactions WHERE tx_type = \"unknown\"').fetchone()[0]
print(f'Unknown tx_type: {unknown}')

other_exp = db.execute('SELECT count(1) FROM transactions WHERE category = \"Other\" AND tx_type = \"expense\"').fetchone()[0]
print(f'Uncategorized expenses (Other): {other_exp}')

rate_months = db.execute('SELECT count(DISTINCT month) FROM exchange_rates').fetchone()[0]
print(f'Exchange rate months: {rate_months}')

budgets = db.execute('SELECT count(1) FROM budget_targets').fetchone()[0]
print(f'Budget targets: {budgets}')

summaries = db.execute('SELECT count(1) FROM monthly_summaries').fetchone()[0]
print(f'Monthly summaries: {summaries}')

# Date range
dr = db.execute('SELECT MIN(date), MAX(date) FROM transactions').fetchone()
print(f'Date range: {dr[0]} → {dr[1]}')

# Last import
last = db.execute('SELECT MAX(date) FROM transactions').fetchone()[0]
print(f'Last transaction: {last}')

db.close()
"
```

---

## 10. Known Classification Rules (as of 2026-03-11)

These patterns have been validated by the user. Apply them when importing new data:

### Income patterns
| Description pattern | tx_type | category |
|---|---|---|
| `Top-up by 2268` | income | Salary |
| `Payment from NOELIA RUEDA GALAN` | income | Family |
| `Payment from GALAN, GALA, PILAR` | income | Family |

### Self-transfer patterns (NOT income)
| Description pattern | tx_type | category |
|---|---|---|
| `Payment from RUEDA GALAN DIEGO` | internal_transfer | Savings |
| `Payment from DIEGO RUEDA GALAN` | internal_transfer | Savings |
| `SWIFT Transfer to Diego Rueda Galán` | internal_transfer | Savings |
| `Payment from CURRENCY ONE SPOLKA AKCYJNA` | exchange | Exchange |

### Partner / shared expenses
| Description pattern | tx_type | category |
|---|---|---|
| `SWIFT Transfer to Agnieszka Łyszcz` | internal_transfer | Partner/Shared |

### Rent (recurring Revolut charges)
| Pattern | Amount | Period | category |
|---|---|---|---|
| `Revolut Bank UAB` | -1,250 PLN | Nov 2023 → Mar 2025 | Rent |
| `Revolut Bank UAB` | -900 PLN | Dec 2023 → Sep 2024 | Rent |
| `Revolut Payments UAB` | -750 PLN | Jun 2021 → Apr 2022 | Rent |
| `Revolut Bank UAB` | -160 EUR | Aug 2022 → Jul 2023 | Groceries (partner food) |

### Refunds (NOT income)
Positive amounts from merchants like Allegro, Amazon, Temu, AliExpress, eBay, Decathlon, etc.
→ tx_type = `refund`, category = `Refund`

### Category mappings for known merchants
| Pattern | Category |
|---|---|
| Żabka, Lupa, DIA, Fruteria, Frutoseco, Mercadona | Groceries |
| Jak dojadę, Uber, Bolt, Renfe, Alsa, WTP, Petroprix, VINCI | Transport |
| Wodny Park, WEST Bouldering, Funpark Digiloo, Makak, Murall, Gimnasio | Sports & Entertainment |
| Wizz Air, Hrs | Travel |
| Orange Flex, T-Mobile | Telecom |
| Vultr, Google Play | Subscriptions |
| Temu, eBay, furgonetka, Rozetka, HSNstore, ECOBI, Packlink | Shopping |
| Aplazame | Installments |
| Farmacia Castros, Dr.Max, LUX MED | Health |
| Binance | Investment |
| Cash withdrawal* | Cash |

---

## Monthly Workflow (Vaultkeeper)

1. **1st of month**: Remind user to export Revolut CSV for previous month
2. **When CSV arrives** (via Matrix or filesystem):
   a. Run import (Procedure 1)
   b. Check for unclassified (`category = 'Other'`) — reclassify obvious ones (Procedure 4)
   c. Report any unknowns to user for manual classification
3. **3rd of month**: Generate full cycle report for cycle N-2 (Procedure 2)
4. **Every Monday at 08:30**: Budget pulse check (Procedure 3)
5. **On user request**: Any query, reclassification, or report
