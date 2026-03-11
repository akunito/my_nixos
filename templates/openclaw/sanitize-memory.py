#!/usr/bin/env python3
"""
Sanitize OpenClaw memory files — strip prompt injection patterns.

Runs AFTER session-memory hook writes a file. Deterministic code, immune to injection.
Same philosophy as sanitize-csv.py — code-level defense that survives context compaction.
"""
import re
import sys
from pathlib import Path

MEMORY_DIR = Path.home() / ".openclaw/workspace/memory"

# Patterns that indicate injection attempts in memory files.
# These are stripped or replaced with a sanitized marker.
INJECTION_PATTERNS = [
    # Direct instruction injection
    (re.compile(r'(?i)\b(ignore|disregard|forget)\s+(all\s+)?(previous|prior|above)\s+(instructions?|rules?|directives?|prompts?)'), "[INJECTION STRIPPED]"),
    (re.compile(r'(?i)\byou\s+are\s+now\b'), "[INJECTION STRIPPED]"),
    (re.compile(r'(?i)\bnew\s+(system\s+)?instructions?\s*:'), "[INJECTION STRIPPED]"),
    (re.compile(r'(?i)^system\s*:', re.MULTILINE), "[INJECTION STRIPPED]"),
    (re.compile(r'(?i)\bIMPORTANT\s*:\s*(?:override|ignore|disregard|forget)'), "[INJECTION STRIPPED]"),
    # Role-play / identity hijack
    (re.compile(r'(?i)\b(act|pretend|behave)\s+as\s+(if\s+)?(you\s+are|a|an)\b'), "[INJECTION STRIPPED]"),
    (re.compile(r'(?i)\byour\s+new\s+(role|identity|persona)\b'), "[INJECTION STRIPPED]"),
    # Code/data exfiltration attempts
    (re.compile(r'(?i)\b(execute|run|eval)\s*\('), "[INJECTION STRIPPED]"),
    # Base64 blobs (>100 chars of base64 — likely encoded payload)
    (re.compile(r'[A-Za-z0-9+/]{100,}={0,2}'), "[BASE64 BLOB STRIPPED]"),
    # Embedded code blocks (triple backticks with executable-looking content)
    (re.compile(r'```(?:bash|sh|python|javascript|js|ruby|perl|php|powershell)\n.*?```', re.DOTALL), "[CODE BLOCK STRIPPED]"),
]

def sanitize_file(filepath: Path) -> int:
    """Sanitize a single memory file in-place. Returns count of patterns stripped."""
    content = filepath.read_text(encoding="utf-8")
    count = 0

    for pattern, replacement in INJECTION_PATTERNS:
        content, n = pattern.subn(replacement, content)
        count += n

    if count > 0:
        filepath.write_text(content, encoding="utf-8")
        print(f"Sanitized {count} patterns in {filepath.name}")

    return count

def main():
    if not MEMORY_DIR.exists():
        sys.exit(0)

    # Process only recent files (today and yesterday) to avoid re-scanning old files
    from datetime import date, timedelta
    today = date.today()
    yesterday = today - timedelta(days=1)
    prefixes = [today.isoformat(), yesterday.isoformat()]

    total = 0
    for md_file in sorted(MEMORY_DIR.glob("*.md")):
        if any(md_file.name.startswith(p) for p in prefixes):
            total += sanitize_file(md_file)

    # Also always sanitize MEMORY.md (Tier 1)
    memory_md = MEMORY_DIR.parent / "MEMORY.md"
    if memory_md.exists():
        total += sanitize_file(memory_md)

    if total > 0:
        print(f"Total patterns stripped: {total}")

if __name__ == "__main__":
    main()
