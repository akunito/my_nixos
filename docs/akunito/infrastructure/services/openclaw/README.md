---
id: infrastructure.services.openclaw
summary: "OpenClaw AI personal assistant: architecture, integrations, and VPS deployment"
tags: [openclaw, ai, assistant, vps, docker, telegram, discord, matrix, automation]
related_files: [templates/openclaw/**, profiles/VPS_PROD-config.nix]
date: 2026-03-04
status: published
---

# OpenClaw — Personal AI Assistant

## What is OpenClaw?

OpenClaw (247k GitHub stars, MIT license) is a self-hosted AI gateway created by Peter Steinberger (PSPDFKit founder). It bridges 23+ messaging platforms with AI models via a single Gateway process. Originally "Clawdbot" (Nov 2025), renamed and went viral Jan 2026. Steinberger joined OpenAI Feb 2026; project moved to an open-source foundation.

**Core concept**: Run one Gateway on your server. It connects your chat apps (Telegram, Discord, WhatsApp, Matrix, Slack, etc.) to AI models (Anthropic, OpenAI, Qwen, local models). You chat with your AI assistant from any app you already use.

**Key capabilities**:
- Multi-channel gateway (23+ platforms simultaneously)
- Voice transcription (built-in, multi-provider fallback)
- Text-to-speech (ElevenLabs, OpenAI, Edge TTS)
- Built-in cron jobs and webhooks (automation without n8n)
- MCP server support and custom skills
- Browser automation (Playwright/CDP)
- Sub-agent orchestration
- Docker sandboxing for tool isolation
- Google Calendar, Gmail, Workspace integration
- Long-term memory and session compaction

## Documentation Index

| Document | Content |
|----------|---------|
| [Architecture](architecture.md) | Gateway model, deployment modes, filesystem layout |
| [Docker Deployment](docker-deployment.md) | Docker Compose, rootless Docker, VPS-specific setup |
| [Channels](channels.md) | All 23+ messaging platforms, config patterns |
| [Security](security.md) | Auth, sandboxing, secrets management, hardening |
| [Automation](automation.md) | Cron jobs, webhooks, hooks, Gmail PubSub |
| [Skills & Plugins](skills-plugins.md) | Custom skills, MCP servers, community plugins |
| [Audio & TTS](audio-tts.md) | Voice transcription, text-to-speech, voice wake |
| [Tools](tools.md) | Browser automation, exec, Lobster workflows, sub-agents |
| [Integrations](integrations.md) | Google Calendar, Plane, n8n, Matrix, Postfix |
| [Finance System](finance-system.md) | Vaultkeeper finance: Revolut import, budgets, cycle reports |

## Deployment Plan

See `~/.claude/plans/transient-stirring-shell.md` for the VPS_PROD deployment plan.

## Quick Reference

| Property | Value |
|----------|-------|
| GitHub | https://github.com/openclaw/openclaw |
| Docs | https://docs.openclaw.ai/ |
| License | MIT |
| Runtime | Node >= 22 |
| Default port | 18789 |
| Config file | `~/.openclaw/openclaw.json` |
| Workspace | `~/.openclaw/workspace/` |
| Docker image | `ghcr.io/openclaw/openclaw:latest` |
| Health endpoints | `/healthz`, `/readyz` |
| Install | `npm install -g openclaw@latest` |
