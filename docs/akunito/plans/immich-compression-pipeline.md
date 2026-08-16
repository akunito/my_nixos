---
title: Immich library compression pipeline (videos + images)
status: IN PROGRESS — building, not yet run on data
owner: akunito
created: 2026-08-13
---

# Immich library compression — design & runbook

## Goal
Re-encode/compress the existing Immich library (all **38,867** assets: 36,721 IMAGE + 2,146 VIDEO) to reduce storage with minimal visible quality loss, **preserving albums, named faces, favorites, descriptions, stacks, and timeline**. Then keep new uploads compressed automatically.

## Why this is non-trivial (Immich v3 constraints)
- Immich's Postgres DB is the source of truth (checksum, size, path, all organization).
- v3 **removed** the `replaceAsset` API (`PUT /assets/:id/original`) — no supported in-place file swap.
- Moving assets to an **external library** re-imports them = **loses albums/faces/favorites**. Not acceptable.
- Therefore the only way to keep associations is to swap the file **and** update the asset's DB row (`checksum`, `fileSizeInByte`) to match. This is **unsupported DB surgery** — de-risked by doing it in a full clone first, validating, then promoting.

## Model: full parallel clone → validate → promote (never mutate prod until cutover)
1. **Clone** prod Immich into `immich-dev` (separate stack, port 2284, `pictures-dev.local.akunito.com`). Clone = full DB (694 MB) + `upload/` files (~74 G). `thumbs/` + `encoded-video/` excluded (dev regenerates them).
2. **Process** the clone with the pipeline below (compress files + DB update).
3. **Validate** the dev instance in its own web UI: images display, videos play, albums/faces/favorites intact, no "missing file" / integrity errors.
4. **Promote** (cutover): stop prod, swap prod's library dir + DB for the processed dev ones, restart, verify. Prod's pre-compression library is archived, plus the NAS backup remains.
5. **Auto-compress new uploads** (ongoing service): nightly job finds assets created after cutover and runs the same per-asset pipeline in place.
6. **Cleanup**: after a confidence window, remove the archived pre-compression library; the fresh compressed backup overwrites the NAS repo and old snapshots age out via retention (**keep ≥1 pre-compression snapshot until fully confident**).

## Per-asset pipeline (runs against the dev clone)
For each asset (`id`, `type`, `originalPath`, `originalFileName`, `checksum`, `asset_exif.fileSizeInByte`):
1. Map `originalPath` (`/data/...`) → host dev-library path. Skip if already in the processed-log (idempotent/resumable).
2. **Compress to a temp file, KEEPING the same extension/container** (so `originalPath`/`originalFileName` never change — only `checksum` + `fileSizeInByte` do):
   - **VIDEO** → `ffmpeg -i src -map_metadata 0 -map 0 -c:v libx265 -crf 26 -preset medium -tag:v hvc1 -c:a copy -movflags +faststart out.<same-ext>` (H.265; ~40–60% smaller; audio copied; rotation/metadata preserved). AV1 (`libsvtav1 -crf 30`) optional later.
   - **JPEG** → re-encode quality ~85 preserving EXIF (`jpegoptim --max=85 --strip-none`, or mozjpeg). Modest gain.
   - **PNG** → `oxipng -o4 --strip safe` (lossless).
   - **HEIC / RAW / other** → **skip** (already efficient / compat risk).
3. **Validate temp**: decodes cleanly (`ffprobe`/`identify`); dimensions match; video duration within ±1s and has expected streams; **size strictly smaller** (else keep original, mark skipped).
4. Compute `new_sha1 = sha1(temp)`, `new_size = bytes(temp)`.
5. Atomically replace original at the same path (`mv temp path`).
6. DB update (dev): `UPDATE asset SET checksum = decode('<hex>','hex') WHERE id = :id;`  `UPDATE asset_exif SET "fileSizeInByte" = :n WHERE "assetId" = :id;`
7. Append to processed-log.
After the batch: trigger dev Immich **Regenerate Thumbnails** + **Transcode Video** jobs (or clear `thumbs/`+`encoded-video/`), then validate the UI.

## CRITICAL pre-flight check (Phase 1 gate)
Before trusting any DB write: pick 3 existing assets, compute `sha1` of their files on disk, and confirm it equals `encode(asset.checksum,'hex')` in the DB. This proves Immich's checksum = SHA-1 and that our `decode(hex)` write format is correct. **If it doesn't match, STOP** — the whole approach depends on this.

## Tooling
Host has no media tools; provide ephemerally via `nix shell nixpkgs#ffmpeg nixpkgs#jpegoptim nixpkgs#oxipng nixpkgs#exiftool nixpkgs#imagemagick -c <script>`. DB via `psql`. Pipeline is a Python or Bash script with dry-run, resume, per-asset logging, and a hard stop on any validation failure.

## Safety gates / rollback
- Prod library is **never modified** until the validated promote step.
- Pre-compression NAS snapshot `dfeed3b6` (2026-08-09, 120.7 G) is the ultimate net; take a fresh one immediately before promote.
- Every asset: compress→validate→replace→DB-update is per-asset atomic and resumable; a failure skips that asset (keeps original), never corrupts.
- Keep the archived pre-compression prod library on disk until a confidence window passes.

## Open decisions
- Video codec: H.265 (safe, universal) vs AV1 (smaller, slower, newer). Default H.265 CRF 26.
- Image handling: whether to touch JPEGs at all (low gain, high op-count) — reconsider after seeing video savings.
- CRF/quality tuning after a sample batch shows real size/quality tradeoff.
