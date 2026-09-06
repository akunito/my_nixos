"""Auto-commit the state files; push on demand."""
from __future__ import annotations

import subprocess
from pathlib import Path

from . import log, paths

_log = log.get("git")


_top_cache: Path | None = None


def _top() -> Path:
    """Work-tree root; git pathspecs below are relative to it, so every git
    call runs from there (running from STATE_DIR made `add user/wm/...` fail)."""
    global _top_cache
    if _top_cache is None:
        proc = subprocess.run(["git", "-C", str(paths.STATE_DIR), "rev-parse", "--show-toplevel"],
                              capture_output=True, text=True)
        _top_cache = Path(proc.stdout.strip()) if proc.returncode == 0 and proc.stdout.strip() else paths.STATE_DIR
    return _top_cache


def _git(args: list[str], cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess:
    cmd = ["git", "-C", str(cwd or _top()), *args]
    _log.debug("exec %s", " ".join(cmd))
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {proc.stderr.strip() or proc.stdout.strip()}")
    return proc


def in_repo() -> bool:
    if not paths.STATE_DIR.exists():
        return False
    return _git(["rev-parse", "--is-inside-work-tree"], cwd=paths.STATE_DIR, check=False).returncode == 0


def toplevel() -> Path | None:
    if not in_repo():
        return None
    return _top()


def _rel(paths_: list[Path]) -> list[str]:
    top = toplevel()
    return [str(p.resolve().relative_to(top)) for p in paths_] if top else [str(p) for p in paths_]


def status() -> dict:
    """Dirty state files + ahead/behind counts, for the UI footer."""
    if not paths.git_enabled():
        return {"enabled": False}
    if not in_repo():
        return {"enabled": True, "repo": False}
    files = [p for p in (paths.common_file(), paths.profile_file()) if p.exists()]
    dirty = _git(["status", "--porcelain", "--", *_rel(files)], check=False).stdout.strip().splitlines() if files else []
    ahead = behind = None
    upstream = _git(["rev-parse", "--abbrev-ref", "@{u}"], check=False)
    if upstream.returncode == 0:
        counts = _git(["rev-list", "--left-right", "--count", "@{u}...HEAD"], check=False).stdout.split()
        if len(counts) == 2:
            behind, ahead = int(counts[0]), int(counts[1])
    branch = _git(["rev-parse", "--abbrev-ref", "HEAD"], check=False).stdout.strip()
    return {"enabled": True, "repo": True, "branch": branch, "dirty": [d.strip() for d in dirty],
            "ahead": ahead, "behind": behind, "upstream": upstream.stdout.strip() or None}


def commit(files: list[Path], message: str) -> str | None:
    """Commit only these paths. Returns the short sha, or None if nothing changed."""
    if not paths.git_enabled():
        _log.debug("git disabled by SWAY_APPS_GIT")
        return None
    if not in_repo():
        _log.warning("state dir %s is not inside a git repo; not committing", paths.STATE_DIR)
        return None
    existing = [f for f in files if f.exists()]
    if not existing:
        return None
    rel = _rel(existing)
    _git(["add", "--", *rel])
    if _git(["diff", "--cached", "--quiet", "--", *rel], check=False).returncode == 0:
        return None
    with log.action("git.commit", files=rel) as res:
        _git(["commit", "--quiet", "--no-verify", "-m", f"sway-apps: {message}", "--", *rel])
        sha = _git(["rev-parse", "--short", "HEAD"]).stdout.strip()
        res["sha"] = sha
    return sha


def push() -> str:
    with log.action("git.push") as res:
        proc = _git(["push", "--porcelain"], check=False)
        out = (proc.stdout + proc.stderr).strip()
        res["ok"] = proc.returncode == 0
        if proc.returncode != 0:
            raise RuntimeError(out or "git push failed")
    return out


def pull() -> str:
    with log.action("git.pull") as res:
        proc = _git(["pull", "--ff-only"], check=False)
        out = (proc.stdout + proc.stderr).strip()
        res["ok"] = proc.returncode == 0
        if proc.returncode != 0:
            raise RuntimeError(out or "git pull failed")
    return out
