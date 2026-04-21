#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3

"""Fetch missing Lutris banners/covers/icons for games in pga.db.

Hits https://lutris.net/api/games/?search=<name>, picks the best fuzzy match,
and downloads the art to ~/.local/share/lutris/{banners,coverart,icons}/<slug>.{jpg,png}.
Keeps our local pga.db slugs unchanged.

Usage:
    fetch-lutris-art.py                    # dry run: show matches, no download
    fetch-lutris-art.py --execute          # download missing art
    fetch-lutris-art.py --execute --force  # redownload even if files exist
    fetch-lutris-art.py --only "Witcher 3,Stray"

A per-game candidate is accepted when name similarity >= THRESHOLD (0.60).
Anything below is reported and left for manual review.
"""

from __future__ import annotations

import argparse
import difflib
import json
import sqlite3
import sys
import urllib.parse
import urllib.request
from pathlib import Path

HOME = Path.home()
PGA_DB = HOME / ".local/share/lutris/pga.db"
BANNERS = HOME / ".local/share/lutris/banners"
COVERART = HOME / ".local/share/lutris/coverart"
ICONS = HOME / ".local/share/lutris/icons"

API_BASE = "https://lutris.net/api/games"
THRESHOLD = 0.60
TIMEOUT = 15

# Manual overrides for games whose pga.db name doesn't resolve via fuzzy search:
# - abbreviations the Lutris search can't expand ("GTA 5" -> "Grand Theft Auto V")
# - typos in the local pga.db name ("Alix" -> "Alyx")
# Keyed by our local slug -> official lutris.net slug.
MANUAL_OVERRIDES: dict[str, str] = {
    "gta-5": "grand-theft-auto-v",
    "half-life-alix": "half-life-alyx",
    "trine4": "trine-4-the-nightmare-prince",
    "trine5": "trine-5-a-clockwork-conspiracy",
    # Search fuzzily returned "Street Fighter IV" (one-character edit). Pin to V.
    "street-fighter-v": "street-fighter-v-champion-edition",
    # Our slug super-bomberman-r2 has no art on lutris.net, but the sibling
    # super-bomberman-r-2 (same game, different slug) does.
    "super-bomberman-r2": "super-bomberman-r-2",
}


def load_games() -> list[tuple[str, str]]:
    with sqlite3.connect(PGA_DB) as c:
        return list(c.execute(
            "SELECT slug, name FROM games WHERE installed=1 AND runner='wine' ORDER BY name"
        ))


def http_get_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "fetch-lutris-art/1.0"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read())


def search_game(name: str) -> list[dict]:
    # Try the name as given, then a punctuation-stripped variant.
    # The lutris.net search is picky about colons and apostrophes.
    variants = [name]
    cleaned = "".join(c if c.isalnum() or c == " " else " " for c in name)
    cleaned = " ".join(cleaned.split())
    if cleaned and cleaned != name:
        variants.append(cleaned)
    for v in variants:
        q = urllib.parse.urlencode({"search": v, "format": "json"})
        data = http_get_json(f"{API_BASE}?{q}")
        results = data.get("results", []) or []
        if results:
            return results
    return []


def fetch_game(slug: str) -> dict | None:
    q = urllib.parse.urlencode({"format": "json"})
    try:
        return http_get_json(f"{API_BASE}/{slug}?{q}")
    except Exception:
        return None


def norm(s: str) -> str:
    return "".join(c.lower() for c in s if c.isalnum())


def pick_match(name: str, results: list[dict]) -> tuple[dict | None, float]:
    if not results:
        return None, 0.0
    qn = norm(name)
    # Score each candidate by best similarity against name or any alias name
    best_r: dict | None = None
    best_score = 0.0
    for r in results:
        candidates: list[str] = [r.get("name", "")]
        for a in r.get("aliases") or []:
            candidates.append(a.get("name", ""))
        score = max(
            (difflib.SequenceMatcher(None, qn, norm(c)).ratio() for c in candidates if c),
            default=0.0,
        )
        if score > best_score:
            best_r, best_score = r, score
    return best_r, best_score


