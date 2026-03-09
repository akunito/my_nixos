#!/usr/bin/env python3
"""
OpenClaw Matrix Bridge — connects OpenClaw agents to Matrix rooms with E2E encryption.

Each agent (Alfred, Vaultkeeper, Scout) gets its own Matrix bot user and encrypted room.
User messages are forwarded to OpenClaw's Chat Completions API, responses sent back to Matrix.

Deploy to: ~/.openclaw-matrix-bridge/ on VPS_PROD
"""

import asyncio
import argparse
import json
import logging
import os
import re
import signal
import sys
from pathlib import Path
from typing import Optional

import aiohttp
import structlog
import yaml
from nio import (
    AsyncClient,
    AsyncClientConfig,
    MatrixRoom,
    RoomMessageText,
    InviteMemberEvent,
    MegolmEvent,
    ToDeviceError,
)
from nio.crypto import TrustState

structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.dev.ConsoleRenderer(),
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

log = structlog.get_logger()


class AgentBridge:
    """Bridges a single OpenClaw agent to a Matrix room with E2E encryption."""

    def __init__(self, agent_id: str, config: dict, openclaw_config: dict):
        self.agent_id = agent_id
        self.agent_config = config
        self.openclaw_config = openclaw_config
        self.room_id = config["room_id"]
        self.allowed_users = config.get("allowed_users", [])
        self.client: Optional[AsyncClient] = None
        self._http_session: Optional[aiohttp.ClientSession] = None

    async def start(self):
        """Initialize Matrix client with E2E and start syncing."""
        base_dir = Path.home() / ".openclaw-matrix-bridge" / self.agent_id
        store_dir = base_dir / "store"
        store_dir.mkdir(parents=True, exist_ok=True)

        client_config = AsyncClientConfig(
            max_limit_exceeded=0,
            max_timeouts=0,
            store_sync_tokens=True,
            encryption_enabled=True,
        )

        self.client = AsyncClient(
            self.agent_config["homeserver"],
            self.agent_config["bot_user"],
            config=client_config,
            store_path=str(store_dir),
        )

        # Load access token
        token_file = self.agent_config["access_token_file"]
        if not Path(token_file).exists():
            log.error("Access token file not found", agent=self.agent_id, path=token_file)
            sys.exit(1)

        with open(token_file) as f:
            access_token = f.read().strip()

        # Device ID persistence
        device_id_file = base_dir / "device_id"
        if device_id_file.exists():
            with open(device_id_file) as f:
                device_id = f.read().strip()
        else:
            device_id = self.agent_config.get("device_id", f"OPENCLAW_{self.agent_id.upper()}")
            with open(device_id_file, "w") as f:
                f.write(device_id)

        self.client.restore_login(
            user_id=self.agent_config["bot_user"],
            device_id=device_id,
            access_token=access_token,
        )
        log.info("Login restored", agent=self.agent_id, device=device_id)

        # Event callbacks
        self.client.add_event_callback(self._on_message, RoomMessageText)
        self.client.add_event_callback(self._on_invite, InviteMemberEvent)
        self.client.add_event_callback(self._on_encrypted_message, MegolmEvent)

        # Initial sync
        log.info("Initial sync...", agent=self.agent_id)
        await self.client.sync(timeout=30000, full_state=True)
        await self._setup_encryption_trust()

        # Create HTTP session for OpenClaw API
        self._http_session = aiohttp.ClientSession()

        log.info("Agent bridge started", agent=self.agent_id, room=self.room_id)
        await self.client.sync_forever(timeout=30000)

    async def stop(self):
        """Gracefully stop this agent bridge."""
        if self._http_session:
            await self._http_session.close()
        if self.client:
            await self.client.close()
        log.info("Agent bridge stopped", agent=self.agent_id)

    async def _setup_encryption_trust(self):
        """Auto-trust devices of allowed users for seamless E2E."""
        for user_id in self.allowed_users:
            devices = list(self.client.device_store.active_user_devices(user_id))
            for device in devices:
                if device.trust_state != TrustState.verified:
                    self.client.verify_device(device)
                    log.info("Trusted device", agent=self.agent_id, user=user_id, device=device.device_id)

    async def _on_encrypted_message(self, room: MatrixRoom, event: MegolmEvent):
        """Handle failed decryption — request missing keys."""
        if room.room_id != self.room_id:
            return

        log.warning("Decryption failed", agent=self.agent_id, sender=event.sender)

        if event.sender != self.client.user_id:
            try:
                await self.client.request_room_key(event)
            except Exception as e:
                log.error("Key request failed", agent=self.agent_id, error=str(e))

            await self._send_message(
                room,
                "Could not decrypt your message. Try sending again or check encryption status.",
            )

    async def _on_invite(self, room: MatrixRoom, event: InviteMemberEvent):
        """Auto-join rooms from allowed users."""
        if event.state_key != self.client.user_id:
            return

        if event.sender in self.allowed_users:
            log.info("Accepting invite", agent=self.agent_id, room=room.room_id)
            await self.client.join(room.room_id)
        else:
            log.warning("Rejecting invite", agent=self.agent_id, from_user=event.sender)

    async def _on_message(self, room: MatrixRoom, event: RoomMessageText):
        """Handle incoming messages — forward to OpenClaw, return response."""
        if event.sender == self.client.user_id:
            return
        if room.room_id != self.room_id:
            return
        if event.sender not in self.allowed_users:
            log.warning("Unauthorized message", agent=self.agent_id, user=event.sender)
            return

        message = event.body.strip()
        log.info(
            "Message received",
            agent=self.agent_id,
            user=event.sender,
            preview=message[:80],
        )

        # Handle commands
        if message.startswith("/"):
            await self._handle_command(room, event.sender, message)
            return

        # Send typing indicator
        await self.client.room_typing(room.room_id, typing_state=True, timeout=60000)

        try:
            response_text = await self._forward_to_openclaw(message, event.sender)
            await self._send_message(room, response_text)
        except asyncio.TimeoutError:
            await self._send_message(room, "Request timed out. Try a shorter message.")
        except Exception as e:
            log.error("OpenClaw error", agent=self.agent_id, error=str(e))
            await self._send_message(room, f"Error communicating with OpenClaw: {e}")
        finally:
            await self.client.room_typing(room.room_id, typing_state=False)

    async def _handle_command(self, room: MatrixRoom, sender: str, message: str):
        """Handle bot commands."""
        command = message.split()[0].lower()

        if command == "/status":
            status = f"**{self.agent_id.capitalize()} Status**\n"
            status += f"- Room Encrypted: {'Yes' if room.encrypted else 'No'}\n"
            if room.encrypted:
                devices = list(self.client.device_store.active_user_devices(sender))
                verified = sum(1 for d in devices if d.trust_state.is_verified())
                status += f"- Verified Devices: {verified}/{len(devices)}\n"
            status += f"- OpenClaw Agent: `{self.agent_id}`"
            await self._send_message(room, status)

        elif command == "/trust":
            devices = list(self.client.device_store.active_user_devices(sender))
            trusted = 0
            for device in devices:
                if device.trust_state != TrustState.verified:
                    self.client.verify_device(device)
                    trusted += 1
            msg = f"Trusted {trusted} new device(s)." if trusted else "All devices already trusted."
            await self._send_message(room, msg)

        elif command == "/help":
            await self._send_message(room, (
                f"**{self.agent_id.capitalize()} Commands**\n"
                "- `/status` - Encryption & agent status\n"
                "- `/trust` - Trust all your devices\n"
                "- `/help` - This help message\n\n"
                "Send any message to chat with the agent."
            ))
        else:
            await self._send_message(room, f"Unknown command: `{command}`. Use `/help`.")

    async def _forward_to_openclaw(self, message: str, sender: str) -> str:
        """Forward message to OpenClaw Chat Completions API and return response."""
        gateway_url = self.openclaw_config["gateway_url"]
        token = self._load_gateway_token()

        url = f"{gateway_url}/v1/chat/completions"
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

        # Use OpenAI-compatible chat completions format
        # Session key includes agent+sender for per-user-per-agent sessions
        session_key = f"matrix:{self.agent_id}:{sender}"
        payload = {
            "model": self.openclaw_config.get("model", "modelstudio/qwen3.5-plus"),
            "messages": [{"role": "user", "content": message}],
            "metadata": {
                "agentId": self.agent_id,
                "sessionKey": session_key,
                "channel": "matrix",
                "peer": {"id": sender, "kind": "dm"},
            },
        }

        async with self._http_session.post(
            url, headers=headers, json=payload, timeout=aiohttp.ClientTimeout(total=300)
        ) as resp:
            if resp.status != 200:
                body = await resp.text()
                raise RuntimeError(f"OpenClaw returned {resp.status}: {body[:500]}")

            data = await resp.json()
            # Extract response from OpenAI-compatible format
            choices = data.get("choices", [])
            if choices:
                return choices[0].get("message", {}).get("content", "No response.")
            return "No response from agent."

    def _load_gateway_token(self) -> str:
        """Load gateway token from file."""
        token_file = self.openclaw_config.get("gateway_token_file", "")
        if token_file and Path(token_file).exists():
            with open(token_file) as f:
                return f.read().strip()
        raise RuntimeError(f"Gateway token file not found: {token_file}")

    async def _send_message(self, room: MatrixRoom, message: str):
        """Send encrypted message to Matrix room."""
        if room.encrypted:
            try:
                await self._share_room_keys(room)
            except Exception as e:
                log.warning("Key share failed", agent=self.agent_id, error=str(e))

        result = await self.client.room_send(
            room.room_id,
            message_type="m.room.message",
            content={
                "msgtype": "m.text",
                "body": message,
                "format": "org.matrix.custom.html",
                "formatted_body": _markdown_to_html(message),
            },
        )

        if isinstance(result, ToDeviceError):
            log.error("Send failed", agent=self.agent_id, error=str(result))

    async def _share_room_keys(self, room: MatrixRoom):
        """Share encryption keys with allowed room members."""
        members = await self.client.joined_members(room.room_id)
        for member in members.members:
            devices = list(self.client.device_store.active_user_devices(member.user_id))
            for device in devices:
                if device.trust_state != TrustState.verified:
                    if member.user_id in self.allowed_users:
                        self.client.verify_device(device)


