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
    rel = _rel(existing)  # files or directories (apps/snapshots/)
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


# --------------------------------------------------------------------------
# sync: rebase our state commits onto upstream, merge the JSON semantically
# when both sides touched a state file, push. sway-apps commits only ever
# touch the state files, so a conflict can only be inside them, and those are
# id-keyed collections the tool knows how to merge (per item, newest
# `updated_at` wins; a one-sided delete wins over an untouched item; a delete
# on one side vs an edit on the other keeps the edit).

import json as _json
import time as _time

_SECTIONS = ("rules", "startup", "monitors", "shortcuts", "tools", "nodes")


def stamp(item: dict) -> dict:
    item["updated_at"] = int(_time.time())
    return item


def _merge_section(base: list, ours: list, theirs: list) -> list:
    b = {x["id"]: x for x in base}
    o = {x["id"]: x for x in ours}
    t = {x["id"]: x for x in theirs}
    out: dict[str, dict] = {}
    for i in list(dict.fromkeys(list(o) + list(t) + list(b))):
        bo, oo, to = b.get(i), o.get(i), t.get(i)
        if oo is None and to is None:
            continue                     # deleted everywhere
        if oo is None:                    # we deleted (or never had it)
            out[i] = to if (bo is None or to != bo) else None  # they changed/added it -> keep; else honour our delete
        elif to is None:
            out[i] = oo if (bo is None or oo != bo) else None
        elif oo == to:
            out[i] = oo
        elif oo == bo:
            out[i] = to                   # only they changed it
        elif to == bo:
            out[i] = oo                   # only we changed it
        else:                             # both changed: newest wins
            out[i] = oo if int(oo.get("updated_at", 0)) >= int(to.get("updated_at", 0)) else to
    # keep "ours" ordering first, then new items from theirs
    order = [i for i in o if i in out and out[i] is not None] + [i for i in t if i in out and out[i] is not None and i not in o]
    return [out[i] for i in order]


def merge_state_json(base_txt: str, ours_txt: str, theirs_txt: str) -> str:
    base = _json.loads(base_txt) if base_txt.strip() else {}
    ours = _json.loads(ours_txt)
    theirs = _json.loads(theirs_txt)
    merged = dict(ours)
    for sec in _SECTIONS:
        merged[sec] = _merge_section(base.get(sec, []), ours.get(sec, []), theirs.get(sec, []))
    ms = dict(theirs.get("settings", {})); ms.update(ours.get("settings", {}))
    merged["settings"] = ms
    merged["version"] = max(int(ours.get("version", 1)), int(theirs.get("version", 1)))
    return _json.dumps(merged, indent=2, ensure_ascii=False) + "\n"


def _resolve_conflicts() -> list[str]:
    """During a rebase stop: semantically merge every conflicted state file."""
    top = _top()
    conflicted = _git(["diff", "--name-only", "--diff-filter=U"], check=False).stdout.split()
    fixed = []
    for rel in conflicted:
        if not rel.endswith(".json") or "/apps/" not in rel:
            continue  # not ours: leave it to the human
        def show(spec: str) -> str:
            pr = _git(["show", f"{spec}:{rel}"], check=False)
            return pr.stdout if pr.returncode == 0 else ""
        # In a rebase, "ours" (stage 2) is upstream and "theirs" (stage 3) is our replayed commit.
        merged = merge_state_json(show(":1"), show(":3"), show(":2"))
        (top / rel).write_text(merged)
        _git(["add", "--", rel])
        fixed.append(rel)
    return fixed


def sync(push_after: bool = True) -> dict:
    """fetch -> rebase our commits (auto-merging state JSON) -> push."""
    if not paths.git_enabled() or not in_repo():
        return {"ok": False, "skipped": "git disabled or not a repo"}
    with log.action("git.sync") as res:
        st = status()
        if st.get("dirty"):
            return {"ok": False, "error": "state files have uncommitted changes; save first"}
        _git(["fetch", "--quiet"], check=False)
        behind = st.get("behind") or 0
        # re-read after fetch
        counts = _git(["rev-list", "--left-right", "--count", "@{u}...HEAD"], check=False).stdout.split()
        behind, ahead = (int(counts[0]), int(counts[1])) if len(counts) == 2 else (0, 0)
        res["behind"] = behind; res["ahead"] = ahead
        merged_files: list[str] = []
        if behind:
            # Only rebase if OUR unpushed commits touch nothing but state files;
            # otherwise a human is mid-work in this checkout.
            ours_files = _git(["diff", "--name-only", "@{u}...HEAD"], check=False).stdout.split()
            foreign = [f for f in ours_files if not (f.endswith(".json") and "/apps/" in f)]
            if foreign and ahead:
                return {"ok": False, "error": f"unpushed commits touch non-state files ({foreign[:3]}); sync by hand"}
            pr = _git(["rebase", "--autostash", "@{u}"], check=False)
            tries = 0
            while pr.returncode != 0 and tries < 10:
                tries += 1
                fixed = _resolve_conflicts()
                if not fixed:
                    _git(["rebase", "--abort"], check=False)
                    return {"ok": False, "error": "rebase conflict outside state files; aborted: " + (pr.stderr or pr.stdout)[-300:]}
                merged_files += fixed
                pr = _git(["-c", "core.editor=true", "rebase", "--continue"], check=False)
            if pr.returncode != 0:
                _git(["rebase", "--abort"], check=False)
                return {"ok": False, "error": "rebase failed: " + (pr.stderr or pr.stdout)[-300:]}
        res["merged"] = merged_files
        pushed = False
        if push_after:
            counts = _git(["rev-list", "--left-right", "--count", "@{u}...HEAD"], check=False).stdout.split()
            if len(counts) == 2 and int(counts[1]) > 0:
                pp = _git(["push", "--quiet"], check=False)
                pushed = pp.returncode == 0
                if not pushed:
                    return {"ok": False, "error": "push failed: " + (pp.stderr or pp.stdout)[-300:], "merged": merged_files}
        res["pushed"] = pushed
        return {"ok": True, "behind": behind, "ahead": ahead, "merged": merged_files, "pushed": pushed}


def auto_sync_enabled() -> bool:
    import os
    from .gui import theme  # config.json lives with the theme config
    v = os.environ.get("SWAY_APPS_AUTO_SYNC")
    if v is not None:
        return v not in ("0", "false", "no")
    return bool(theme.load_config().get("auto_sync", True))


def pull() -> str:
    with log.action("git.pull") as res:
        proc = _git(["pull", "--ff-only"], check=False)
        out = (proc.stdout + proc.stderr).strip()
        res["ok"] = proc.returncode == 0
        if proc.returncode != 0:
            raise RuntimeError(out or "git pull failed")
    return out
