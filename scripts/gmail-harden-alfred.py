#!/usr/bin/env python3
"""
Gmail hardening script for Alfred's OpenClaw account.

Sets up all security filters, verifies account settings, and reports status.
Run once after creating the Gmail account and OAuth credentials.

Prerequisites:
  1. Create Google Cloud project with Gmail API enabled
  2. Create OAuth 2.0 Desktop credentials, download client_secret_*.json
  3. pip install google-auth-oauthlib google-api-python-client

Usage:
  python3 gmail-harden-alfred.py --credentials /path/to/client_secret.json

After running: Change the Gmail password to revoke this script's access.
"""

import argparse
import json
import os
import sys
from pathlib import Path

try:
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError
except ImportError:
    print("ERROR: Missing dependencies. Run:")
    print("  pip install google-auth-oauthlib google-api-python-client")
    sys.exit(1)

# Gmail API scope — gmail.settings.basic for filters, gmail.readonly for verification
SCOPES = [
    "https://www.googleapis.com/auth/gmail.settings.basic",
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.labels",
]

ALFRED_EMAIL = "alfred5r67s7b53df3fsg57@gmail.com"

# ============================================================================
# FILTER DEFINITIONS
# ============================================================================

# Allowlisted senders — only these reach the inbox
ALLOWLIST_SENDERS = [
    "diego88aku@gmail.com",
    "*@github.com",
    "noreply@plane.akunito.com",
    "*@jellyseerr.akunito.com",
    "*@google.com",
    "*@googlemail.com",
    "*@accounts.google.com",
]

# Prompt injection patterns to catch in subject/body
PROMPT_INJECTION_PATTERNS = [
    "ignore previous",
    "ignore all",
    "system prompt",
    "you are now",
    "new instructions",
    "act as",
    "pretend to be",
    "forget everything",
    "disregard",
    "override",
    "jailbreak",
    "DAN",
    "do anything now",
    "ignore above",
    "ignore the above",
    "reveal your",
    "repeat after me",
    "execute command",
    "run command",
    "forward all",
    "send to",
    "exfiltrate",
    "base64",
    "eval(",
    "<script",
    "javascript:",
]


