"""Finance Transaction Tagger — Flask + htmx web UI for Vaultkeeper DB."""

import os
import json
import sqlite3
import functools
from datetime import datetime, timezone
from flask import Flask, request, render_template, jsonify, g, session, redirect, url_for

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", os.urandom(32).hex())

DB_PATH = os.environ.get("DB_PATH", "/data/vaultkeeper.db")
FINANCE_USER = os.environ.get("FINANCE_USER", "")
FINANCE_PASSWORD = os.environ.get("FINANCE_PASSWORD", "")

# Classification constants
VALID_TX_TYPES = [
    "expense", "income", "exchange", "internal_transfer",
    "top_up", "investment", "refund", "unknown",
]

CATEGORY_MAP = {
    "Essential": ["Groceries", "Transport", "Rent", "Subscriptions", "Telecom", "Health", "Sports", "Pets"],
    "Discretionary": ["Shopping", "Dining", "Entertainment", "Travel", "Investments", "Installments", "Cash", "Revolut Misc", "Other"],
    "Salary": ["Salary"],
    "Other": ["Family", "Sales", "Other Income"],
    "Crypto": ["Crypto"],
    "Stocks": ["Stocks"],
    "Internal": ["Savings", "Partner/Shared"],
    "Exchange": ["Savings", "Exchange"],
    "Refund": ["Refund"],
    "Top-up": ["Savings"],
}

# Flat list of all categories and groups
ALL_CATEGORIES = sorted(set(c for cats in CATEGORY_MAP.values() for c in cats))
ALL_CATEGORY_GROUPS = sorted(CATEGORY_MAP.keys())

ROWS_PER_PAGE = 50

# SQL fragment for effective (override-aware) values (t. prefix for JOIN queries)
EFF_COLUMNS = """,
    t.override_tx_type, t.override_category_group, t.override_category, t.overrides_disabled,
    CASE WHEN t.overrides_disabled = 0 AND t.override_tx_type IS NOT NULL
         THEN t.override_tx_type ELSE t.tx_type END AS eff_tx_type,
    CASE WHEN t.overrides_disabled = 0 AND t.override_category_group IS NOT NULL
         THEN t.override_category_group ELSE t.category_group END AS eff_category_group,
    CASE WHEN t.overrides_disabled = 0 AND t.override_category IS NOT NULL
         THEN t.override_category ELSE t.category END AS eff_category"""

ENR_COLUMNS = """,
    e.id AS enr_id, e.recipient_name, e.merchant_name, e.merchant_city,
    e.merchant_country, e.user_comment, e.revolut_tag, e.localised_description"""

TX_JOIN = "FROM transactions t LEFT JOIN transaction_enrichment e ON e.transaction_id = t.id"


def get_db():
    """Get a database connection for the current request."""
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.execute("PRAGMA journal_mode=WAL")
        g.db.execute("PRAGMA busy_timeout=5000")
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(exception):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def ensure_override_columns():
    """Add override columns to transactions table if missing."""
    db = get_db()
    existing = {row[1] for row in db.execute("PRAGMA table_info(transactions)").fetchall()}
    for col in ("override_tx_type", "override_category_group", "override_category"):
        if col not in existing:
            db.execute(f"ALTER TABLE transactions ADD COLUMN {col} TEXT DEFAULT NULL")
    if "overrides_disabled" not in existing:
        db.execute("ALTER TABLE transactions ADD COLUMN overrides_disabled INTEGER DEFAULT 0")
    db.commit()


def ensure_category_rules_table():
    """Create category_rules table if it doesn't exist."""
    db = get_db()
    db.execute("""
        CREATE TABLE IF NOT EXISTS category_rules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            match_field TEXT NOT NULL DEFAULT 'description',
            match_pattern TEXT NOT NULL,
            match_type TEXT NOT NULL DEFAULT 'like',
            set_tx_type TEXT,
            set_category TEXT,
            set_category_group TEXT,
            priority INTEGER NOT NULL DEFAULT 100,
            enabled INTEGER NOT NULL DEFAULT 1,
            note TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
    """)
    db.commit()


