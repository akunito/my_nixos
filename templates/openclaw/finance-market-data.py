#!/usr/bin/env python3
"""
Finance Market Data Service for OpenClaw/Vaultkeeper.

Host-side script that fetches exchange rates and asset prices,
writing directly to vaultkeeper.db. No LLM involvement.

Usage:
  finance-market-data.py [--mode MODE] [--backfill START END] [--db PATH]

Modes:
  fiat      Fetch ECB monthly average rates for previous month
  daily     Fetch crypto prices (and stocks when configured)
  csv       Process CoinGecko portfolio CSV files from finance-imports/
  all       Run fiat + daily + csv (default)

Backfill:
  --backfill 2024-01 2026-02   Fetch ECB rates for a range of months
"""

import argparse
import csv
import hashlib
import json
import logging
import os
import sqlite3
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, date, timedelta
from pathlib import Path

try:
    import requests
except ImportError:
    print("ERROR: 'requests' package required. Install via nix or pip.", file=sys.stderr)
    sys.exit(1)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("finance-market-data")

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DEFAULT_DB = os.path.expanduser("~/.openclaw/finance-data/vaultkeeper.db")
DEFAULT_IMPORTS = os.path.expanduser("~/.openclaw/finance-imports")

ECB_ENDPOINT = "https://data-api.ecb.europa.eu/service/data/EXR"
COINGECKO_API = "https://api.coingecko.com/api/v3"

# Sanity-check bounds for rates (fallback when no history exists)
RATE_BOUNDS = {
    ("EUR", "PLN"): (3.5, 5.5),
    ("GBP", "PLN"): (4.5, 7.0),
    ("USD", "PLN"): (3.0, 5.0),
}

# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------

def get_db(db_path: str) -> sqlite3.Connection:
    """Open DB with WAL mode and create tables if missing."""
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    _ensure_tables(conn)
    return conn


