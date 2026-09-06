"""Logging: rotating file (50 MiB cap) + journald mirror for warnings.

Every user-visible action goes through `action()`, which records the
parameters, the outcome and the wall time, so a failing click or command can
be replayed from the log alone.
"""
from __future__ import annotations

import contextlib
import getpass
import logging
import logging.handlers
import os
import sys
import time
from typing import Any, Iterator

from . import paths

_ROOT = "sway-apps"
_configured = False


class _SyslogMirror(logging.handlers.SysLogHandler):
    """journald picks /dev/log up; identifier = sway-apps."""

    def emit(self, record: logging.LogRecord) -> None:  # pragma: no cover - best effort
        try:
            super().emit(record)
        except Exception:
            pass


def setup(verbose: bool = False, stderr: bool | None = None) -> logging.Logger:
    """Idempotent. `stderr` defaults to True when attached to a terminal."""
    global _configured
    root = logging.getLogger(_ROOT)
    if _configured:
        return root
    _configured = True
    root.setLevel(logging.DEBUG)
    root.propagate = False

    fmt = logging.Formatter(
        "%(asctime)s %(levelname)-7s %(name)s %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
    )

    try:
        paths.LOCAL_STATE_DIR.mkdir(parents=True, exist_ok=True)
        fh = logging.handlers.RotatingFileHandler(
            paths.LOG_FILE,
            maxBytes=paths.LOG_MAX_BYTES,
            backupCount=paths.LOG_BACKUP_COUNT,
            encoding="utf-8",
        )
        fh.setLevel(logging.DEBUG)
        fh.setFormatter(fmt)
        root.addHandler(fh)
    except OSError as exc:  # log dir unwritable: keep going on stderr only
        print(f"sway-apps: cannot open log file: {exc}", file=sys.stderr)

    if os.path.exists("/dev/log"):
        try:
            jh = _SyslogMirror(address="/dev/log")
            jh.ident = "sway-apps: "
            jh.setLevel(logging.WARNING)
            jh.setFormatter(logging.Formatter("%(levelname)s %(name)s %(message)s"))
            root.addHandler(jh)
        except OSError:
            pass

    if stderr is None:
        stderr = sys.stderr.isatty()
    if stderr:
        sh = logging.StreamHandler(sys.stderr)
        sh.setLevel(logging.DEBUG if verbose else logging.WARNING)
        sh.setFormatter(logging.Formatter("%(levelname)s: %(message)s"))
        root.addHandler(sh)

    root.debug(
        "session start pid=%s user=%s argv=%r", os.getpid(), getpass.getuser(), sys.argv
    )
    return root


def get(name: str) -> logging.Logger:
    return logging.getLogger(f"{_ROOT}.{name}")


def _fmt_kwargs(kwargs: dict[str, Any]) -> str:
    return " ".join(f"{k}={v!r}" for k, v in kwargs.items())


@contextlib.contextmanager
def action(name: str, **params: Any) -> Iterator[dict[str, Any]]:
    """Log `name start ... / name ok|fail duration=...` around a block.

    The yielded dict can be filled with result fields that end up in the
    closing line (e.g. result["windows"] = 3).
    """
    log = get("action")
    started = time.monotonic()
    log.info("%s start %s", name, _fmt_kwargs(params))
    result: dict[str, Any] = {}
    try:
        yield result
    except Exception as exc:
        elapsed = time.monotonic() - started
        log.error("%s FAIL duration=%.3fs error=%s: %s %s", name, elapsed, type(exc).__name__, exc, _fmt_kwargs(result))
        raise
    elapsed = time.monotonic() - started
    log.info("%s ok duration=%.3fs %s", name, elapsed, _fmt_kwargs(result))