def ensure_enrichment_table():
    """Create transaction_enrichment table if it doesn't exist."""
    db = get_db()
    db.execute("""
        CREATE TABLE IF NOT EXISTS transaction_enrichment (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transaction_id INTEGER REFERENCES transactions(id) ON DELETE SET NULL,
            revolut_id TEXT,
            revolut_leg_id TEXT,
            recipient_name TEXT,
            merchant_name TEXT,
            merchant_city TEXT,
            merchant_country TEXT,
            merchant_address TEXT,
            merchant_mcc TEXT,
            user_comment TEXT,
            revolut_type TEXT,
            revolut_tag TEXT,
            revolut_category TEXT,
            exchange_rate REAL,
            balance_after INTEGER,
            localised_description TEXT,
            source_date TEXT,
            source_amount REAL,
            source_currency TEXT,
            source_description TEXT,
            match_confidence TEXT DEFAULT 'none',
            raw_json TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            UNIQUE(revolut_id, revolut_leg_id)
        )
    """)
    db.execute("CREATE INDEX IF NOT EXISTS idx_enr_tx_id ON transaction_enrichment(transaction_id)")
    db.execute("CREATE INDEX IF NOT EXISTS idx_enr_revolut_id ON transaction_enrichment(revolut_id)")
    # Index on transactions table for faster enrichment matching lookups
    db.execute("CREATE INDEX IF NOT EXISTS idx_tx_date_currency_amount ON transactions(date, currency, amount)")
    db.commit()


