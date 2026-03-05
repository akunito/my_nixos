---
id: infrastructure.services.openclaw.channels
summary: "OpenClaw messaging channel integrations: 23+ platforms, configuration, and policies"
tags: [openclaw, channels, telegram, discord, matrix, whatsapp, slack, signal]
date: 2026-03-04
status: published
---

# OpenClaw Channels

## Supported Platforms (23+)

### Built-in Channels

| Channel | Auth Method | Key Details |
|---------|-------------|-------------|
| **Telegram** | Bot token (BotFather) | Fastest setup. Groups with mention gating. Voice notes. |
| **Discord** | Bot token + Gateway | Servers, channels, DMs, threads. Requires "Message Content Intent". |
| **WhatsApp** | QR pairing (Baileys) | Requires phone link. Disk-based state. Most popular channel. |
| **Signal** | signal-cli | Privacy-focused. Requires registered phone number. |
| **Slack** | Bolt SDK workspace app | Enterprise-grade. Channels, DMs, threads. |
| **Google Chat** | HTTP webhook | Google Workspace integration. |
| **iMessage** | BlueBubbles (recommended) | macOS server required. Legacy direct mode deprecated. |
| **IRC** | Standard IRC | Channels + DMs with pairing/allowlist. |
| **WebChat** | Built-in | Gateway UI at `http://127.0.0.1:18789/`. No external setup. |

### Plugin Channels (install via `openclaw plugins install`)

| Channel | Package | Notes |
|---------|---------|-------|
| **Matrix** | `@openclaw/matrix` | Self-hosted Synapse support, E2EE, federation |
| **Microsoft Teams** | Plugin | Bot Framework, enterprise |
| **Mattermost** | Plugin | Bot API + WebSocket |
| **Nextcloud Talk** | Plugin | Self-hosted Nextcloud chat |
| **LINE** | Plugin | Messaging API bot |
| **Feishu/Lark** | Plugin | WebSocket-based |
| **Nostr** | Plugin | Decentralized DMs via NIP-04 |
| **Synology Chat** | Plugin | Via outgoing+incoming webhooks |
| **Tlon** | Plugin | Urbit-based |
| **Twitch** | Plugin | Chat via IRC connection |
| **Zalo** | Plugin | Vietnam messenger (bot + personal) |
| **WeChat** | `@icesword760/openclaw-wechat` | Community plugin |

## Channel Configuration Pattern

All channels follow a consistent config pattern in `openclaw.json`:

```jsonc
{
  "channels": {
    "<channel>": {
      "dmPolicy": "pairing",           // pairing | allowlist | open | disabled
      "allowFrom": ["user_id"],        // Explicit allowlist (channel-specific IDs)
      "groups": {
        "*": {                          // Wildcard = all groups
          "requireMention": true        // Bot must be @mentioned in groups
        }
      }
    }
  }
}
```

## DM Policies

| Policy | Behavior | Security |
|--------|----------|----------|
| `pairing` | Unknown senders get time-limited pairing code (1hr, max 3 pending) | **Recommended** |
| `allowlist` | Block all unknown senders | Strict |
| `open` | Allow anyone (requires `"*"` in allowlist) | Risky |
| `disabled` | Ignore all inbound DMs | Maximum isolation |

## Telegram Setup

```bash
# 1. Create bot via @BotFather → /newbot → copy token
# 2. Add to OpenClaw
openclaw channels add telegram --token "BOT_TOKEN"
```

Config options:
- `channels.telegram.botToken` or env `TELEGRAM_BOT_TOKEN`
- `channels.telegram.groups."*".requireMention: true`
- `channels.telegram.allowFrom: ["user_id"]`
- `channels.telegram.webhookUrl` + `webhookSecret` (optional, for webhook mode)
- Voice notes: auto-transcribed if `tools.media.audio.enabled: true`
- Group preflight: transcribes voice before checking mentions

**How it works**: Bot connects **outbound** from your server to Telegram's API. Your phone talks to Telegram servers normally. No inbound ports needed.

## Discord Setup

```bash
# 1. Create app at discord.com/developers → Bot → copy token
# 2. Enable "Message Content Intent" in Bot settings
# 3. Invite to server with Send Messages + Read History permissions
# 4. Add to OpenClaw
openclaw channels add discord --token "BOT_TOKEN"
```

Config options:
- `channels.discord.dmPolicy: "pairing"`
- Thread support with `/focus` and `/unfocus` commands
- `/session idle <duration>` for auto-unfocus
- TTS registered as `/voice` (avoids built-in Discord `/tts` conflict)

## Matrix Setup (Plugin)

```bash
openclaw plugins install @openclaw/matrix
```

```jsonc
{
  "channels": {
    "matrix": {
      "homeserver": "http://host.docker.internal:8008",
      "userId": "@bot:matrix.example.com",
      "accessToken": "ACCESS_TOKEN",
      "dm": { "policy": "pairing" },
      "autoJoin": "allowlist",
      "autoJoinAllowlist": ["@user:matrix.example.com"],
      "groupPolicy": "allowlist",
      "encryption": true
    }
  }
}
```

**Note**: Matrix plugin uses `homeserver` (not `homeserverUrl`), `dm.policy` (nested), `autoJoin` as enum (`"always"`, `"allowlist"`, `"off"`).

Features: Federation, E2EE via `encryption: true` (Rust crypto SDK, requires verification), threads, reactions, rich media, multi-account support. For self-hosted Synapse: connect via `host.docker.internal:8008` (localhost, no external traffic).

## WhatsApp Setup

```bash
openclaw channels add whatsapp
# Scan QR code from terminal
```

- Requires QR pairing with phone (Baileys library)
- State stored at `~/.openclaw/credentials/whatsapp/`
- Public inbound DMs require `dmPolicy: "open"` + `"*"` in allowlist
- Voice notes auto-transcribed

## Multi-Channel Routing

All channels run simultaneously. The gateway routes based on:
- Inbound: channel adapter identifies source → session isolation → agent routing
- Outbound: cron/webhook `channel` parameter selects delivery target
- Cross-channel: sub-agents can announce to different channels than the trigger

## Group Chat Behavior

- Default: `requireMention: true` — bot only responds when @mentioned
- Voice notes in groups: preflight transcription checks mentions before processing
- Disable per-group: `channels.<ch>.groups.<chatId>.disableAudioPreflight: true`