def _ensure_tables(conn: sqlite3.Connection):
    """Create tables used by this script if they don't exist."""
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS exchange_rates (
            month TEXT NOT NULL,
            from_currency TEXT NOT NULL,
            to_currency TEXT NOT NULL,
            rate REAL NOT NULL,
            source TEXT NOT NULL,
            PRIMARY KEY (month, from_currency, to_currency)
        );

        CREATE TABLE IF NOT EXISTS asset_prices (
            date TEXT NOT NULL,
            asset_type TEXT NOT NULL,
            symbol TEXT NOT NULL,
            price_base REAL NOT NULL,
            source TEXT NOT NULL,
            PRIMARY KEY (date, asset_type, symbol)
        );

        CREATE TABLE IF NOT EXISTS holdings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            asset_type TEXT NOT NULL,
            symbol TEXT NOT NULL,
            quantity REAL NOT NULL,
            avg_buy_price REAL,
            source TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE (asset_type, symbol)
        );

        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
        );
    """)
    # Seed default settings if missing
    defaults = {
        "base_currency": "PLN",
        "tracked_crypto": "BTC",
        "tracked_stocks": "",
        "tracked_currencies": "EUR,GBP,USD",
        "coingecko_api_key": "",
    }
    for k, v in defaults.items():
        conn.execute(
            "INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)", (k, v)
        )
    conn.commit()


def get_setting(conn: sqlite3.Connection, key: str, default: str = "") -> str:
    row = conn.execute("SELECT value FROM settings WHERE key = ?", (key,)).fetchone()
    return row[0] if row else default


# ---------------------------------------------------------------------------
# Rate sanity check
# ---------------------------------------------------------------------------

def check_rate_sanity(conn: sqlite3.Connection, month: str, from_cur: str, to_cur: str, rate: float) -> bool:
    """Return True if rate looks plausible. Log warning if not."""
    # Check against previous month
    prev = _prev_month(month)
    row = conn.execute(
        "SELECT rate FROM exchange_rates WHERE month = ? AND from_currency = ? AND to_currency = ?",
        (prev, from_cur, to_cur),
    ).fetchone()
    if row:
        prev_rate = row[0]
        if rate > prev_rate * 2 or rate < prev_rate * 0.5:
            log.warning(
                "Rate %s/%s for %s (%.4f) differs >2x from previous month (%.4f) — flagging",
                from_cur, to_cur, month, rate, prev_rate,
            )
            return False
        return True

    # No history — check static bounds
    pair = (from_cur, to_cur)
    if pair in RATE_BOUNDS:
        lo, hi = RATE_BOUNDS[pair]
        if rate < lo or rate > hi:
            log.warning(
                "Rate %s/%s for %s (%.4f) outside static bounds [%.1f, %.1f] — flagging",
                from_cur, to_cur, month, rate, lo, hi,
            )
            return False
    return True


def _prev_month(month: str) -> str:
    y, m = int(month[:4]), int(month[5:7])
    m -= 1
    if m == 0:
        m = 12
        y -= 1
    return f"{y:04d}-{m:02d}"


# ---------------------------------------------------------------------------
# ECB Fiat Rates
# ---------------------------------------------------------------------------

def fetch_ecb_rates(conn: sqlite3.Connection, month: str):
    """Fetch ECB monthly average rates for the given month and write to DB."""
    base_currency = get_setting(conn, "base_currency", "PLN")
    tracked = [c.strip() for c in get_setting(conn, "tracked_currencies", "EUR,GBP,USD").split(",") if c.strip()]

    y, m = month.split("-")
    start_date = f"{y}-{m}-01"
    # End of month
    if int(m) == 12:
        end_date = f"{int(y)+1}-01-01"
    else:
        end_date = f"{y}-{int(m)+1:02d}-01"

    # ECB publishes EUR-based rates. Fetch EUR/X for each tracked currency.
    # We need EUR/PLN, EUR/GBP, EUR/USD etc.
    currencies_to_fetch = set(tracked)
    if base_currency != "EUR":
        currencies_to_fetch.add(base_currency)
    currencies_to_fetch.discard("EUR")  # ECB doesn't have EUR/EUR

    eur_rates = {}  # currency -> rate (1 EUR = N units of currency)

    for cur in currencies_to_fetch:
        url = f"{ECB_ENDPOINT}/M.{cur}.EUR.SP00.A"
        params = {
            "startPeriod": start_date,
            "endPeriod": end_date,
            "format": "csvdata",
        }
        try:
            resp = requests.get(url, params=params, timeout=30)
            resp.raise_for_status()
        except requests.RequestException as e:
            log.error("ECB fetch failed for EUR/%s month %s: %s", cur, month, e)
            continue

        # Parse CSV response — look for OBS_VALUE column
        lines = resp.text.strip().split("\n")
        if len(lines) < 2:
            log.warning("No ECB data for EUR/%s month %s", cur, month)
            continue

        reader = csv.DictReader(lines)
        values = []
        for row in reader:
            if "OBS_VALUE" in row and row["OBS_VALUE"]:
                try:
                    values.append(float(row["OBS_VALUE"]))
                except ValueError:
                    pass

        if not values:
            log.warning("No rate values for EUR/%s month %s", cur, month)
            continue

        avg_rate = sum(values) / len(values)
        eur_rates[cur] = avg_rate
        log.info("ECB EUR/%s for %s: %.4f (avg of %d observations)", cur, month, avg_rate, len(values))

    # Now compute rates relative to base currency and write to DB
    if base_currency == "EUR":
        # Direct: 1 EUR = N of target. Store as from_currency -> EUR
        for cur, rate in eur_rates.items():
            _write_rate(conn, month, cur, "EUR", 1.0 / rate, "ecb")
    else:
        # base_currency is e.g. PLN
        base_rate = eur_rates.get(base_currency)
        if base_rate is None:
            log.error("Cannot compute rates: no ECB data for EUR/%s in %s", base_currency, month)
            return

        # EUR -> base
        _write_rate(conn, month, "EUR", base_currency, base_rate, "ecb")

        # Other currencies -> base (cross-rate via EUR)
        for cur, eur_to_cur in eur_rates.items():
            if cur == base_currency:
                continue
            # 1 unit of cur = (base_rate / eur_to_cur) units of base
            cross_rate = base_rate / eur_to_cur
            _write_rate(conn, month, cur, base_currency, cross_rate, "ecb")

    conn.commit()


def _write_rate(conn: sqlite3.Connection, month: str, from_cur: str, to_cur: str, rate: float, source: str):
    """Write a rate, respecting precedence: never overwrite manual."""
    existing = conn.execute(
        "SELECT source FROM exchange_rates WHERE month = ? AND from_currency = ? AND to_currency = ?",
        (month, from_cur, to_cur),
    ).fetchone()

    if existing and existing[0] == "manual":
        log.info("Skipping %s/%s for %s — manual override exists", from_cur, to_cur, month)
        return

    check_rate_sanity(conn, month, from_cur, to_cur, rate)

    conn.execute(
        "INSERT OR REPLACE INTO exchange_rates (month, from_currency, to_currency, rate, source) VALUES (?, ?, ?, ?, ?)",
        (month, from_cur, to_cur, rate, source),
    )
    log.info("Wrote rate %s/%s for %s: %.4f (source=%s)", from_cur, to_cur, month, rate, source)


def backfill_ecb(conn: sqlite3.Connection, start_month: str, end_month: str):
    """Fetch ECB rates for a range of months."""
    current = start_month
    while current <= end_month:
        log.info("Backfilling ECB rates for %s", current)
        fetch_ecb_rates(conn, current)
        current = _next_month(current)


def _next_month(month: str) -> str:
    y, m = int(month[:4]), int(month[5:7])
    m += 1
    if m > 12:
        m = 1
        y += 1
    return f"{y:04d}-{m:02d}"


# ---------------------------------------------------------------------------
# CoinGecko Crypto Prices
# ---------------------------------------------------------------------------

def fetch_crypto_prices(conn: sqlite3.Connection):
    """Fetch current prices for tracked crypto assets."""
    tracked_str = get_setting(conn, "tracked_crypto", "")
    if not tracked_str.strip():
        log.info("No tracked crypto assets — skipping price fetch")
        return

    symbols = [s.strip().upper() for s in tracked_str.split(",") if s.strip()]
    base_currency = get_setting(conn, "base_currency", "PLN").lower()
    api_key = get_setting(conn, "coingecko_api_key", "")

    # CoinGecko uses full names as IDs — map common symbols
    symbol_to_id = {
        "BTC": "bitcoin",
        "ETH": "ethereum",
        "SOL": "solana",
        "ADA": "cardano",
        "DOT": "polkadot",
        "LINK": "chainlink",
        "AVAX": "avalanche-2",
        "MATIC": "matic-network",
        "XRP": "ripple",
        "DOGE": "dogecoin",
        "LTC": "litecoin",
        "UNI": "uniswap",
        "ATOM": "cosmos",
    }

    ids = []
    symbol_map = {}  # coingecko_id -> our symbol
    for sym in symbols:
        cg_id = symbol_to_id.get(sym, sym.lower())
        ids.append(cg_id)
        symbol_map[cg_id] = sym

    if not ids:
        return

    headers = {}
    if api_key:
        headers["x-cg-demo-api-key"] = api_key

    url = f"{COINGECKO_API}/simple/price"
    params = {
        "ids": ",".join(ids),
        "vs_currencies": base_currency,
    }

    try:
        resp = requests.get(url, params=params, headers=headers, timeout=30)
        resp.raise_for_status()
        data = resp.json()
    except requests.RequestException as e:
        log.error("CoinGecko price fetch failed: %s", e)
        return
    except json.JSONDecodeError as e:
        log.error("CoinGecko response not valid JSON: %s", e)
        return

    today = date.today().isoformat()
    for cg_id, prices in data.items():
        sym = symbol_map.get(cg_id, cg_id.upper())
        price = prices.get(base_currency)
        if price is None:
            log.warning("No %s price for %s", base_currency, sym)
            continue

        conn.execute(
            "INSERT OR REPLACE INTO asset_prices (date, asset_type, symbol, price_base, source) VALUES (?, 'crypto', ?, ?, 'coingecko')",
            (today, sym, float(price)),
        )
        log.info("Wrote crypto price %s: %.2f %s", sym, price, base_currency.upper())

    conn.commit()


# ---------------------------------------------------------------------------
# CoinGecko Portfolio CSV Import
# ---------------------------------------------------------------------------

def process_coingecko_csvs(conn: sqlite3.Connection, imports_dir: str):
    """Process CoinGecko portfolio CSV files from the imports directory."""
    imports_path = Path(imports_dir)
    if not imports_path.exists():
        log.info("Imports directory %s does not exist — skipping CSV processing", imports_dir)
        return

    csv_files = sorted(imports_path.glob("coingecko-portfolio-*.csv"))
    if not csv_files:
        log.info("No CoinGecko portfolio CSVs found")
        return

    for csv_file in csv_files:
        name = csv_file.name
        # Always re-process 'latest', skip dated files if already processed
        if "latest" not in name:
            marker = csv_file.with_suffix(".processed")
            if marker.exists():
                continue

        log.info("Processing CoinGecko portfolio CSV: %s", name)
        try:
            _import_coingecko_csv(conn, csv_file)
            if "latest" not in name:
                csv_file.with_suffix(".processed").touch()
        except Exception as e:
            log.error("Failed to process %s: %s", name, e)

    conn.commit()


def _import_coingecko_csv(conn: sqlite3.Connection, csv_path: Path):
    """Parse a CoinGecko portfolio CSV and upsert holdings.

    NOTE: The exact column format must be verified from an actual export.
    Expected columns may include: Coin, Symbol, Quantity, Buy Price, etc.
    This parser attempts common column names and rejects unrecognized formats.
    """
    with open(csv_path, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        columns = set(reader.fieldnames or [])

        # Try to identify the format
        # Common expected columns: coin/symbol + quantity/amount
        symbol_col = None
        qty_col = None
        price_col = None

        for candidate in ("Symbol", "symbol", "Ticker", "ticker", "Coin Symbol"):
            if candidate in columns:
                symbol_col = candidate
                break

        for candidate in ("Quantity", "quantity", "Amount", "amount", "Holdings", "holdings"):
            if candidate in columns:
                qty_col = candidate
                break

        for candidate in ("Buy Price", "buy_price", "Avg Buy Price", "Average Buy Price", "Cost Basis"):
            if candidate in columns:
                price_col = candidate
                break

        if not symbol_col or not qty_col:
            log.error(
                "Unrecognized CoinGecko CSV format in %s. Found columns: %s. "
                "Need at least a symbol column and a quantity column.",
                csv_path.name, ", ".join(columns),
            )
            return

        now = datetime.now().isoformat()
        count = 0
        for row in reader:
            sym = row.get(symbol_col, "").strip().upper()
            qty_str = row.get(qty_col, "").strip().replace(",", "")
            if not sym or not qty_str:
                continue
            try:
                qty = float(qty_str)
            except ValueError:
                continue

            avg_price = None
            if price_col and row.get(price_col, "").strip():
                try:
                    avg_price = float(row[price_col].strip().replace(",", ""))
                except ValueError:
                    pass

            conn.execute(
                """INSERT INTO holdings (asset_type, symbol, quantity, avg_buy_price, source, updated_at)
                   VALUES ('crypto', ?, ?, ?, 'coingecko_csv', ?)
                   ON CONFLICT (asset_type, symbol) DO UPDATE SET
                     quantity = excluded.quantity,
                     avg_buy_price = COALESCE(excluded.avg_buy_price, holdings.avg_buy_price),
                     source = excluded.source,
                     updated_at = excluded.updated_at""",
                (sym, qty, avg_price, now),
            )
            count += 1

        log.info("Upserted %d holdings from %s", count, csv_path.name)

        # Auto-populate tracked_crypto from holdings
        rows = conn.execute(
            "SELECT symbol FROM holdings WHERE asset_type = 'crypto' ORDER BY symbol"
        ).fetchall()
        if rows:
            tracked = ",".join(r[0] for r in rows)
            conn.execute(
                "INSERT OR REPLACE INTO settings (key, value) VALUES ('tracked_crypto', ?)",
                (tracked,),
            )


# ---------------------------------------------------------------------------
# Stock Prices (future — placeholder)
# ---------------------------------------------------------------------------

def fetch_stock_prices(conn: sqlite3.Connection):
    """Fetch stock prices using yfinance. Placeholder for future use."""
    tracked_str = get_setting(conn, "tracked_stocks", "")
    if not tracked_str.strip():
        log.info("No tracked stocks — skipping")
        return

    try:
        import yfinance as yf
    except ImportError:
        log.warning("yfinance not available — skipping stock prices")
        return

    base_currency = get_setting(conn, "base_currency", "PLN")
    symbols = [s.strip().upper() for s in tracked_str.split(",") if s.strip()]
    today = date.today().isoformat()

    for sym in symbols:
        try:
            ticker = yf.Ticker(sym)
            info = ticker.info
            price = info.get("regularMarketPrice") or info.get("currentPrice")
            currency = info.get("currency", "USD")

            if price is None:
                log.warning("No price data for stock %s", sym)
                continue

            # Convert to base currency if needed
            if currency.upper() != base_currency:
                # Look up latest exchange rate
                rate_row = conn.execute(
                    "SELECT rate FROM exchange_rates WHERE from_currency = ? AND to_currency = ? ORDER BY month DESC LIMIT 1",
                    (currency.upper(), base_currency),
                ).fetchone()
                if rate_row:
                    price = price * rate_row[0]
                else:
                    log.warning("No exchange rate for %s/%s — storing raw price for %s", currency, base_currency, sym)

            conn.execute(
                "INSERT OR REPLACE INTO asset_prices (date, asset_type, symbol, price_base, source) VALUES (?, 'stock', ?, ?, 'yahoo')",
                (today, sym, float(price)),
            )
            log.info("Wrote stock price %s: %.2f %s", sym, price, base_currency)

        except Exception as e:
            log.error("Failed to fetch stock price for %s: %s", sym, e)

    conn.commit()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Finance market data service for OpenClaw/Vaultkeeper")
    parser.add_argument("--mode", choices=["fiat", "daily", "csv", "all"], default="all", help="What to fetch")
    parser.add_argument("--backfill", nargs=2, metavar=("START", "END"), help="Backfill ECB rates for YYYY-MM range")
    parser.add_argument("--db", default=DEFAULT_DB, help=f"Path to vaultkeeper.db (default: {DEFAULT_DB})")
    parser.add_argument("--imports-dir", default=DEFAULT_IMPORTS, help=f"Path to CSV imports dir (default: {DEFAULT_IMPORTS})")
    args = parser.parse_args()

    # Ensure DB directory exists
    db_dir = os.path.dirname(args.db)
    if db_dir:
        os.makedirs(db_dir, exist_ok=True)

    conn = get_db(args.db)

    try:
        if args.backfill:
            backfill_ecb(conn, args.backfill[0], args.backfill[1])
            return

        if args.mode in ("fiat", "all"):
            # Fetch rates for previous month
            today = date.today()
            if today.month == 1:
                prev_month = f"{today.year - 1}-12"
            else:
                prev_month = f"{today.year}-{today.month - 1:02d}"
            log.info("Fetching ECB rates for %s", prev_month)
            fetch_ecb_rates(conn, prev_month)

        if args.mode in ("daily", "all"):
            fetch_crypto_prices(conn)
            fetch_stock_prices(conn)

        if args.mode in ("csv", "all"):
            process_coingecko_csvs(conn, args.imports_dir)

    except Exception as e:
        log.error("Unhandled error: %s", e)
        sys.exit(1)
    finally:
        conn.close()

    log.info("Done")


if __name__ == "__main__":
    main()
