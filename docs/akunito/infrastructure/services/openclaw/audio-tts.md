---
id: infrastructure.services.openclaw.audio
summary: "OpenClaw voice transcription, text-to-speech, and voice wake"
tags: [openclaw, audio, voice, transcription, whisper, tts, elevenlabs]
date: 2026-03-04
status: published
---

# OpenClaw Audio & TTS

## Voice Transcription (Inbound)

OpenClaw automatically transcribes voice messages from Telegram, Discord, WhatsApp, Matrix, etc.

### Auto-Detection Priority (no config needed)

Without explicit configuration, OpenClaw tries in order:
1. Local CLI tools: `sherpa-onnx-offline`, `whisper-cli`, `whisper` Python package
2. Gemini CLI (file reading)
3. Provider keys: OpenAI → Groq → Deepgram → Google

Disable: `tools.media.audio.enabled: false`

### Explicit Configuration

```jsonc
{
  "tools": {
    "media": {
      "audio": {
        "enabled": true,
        "maxBytes": 20971520,              // 20MB max file size
        "echoTranscript": true,            // Show transcript in chat
        "echoFormat": "Transcript: \"{transcript}\"",
        "models": [
          // Provider-based (cloud API)
          { "provider": "openai", "model": "gpt-4o-mini-transcribe" },
          { "provider": "openai", "model": "gpt-4o-transcribe" },
          { "provider": "groq", "model": "whisper-large-v3-turbo" },
          { "provider": "deepgram", "model": "nova-3" },
          { "provider": "mistral", "model": "voxtral-mini-latest" },

          // CLI-based (local, fallback)
          {
            "type": "cli",
            "command": "whisper",
            "args": ["--model", "base", "{{MediaPath}}"],
            "timeoutSeconds": 60
          }
        ]
      }
    }
  }
}
```

### Provider Comparison

| Provider | Model | Accuracy | Speed | Cost |
|----------|-------|----------|-------|------|
| OpenAI | `gpt-4o-mini-transcribe` | 95-97% | <1s | $0.006/min |
| OpenAI | `gpt-4o-transcribe` | 97%+ | <1s | $0.012/min |
| Groq | `whisper-large-v3-turbo` | 95-97% | <300ms | Free tier |
| Deepgram | `nova-3` | 95-96% | <300ms | $0.0077/min |
| Local Whisper | `base` (74M) | 95% | 5-15s/min on CPU | Free |
| Local Whisper | `small` (244M) | 96% | 20-30s/min on CPU | Free |

**Recommendation for VPS**: Groq (free, fast) as primary → OpenAI as fallback → local Whisper as last resort.

### Limits & Behavior

- Min file size: 1024 bytes (smaller discarded)
- Max file size: 20MB default (`maxBytes`)
- Max transcript length: unlimited default (`maxChars`)
- CLI stdout cap: 5MB
- Default timeout: 60s per CLI execution
- Multiple attachments: `tools.media.audio.attachments.mode: "all"`

### Scope Gating

Restrict transcription by chat type:
```jsonc
{
  "scope": {
    "default": "allow",
    "rules": [{ "action": "deny", "match": { "chatType": "group" } }]
  }
}
```

### Group Chat Mention Detection

When `requireMention: true`, OpenClaw performs **preflight transcription** before checking mentions — voice notes can satisfy mention requirements. Disable per-group: `disableAudioPreflight: true`.

### Voice → Structured Data Flow

1. User sends voice memo via Telegram/Discord
2. OpenClaw auto-transcribes (provider chain)
3. Transcript echoed: `Transcript: "I had an idea for..."`
4. AI processes transcript as regular text
5. Can create Plane tickets, calendar events, etc. from voice

---

## Text-to-Speech (Outbound)

### Providers

| Provider | API Key | Notes |
|----------|---------|-------|
| **ElevenLabs** | `ELEVENLABS_API_KEY` or `XI_API_KEY` | Advanced voice customization |
| **OpenAI** | `OPENAI_API_KEY` | Full-featured |
| **Edge TTS** | None (free) | Microsoft neural, no SLA, fallback default |

### Configuration

Auto-TTS is **disabled by default**:

```jsonc
{
  "messages": {
    "tts": {
      "auto": "off",              // off | always | inbound | tagged
      "maxTextLength": 5000,      // Character limit
      "timeoutMs": 30000,
      "summaryModel": "provider/model",  // Summarize long replies before TTS
      "mode": "final"             // final | all (include tool replies?)
    }
  }
}
```

### ElevenLabs Voice Settings

```jsonc
{
  "stability": 0.5,
  "similarityBoost": 0.75,
  "style": 0.0,
  "useSpeakerBoost": true,
  "speed": 1.0,
  "languageCode": "en"
}
```

### Audio Output Formats

| Channel | Format |
|---------|--------|
| Telegram | Opus voice note (48kHz/64kbps, round bubble UI) |
| Other channels | MP3 (44.1kHz/128kbps) |
| Edge TTS | Configurable (default MP3) |

### Slash Commands

- `/tts off|always|inbound|tagged` — Toggle modes
- `/tts status` — Current settings
- `/tts provider {name}` — Switch provider
- `/tts audio {text}` — One-off audio generation
- Discord: registered as `/voice` (avoids built-in `/tts` conflict)

### Model-Driven Overrides

Models can emit `[[tts:...]]` directives in replies:
```
[[tts:voiceId=pMsXgVXv3BLzUgSXRplE model=eleven_v3 speed=1.1]]
```

---

## Voice Wake

Trigger words that activate listening on connected devices (macOS, iOS):

```json
// ~/.openclaw/settings/voicewake.json
{ "triggers": ["openclaw", "claude", "computer"] }
```

- macOS: `VoiceWakeRuntime` gates triggers using global list
- iOS: `VoiceWakeManager` trigger detection
- Android: Currently disabled (manual microphone)
- Protocol: `voicewake.get`, `voicewake.set`, `voicewake.changed` broadcast

---

## Date/Time Handling

```jsonc
{
  "agents": {
    "defaults": {
      "envelopeTimezone": "local",     // utc | local | user | IANA zone
      "envelopeTimestamp": "on",
      "userTimezone": "Europe/Madrid",
      "timeFormat": "auto"             // auto | 12 | 24
    }
  }
}
```

Message envelope format: `[Provider ... 2026-01-05 16:26 CET] message text`
Current time access: Use the `session_status` tool.
