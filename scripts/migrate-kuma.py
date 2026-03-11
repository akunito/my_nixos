#!/usr/bin/env python3
"""
Migrate Uptime Kuma monitors from TrueNAS (Home) to VPS (Public).

Connects to both instances, exports state, then migrates notifications, tags,
monitors (groups first), and status pages with deduplication and ID remapping.

Usage:
    export KUMA_SRC_URL="http://192.168.20.200:3001"
    export KUMA_SRC_USERNAME="akunito"
    export KUMA_SRC_PASSWORD="<password>"
    export KUMA_DST_URL="https://status.akunito.com"
    export KUMA_DST_JWT="<jwt-token>"

    python3 scripts/migrate-kuma.py --dry-run --verbose
    python3 scripts/migrate-kuma.py --export-only -o /tmp/kuma-export.json
    python3 scripts/migrate-kuma.py --verbose
"""

import argparse
import json
import os
import sys
from datetime import datetime

from uptime_kuma_api import UptimeKumaApi, MonitorType


# Monitor fields to copy (excludes internal/computed fields)
MONITOR_COPY_FIELDS = [
    "type", "name", "url", "method", "hostname", "port", "keyword",
    "invertKeyword", "maxretries", "interval", "retryInterval",
    "resendInterval", "upsideDown", "maxredirects", "accepted_statuscodes",
    "ignoreTls", "expiryNotification", "timeout", "description",
    "httpBodyEncoding", "body", "headers", "authMethod",
    "basic_auth_user", "basic_auth_pass", "authDomain", "authWorkstation",
    "proxyId", "dns_resolve_server", "dns_resolve_type", "packetSize",
    "mqttUsername", "mqttPassword", "mqttTopic", "mqttSuccessMessage",
    "databaseConnectionString", "databaseQuery",
    "docker_container", "docker_host",
    "radiusUsername", "radiusPassword", "radiusSecret",
    "radiusCalledStationId", "radiusCallingStationId",
    "game", "gamedigGivenPortOnly", "jsonPath", "expectedValue",
    "kafkaProducerBrokers", "kafkaProducerTopic", "kafkaProducerMessage",
    "kafkaProducerSsl", "kafkaProducerAllowAutoTopicCreation",
]


def log(msg, verbose_only=False, verbose=False):
    if verbose_only and not verbose:
        return
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")


def connect_source(url, username=None, password=None, jwt_token=None):
    """Connect to source Kuma (TrueNAS) via JWT token or username/password."""
    api = UptimeKumaApi(url, timeout=60, wait_events=2)
    if jwt_token:
        api.login_by_token(jwt_token)
    elif username and password:
        result = api.login(username, password)
        if result.get("tokenRequired"):
            api.disconnect()
            raise RuntimeError(
                "2FA is enabled on source. Use KUMA_SRC_JWT instead of username/password."
            )
    else:
        raise RuntimeError("Provide either JWT token or username/password for source.")
    return api


def connect_target(url, jwt_token):
    """Connect to target Kuma (VPS) via JWT token."""
    api = UptimeKumaApi(url, timeout=60, wait_events=2)
    api.login_by_token(jwt_token)
    return api


def export_state(api, label):
    """Export full state from a Kuma instance."""
    monitors = api.get_monitors()
    notifications = api.get_notifications()
    tags = api.get_tags()
    status_pages = api.get_status_pages()

    # Get full status page details (includes publicGroupList)
    status_page_details = []
    for page in status_pages:
        try:
            detail = api.get_status_page(page["slug"])
            status_page_details.append(detail)
        except Exception as e:
            log(f"  WARNING: Could not get details for status page '{page['slug']}': {e}")
            status_page_details.append(page)

    return {
        "label": label,
        "monitors": monitors,
        "notifications": notifications,
        "tags": tags,
        "status_pages": status_pages,
        "status_page_details": status_page_details,
        "monitor_count": len(monitors),
        "notification_count": len(notifications),
        "tag_count": len(tags),
        "status_page_count": len(status_pages),
    }