def download(url: str, dst: Path, *, execute: bool, force: bool) -> str:
    if not url:
        return "no url"
    if dst.exists() and not force:
        return "exists"
    if not execute:
        return f"would fetch -> {dst.name}"
    dst.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "fetch-lutris-art/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r, open(dst, "wb") as f:
            f.write(r.read())
        return f"ok ({dst.stat().st_size // 1024} KB)"
    except Exception as e:
        return f"FAILED {e}"


def main() -> int:
    ap = argparse.ArgumentParser(description="Fetch Lutris art from lutris.net API")
    ap.add_argument("--execute", action="store_true", help="Download files (default: dry run)")
    ap.add_argument("--force", action="store_true", help="Redownload even if file exists")
    ap.add_argument("--only", type=str, default="", help="Comma-separated game names to limit to")
    ap.add_argument("--threshold", type=float, default=THRESHOLD,
                    help=f"Min name similarity to accept (default {THRESHOLD})")
    args = ap.parse_args()

    if not PGA_DB.exists():
        sys.exit(f"ERROR: {PGA_DB} not found")

    only_set = {s.strip() for s in args.only.split(",") if s.strip()}
    games = load_games()
    if only_set:
        games = [(s, n) for s, n in games if n in only_set]

    mode = "EXECUTE" if args.execute else "DRY RUN"
    print(f"=== fetch-lutris-art ({mode}) — {len(games)} games, threshold={args.threshold} ===\n")

    low_score: list[tuple[str, str, float, str]] = []
    matched = 0
    skipped = 0

    for slug, name in games:
        banner_dst = BANNERS / f"{slug}.jpg"
        cover_dst = COVERART / f"{slug}.jpg"
        icon_dst = ICONS / f"{slug}.png"

        if (banner_dst.exists() and cover_dst.exists() and icon_dst.exists()) and not args.force:
            print(f"[ok  ] {slug}: art already present")
            skipped += 1
            continue

        # Check manual override first
        if slug in MANUAL_OVERRIDES:
            override_slug = MANUAL_OVERRIDES[slug]
            hit = fetch_game(override_slug)
            score = 1.0
            if not hit:
                print(f"[err ] {slug}: manual override slug {override_slug!r} not found on lutris.net")
                continue
        else:
            try:
                results = search_game(name)
            except Exception as e:
                print(f"[err ] {slug}: API error — {e}")
                continue

            hit, score = pick_match(name, results)
            if not hit or score < args.threshold:
                remote = hit.get("slug") if hit else "(no results)"
                print(f"[low ] {slug}: best={remote!r} score={score:.2f} — below threshold")
                low_score.append((slug, name, score, remote or ""))
                continue

        remote_slug = hit["slug"]
        banner_url = hit.get("banner_url") or ""
        icon_url = hit.get("icon_url") or ""
        cover_url = hit.get("coverart") or ""

        b = download(banner_url, banner_dst, execute=args.execute, force=args.force)
        c = download(cover_url, cover_dst, execute=args.execute, force=args.force)
        i = download(icon_url, icon_dst, execute=args.execute, force=args.force)

        print(f"[match] {slug}  -> {remote_slug}  (score={score:.2f})")
        print(f"         banner: {b}")
        print(f"         cover:  {c}")
        print(f"         icon:   {i}")
        matched += 1

    print(f"\n=== summary: matched={matched}  skipped_existing={skipped}  low_score={len(low_score)} ===")
    if low_score:
        print("\nReview these manually (score < threshold):")
        for slug, name, score, remote in low_score:
            print(f"  {slug}  ({name!r}): best candidate {remote!r} score={score:.2f}")
    if not args.execute:
        print("\n(dry run) re-run with --execute to download.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