def login_required(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        if not session.get("authenticated"):
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return wrapper


# --- Auth routes ---

@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        if (request.form.get("username") == FINANCE_USER and
                request.form.get("password") == FINANCE_PASSWORD and
                FINANCE_USER):
            session["authenticated"] = True
            return redirect(url_for("index"))
        error = "Invalid credentials"
    return render_template("login.html", error=error)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


# --- Health check ---

@app.route("/health")
def health():
    try:
        db = get_db()
        db.execute("SELECT 1").fetchone()
        return jsonify({"status": "ok"}), 200
    except Exception as e:
        return jsonify({"status": "error", "detail": str(e)}), 500


# --- Main page ---

@app.route("/")
@login_required
def index():
    return render_template("index.html",
                           tx_types=VALID_TX_TYPES,
                           category_groups=ALL_CATEGORY_GROUPS,
                           categories=ALL_CATEGORIES,
                           category_map=CATEGORY_MAP)


# --- Transaction list (htmx partial) ---

@app.route("/transactions")
@login_required
def transactions():
    db = get_db()
    ensure_override_columns()
    ensure_enrichment_table()
    page = max(1, request.args.get("page", 1, type=int))
    offset = (page - 1) * ROWS_PER_PAGE

    # Effective-value expressions for filters (t. prefix for aliased queries)
    eff_tx_type = "(CASE WHEN t.overrides_disabled=0 AND t.override_tx_type IS NOT NULL THEN t.override_tx_type ELSE t.tx_type END)"
    eff_cat_group = "(CASE WHEN t.overrides_disabled=0 AND t.override_category_group IS NOT NULL THEN t.override_category_group ELSE t.category_group END)"
    eff_cat = "(CASE WHEN t.overrides_disabled=0 AND t.override_category IS NOT NULL THEN t.override_category ELSE t.category END)"

    # Build filters
    conditions = []
    params = []

    date_from = request.args.get("date_from", "").strip()
    date_to = request.args.get("date_to", "").strip()
    tx_type = request.args.get("tx_type", "").strip()
    category_group = request.args.get("category_group", "").strip()
    search = request.args.get("search", "").strip()
    unclassified = request.args.get("unclassified", "").strip()

    if date_from:
        conditions.append("t.date >= ?")
        params.append(date_from)
    if date_to:
        conditions.append("t.date <= ?")
        params.append(date_to)
    if tx_type:
        conditions.append(f"{eff_tx_type} = ?")
        params.append(tx_type)
    if category_group:
        conditions.append(f"{eff_cat_group} = ?")
        params.append(category_group)
    if search:
        conditions.append("(t.description LIKE ? OR t.raw_description LIKE ?)")
        params.extend([f"%{search}%", f"%{search}%"])
    if unclassified == "1":
        conditions.append(f"({eff_cat} IN ('Revolut Misc', 'Other') OR {eff_cat} IS NULL OR {eff_tx_type} = 'unknown')")

    where = " AND ".join(conditions) if conditions else "1=1"

    # Count
    count = db.execute(f"SELECT COUNT(*) FROM transactions t WHERE {where}", params).fetchone()[0]
    total_pages = max(1, (count + ROWS_PER_PAGE - 1) // ROWS_PER_PAGE)
    page = min(page, total_pages)

    # Fetch rows with enrichment LEFT JOIN
    rows = db.execute(
        f"SELECT t.id, t.date, t.description, t.amount, t.currency, t.tx_type, t.category_group, t.category "
        f"{EFF_COLUMNS} {ENR_COLUMNS} "
        f"{TX_JOIN} WHERE {where} ORDER BY t.date DESC, t.id DESC LIMIT ? OFFSET ?",
        params + [ROWS_PER_PAGE, offset]
    ).fetchall()

    # Build filter query string for pagination links
    filter_params = []
    if date_from:
        filter_params.append(f"date_from={date_from}")
    if date_to:
        filter_params.append(f"date_to={date_to}")
    if tx_type:
        filter_params.append(f"tx_type={tx_type}")
    if category_group:
        filter_params.append(f"category_group={category_group}")
    if search:
        filter_params.append(f"search={search}")
    if unclassified == "1":
        filter_params.append("unclassified=1")
    filter_qs = "&".join(filter_params)

    return render_template("_transactions.html",
                           rows=rows,
                           page=page,
                           total_pages=total_pages,
                           count=count,
                           filter_qs=filter_qs,
                           tx_types=VALID_TX_TYPES,
                           category_groups=ALL_CATEGORY_GROUPS,
                           categories=ALL_CATEGORIES,
                           category_map=CATEGORY_MAP)


# --- Update a single transaction field ---

@app.route("/transactions/<int:tx_id>", methods=["PUT"])
@login_required
def update_transaction(tx_id):
    db = get_db()
    ensure_override_columns()
    data = request.form

    updates = []
    params = []

    for field in ("tx_type", "category", "category_group"):
        val = data.get(field)
        if val is not None:
            if field == "tx_type" and val not in VALID_TX_TYPES:
                return jsonify({"error": f"Invalid tx_type: {val}"}), 400
            if field == "category_group" and val not in ALL_CATEGORY_GROUPS:
                return jsonify({"error": f"Invalid category_group: {val}"}), 400
            if field == "category" and val not in ALL_CATEGORIES:
                return jsonify({"error": f"Invalid category: {val}"}), 400
            updates.append(f"override_{field} = ?")
            params.append(val)

    if not updates:
        return jsonify({"error": "No fields to update"}), 400

    updates.append("overrides_disabled = 0")
    params.append(tx_id)
    db.execute(f"UPDATE transactions SET {', '.join(updates)} WHERE id = ?", params)
    db.commit()

    row = _fetch_tx_row(db, tx_id)
    if not row:
        return jsonify({"error": "Transaction not found"}), 404

    return render_template("_transaction_row.html",
                           row=row,
                           tx_types=VALID_TX_TYPES,
                           category_groups=ALL_CATEGORY_GROUPS,
                           categories=ALL_CATEGORIES,
                           category_map=CATEGORY_MAP,
                           flash="success")


def _fetch_tx_row(db, tx_id):
    """Fetch a single transaction row with override + effective + enrichment columns."""
    ensure_enrichment_table()
    return db.execute(
        f"SELECT t.id, t.date, t.description, t.amount, t.currency, t.tx_type, t.category_group, t.category "
        f"{EFF_COLUMNS} {ENR_COLUMNS} {TX_JOIN} WHERE t.id = ?", (tx_id,)
    ).fetchone()


def _render_tx_row(row, flash=None):
    """Render a single transaction row partial."""
    return render_template("_transaction_row.html",
                           row=row,
                           tx_types=VALID_TX_TYPES,
                           category_groups=ALL_CATEGORY_GROUPS,
                           categories=ALL_CATEGORIES,
                           category_map=CATEGORY_MAP,
                           flash=flash)


# --- Override endpoints ---

@app.route("/transactions/<int:tx_id>/override/toggle", methods=["POST"])
@login_required
def toggle_override(tx_id):
    db = get_db()
    ensure_override_columns()
    db.execute(
        "UPDATE transactions SET overrides_disabled = 1 - overrides_disabled WHERE id = ?",
        (tx_id,)
    )
    db.commit()
    row = _fetch_tx_row(db, tx_id)
    if not row:
        return jsonify({"error": "Transaction not found"}), 404
    return _render_tx_row(row, flash="success")


@app.route("/transactions/<int:tx_id>/override", methods=["DELETE"])
@login_required
def delete_override(tx_id):
    db = get_db()
    ensure_override_columns()
    db.execute(
        "UPDATE transactions SET override_tx_type = NULL, override_category_group = NULL, "
        "override_category = NULL, overrides_disabled = 0 WHERE id = ?",
        (tx_id,)
    )
    db.commit()
    row = _fetch_tx_row(db, tx_id)
    if not row:
        return jsonify({"error": "Transaction not found"}), 404
    return _render_tx_row(row, flash="success")


# --- Rules CRUD ---

@app.route("/rules")
@login_required
def rules():
    db = get_db()
    ensure_category_rules_table()
    rows = db.execute("SELECT * FROM category_rules ORDER BY priority ASC, id ASC").fetchall()
    return render_template("_rules.html",
                           rules=rows,
                           tx_types=VALID_TX_TYPES,
                           category_groups=ALL_CATEGORY_GROUPS,
                           categories=ALL_CATEGORIES)


@app.route("/rules", methods=["POST"])
@login_required
def create_rule():
    db = get_db()
    ensure_category_rules_table()

    match_field = request.form.get("match_field", "description")
    match_pattern = request.form.get("match_pattern", "").strip()
    match_type = request.form.get("match_type", "like")
    set_tx_type = request.form.get("set_tx_type", "").strip() or None
    set_category = request.form.get("set_category", "").strip() or None
    set_category_group = request.form.get("set_category_group", "").strip() or None
    priority = request.form.get("priority", 100, type=int)
    note = request.form.get("note", "").strip() or None

    if not match_pattern:
        return "<tr><td colspan='9' class='error'>Pattern is required</td></tr>", 400

    db.execute(
        """INSERT INTO category_rules
           (match_field, match_pattern, match_type, set_tx_type, set_category, set_category_group, priority, note)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (match_field, match_pattern, match_type, set_tx_type, set_category, set_category_group, priority, note)
    )
    db.commit()

    # If created from matching-rules panel, refresh that panel instead
    refresh_tx = request.form.get("_refresh_matching", "").strip()
    if refresh_tx:
        return redirect(url_for("matching_rules", tx_id=int(refresh_tx)), code=303)

    rows = db.execute("SELECT * FROM category_rules ORDER BY priority ASC, id ASC").fetchall()
    return render_template("_rules.html",
                           rules=rows,
                           tx_types=VALID_TX_TYPES,
                           category_groups=ALL_CATEGORY_GROUPS,
                           categories=ALL_CATEGORIES)


@app.route("/rules/<int:rule_id>/toggle", methods=["PUT"])
@login_required
def toggle_rule(rule_id):
    db = get_db()
    db.execute(
        "UPDATE category_rules SET enabled = 1 - enabled, updated_at = datetime('now') WHERE id = ?",
        (rule_id,)
    )
    db.commit()

    rows = db.execute("SELECT * FROM category_rules ORDER BY priority ASC, id ASC").fetchall()
    return render_template("_rules.html",
                           rules=rows,
                           tx_types=VALID_TX_TYPES,
                           category_groups=ALL_CATEGORY_GROUPS,
                           categories=ALL_CATEGORIES)


@app.route("/rules/<int:rule_id>", methods=["PUT"])
@login_required
def update_rule(rule_id):
    db = get_db()
    ensure_category_rules_table()

    match_field = request.form.get("match_field", "description")
    match_pattern = request.form.get("match_pattern", "").strip()
    match_type = request.form.get("match_type", "like")
    set_tx_type = request.form.get("set_tx_type", "").strip() or None
    set_category = request.form.get("set_category", "").strip() or None
    set_category_group = request.form.get("set_category_group", "").strip() or None
    priority = request.form.get("priority", 100, type=int)
    note = request.form.get("note", "").strip() or None

    if not match_pattern:
        return "<tr><td colspan='11' class='error'>Pattern is required</td></tr>", 400

    db.execute(
        """UPDATE category_rules
           SET match_field=?, match_pattern=?, match_type=?, set_tx_type=?,
               set_category=?, set_category_group=?, priority=?, note=?,
               updated_at=datetime('now')
           WHERE id=?""",
        (match_field, match_pattern, match_type, set_tx_type,
         set_category, set_category_group, priority, note, rule_id)
    )
    db.commit()

    rows = db.execute("SELECT * FROM category_rules ORDER BY priority ASC, id ASC").fetchall()
    return render_template("_rules.html",
                           rules=rows,
                           tx_types=VALID_TX_TYPES,
                           category_groups=ALL_CATEGORY_GROUPS,
                           categories=ALL_CATEGORIES)


@app.route("/rules/<int:rule_id>", methods=["DELETE"])
@login_required
def delete_rule(rule_id):
    db = get_db()
    db.execute("DELETE FROM category_rules WHERE id = ?", (rule_id,))
    db.commit()

    rows = db.execute("SELECT * FROM category_rules ORDER BY priority ASC, id ASC").fetchall()
    return render_template("_rules.html",
                           rules=rows,
                           tx_types=VALID_TX_TYPES,
                           category_groups=ALL_CATEGORY_GROUPS,
                           categories=ALL_CATEGORIES)


# --- Transaction matching rules ---

@app.route("/transactions/<int:tx_id>/matching-rules")
@login_required
def matching_rules(tx_id):
    db = get_db()
    ensure_category_rules_table()

    ensure_override_columns()
    tx = db.execute(
        "SELECT t.id, t.description, t.raw_description, t.raw_category "
        f"{EFF_COLUMNS} FROM transactions t WHERE t.id = ?",
        (tx_id,)
    ).fetchone()
    if not tx:
        return "<p class='error'>Transaction not found</p>", 404

    rules = db.execute(
        "SELECT * FROM category_rules WHERE enabled = 1 ORDER BY priority ASC, id ASC"
    ).fetchall()

    matching = []
    for rule in rules:
        field_val = tx[rule["match_field"]] or ""
        pattern = rule["match_pattern"]
        if rule["match_type"] == "like":
            hit = db.execute("SELECT ? LIKE ?", (field_val, pattern)).fetchone()[0]
        else:
            hit = (field_val == pattern)
        if hit:
            matching.append(rule)

    return render_template("_matching_rules.html",
                           tx=tx,
                           matching=matching,
                           tx_types=VALID_TX_TYPES,
                           category_groups=ALL_CATEGORY_GROUPS,
                           categories=ALL_CATEGORIES)


# --- Apply all rules ---

@app.route("/rules/apply", methods=["POST"])
@login_required
def apply_rules():
    db = get_db()
    ensure_category_rules_table()
    ensure_override_columns()

    rules = db.execute("""
        SELECT id, match_field, match_pattern, match_type,
               set_tx_type, set_category, set_category_group, note
        FROM category_rules WHERE enabled = 1 ORDER BY priority ASC
    """).fetchall()

    total_affected = 0
    details = []

    for rule in rules:
        rid = rule["id"]
        field = rule["match_field"]
        pattern = rule["match_pattern"]
        mtype = rule["match_type"]
        st = rule["set_tx_type"]
        sc = rule["set_category"]
        sg = rule["set_category_group"]
        note = rule["note"]

        op = "LIKE" if mtype == "like" else "="
        rule_cnt = 0

        for col, val in [("tx_type", st), ("category", sc), ("category_group", sg)]:
            if not val:
                continue
            sql = (f"UPDATE transactions SET {col} = ? "
                   f"WHERE {field} {op} ? "
                   f"AND (override_{col} IS NULL OR overrides_disabled = 1)")
            cnt = db.execute(sql, (val, pattern)).rowcount
            rule_cnt += cnt

        if rule_cnt > 0:
            total_affected += rule_cnt
            details.append(f"Rule {rid}: {rule_cnt} field-updates ({note or pattern})")

    db.commit()

    result_html = f"<div class='apply-result success'>Applied {len(rules)} rules — {total_affected} rows updated</div>"
    if details:
        result_html += "<ul class='apply-details'>"
        for d in details:
            result_html += f"<li>{d}</li>"
        result_html += "</ul>"

    return result_html


# --- Enrichment helpers ---

def _parse_revolut_transaction(obj):
    """Parse a Revolut API transaction object into enrichment fields."""
    revolut_id = obj.get("id", "")
    revolut_leg_id = obj.get("legId", "")

    # Date from epoch ms
    started_date = obj.get("startedDate") or obj.get("createdDate")
    if started_date:
        dt = datetime.fromtimestamp(started_date / 1000, tz=timezone.utc)
        source_date = dt.strftime("%Y-%m-%d")
    else:
        source_date = None

    # Amount in cents → decimal
    amount_cents = obj.get("amount", 0)
    source_amount = amount_cents / 100.0
    source_currency = obj.get("currency", "")

    revolut_type = obj.get("type", "")

    # Merchant info
    merchant = obj.get("merchant") or {}
    merchant_name = merchant.get("name")
    merchant_city = merchant.get("city")
    merchant_country = merchant.get("country")
    merchant_address = merchant.get("address")
    merchant_mcc = merchant.get("mcc")

    source_description = obj.get("description", "")

    # Extract recipient from description for transfers
    recipient_name = None
    if revolut_type == "TRANSFER" and source_description:
        for prefix in ("To ", "From "):
            if source_description.startswith(prefix):
                name = source_description[len(prefix):]
                # Skip pocket/savings transfers like "To PLN", "To pocket PLN ..."
                if not any(name.startswith(c) for c in ("PLN", "EUR", "USD", "GBP", "BTC", "ETH", "XRP", "DOT", "pocket")):
                    recipient_name = name
                break

    # Localised description
    loc_desc_obj = obj.get("localisedDescription") or {}
    if isinstance(loc_desc_obj, dict):
        loc_params = loc_desc_obj.get("params") or []
        if loc_params:
            if isinstance(loc_params, list):
                parts = [str(d.get("value", "")) for d in loc_params if isinstance(d, dict) and d.get("value")]
            else:
                parts = [str(v) for v in loc_params.values() if v]
            localised_description = " ".join(parts) if parts else loc_desc_obj.get("key", "")
        else:
            localised_description = loc_desc_obj.get("key", "")
    elif isinstance(loc_desc_obj, str):
        localised_description = loc_desc_obj
    else:
        localised_description = None

    user_comment = obj.get("comment") or obj.get("note")
    revolut_tag = obj.get("tag")
    revolut_category = obj.get("category")
    exchange_rate = obj.get("rate")
    balance_after = obj.get("balance")

    return {
        "revolut_id": revolut_id,
        "revolut_leg_id": revolut_leg_id or "",
        "recipient_name": recipient_name,
        "merchant_name": merchant_name,
        "merchant_city": merchant_city,
        "merchant_country": merchant_country,
        "merchant_address": merchant_address,
        "merchant_mcc": merchant_mcc,
        "user_comment": user_comment,
        "revolut_type": revolut_type,
        "revolut_tag": revolut_tag,
        "revolut_category": revolut_category,
        "exchange_rate": exchange_rate,
        "balance_after": balance_after,
        "localised_description": localised_description,
        "source_date": source_date,
        "source_amount": source_amount,
        "source_currency": source_currency,
        "source_description": source_description,
        "raw_json": json.dumps(obj),
    }


def _try_match(db, date, amount, currency, desc, date_range, amount_tol, suffix):
    """Try to match a single enrichment record within the given date/amount window.

    Returns (transaction_id, confidence) tuple.
    """
    abs_amount = abs(amount)

    if date_range == 0:
        date_clause = "date = ?"
        date_params = [date]
    else:
        date_clause = "date BETWEEN date(?, ?) AND date(?, ?)"
        date_params = [date, f"-{date_range} days", date, f"+{date_range} days"]

    rows = db.execute(
        f"SELECT id, description FROM transactions "
        f"WHERE {date_clause} AND ABS(amount) BETWEEN ? AND ? AND currency = ?",
        (*date_params, abs_amount - amount_tol, abs_amount + amount_tol, currency)
    ).fetchall()

    if not rows:
        return None, "none"

    # Tier 1 — Exact: description substring match
    if desc:
        for row in rows:
            tx_desc = (row["description"] or "").lower()
            src_desc = desc.lower()
            if src_desc in tx_desc or tx_desc in src_desc:
                return row["id"], f"exact{suffix}"

    # Tier 2 — Fuzzy: word overlap ≥ 2
    if desc:
        for row in rows:
            tx_words = set((row["description"] or "").lower().split())
            src_words = set(desc.lower().split())
            if len(tx_words & src_words) >= 2:
                return row["id"], f"fuzzy{suffix}"

    # Tier 3 — Loose: single candidate
    if len(rows) == 1:
        return rows[0]["id"], f"loose{suffix}"

    return None, "none"


def _match_enrichment_to_transaction(db, enrichment):
    """Match an enrichment record to an existing transaction.

    Returns (transaction_id, confidence) tuple.
    Uses multi-pass matching with progressively wider date/amount windows:
      Pass 1: exact date, ±0.005 amount
      Pass 2: ±1 day, ±0.02 amount (settlement date offset)
      Pass 3: ±2 days, ±0.02 amount (weekend/holiday delays)
    """
    date = enrichment["source_date"]
    amount = enrichment["source_amount"]
    currency = enrichment["source_currency"]
    desc = enrichment["source_description"] or ""

    if not date or amount is None:
        return None, "none"

    # Pass 1: exact date, tight tolerance
    result = _try_match(db, date, amount, currency, desc, date_range=0, amount_tol=0.005, suffix="")
    if result[0]:
        return result

    # Pass 2: ±1 day, wider tolerance (Revolut UTC vs bank settlement date)
    result = _try_match(db, date, amount, currency, desc, date_range=1, amount_tol=0.02, suffix="_fuzzydate")
    if result[0]:
        return result

    # Pass 3: ±2 days (weekend/holiday settlement delays)
    return _try_match(db, date, amount, currency, desc, date_range=2, amount_tol=0.02, suffix="_extdate")


# --- Enrichment routes ---

@app.route("/enrichment")
@login_required
def enrichment():
    db = get_db()
    ensure_enrichment_table()

    total = db.execute("SELECT COUNT(*) FROM transaction_enrichment").fetchone()[0]
    matched = db.execute(
        "SELECT COUNT(*) FROM transaction_enrichment WHERE transaction_id IS NOT NULL"
    ).fetchone()[0]
    unmatched_rows = db.execute(
        "SELECT * FROM transaction_enrichment WHERE transaction_id IS NULL "
        "ORDER BY source_date DESC"
    ).fetchall()

    return render_template("_enrichment.html",
                           total=total,
                           matched=matched,
                           unmatched=unmatched_rows)


@app.route("/enrichment/upload", methods=["POST"])
@login_required
def upload_enrichment():
    db = get_db()
    ensure_enrichment_table()

    file = request.files.get("file")
    if not file:
        return "<div class='apply-result' style='border:1px solid var(--danger);color:var(--danger)'>No file uploaded</div>", 400

    try:
        data = json.loads(file.read())
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        return f"<div class='apply-result' style='border:1px solid var(--danger);color:var(--danger)'>Invalid JSON: {e}</div>", 400

    if not isinstance(data, list):
        return "<div class='apply-result' style='border:1px solid var(--danger);color:var(--danger)'>Expected a JSON array</div>", 400

    stats = {"imported": 0, "skipped": 0, "matched": 0, "errors": 0}

    for obj in data:
        try:
            enrichment_data = _parse_revolut_transaction(obj)

            # Skip if already exists
            existing = db.execute(
                "SELECT id FROM transaction_enrichment WHERE revolut_id = ? AND revolut_leg_id = ?",
                (enrichment_data["revolut_id"], enrichment_data["revolut_leg_id"])
            ).fetchone()

            if existing:
                stats["skipped"] += 1
                continue

            tx_id, confidence = _match_enrichment_to_transaction(db, enrichment_data)

            db.execute("""
                INSERT INTO transaction_enrichment (
                    transaction_id, revolut_id, revolut_leg_id,
                    recipient_name, merchant_name, merchant_city, merchant_country,
                    merchant_address, merchant_mcc, user_comment, revolut_type,
                    revolut_tag, revolut_category, exchange_rate, balance_after,
                    localised_description, source_date, source_amount, source_currency,
                    source_description, match_confidence, raw_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                tx_id, enrichment_data["revolut_id"], enrichment_data["revolut_leg_id"],
                enrichment_data["recipient_name"], enrichment_data["merchant_name"],
                enrichment_data["merchant_city"], enrichment_data["merchant_country"],
                enrichment_data["merchant_address"], enrichment_data["merchant_mcc"],
                enrichment_data["user_comment"], enrichment_data["revolut_type"],
                enrichment_data["revolut_tag"], enrichment_data["revolut_category"],
                enrichment_data["exchange_rate"], enrichment_data["balance_after"],
                enrichment_data["localised_description"], enrichment_data["source_date"],
                enrichment_data["source_amount"], enrichment_data["source_currency"],
                enrichment_data["source_description"], confidence, enrichment_data["raw_json"]
            ))

            stats["imported"] += 1
            if tx_id:
                stats["matched"] += 1
        except Exception:
            stats["errors"] += 1

    db.commit()

    return (
        f"<div class='apply-result success'>"
        f"Imported: {stats['imported']} | Matched: {stats['matched']} | "
        f"Skipped (duplicates): {stats['skipped']} | Errors: {stats['errors']}"
        f"</div>"
    )


@app.route("/enrichment/<int:enr_id>/link", methods=["POST"])
@login_required
def link_enrichment(enr_id):
    db = get_db()
    ensure_enrichment_table()

    tx_id = request.form.get("tx_id", type=int)
    if not tx_id:
        return "<div class='error'>Transaction ID is required</div>", 400

    # Verify transaction exists
    tx = db.execute("SELECT id FROM transactions WHERE id = ?", (tx_id,)).fetchone()
    if not tx:
        return f"<div class='error'>Transaction {tx_id} not found</div>", 404

    db.execute(
        "UPDATE transaction_enrichment SET transaction_id = ?, match_confidence = 'manual' WHERE id = ?",
        (tx_id, enr_id)
    )
    db.commit()

    # Re-render enrichment tab
    return redirect(url_for("enrichment"), code=303)


@app.route("/enrichment/<int:enr_id>", methods=["DELETE"])
@login_required
def delete_enrichment(enr_id):
    db = get_db()
    ensure_enrichment_table()
    db.execute("DELETE FROM transaction_enrichment WHERE id = ?", (enr_id,))
    db.commit()
    return redirect(url_for("enrichment"), code=303)


@app.route("/enrichment/rematch", methods=["POST"])
@login_required
def rematch_enrichment():
    db = get_db()
    ensure_enrichment_table()

    unmatched = db.execute(
        "SELECT * FROM transaction_enrichment WHERE transaction_id IS NULL"
    ).fetchall()

    matched_count = 0
    for row in unmatched:
        enrichment_data = {
            "source_date": row["source_date"],
            "source_amount": row["source_amount"],
            "source_currency": row["source_currency"],
            "source_description": row["source_description"],
        }
        tx_id, confidence = _match_enrichment_to_transaction(db, enrichment_data)
        if tx_id:
            db.execute(
                "UPDATE transaction_enrichment SET transaction_id = ?, match_confidence = ? WHERE id = ?",
                (tx_id, confidence, row["id"])
            )
            matched_count += 1

    db.commit()

    return (
        f"<div class='apply-result success'>"
        f"Re-matched {matched_count} of {len(unmatched)} unlinked records"
        f"</div>"
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8190, debug=True)