def find_matching_notification(src_notif, dst_notifications):
    """Find a matching notification in target by name and type."""
    for dn in dst_notifications:
        if dn.get("name") == src_notif.get("name") and dn.get("type") == src_notif.get("type"):
            return dn
    return None


def find_matching_tag(src_tag, dst_tags):
    """Find a matching tag in target by name."""
    for dt in dst_tags:
        if dt.get("name") == src_tag.get("name"):
            return dt
    return None


def find_matching_monitor(src_monitor, dst_monitors):
    """Find a matching monitor in target by name+type or url+type or hostname+type."""
    for dm in dst_monitors:
        # Match by name + type
        if dm.get("name") == src_monitor.get("name") and dm.get("type") == src_monitor.get("type"):
            return dm
        # Match by URL + type for HTTP/keyword monitors (skip empty URLs like 'https://')
        src_url = src_monitor.get("url", "")
        dst_url = dm.get("url", "")
        if (src_url and dst_url and len(src_url) > 10  # skip empty 'https://'
                and src_url == dst_url
                and dm.get("type") == src_monitor.get("type")):
            return dm
        # Match by hostname + type for ping monitors
        src_host = src_monitor.get("hostname", "")
        dst_host = dm.get("hostname", "")
        if (src_host and dst_host and src_host == dst_host
                and dm.get("type") == src_monitor.get("type")):
            return dm
    return None


def find_status_page_by_slug(slug, dst_status_pages):
    """Find a status page in target by slug."""
    for sp in dst_status_pages:
        if sp.get("slug") == slug:
            return sp
    return None


def build_monitor_params(monitor, id_map):
    """Build parameters for add_monitor from a source monitor dict."""
    params = {}
    for field in MONITOR_COPY_FIELDS:
        val = monitor.get(field)
        if val is not None:
            params[field] = val

    # Remap parent group ID
    if monitor.get("parent"):
        new_parent = id_map["monitors"].get(monitor["parent"])
        if new_parent:
            params["parent"] = new_parent

    # Remap notification IDs (can be dict {id: true/false} or list [id, ...])
    old_notif_list = monitor.get("notificationIDList")
    if old_notif_list:
        if isinstance(old_notif_list, dict):
            new_notif_list = {}
            for old_id_str, enabled in old_notif_list.items():
                new_id = id_map["notifications"].get(int(old_id_str))
                if new_id is not None:
                    new_notif_list[str(new_id)] = enabled
            if new_notif_list:
                params["notificationIDList"] = new_notif_list
        elif isinstance(old_notif_list, list):
            new_notif_list = {}
            for old_id in old_notif_list:
                new_id = id_map["notifications"].get(int(old_id))
                if new_id is not None:
                    new_notif_list[str(new_id)] = True
            if new_notif_list:
                params["notificationIDList"] = new_notif_list

    return params


def build_notification_params(notif):
    """Extract notification parameters for add_notification, rewriting SMTP for VPS."""
    # The notification dict from get_notifications() contains all fields directly
    params = {}
    # Copy all non-internal fields
    skip_fields = {"id", "userId", "isDefault", "active"}
    for key, val in notif.items():
        if key not in skip_fields and val is not None:
            params[key] = val

    # Rewrite SMTP settings for VPS context (localhost Postfix instead of Tailscale)
    if params.get("type") == "smtp":
        if params.get("smtpHost") in ("100.64.0.6", "100.64.0.6:25"):
            params["smtpHost"] = "localhost"
            params["smtpPort"] = 25
            # VPS Postfix trusts localhost — remove auth
            params.pop("smtpUsername", None)
            params.pop("smtpPassword", None)
            params["smtpSecure"] = False

    params["isDefault"] = notif.get("isDefault", False)
    return params


def remap_public_group_list(group_list, monitor_id_map):
    """Remap monitor IDs in status page publicGroupList."""
    remapped = []
    for group in group_list:
        new_group = {
            "name": group.get("name", ""),
            "weight": group.get("weight", 1),
        }
        new_monitors = []
        for mon_ref in group.get("monitorList", []):
            old_id = mon_ref.get("id")
            new_id = monitor_id_map.get(old_id)
            if new_id is not None:
                new_monitors.append({"id": new_id})
        new_group["monitorList"] = new_monitors
        remapped.append(new_group)
    return remapped


