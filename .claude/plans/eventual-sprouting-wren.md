---
id: plans.rss-ai-upgrade
summary: Migrate FreshRSS to Miniflux, add feeds, deploy miniflux-ai with Gemini
tags: [infrastructure, vps, docker, rss, ai]
date: 2026-02-23
status: draft
---

# RSS & AI News Aggregation Upgrade

## Context

FreshRSS runs on VPS_PROD (256MB, SQLite, port 8082) but has no AI capabilities. Goals:
1. Migrate to Miniflux (leaner Go-based reader, uses existing PostgreSQL 17)
2. Add RSS feeds: Linux, self-hosting, NixOS, security/privacy, IPTorrents, international news
3. Deploy miniflux-ai with Gemini API for daily AI summaries
4. Keep full RSS reading available -- AI summaries are additive, not a replacement

## Architecture

```
RSS Feeds ──► Miniflux (full reader + API) ──► miniflux-ai (AI processing)
                 port 8084                         port 8085 (internal)
                 PostgreSQL 17                     Gemini API
                 news.akunito.com                  config.yml-based
                 ▲                                 │
                 │                                 │
                 └── subscribes to ◄── /rss/ai-news (daily digest feed)
```

**How it works**: Miniflux is your full RSS reader (read any article in full). miniflux-ai runs alongside it and:
- Prepends AI summaries to each article (visible when you open an article in Miniflux)
- Generates daily digest feeds at scheduled times (07:30, 18:00, 22:00)
- The digest is published as an RSS feed that Miniflux subscribes to

**Note on feedback**: miniflux-ai uses static interest prompts (no ML-based preference learning). Tuning is done by editing the config.yml prompts and agent allow/deny lists. This is a limitation -- if you later want active feedback learning, auto-news would be the upgrade path.

## RSS Feeds to Add

**Linux** (category: "Linux"):
- `https://lwn.net/headlines/rss` -- LWN.net
- `https://www.phoronix.com/rss.php` -- Phoronix
- `https://linuxunplugged.com/rss` -- Linux Unplugged
- `https://itsfoss.com/feed/` -- It's FOSS

**NixOS** (category: "NixOS"):
- `https://discourse.nixos.org/latest.rss` -- NixOS Discourse
- `https://weekly.nixos.org/feeds/all.rss.xml` -- NixOS Weekly
- `https://www.reddit.com/r/NixOS/.rss` -- r/NixOS

**Self-hosting** (category: "Self-hosting"):
- `https://selfh.st/rss/` -- SelfHosted newsletter
- `https://www.reddit.com/r/selfhosted/.rss` -- r/selfhosted
- `https://noted.lol/rss/` -- Noted blog
- `https://perfectmediaserver.com/feed.xml` -- Perfect Media Server

**Security/Privacy** (category: "Security"):
- `https://krebsonsecurity.com/feed/` -- Krebs on Security
- `https://feeds.feedburner.com/TheHackersNews` -- The Hacker News
- `https://www.privacyguides.org/en/feed_rss_created.xml` -- Privacy Guides

**IPTorrents** (category: "Torrents"):
- User must provide personal RSS URL from IPTorrents (Settings -> RSS -> copy feed URL)

**International News** (category: "World News"):
- `https://feeds.bbci.co.uk/news/world/rss.xml` -- BBC World
- `https://rss.nytimes.com/services/xml/rss/nyt/World.xml` -- NYT World
- `https://www.aljazeera.com/xml/rss/all.xml` -- Al Jazeera
- `https://feeds.reuters.com/reuters/worldNews` -- Reuters World

## Implementation Phases

### Phase 1: NixOS Config -- Database & Secrets

**`profiles/VPS_PROD-config.nix`** -- add miniflux database + credentials:
```nix
# Line ~82: Add password
dbMinifluxPassword = secrets.dbMinifluxPassword;

# Line ~93: Add database
postgresqlServerDatabases = [ "plane" "rails_database_prod" "matrix" "miniflux" ];

# Line ~94-110: Add user
{
  name = "miniflux";
  passwordFile = "/etc/secrets/db-miniflux-password";
  ensureDBOwnership = true;
}

# Line ~233: Add stacks (keep freshrss temporarily)
{ name = "miniflux"; path = "miniflux"; }
{ name = "miniflux-ai"; path = "miniflux-ai"; }

# Line ~203: Add Prometheus target (Miniflux exposes /metrics natively)
{ name = "miniflux"; host = "127.0.0.1"; port = 8084; }

# Line ~214: Add blackbox probe
{ name = "miniflux"; url = "https://news.${secrets.publicDomain}"; }
```

