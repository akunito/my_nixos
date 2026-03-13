---
title: Revolut Enrichment Data
tags: [finance, revolut, enrichment]
updated: 2026-03-13
---

# Revolut Enrichment Data

Enrichment data supplements bank transactions imported via CSV with additional details from the Revolut API: merchant location, user comments, tags, recipient names, and localised descriptions.

## What enrichment provides

| Field | Source | Example |
|-------|--------|---------|
| `merchant_name` | `merchant.name` | "Biedronka" |
| `merchant_city` | `merchant.city` | "Gdansk" |
| `merchant_country` | `merchant.country` | "POL" |
| `recipient_name` | Parsed from `description` | "AGNIESZKA MAJA LYSZCZ" |
| `user_comment` | `comment` or `note` | "Groceries for the week" |
| `revolut_tag` | `tag` | "#shopping" |
| `localised_description` | `localisedDescription.params` | "Crux PLN" |

## Export process

The export uses a browser console script (`revolut-export.js`) that intercepts Revolut's XHR calls to capture authentication headers.

### Steps

1. Open [app.revolut.com](https://app.revolut.com) and log in
2. Open DevTools Console (F12 → Console tab)
3. Copy-paste `revolut-export.js` from the repo (`templates/finance-tagger/revolut-export.js`) and press Enter
4. **Click around in the app** (e.g. open transactions or accounts) — this triggers the XHR header capture (the script needs to intercept at least one API call to grab the `X-Device-Id` and auth token)
5. Wait for the script to paginate through all pockets (progress shown in console)
6. A JSON file downloads automatically when done (named `revolut-transactions-YYYY-MM-DD.json`)

### Why XHR interception?

Revolut's API requires a dynamic `X-Device-Id` header that changes per session. The script monkey-patches `XMLHttpRequest.prototype.open` and `.setRequestHeader` to capture these headers from the app's own requests, then reuses them for the export API calls.

### Rate limiting

The script waits 500ms between API requests to avoid rate-limiting blocks from Revolut.

## Upload & import

1. Go to the finance-tagger app → **Enrichment** tab
2. Upload the JSON file via the upload form
3. The importer parses each transaction, filters to relevant records, and stores them
4. Matching happens automatically by Revolut transaction ID

### Filtering rules

Only these transactions are imported:
- **State**: `COMPLETED` only (pending/declined/reverted are skipped)
- **Currencies**: PLN, EUR, GBP, USD
- **Types excluded**: `REWARD` (cashback entries are skipped)
- **Amounts**: Stored as cents in the API, converted to decimal on import

## Re-running for new transactions

Simply re-export and re-upload. The import is idempotent — existing records (matched by `revolut_id`) are skipped as duplicates. Only new transactions are added.

## Data notes

- `counterpart.name` is never populated in Revolut's API — recipient info for transfers is parsed from the `description` field (e.g., "To AGNIESZKA MAJA LYSZCZ")
- `localisedDescription.params` is always a list of `{'key': ..., 'value': ...}` dicts, not a plain dict
- Pocket-to-pocket transfers (e.g., "To PLN", "To EUR") are excluded from recipient extraction
- The `revolut_leg_id` is used together with `revolut_id` for precise matching
