# Skill: Media Requests & Watch History (Jellyseerr + Jellyfin)

## Purpose
Search for movies/TV shows, manage media requests via Jellyseerr, and check watch history from Jellyfin.

## How to Access
```
exec /home/node/.openclaw/bin/mcp call jellyseerr.<tool_name> [key=value ...]
```

## Available Tools

### Search & Discovery
- `jellyseerr.search_media` query=TEXT — Search movies and TV shows
- `jellyseerr.get_trending` type=movie|tv — Get trending movies/shows
- `jellyseerr.get_discover` type=movie|tv — Discover popular movies/TV

### Requesting Media
- `jellyseerr.request_media` media_type=movie|tv title=TEXT — Request a movie or TV show

### Request Management
- `jellyseerr.get_requests` — List media requests (take, skip, filter options)
- `jellyseerr.get_request` request_id=ID — Get a specific request

### Watch History & Library (Jellyfin)
- `jellyseerr.get_watch_history` type=Movie|Series|Movie,Series limit=20 — Get Aku's watched movies/shows
- `jellyseerr.get_library_recent` limit=20 — Get recently added media to the library

## CRITICAL: Requesting Media
- **ALWAYS** provide `title` when calling `request_media`. The tool will search for the correct TMDB ID automatically.
- **NEVER** guess or memorize TMDB IDs — they are numeric and impossible to recall correctly.
- For TV shows, seasons are auto-populated if not specified. All available seasons are requested by default.
- Example: `jellyseerr.request_media media_type=tv title="The Witcher"`
- Example: `jellyseerr.request_media media_type=movie title="Interstellar"`

## Rate Limits
- 20 requests per hour (write operations)
