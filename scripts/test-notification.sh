#!/usr/bin/env bash

# Test script for email notification setup
# Usage: ./scripts/test-notification.sh [smtp_host] [to_email]

set -e

SMTP_HOST="${1:-192.168.8.89}"
TO_EMAIL="${2:-diego88aku@gmail.com}"
FROM_EMAIL="nixos@akunito.com"
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "Testing email notification setup..."
echo "  SMTP Host: $SMTP_HOST"
echo "  From: $FROM_EMAIL"
echo "  To: $TO_EMAIL"
echo ""

# Build email body
EMAIL_BODY="Subject: [TEST] Email notification test from $HOSTNAME
From: NixOS Test <$FROM_EMAIL>
To: $TO_EMAIL

This is a test email notification from $HOSTNAME.

Timestamp: $TIMESTAMP
SMTP Host: $SMTP_HOST

If you received this email, your notification setup is working correctly.

This is a test message.
"

# Test with basic sendmail command
echo "Sending test email..."
if command -v msmtp &> /dev/null; then
    echo "$EMAIL_BODY" | msmtp --host="$SMTP_HOST" --port=25 --from="$FROM_EMAIL" "$TO_EMAIL"
    echo "✓ Test email sent via msmtp"
elif command -v sendmail &> /dev/null; then
    echo "$EMAIL_BODY" | sendmail -t
    echo "✓ Test email sent via sendmail"
else
    echo "✗ Error: No mail transfer agent found (msmtp or sendmail)"
    echo "  Install with: nix-shell -p msmtp"
    exit 1
fi

echo ""
echo "Check your email at $TO_EMAIL to verify receipt."
