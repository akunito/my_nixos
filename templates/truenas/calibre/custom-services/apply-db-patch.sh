#!/bin/bash
# Apply the expire_on_commit fix to Calibre-Web-Automated's SQLAlchemy session
# factory (fixes DetachedInstanceError).
#
# This is a SURGICAL sed, deliberately not a whole-file copy. Until 2026-08-13
# this script dropped a frozen cps/db.py (captured 2026-02-23, 1302 lines) over
# the one shipped in the image (1359 lines by then). Because the image tracks
# :latest, that silently reverted ~57 lines of upstream changes on every single
# container start, and the gap grew with each pull.
#
# The fix itself is still required: upstream's db.py still constructs the
# scoped_session without expire_on_commit at this one call site.
#
# Idempotent, and it tells you if upstream ever changes the line so this can be
# dropped rather than failing silently.
set -u

TARGET=/app/calibre-web-automated/cps/db.py
FIXED='bind=cls.engine, future=True, expire_on_commit=False))'
UNFIXED='bind=cls.engine, future=True))'

if [ ! -f "$TARGET" ]; then
    echo "[custom-patch] ERROR: $TARGET not found - CWA layout changed?"
    exit 0
fi

if grep -qF "$FIXED" "$TARGET"; then
    echo "[custom-patch] expire_on_commit already present, nothing to do"
    exit 0
fi

if ! grep -qF "$UNFIXED" "$TARGET"; then
    echo "[custom-patch] WARNING: neither patched nor expected unpatched line found."
    echo "[custom-patch] Upstream db.py has changed - re-check whether this patch is still needed."
    exit 0
fi

sed -i 's/bind=cls\.engine, future=True))/bind=cls.engine, future=True, expire_on_commit=False))/' "$TARGET"

if grep -qF "$FIXED" "$TARGET"; then
    echo "[custom-patch] expire_on_commit fix applied to the image's own db.py"
else
    echo "[custom-patch] ERROR: sed did not apply the fix"
fi
