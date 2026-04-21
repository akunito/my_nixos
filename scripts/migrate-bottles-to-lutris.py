#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3Packages.pyyaml rsync

"""Migrate programs from the Bottles "Games" bottle into Lutris.

Idempotent, dry-run by default. See plan file
/home/akunito/.claude/plans/after-updating-desk-yesterday-virtual-sifakis.md.

Usage:
    migrate-bottles-to-lutris.py                 # dry run
    migrate-bottles-to-lutris.py --execute       # apply
    migrate-bottles-to-lutris.py --only "Stardew Valley,Stray"
    migrate-bottles-to-lutris.py --no-saves-copy

Each game gets its own wine prefix at ~/Games/<slug>/, a Lutris yml under
~/.local/share/lutris/games/, and a pga.db row. Save directories inside the new
prefix are symlinked into ~/GameSaves/ via scripts/redirect-game-saves.sh so the
6-hour NAS backup picks them up.

Bottles itself is never modified.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import yaml

HOME = Path.home()
BOTTLE = HOME / ".local/share/bottles/bottles/Games"
BOTTLE_YML = BOTTLE / "bottle.yml"
LUTRIS_GAMES_DIR = HOME / ".local/share/lutris/games"
LUTRIS_PGA_DB = HOME / ".local/share/lutris/pga.db"
GAMES_ROOT = HOME / "Games"
GAMESAVES = HOME / "GameSaves"
REDIRECT_SCRIPT = Path(__file__).parent / "redirect-game-saves.sh"

SKIP_NAMES = {
    "Steam",
    "EA Client",
    "Setup",
    "Witcher 3 - REDlauncher",
    "Witcher 3 - REDprelauncher",
    "UnravelTwo",
    "Worms World Party Remastered - Editor",
    "RimWorld",  # already migrated
}

DEFAULT_GAMESCOPE_RES = "3840x2160"
DEFAULT_FPS_LIMIT = "120"
DEFAULT_WINE_VERSION = "Proton - Experimental"


# ---------- helpers ----------

def slugify(name: str) -> str:
    s = name.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-")
    return s


def parse_bottles_arguments(args_raw: str | None) -> tuple[dict[str, str], str | None]:
    """Split Bottles 'arguments' into (env-dict, positional-args-string).

    Bottles places env vars before %command% and args after. Example:
        "FOO=1 BAR=2 %command% -flag -xyz"  -> ({FOO:1,BAR:2}, "-flag -xyz")
        "%command% -flag"                   -> ({},            "-flag")
        "FOO=1 %command%"                   -> ({FOO:1},       None)
    """
    if not args_raw:
        return {}, None
    # Split around %command%
    if "%command%" in args_raw:
        before, _, after = args_raw.partition("%command%")
    else:
        before, after = args_raw, ""
    env: dict[str, str] = {}
    for token in before.strip().split():
        if "=" in token:
            k, _, v = token.partition("=")
            env[k] = v
    post = after.strip() or None
    return env, post


def load_bottle() -> dict:
    with open(BOTTLE_YML) as f:
        return yaml.safe_load(f)


def existing_lutris_exes() -> set[str]:
    """Return the set of lowercased exe paths already known to Lutris."""
    out: set[str] = set()
    # From pga.db
    try:
        with sqlite3.connect(LUTRIS_PGA_DB) as c:
            for (e,) in c.execute("SELECT executable FROM games WHERE executable IS NOT NULL"):
                if e:
                    out.add(e.lower())
    except sqlite3.OperationalError:
        pass
    # From existing yml files (covers entries written directly)
    for yml in sorted(LUTRIS_GAMES_DIR.glob("*.yml")):
        try:
            data = yaml.safe_load(yml.read_text())
        except yaml.YAMLError:
            continue
        if isinstance(data, dict):
            exe = (data.get("game") or {}).get("exe")
            if exe:
                out.add(exe.lower())
    return out


def existing_slugs() -> set[str]:
    try:
        with sqlite3.connect(LUTRIS_PGA_DB) as c:
            return {s for (s,) in c.execute("SELECT slug FROM games WHERE slug IS NOT NULL")}
    except sqlite3.OperationalError:
        return set()


def ensure_lutris_not_running() -> None:
    r = subprocess.run(["pgrep", "-x", "lutris"], capture_output=True)
    if r.returncode == 0:
        sys.exit("ERROR: Lutris is running. Quit Lutris and rerun. (pgrep -x lutris matched)")


# ---------- migration ----------

@dataclass
class Plan:
    name: str
    slug: str
    exe: str
    prefix: Path
    yml_path: Path
    yml_data: dict
    ts: int
    overrides: list[str] = field(default_factory=list)


def make_plan(prog: dict, ts_seed: int, used_slugs: set[str]) -> Plan | None:
    name = prog.get("name", "").strip()
    exe = prog.get("path") or prog.get("executable")
    if not name or not exe:
        return None

    slug_base = slugify(name)
    slug = slug_base
    i = 2
    while slug in used_slugs:
        slug = f"{slug_base}-{i}"
        i += 1
    used_slugs.add(slug)

    ts = ts_seed + len(used_slugs)  # unique per game within this run
    prefix = GAMES_ROOT / slug
    yml_path = LUTRIS_GAMES_DIR / f"{slug}-{ts}.yml"

    # --- Base yml ---
    env = {"UNITY_CRASH_HANDLER": "0"}
    system: dict = {
        "gamescope": True,
        "gamescope_game_res": DEFAULT_GAMESCOPE_RES,
        "gamescope_output_res": DEFAULT_GAMESCOPE_RES,
        "gamescope_fps_limiter": DEFAULT_FPS_LIMIT,
    }
    game_block: dict = {
        "exe": exe,
        "prefix": str(prefix),
    }
    wine_block: dict = {
        "version": DEFAULT_WINE_VERSION,
        "Dpi": False,
    }

    overrides: list[str] = []

    # Per-game: split args into env + leftover args
    arg_env, arg_tail = parse_bottles_arguments(prog.get("arguments"))
    if arg_env:
        env.update(arg_env)
        overrides.append(f"args-env={list(arg_env)}")
    if arg_tail:
        game_block["args"] = arg_tail
        overrides.append(f"args={arg_tail!r}")

    # fsr
    fsr = prog.get("fsr")
    if fsr is True:
        env["WINE_FULLSCREEN_FSR"] = "1"
        overrides.append("fsr=on")
    elif fsr is False:
        overrides.append("fsr=off")

    # gamescope override
    if prog.get("gamescope") is False:
        system["gamescope"] = False
        overrides.append("gamescope=off")

    # virtual_desktop
    if prog.get("virtual_desktop") is True:
        wine_block["Virtual Desktop"] = DEFAULT_GAMESCOPE_RES
        overrides.append("virtual-desktop")

    # dxvk / vkd3d disabled -> fall back to native wined3d (Proton env)
    if prog.get("dxvk") is False and prog.get("vkd3d") is False:
        env["PROTON_USE_WINED3D"] = "1"
        overrides.append("wined3d")

    system["env"] = env

    yml_data = {
        "game": game_block,
        "system": system,
        "wine": wine_block,
    }

    return Plan(
        name=name,
        slug=slug,
        exe=exe,
        prefix=prefix,
        yml_path=yml_path,
        yml_data=yml_data,
        ts=ts,
        overrides=overrides,
    )


def write_yml(p: Plan) -> None:
    p.yml_path.parent.mkdir(parents=True, exist_ok=True)
    with open(p.yml_path, "w") as f:
        yaml.safe_dump(p.yml_data, f, sort_keys=False, allow_unicode=True)


def insert_pga_row(conn: sqlite3.Connection, p: Plan) -> None:
    directory = str(Path(p.exe).parent)
    conn.execute(
        """INSERT INTO games
           (name, slug, runner, configpath, installed, installed_at,
            platform, executable, directory)
           VALUES (?, ?, 'wine', ?, 1, ?, 'Windows', ?, ?)""",
        (p.name, p.slug, f"{p.slug}-{p.ts}", p.ts, p.exe, directory),
    )


def create_prefix(p: Plan, execute: bool) -> None:
    if execute:
        p.prefix.mkdir(parents=True, exist_ok=True)
        # Bare minimum wine prefix skeleton so redirect-game-saves.sh can do its thing
        drive_c_users = p.prefix / "drive_c/users/steamuser"
        (drive_c_users / "AppData").mkdir(parents=True, exist_ok=True)


def run_redirect(p: Plan, execute: bool) -> None:
    flag = ["--execute"] if execute else []
    # Ensure AppData/LocalLow, Roaming, Documents exist as dirs so script can symlink them.
    # When run for a fresh skeleton they won't exist; redirect-game-saves.sh treats a
    # missing src dir as "create a symlink directly" which is exactly what we want.
    subprocess.run(
        [str(REDIRECT_SCRIPT), str(p.prefix), *flag],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def rsync_saves(execute: bool) -> dict[str, str]:
    results: dict[str, str] = {}
    # rsync semantics: trailing slash on src = "contents of", no trailing = "the dir itself"
    # Path() strips trailing slashes, so we append them as strings explicitly.
    pairs = [
        (BOTTLE / "drive_c/users/steamuser/AppData/LocalLow", GAMESAVES / "LocalLow"),
        (BOTTLE / "drive_c/users/steamuser/AppData/Roaming",  GAMESAVES / "Roaming"),
        (BOTTLE / "drive_c/users/steamuser/Documents",        GAMESAVES / "Documents"),
    ]
    for src, dst in pairs:
        if not src.exists():
            results[src.name] = "source missing (skipped)"
            continue
        dst.mkdir(parents=True, exist_ok=True)
        cmd = ["rsync", "-a", "--update", "--stats"]
        if not execute:
            cmd.append("--dry-run")
        # Trailing slash on src so we merge contents, not nest the dir.
        cmd.extend([f"{src}/", f"{dst}/"])
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            results[src.name] = f"FAILED rc={r.returncode}\n{r.stderr.strip()}"
        else:
            total_line = next(
                (l for l in r.stdout.splitlines() if "Total transferred file size" in l),
                "",
            )
            results[src.name] = total_line or "ok"
    return results


# ---------- main ----------

def main() -> int:
    ap = argparse.ArgumentParser(description="Migrate Bottles Games -> Lutris")
    ap.add_argument("--execute", action="store_true", help="Apply changes (default: dry run)")
    ap.add_argument("--only", type=str, default="",
                    help="Comma-separated list of game names to migrate (others skipped)")
    ap.add_argument("--no-saves-copy", action="store_true",
                    help="Skip the Bottles -> GameSaves rsync stage")
    args = ap.parse_args()

    if not BOTTLE_YML.exists():
        sys.exit(f"ERROR: {BOTTLE_YML} not found")
    if not LUTRIS_PGA_DB.exists():
        sys.exit(f"ERROR: {LUTRIS_PGA_DB} not found")
    if not REDIRECT_SCRIPT.exists():
        sys.exit(f"ERROR: helper missing: {REDIRECT_SCRIPT}")

    if args.execute:
        ensure_lutris_not_running()

    only_set = {s.strip() for s in args.only.split(",") if s.strip()}

    bottle = load_bottle()
    progs = bottle.get("External_Programs", {}) or {}

    existing_exes = existing_lutris_exes()
    used_slugs = existing_slugs()
    ts_seed = int(time.time())

    plans: list[Plan] = []
    skipped: list[tuple[str, str]] = []  # (name, reason)
    seen_exes_this_run: set[str] = set()

    # Deterministic order: by name
    for uid in sorted(progs.keys(), key=lambda k: (progs[k].get("name") or "").lower()):
        prog = progs[uid]
        name = (prog.get("name") or "").strip()
        exe = prog.get("path") or prog.get("executable")

        if only_set and name not in only_set:
            continue  # explicit subset filter
        if name in SKIP_NAMES:
            skipped.append((name, "in SKIP_NAMES"))
            continue
        if not exe:
            skipped.append((name, "no exe path"))
            continue
        if exe.lower() in existing_exes:
            skipped.append((name, "already in Lutris"))
            continue
        if exe.lower() in seen_exes_this_run:
            skipped.append((name, "duplicate exe within run"))
            continue
        seen_exes_this_run.add(exe.lower())

        p = make_plan(prog, ts_seed, used_slugs)
        if p is None:
            skipped.append((name, "plan build failed"))
            continue
        plans.append(p)

    mode = "EXECUTE" if args.execute else "DRY RUN"
    print(f"=== Bottles -> Lutris migration ({mode}) ===")
    print(f"planned: {len(plans)}   skipped: {len(skipped)}\n")

    for p in plans:
        ovr = ", ".join(p.overrides) or "-"
        print(f"[{p.slug}] {p.name}")
        print(f"    exe:       {p.exe}")
        print(f"    prefix:    {p.prefix}")
        print(f"    overrides: {ovr}")

    if skipped:
        print("\n-- skipped --")
        for name, reason in skipped:
            print(f"  {name}: {reason}")

    # ---- save-data copy stage ----
    if not args.no_saves_copy:
        print("\n=== Bottles -> GameSaves rsync ===")
        results = rsync_saves(args.execute)
        for k, v in results.items():
            print(f"  {k}: {v}")

    # ---- Write files + pga.db ----
    if not args.execute:
        print("\n(dry run) no yml/pga.db/prefix changes written.")
        print("Re-run with --execute to apply.")
        return 0

    if not plans:
        print("\nNothing to migrate. Exiting.")
        return 0

    # Backup pga.db
    bak = LUTRIS_PGA_DB.with_suffix(f".db.bak.{ts_seed}")
    shutil.copy2(LUTRIS_PGA_DB, bak)
    print(f"\nBackup: {bak}")

    print(f"\nWriting {len(plans)} Lutris entries...")
    with sqlite3.connect(LUTRIS_PGA_DB) as conn:
        for p in plans:
            create_prefix(p, execute=True)
            write_yml(p)
            insert_pga_row(conn, p)
            try:
                run_redirect(p, execute=True)
            except subprocess.CalledProcessError as e:
                print(f"  ! redirect-game-saves.sh failed for {p.slug}: {e.stderr.strip()}")
            print(f"  {p.slug} -> {p.yml_path.name}")
        conn.commit()

    print(f"\n[done] {len(plans)} games migrated, {len(skipped)} skipped.")
    print(f"pga.db backup: {bak}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