def migrate(src_api, dst_api, dry_run=False, verbose=False):
    """Run the full migration from source to target."""
    id_map = {
        "notifications": {},
        "tags": {},
        "monitors": {},
    }
    stats = {"created": 0, "skipped": 0, "errors": 0}

    # ── Export state ──────────────────────────────────────────────────
    log("Exporting source (TrueNAS) state...")
    src = export_state(src_api, "source_truenas")
    log(f"  Source: {src['monitor_count']} monitors, {src['notification_count']} notifications, "
        f"{src['tag_count']} tags, {src['status_page_count']} status pages")

    log("Exporting target (VPS) state...")
    dst = export_state(dst_api, "target_vps")
    log(f"  Target: {dst['monitor_count']} monitors, {dst['notification_count']} notifications, "
        f"{dst['tag_count']} tags, {dst['status_page_count']} status pages")

    # ── Phase 1: Notifications ────────────────────────────────────────
    log("\n=== Phase 1: Notifications ===")
    for notif in src["notifications"]:
        existing = find_matching_notification(notif, dst["notifications"])
        if existing:
            id_map["notifications"][notif["id"]] = existing["id"]
            log(f"  SKIP notification '{notif['name']}' (exists as #{existing['id']})", verbose_only=True, verbose=verbose)
            stats["skipped"] += 1
            continue

        params = build_notification_params(notif)
        log(f"  {'DRY-RUN ' if dry_run else ''}CREATE notification '{notif['name']}' (type={notif.get('type')})")
        if not dry_run:
            try:
                result = dst_api.add_notification(**params)
                new_id = result.get("id")
                id_map["notifications"][notif["id"]] = new_id
                log(f"    Created as #{new_id}", verbose_only=True, verbose=verbose)
                stats["created"] += 1
            except Exception as e:
                log(f"    ERROR: {e}")
                stats["errors"] += 1
        else:
            stats["created"] += 1

    # ── Phase 2: Tags ─────────────────────────────────────────────────
    log("\n=== Phase 2: Tags ===")
    for tag in src["tags"]:
        existing = find_matching_tag(tag, dst["tags"])
        if existing:
            id_map["tags"][tag["id"]] = existing["id"]
            log(f"  SKIP tag '{tag['name']}' (exists as #{existing['id']})", verbose_only=True, verbose=verbose)
            stats["skipped"] += 1
            continue

        log(f"  {'DRY-RUN ' if dry_run else ''}CREATE tag '{tag['name']}' (color={tag.get('color')})")
        if not dry_run:
            try:
                result = dst_api.add_tag(name=tag["name"], color=tag.get("color", "#000000"))
                new_id = result.get("id")
                id_map["tags"][tag["id"]] = new_id
                log(f"    Created as #{new_id}", verbose_only=True, verbose=verbose)
                stats["created"] += 1
            except Exception as e:
                log(f"    ERROR: {e}")
                stats["errors"] += 1
        else:
            stats["created"] += 1

    # ── Phase 3: Monitors (groups first, then children) ───────────────
    log("\n=== Phase 3: Monitors ===")
    groups = [m for m in src["monitors"] if m.get("type") == MonitorType.GROUP]
    non_groups = [m for m in src["monitors"] if m.get("type") != MonitorType.GROUP]

    # 3a: Groups
    log(f"  Migrating {len(groups)} monitor groups...")
    for monitor in groups:
        existing = find_matching_monitor(monitor, dst["monitors"])
        if existing:
            id_map["monitors"][monitor["id"]] = existing["id"]
            log(f"  SKIP group '{monitor['name']}' (exists as #{existing['id']})", verbose_only=True, verbose=verbose)
            stats["skipped"] += 1
            continue

        params = build_monitor_params(monitor, id_map)
        log(f"  {'DRY-RUN ' if dry_run else ''}CREATE group '{monitor['name']}'")
        if not dry_run:
            try:
                result = dst_api.add_monitor(**params)
                new_id = result.get("monitorID")
                id_map["monitors"][monitor["id"]] = new_id
                log(f"    Created as #{new_id}", verbose_only=True, verbose=verbose)
                stats["created"] += 1
            except Exception as e:
                log(f"    ERROR creating group '{monitor['name']}': {e}")
                stats["errors"] += 1
        else:
            stats["created"] += 1

    # 3b: Individual monitors
    log(f"  Migrating {len(non_groups)} individual monitors...")
    for monitor in non_groups:
        existing = find_matching_monitor(monitor, dst["monitors"])
        if existing:
            id_map["monitors"][monitor["id"]] = existing["id"]
            log(f"  SKIP monitor '{monitor['name']}' (exists as #{existing['id']})", verbose_only=True, verbose=verbose)
            stats["skipped"] += 1
            continue

        params = build_monitor_params(monitor, id_map)
        type_label = monitor.get("type", "unknown")
        target = monitor.get("url") or monitor.get("hostname") or ""
        log(f"  {'DRY-RUN ' if dry_run else ''}CREATE monitor '{monitor['name']}' (type={type_label}, target={target})")
        if not dry_run:
            try:
                result = dst_api.add_monitor(**params)
                new_id = result.get("monitorID")
                id_map["monitors"][monitor["id"]] = new_id
                log(f"    Created as #{new_id}", verbose_only=True, verbose=verbose)
                stats["created"] += 1

                # Re-associate tags
                for tag_assoc in monitor.get("tags", []):
                    new_tag_id = id_map["tags"].get(tag_assoc.get("tag_id"))
                    if new_tag_id:
                        try:
                            dst_api.add_monitor_tag(
                                tag_id=new_tag_id,
                                monitor_id=new_id,
                                value=tag_assoc.get("value", ""),
                            )
                        except Exception as e:
                            log(f"    WARNING: Could not add tag to monitor: {e}", verbose_only=True, verbose=verbose)

            except Exception as e:
                log(f"    ERROR creating monitor '{monitor['name']}': {e}")
                stats["errors"] += 1
        else:
            stats["created"] += 1

    # ── Phase 4: Status Pages ─────────────────────────────────────────
    log("\n=== Phase 4: Status Pages ===")
    for detail in src["status_page_details"]:
        slug = detail.get("slug", "")
        title = detail.get("title", slug)
        existing = find_status_page_by_slug(slug, dst["status_pages"])

        src_groups = detail.get("publicGroupList", [])
        remapped_groups = remap_public_group_list(src_groups, id_map["monitors"])

        if existing:
            log(f"  Status page '{slug}' exists in target — merging groups")
            if not dry_run:
                try:
                    existing_detail = dst_api.get_status_page(slug)
                    existing_groups = existing_detail.get("publicGroupList", [])
                    merged_groups = existing_groups + remapped_groups
                    dst_api.save_status_page(
                        slug=slug,
                        id=existing_detail["id"],
                        title=existing_detail.get("title", title),
                        publicGroupList=merged_groups,
                        description=existing_detail.get("description", ""),
                        customCSS=existing_detail.get("customCSS", ""),
                        showPoweredBy=existing_detail.get("showPoweredBy", False),
                    )
                    log(f"    Merged {len(remapped_groups)} groups into existing page")
                    stats["created"] += 1
                except Exception as e:
                    log(f"    ERROR merging status page '{slug}': {e}")
                    stats["errors"] += 1
            else:
                log(f"  DRY-RUN MERGE {len(remapped_groups)} groups into '{slug}'")
                stats["created"] += 1
        else:
            log(f"  {'DRY-RUN ' if dry_run else ''}CREATE status page '{slug}' ({title})")
            if not dry_run:
                try:
                    dst_api.add_status_page(title=title, slug=slug)
                    # Get the created page to obtain its id
                    created_page = dst_api.get_status_page(slug)
                    dst_api.save_status_page(
                        slug=slug,
                        id=created_page["id"],
                        title=title,
                        publicGroupList=remapped_groups,
                        description=detail.get("description", ""),
                        customCSS=detail.get("customCSS", ""),
                        showPoweredBy=detail.get("showPoweredBy", False),
                        icon=detail.get("icon", "/icon.svg"),
                    )
                    log(f"    Created with {len(remapped_groups)} groups")
                    stats["created"] += 1
                except Exception as e:
                    log(f"    ERROR creating status page '{slug}': {e}")
                    stats["errors"] += 1
            else:
                stats["created"] += 1

    return stats, id_map