class BridgeManager:
    """Manages multiple AgentBridge instances."""

    def __init__(self, config_path: str):
        self.config = self._load_config(config_path)
        self.agents: dict[str, AgentBridge] = {}
        self._tasks: list[asyncio.Task] = []

    def _load_config(self, config_path: str) -> dict:
        with open(config_path) as f:
            config = yaml.safe_load(f)
        log.info("Configuration loaded", path=config_path)
        return config

    def _build_agents(self):
        """Create AgentBridge instances from config."""
        matrix_config = self.config.get("matrix", {})
        openclaw_config = self.config.get("openclaw", {})
        allowed_users = matrix_config.get("allowed_users", [])

        for agent_id, agent_cfg in self.config.get("agents", {}).items():
            agent_cfg["homeserver"] = matrix_config["homeserver"]
            agent_cfg["allowed_users"] = allowed_users
            self.agents[agent_id] = AgentBridge(agent_id, agent_cfg, openclaw_config)
            log.info("Agent configured", agent=agent_id, room=agent_cfg["room_id"])

    async def start(self):
        """Start all agent bridges concurrently."""
        self._build_agents()

        for agent_id, agent in self.agents.items():
            task = asyncio.create_task(agent.start(), name=f"agent-{agent_id}")
            self._tasks.append(task)

        log.info("All agents starting", count=len(self.agents))

        # Wait for all — if one fails, log and continue others
        results = await asyncio.gather(*self._tasks, return_exceptions=True)
        for agent_id, result in zip(self.agents.keys(), results):
            if isinstance(result, Exception):
                log.error("Agent failed", agent=agent_id, error=str(result))

    async def stop(self):
        """Stop all agents."""
        for task in self._tasks:
            task.cancel()
        for agent in self.agents.values():
            await agent.stop()
        log.info("Bridge manager stopped")


def _markdown_to_html(text: str) -> str:
    """Convert basic markdown to HTML for Matrix."""
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\*(.+?)\*", r"<em>\1</em>", text)
    text = re.sub(r"```(\w+)?\n(.*?)```", r"<pre><code>\2</code></pre>", text, flags=re.DOTALL)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    text = text.replace("\n", "<br>")
    return text


async def main():
    parser = argparse.ArgumentParser(description="OpenClaw Matrix Bridge")
    parser.add_argument(
        "--config",
        default=str(Path.home() / ".openclaw-matrix-bridge" / "config.yaml"),
        help="Path to config file",
    )
    args = parser.parse_args()

    manager = BridgeManager(args.config)

    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, lambda: asyncio.create_task(manager.stop()))

    try:
        await manager.start()
    except KeyboardInterrupt:
        pass
    finally:
        await manager.stop()


if __name__ == "__main__":
    asyncio.run(main())
