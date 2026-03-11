#!/usr/bin/env python3
"""
Sanitize Revolut CSV imports — strip prompt injection from transaction notes.

Runs BEFORE Vaultkeeper's LLM sees the CSV. Deterministic code, immune to injection.
Preserves original files as .unsanitized for audit trail.
"""
import csv
import re
import shutil
import sys
from pathlib import Path

IMPORTS_DIR = Path.home() / ".openclaw/finance-imports"
MAX_NOTE_LENGTH = 60
# Allow only: letters, digits, spaces, currency symbols, basic punctuation
ALLOWED_CHARS = re.compile(r"[^a-zA-Z0-9àáâãäåæçèéêëìíîïñòóôõöùúûüýÿ \t€£$.,;:!?'\"()/&@#%+-]")

def sanitize_field(value: str) -> str:
    """Truncate and strip suspicious characters from a text field."""
    if not value:
        return value
    cleaned = ALLOWED_CHARS.sub("", value)
    return cleaned[:MAX_NOTE_LENGTH].strip()

def process_csv(filepath: Path) -> int:
    """Sanitize a single CSV file in-place. Returns number of rows processed."""
    # Revolut CSV columns that contain free-text (user-controllable):
    # "Description" (merchant/P2P note) — primary injection vector
    TEXT_COLUMNS = {"Description", "Reference"}

    backup = filepath.with_suffix(".csv.unsanitized")
    if backup.exists():
        # Already sanitized — skip (idempotent)
        return 0

    with open(filepath, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            return 0
        rows = list(reader)

    # Preserve original for audit
    shutil.copy2(filepath, backup)

    sanitized = 0
    for row in rows:
        for col in TEXT_COLUMNS:
            if col in row and row[col]:
                original = row[col]
                row[col] = sanitize_field(original)
                if row[col] != original:
                    sanitized += 1

    with open(filepath, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=reader.fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    return sanitized

def main():
    if not IMPORTS_DIR.exists():
        print(f"No imports directory: {IMPORTS_DIR}")
        sys.exit(0)

    total = 0
    for csv_file in sorted(IMPORTS_DIR.glob("*.csv")):
        count = process_csv(csv_file)
        if count > 0:
            print(f"Sanitized {count} fields in {csv_file.name}")
            total += count

    if total == 0:
        print("No sanitization needed (all clean or already processed)")
    else:
        print(f"Total fields sanitized: {total}")

if __name__ == "__main__":
    main()