def main():
    parser = argparse.ArgumentParser(description="Migrate Uptime Kuma monitors from TrueNAS to VPS")
    parser.add_argument("--dry-run", action="store_true", help="Show plan without making changes")
    parser.add_argument("--export-only", action="store_true", help="Only export data, no migration")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    parser.add_argument("--output", "-o", type=str, default="/tmp/kuma-migration-backup.json",
                        help="Path for export JSON (default: /tmp/kuma-migration-backup.json)")
    args = parser.parse_args()

    # Read credentials from environment
    src_url = os.environ.get("KUMA_SRC_URL")
    src_username = os.environ.get("KUMA_SRC_USERNAME")
    src_password = os.environ.get("KUMA_SRC_PASSWORD")
    src_jwt = os.environ.get("KUMA_SRC_JWT")
    dst_url = os.environ.get("KUMA_DST_URL")
    dst_jwt = os.environ.get("KUMA_DST_JWT")

    if not src_url:
        print("ERROR: Set KUMA_SRC_URL")
        sys.exit(1)
    if not src_jwt and not (src_username and src_password):
        print("ERROR: Set KUMA_SRC_JWT or (KUMA_SRC_USERNAME + KUMA_SRC_PASSWORD)")
        sys.exit(1)
    if not dst_url or not dst_jwt:
        print("ERROR: Set KUMA_DST_URL, KUMA_DST_JWT")
        sys.exit(1)

    # Connect to both instances
    log(f"Connecting to source: {src_url}")
    try:
        src_api = connect_source(src_url, username=src_username, password=src_password, jwt_token=src_jwt)
        log("  Source connected OK")
    except Exception as e:
        print(f"ERROR: Could not connect to source: {e}")
        sys.exit(1)

    log(f"Connecting to target: {dst_url}")
    try:
        dst_api = connect_target(dst_url, dst_jwt)
        log("  Target connected OK")
    except Exception as e:
        src_api.disconnect()
        print(f"ERROR: Could not connect to target: {e}")
        sys.exit(1)

    try:
        # Export state
        log("\n=== Exporting state for backup ===")
        src_state = export_state(src_api, "source_truenas")
        dst_state = export_state(dst_api, "target_vps")

        # Custom JSON serializer for enum types
        def json_serializer(obj):
            if hasattr(obj, "value"):
                return obj.value
            raise TypeError(f"Object of type {type(obj)} is not JSON serializable")

        backup = {
            "timestamp": datetime.now().isoformat(),
            "source": src_state,
            "target": dst_state,
        }
        with open(args.output, "w") as f:
            json.dump(backup, f, indent=2, default=json_serializer)
        log(f"Backup saved to {args.output}")

        if args.export_only:
            log("\n=== Export only mode — no migration performed ===")
            log(f"Source: {src_state['monitor_count']} monitors, {src_state['status_page_count']} status pages")
            log(f"Target: {dst_state['monitor_count']} monitors, {dst_state['status_page_count']} status pages")
            return

        # Run migration
        if args.dry_run:
            log("\n=== DRY RUN — no changes will be made ===")

        stats, id_map = migrate(src_api, dst_api, dry_run=args.dry_run, verbose=args.verbose)

        # Final report
        log("\n=== Migration Summary ===")
        log(f"  Created: {stats['created']}")
        log(f"  Skipped (duplicates): {stats['skipped']}")
        log(f"  Errors: {stats['errors']}")

        if not args.dry_run:
            # Refresh target state and report
            final_state = export_state(dst_api, "target_final")
            log(f"\n  Target now has: {final_state['monitor_count']} monitors, "
                f"{final_state['status_page_count']} status pages")

        if stats["errors"] > 0:
            log(f"\nWARNING: {stats['errors']} errors occurred. Review output above.")
            sys.exit(1)

    finally:
        src_api.disconnect()
        dst_api.disconnect()


if __name__ == "__main__":
    main()