**`secrets/domains.nix`** -- add (git-crypt encrypted):
```nix
dbMinifluxPassword = "GENERATE_STRONG_PASSWORD";
```

**`system/app/database-secrets.nix`** -- add block (follows existing plane/matrix pattern):
```nix
(lib.mkIf ((systemSettings.postgresqlServerEnable or false) && (systemSettings.dbMinifluxPassword or "") != "") {
  "secrets/db-miniflux-password" = {
    text = systemSettings.dbMinifluxPassword;
    mode = "0440";
    user = "root";
    group = "postgres";
  };
})
```

### Phase 2: Deploy Miniflux Container

Create `~/.homelab/miniflux/docker-compose.yml` on VPS:
```yaml
services:
  miniflux:
    image: miniflux/miniflux:latest
    container_name: miniflux
    restart: unless-stopped
    ports:
      - "127.0.0.1:8084:8080"
    environment:
      - DATABASE_URL=postgres://miniflux:${DB_PASSWORD}@host.docker.internal:5432/miniflux?sslmode=disable
      - RUN_MIGRATIONS=1
      - CREATE_ADMIN=1
      - ADMIN_USERNAME=akunito
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - BASE_URL=https://news.${DOMAIN}
      - POLLING_FREQUENCY=60
      - BATCH_SIZE=100
      - POLLING_PARSING_ERROR_LIMIT=0
      - METRICS_COLLECTOR=1
      - METRICS_ALLOWED_NETWORKS=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12
    extra_hosts:
      - "host.docker.internal:host-gateway"
    mem_limit: 256m
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "miniflux", "-healthcheck", "auto"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - proxy

networks:
  proxy:
    external: true
```

Create `~/.homelab/miniflux/.env` with actual values for DB_PASSWORD, ADMIN_PASSWORD, DOMAIN.

Configure Cloudflare tunnel route: `news.akunito.com` -> `127.0.0.1:8084`.

### Phase 3: Migrate FreshRSS -> Miniflux

1. Export OPML: `docker exec freshrss php /var/www/FreshRSS/cli/export-opml-for-user.php --user akunito > feeds.opml`
2. Import into Miniflux via web UI (Settings -> Import -> upload OPML)
3. Verify feeds fetching correctly
4. Keep FreshRSS running 2 weeks as rollback

### Phase 4: Add New RSS Feeds

Add all feeds from the list above via Miniflux web UI, organized into categories.

### Phase 5: Deploy miniflux-ai with Gemini

Create `~/.homelab/miniflux-ai/docker-compose.yml` on VPS:
```yaml
services:
  miniflux_ai:
    container_name: miniflux_ai
    image: ghcr.io/qetesh/miniflux-ai:0.9.3
    restart: unless-stopped
    environment:
      TZ: Europe/Warsaw
    volumes:
      - ./config.yml:/app/config.yml
      - ./entries.json:/app/entries.json
    mem_limit: 256m
    security_opt:
      - no-new-privileges:true
    networks:
      - proxy

networks:
  proxy:
    external: true
```

