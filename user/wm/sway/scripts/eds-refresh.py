#!/usr/bin/env python3
"""
Force evolution-data-server to refresh all enabled calendar sources.

EDS calendar-factory only fetches CalDAV updates when a client subscribes.
gnome-calendar normally does this when you open it; this script does the same
thing headlessly so the Waybar widget's local cache stays current without
requiring the user to open any GUI app.

Run periodically (systemd user timer) and at session start.
"""
import sys

try:
    import gi
    gi.require_version("EDataServer", "1.2")
    gi.require_version("ECal", "2.0")
    from gi.repository import EDataServer, ECal
except Exception as e:
    print(f"eds-refresh: missing/incompatible gi bindings: {e}", file=sys.stderr)
    sys.exit(1)

try:
    registry = EDataServer.SourceRegistry.new_sync(None)
except Exception as e:
    print(f"eds-refresh: cannot reach source registry: {e}", file=sys.stderr)
    sys.exit(1)

sources = registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR)
refreshed = 0
for source in sources:
    if not source.get_enabled():
        continue
    uid = source.get_uid()
    try:
        client = ECal.Client.connect_sync(
            source, ECal.ClientSourceType.EVENTS, 30, None
        )
    except Exception as e:
        print(f"eds-refresh: connect failed for {uid}: {e}", file=sys.stderr)
        continue
    try:
        client.refresh_sync(None)
        refreshed += 1
    except Exception as e:
        # Not all backends support refresh (local sources). Connecting alone
        # is enough to wake the factory and update the cache.
        print(f"eds-refresh: refresh skipped for {uid}: {e}", file=sys.stderr)

print(f"eds-refresh: refreshed {refreshed}/{len(sources)} calendar source(s)")