def authenticate(credentials_path: str) -> Credentials:
    """Authenticate with Gmail API via OAuth flow."""
    token_path = Path(credentials_path).parent / "token_alfred_harden.json"

    creds = None
    if token_path.exists():
        creds = Credentials.from_authorized_user_file(str(token_path), SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(credentials_path, SCOPES)
            creds = flow.run_local_server(
                port=0,
                open_browser=False,
                authorization_prompt_message=(
                    f"\n  Open this URL in an INCOGNITO window (log in as {ALFRED_EMAIL}):\n\n  {{url}}\n"
                ),
                login_hint=ALFRED_EMAIL,
            )
        token_path.write_text(creds.to_json())
        print(f"Token saved to {token_path}")
        print("IMPORTANT: Delete this token file after hardening is complete!")

    return creds


def ensure_labels(service) -> dict:
    """Create required labels if they don't exist. Returns label name→id map."""
    required_labels = ["allowed", "newsletters", "quarantine", "suspicious"]
    existing = service.users().labels().list(userId="me").execute()
    label_map = {l["name"]: l["id"] for l in existing.get("labels", [])}

    for label_name in required_labels:
        if label_name not in label_map:
            body = {
                "name": label_name,
                "labelListVisibility": "labelShow",
                "messageListVisibility": "show",
                "color": {
                    "allowed": {"textColor": "#0b4f30", "backgroundColor": "#a2dcc1"},
                    "newsletters": {"textColor": "#04502e", "backgroundColor": "#b9e4d0"},
                    "quarantine": {"textColor": "#662e37", "backgroundColor": "#fbc8d9"},
                    "suspicious": {"textColor": "#711a36", "backgroundColor": "#f7a7c0"},
                }.get(label_name, {"textColor": "#000000", "backgroundColor": "#ffffff"}),
            }
            result = service.users().labels().create(userId="me", body=body).execute()
            label_map[label_name] = result["id"]
            print(f"  Created label: {label_name} (id: {result['id']})")
        else:
            print(f"  Label exists: {label_name} (id: {label_map[label_name]})")

    return label_map


def create_filters(service, label_map: dict):
    """Create all 5 security filters."""
    # Get existing filters to avoid duplicates
    existing = service.users().settings().filters().list(userId="me").execute()
    existing_queries = set()
    for f in existing.get("filter", []):
        criteria = f.get("criteria", {})
        q = criteria.get("query", "") + criteria.get("from", "")
        existing_queries.add(q)

    filters_to_create = []

    # Filter 1: ALLOWLIST
    allowlist_from = " OR ".join(f"from:{s}" for s in ALLOWLIST_SENDERS)
    filters_to_create.append({
        "name": "ALLOWLIST",
        "body": {
            "criteria": {"from": " ".join(f"{{{s}}}" for s in ALLOWLIST_SENDERS)},
            "action": {
                "addLabelIds": [label_map["allowed"]],
                "removeLabelIds": ["SPAM"],
            },
        },
    })

    # Filter 2: NEWSLETTERS (placeholder — user adds specific senders later)
    filters_to_create.append({
        "name": "NEWSLETTERS",
        "body": {
            "criteria": {"from": "{newsletters-placeholder@example.com}"},
            "action": {
                "addLabelIds": [label_map["newsletters"]],
                "removeLabelIds": ["INBOX"],
            },
        },
    })

    # Filter 3: QUARANTINE (catch-all for non-allowlisted)
    quarantine_exclude = " ".join(f"-from:{s}" for s in ALLOWLIST_SENDERS)
    filters_to_create.append({
        "name": "QUARANTINE",
        "body": {
            "criteria": {"query": quarantine_exclude},
            "action": {
                "addLabelIds": [label_map["quarantine"]],
                "removeLabelIds": ["INBOX"],
            },
        },
    })

    # Filter 4: PROMPT INJECTION PATTERNS
    injection_query = " OR ".join(f'"{p}"' for p in PROMPT_INJECTION_PATTERNS)
    # Gmail filter query has a max length — split if needed
    filters_to_create.append({
        "name": "PROMPT_INJECTION",
        "body": {
            "criteria": {"query": injection_query},
            "action": {
                "addLabelIds": [label_map["suspicious"]],
                "removeLabelIds": ["INBOX"],
            },
        },
    })

    # Filter 5: LEAKED ALIAS TRAP (disposable +tmp- aliases)
    filters_to_create.append({
        "name": "LEAKED_ALIAS_TRAP",
        "body": {
            "criteria": {"to": f"{ALFRED_EMAIL.replace('@', '+tmp-*@')}"},
            "action": {
                "addLabelIds": [label_map["quarantine"]],
                "removeLabelIds": ["INBOX"],
            },
        },
    })

    # Create filters
    created = 0
    for f_def in filters_to_create:
        name = f_def["name"]
        body = f_def["body"]
        try:
            result = (
                service.users()
                .settings()
                .filters()
                .create(userId="me", body=body)
                .execute()
            )
            print(f"  Created filter: {name} (id: {result['id']})")
            created += 1
        except HttpError as e:
            if "Filter already exists" in str(e) or "already exists" in str(e):
                print(f"  Filter exists: {name} (skipped)")
            else:
                print(f"  ERROR creating {name}: {e}")

    return created


def verify_settings(service):
    """Verify account settings are properly hardened."""
    print("\n--- SETTINGS VERIFICATION ---")
    checks_passed = 0
    checks_total = 0

    # Check forwarding
    checks_total += 1
    try:
        fwd = (
            service.users()
            .settings()
            .getAutoForwarding(userId="me")
            .execute()
        )
        if not fwd.get("enabled", False):
            print("  [PASS] Auto-forwarding: DISABLED")
            checks_passed += 1
        else:
            print(f"  [FAIL] Auto-forwarding: ENABLED to {fwd.get('emailAddress')}")
            print("         ACTION: Disable at Settings → Forwarding and POP/IMAP")
    except HttpError:
        print("  [SKIP] Cannot check forwarding (insufficient scope)")

    # Check POP
    checks_total += 1
    try:
        pop = service.users().settings().getPop(userId="me").execute()
        if pop.get("accessWindow") == "disabled":
            print("  [PASS] POP: DISABLED")
            checks_passed += 1
        else:
            print(f"  [FAIL] POP: {pop.get('accessWindow')}")
            print("         ACTION: Disable at Settings → Forwarding and POP/IMAP")
    except HttpError:
        print("  [SKIP] Cannot check POP (insufficient scope)")

    # Check IMAP
    checks_total += 1
    try:
        imap = service.users().settings().getImap(userId="me").execute()
        if not imap.get("enabled", False):
            print("  [PASS] IMAP: DISABLED")
            checks_passed += 1
        else:
            print("  [FAIL] IMAP: ENABLED")
            print("         ACTION: Disable at Settings → Forwarding and POP/IMAP")
    except HttpError:
        print("  [SKIP] Cannot check IMAP (insufficient scope)")

    # Check vacation responder
    checks_total += 1
    try:
        vacation = (
            service.users()
            .settings()
            .getVacation(userId="me")
            .execute()
        )
        if not vacation.get("enableAutoReply", False):
            print("  [PASS] Vacation responder: OFF")
            checks_passed += 1
        else:
            print("  [FAIL] Vacation responder: ON")
            print("         ACTION: Disable at Settings → General → Vacation responder")
    except HttpError:
        print("  [SKIP] Cannot check vacation (insufficient scope)")

    # Check send-as aliases
    checks_total += 1
    try:
        send_as = service.users().settings().sendAs().list(userId="me").execute()
        aliases = send_as.get("sendAs", [])
        if len(aliases) <= 1:
            print(f"  [PASS] Send-as aliases: {len(aliases)} (only primary)")
            checks_passed += 1
        else:
            alias_list = [a["sendAsEmail"] for a in aliases]
            print(f"  [FAIL] Send-as aliases: {len(aliases)} — {alias_list}")
            print("         ACTION: Remove extra aliases at Settings → Accounts")
    except HttpError:
        print("  [SKIP] Cannot check send-as (insufficient scope)")

    # Check delegates
    checks_total += 1
    try:
        delegates = (
            service.users()
            .settings()
            .delegates()
            .list(userId="me")
            .execute()
        )
        delegate_list = delegates.get("delegates", [])
        if not delegate_list:
            print("  [PASS] Delegates: NONE")
            checks_passed += 1
        else:
            print(f"  [FAIL] Delegates: {[d['delegateEmail'] for d in delegate_list]}")
            print("         ACTION: Remove at Settings → Accounts → Grant access")
    except HttpError:
        print("  [SKIP] Cannot check delegates (insufficient scope)")

    # Summary
    print(f"\n  Settings: {checks_passed}/{checks_total} passed")
    return checks_passed, checks_total


def verify_filters(service, label_map: dict):
    """Verify all required filters exist."""
    print("\n--- FILTER VERIFICATION ---")
    existing = service.users().settings().filters().list(userId="me").execute()
    filters = existing.get("filter", [])

    required_labels = {"allowed", "quarantine", "suspicious"}
    found_labels = set()

    for f in filters:
        action = f.get("action", {})
        add_labels = action.get("addLabelIds", [])
        for label_id in add_labels:
            for name, lid in label_map.items():
                if lid == label_id:
                    found_labels.add(name)

    for req in required_labels:
        if req in found_labels:
            print(f"  [PASS] Filter targeting '{req}' label exists")
        else:
            print(f"  [FAIL] No filter targeting '{req}' label found!")

    print(f"\n  Total filters: {len(filters)}")
    print(f"  Required label coverage: {len(found_labels)}/{len(required_labels)}")
    return found_labels >= required_labels


def print_manual_checklist():
    """Print settings that must be checked manually via Gmail web UI."""
    print("\n--- MANUAL CHECKLIST (verify in Gmail web UI) ---")
    print(f"  Login to: https://mail.google.com (as {ALFRED_EMAIL})")
    print()
    print("  Settings → General:")
    print("    [ ] Conversation view: OFF")
    print("    [ ] Snippets: OFF")
    print("    [ ] External images: 'Ask before displaying'")
    print("    [ ] Vacation responder: OFF (verified via API above)")
    print()
    print("  Settings → Chat and Meet:")
    print("    [ ] Chat: OFF")
    print("    [ ] Meet: OFF")
    print()
    print("  Settings → Add-ons:")
    print("    [ ] Remove ALL add-ons")
    print()
    print("  Google Account → Security:")
    print("    [ ] 2FA: Enabled (TOTP, not SMS)")
    print("    [ ] Recovery email: diego88aku@gmail.com")
    print("    [ ] No phone number for recovery")
    print("    [ ] 'Less secure app access': OFF")
    print("    [ ] 'Third-party apps': Only openclaw-assistant OAuth app")
    print("    [ ] Consider: Advanced Protection Program enrollment")
    print()
    print("  AFTER HARDENING COMPLETE:")
    print("    [ ] Change Gmail password (revokes this script's token)")
    print("    [ ] Delete token file from this directory")
    print("    [ ] Remove gmail.settings.basic scope from OAuth app")


def main():
    parser = argparse.ArgumentParser(description="Harden Alfred's Gmail account")
    parser.add_argument(
        "--credentials",
        required=True,
        help="Path to OAuth client_secret_*.json file",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only verify settings, don't create filters",
    )
    args = parser.parse_args()

    if not os.path.exists(args.credentials):
        print(f"ERROR: Credentials file not found: {args.credentials}")
        sys.exit(1)

    print(f"=== Gmail Hardening for {ALFRED_EMAIL} ===\n")

    # Authenticate
    print("Authenticating...")
    creds = authenticate(args.credentials)
    service = build("gmail", "v1", credentials=creds)
    print("Authenticated successfully.\n")

    # Create labels
    print("--- LABELS ---")
    label_map = ensure_labels(service)

    if not args.dry_run:
        # Create filters
        print("\n--- CREATING FILTERS ---")
        created = create_filters(service, label_map)
        print(f"\n  Created {created} new filters")

    # Verify settings
    settings_passed, settings_total = verify_settings(service)

    # Verify filters
    filters_ok = verify_filters(service, label_map)

    # Manual checklist
    print_manual_checklist()

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"  Labels: OK")
    print(f"  Filters: {'OK' if filters_ok else 'INCOMPLETE — check above'}")
    print(f"  Settings: {settings_passed}/{settings_total} passed")
    if not args.dry_run:
        print(f"  Filters created: {created}")
    print()
    print("  NEXT STEPS:")
    print("  1. Complete manual checklist above")
    print("  2. Change Gmail password")
    print("  3. Delete the token file")
    print("  4. Set up n8n audit workflows (see plan Step 8g)")


if __name__ == "__main__":
    main()