Create `~/.homelab/miniflux-ai/config.yml`:
```yaml
log_level: "INFO"

miniflux:
  base_url: http://miniflux:8080
  api_key: MINIFLUX_API_KEY_HERE
  schedule_interval: 15

llm:
  provider: gemini
  base_url: https://generativelanguage.googleapis.com
  api_key: YOUR_GEMINI_API_KEY
  model: gemini-2.5-flash
  timeout: 60
  max_workers: 4
  RPM: 15  # Gemini free tier limit

ai_news:
  url: http://miniflux_ai
  schedule:
    - "07:30"
    - "18:00"
    - "22:00"
  prompts:
    greeting: "According to the current date and 24-hour time, generate a friendly greeting."
    summary: "You are a professional news summary assistant. Generate concise summaries focusing on: linux, nixos, self-hosting, homelab, docker, networking, security, open-source, AI, privacy, international affairs."
    summary_block: "You are a professional news summary assistant. Categorize the news into these topics: Linux & NixOS, Self-hosting & Homelab, Security & Privacy, Technology, World News. For each category, list the most important items with one-line summaries."

agents:
  summary:
    title: '֎ AI summary:'
    prompt: '${content} \n---\nSummarize the above content in three sentences, highlighting key takeaways.'
    style_block: true
    deny_list: []
    allow_list: []

  translate:
    title: "🌐 Translation:"
    prompt: "Translate the following to English if not already in English. If already English, respond with 'Already in English'. \n\n${content}"
    style_block: false
    deny_list: []
    allow_list:
      - "https://www.aljazeera.com/*"
```

Create empty `~/.homelab/miniflux-ai/entries.json`: `echo '[]' > entries.json`

After deployment, generate a Miniflux API key (Settings -> API Keys) and update config.yml.

Then in Miniflux, subscribe to `http://miniflux_ai/rss/ai-news` to receive daily AI digests as a feed.

### Phase 6: Deploy NixOS + Start Containers

```bash
# 1. Commit & push locally (NixOS config changes)
git add profiles/VPS_PROD-config.nix system/app/database-secrets.nix secrets/domains.nix
git commit -m "feat(vps): add Miniflux + miniflux-ai database and Docker stacks"
git push

# 2. Deploy NixOS (creates PostgreSQL database + secrets)
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"

# 3. Create Docker compose dirs and files on VPS
# (scp or create manually via SSH)

# 4. Start containers
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.homelab/miniflux && docker compose up -d"
# After OPML import + API key generation:
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.homelab/miniflux-ai && docker compose up -d"
```

### Phase 7: Update Documentation

- `docs/akunito/infrastructure/INFRASTRUCTURE.md` -- add Miniflux + miniflux-ai to VPS Docker list
- `docs/akunito/infrastructure/services/vps-services.md` -- replace FreshRSS with Miniflux section, add AI service
- `docs/akunito/infrastructure/services/homelab-stack.md` -- update stack list

### Phase 8: Cleanup (after 2 weeks)

- Remove `freshrss` from `homelabDockerStacks` in VPS_PROD-config.nix
- Stop FreshRSS: `docker compose -f ~/.homelab/freshrss/docker-compose.yml down`
- Remove FreshRSS blackbox probe
- Update Cloudflare tunnel (remove or redirect freshrss.akunito.com -> news.akunito.com)

## RAM Budget

| Component | RAM |
|-----------|-----|
| Miniflux | ~50 MB |
| miniflux-ai | ~256 MB |
| FreshRSS (removed after 2 weeks) | -256 MB |
| **Net change** | **~50 MB** |

VPS stays at ~18 GB used / 32 GB total. Plenty of headroom.

## Verification

1. `https://news.akunito.com` loads Miniflux, login works
2. All imported + new feeds fetching correctly (check error count in Miniflux)
3. Articles show AI summaries prepended (open any article after miniflux-ai processes it)
4. AI news digest feed appears in Miniflux (subscribe to `http://miniflux_ai/rss/ai-news`)
5. Digests generated at 07:30, 18:00, 22:00 (check `docker logs miniflux_ai`)
6. Prometheus scraping Miniflux metrics: `curl localhost:8084/metrics`
7. Blackbox probe green for `news.akunito.com`
8. FreshRSS still accessible as rollback at `freshrss.akunito.com` during transition

## Files to Modify

| File | Changes |
|------|---------|
| `profiles/VPS_PROD-config.nix` | Add miniflux DB, user, password, Docker stacks, Prometheus targets, blackbox probe |
| `system/app/database-secrets.nix` | Add miniflux password deployment block |
| `secrets/domains.nix` | Add `dbMinifluxPassword` |
| `docs/akunito/infrastructure/INFRASTRUCTURE.md` | Update VPS container list |
| `docs/akunito/infrastructure/services/vps-services.md` | Replace FreshRSS with Miniflux + miniflux-ai |
| `docs/akunito/infrastructure/services/homelab-stack.md` | Update stack list |
