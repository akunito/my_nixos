#!/usr/bin/env bash
# Generate calendar_mcp_token.json from secrets/domains.nix
# Run on VPS: bash ~/.dotfiles/scripts/generate-calendar-token.sh

set -euo pipefail

SECRETS="${HOME}/.dotfiles/secrets/domains.nix"
OUTPUT="${HOME}/.openclaw/credentials/calendar_mcp_token.json"

if [ ! -f "$SECRETS" ]; then
  echo "ERROR: $SECRETS not found"
  exit 1
fi

CLIENT_ID=$(grep 'googleCalendarClientId' "$SECRETS" | sed 's/.*= "//;s/".*//')
CLIENT_SECRET=$(grep 'googleCalendarClientSecret' "$SECRETS" | sed 's/.*= "//;s/".*//')
REFRESH_TOKEN=$(grep 'googleCalendarRefreshToken' "$SECRETS" | sed 's/.*= "//;s/".*//')

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ] || [ -z "$REFRESH_TOKEN" ]; then
  echo "ERROR: Could not extract Google Calendar credentials from $SECRETS"
  echo "Make sure secrets/domains.nix is decrypted (git-crypt unlock)"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

cat > "$OUTPUT" << EOF
{
  "client_id": "$CLIENT_ID",
  "client_secret": "$CLIENT_SECRET",
  "refresh_token": "$REFRESH_TOKEN",
  "token_uri": "https://oauth2.googleapis.com/token",
  "scopes": ["https://www.googleapis.com/auth/calendar", "https://www.googleapis.com/auth/calendar.events"]
}
EOF

chmod 600 "$OUTPUT"
echo "Created $OUTPUT"
