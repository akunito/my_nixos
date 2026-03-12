"""Finance Transaction Tagger — Flask + htmx web UI for Vaultkeeper DB."""

import os
import sqlite3
import functools
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
    page = max(1, request.args.get("page", 1, type=int))
    offset = (page - 1) * ROWS_PER_PAGE

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
        conditions.append("date >= ?")
        params.append(date_from)
    if date_to:
        conditions.append("date <= ?")
        params.append(date_to)
    if tx_type:
        conditions.append("tx_type = ?")
        params.append(tx_type)
    if category_group:
        conditions.append("category_group = ?")
        params.append(category_group)
    if search:
        conditions.append("(description LIKE ? OR raw_description LIKE ?)")
        params.extend([f"%{search}%", f"%{search}%"])
    if unclassified == "1":
        conditions.append("(category IN ('Revolut Misc', 'Other') OR category IS NULL OR tx_type = 'unknown')")

    where = " AND ".join(conditions) if conditions else "1=1"

    # Count
    count = db.execute(f"SELECT COUNT(*) FROM transactions WHERE {where}", params).fetchone()[0]
    total_pages = max(1, (count + ROWS_PER_PAGE - 1) // ROWS_PER_PAGE)
    page = min(page, total_pages)

    # Fetch rows
    rows = db.execute(
        f"SELECT id, date, description, amount, currency, tx_type, category_group, category "
        f"FROM transactions WHERE {where} ORDER BY date DESC, id DESC LIMIT ? OFFSET ?",
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
            updates.append(f"{field} = ?")
            params.append(val)

    if not updates:
        return jsonify({"error": "No fields to update"}), 400

    params.append(tx_id)
    db.execute(f"UPDATE transactions SET {', '.join(updates)} WHERE id = ?", params)
    db.commit()

    # Return the updated row for htmx swap
    row = db.execute(
        "SELECT id, date, description, amount, currency, tx_type, category_group, category "
        "FROM transactions WHERE id = ?", (tx_id,)
    ).fetchone()

    if not row:
        return jsonify({"error": "Transaction not found"}), 404

    return render_template("_transaction_row.html",
                           row=row,
                           tx_types=VALID_TX_TYPES,
                           category_groups=ALL_CATEGORY_GROUPS,
                           categories=ALL_CATEGORIES,
                           category_map=CATEGORY_MAP,
                           flash="success")


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


# --- Apply all rules ---

@app.route("/rules/apply", methods=["POST"])
@login_required
def apply_rules():
    db = get_db()
    ensure_category_rules_table()

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

        sets = []
        vals = []
        if st:
            sets.append("tx_type=?")
            vals.append(st)
        if sc:
            sets.append("category=?")
            vals.append(sc)
        if sg:
            sets.append("category_group=?")
            vals.append(sg)
        if not sets:
            continue

        op = "LIKE" if mtype == "like" else "="
        sql = f"UPDATE transactions SET {','.join(sets)} WHERE {field} {op} ?"
        vals.append(pattern)
        cnt = db.execute(sql, vals).rowcount
        if cnt > 0:
            total_affected += cnt
            details.append(f"Rule {rid}: {cnt} rows ({note or pattern})")

    db.commit()

    result_html = f"<div class='apply-result success'>Applied {len(rules)} rules — {total_affected} rows updated</div>"
    if details:
        result_html += "<ul class='apply-details'>"
        for d in details:
            result_html += f"<li>{d}</li>"
        result_html += "</ul>"

    return result_html


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8190, debug=True)
