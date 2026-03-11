#!/usr/bin/env python3
"""
OpenClaw Matrix Fallback Monitor — sends Telegram notifications when Matrix messages go unread.

Monitors Matrix rooms for agent messages. If the user doesn't respond within the configured
timeout (default 12 hours), sends a notification to the corresponding Telegram group.

Deploy to: ~/.openclaw-matrix-fallback/ on VPS_PROD
"""

import asyncio
import argparse
import json
import logging
import signal
import sys
from datetime import datetime, timezone
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
    MegolmEvent,
    InviteMemberEvent,
)
from nio.crypto import TrustState

try:
    import zoneinfo
    ZoneInfo = zoneinfo.ZoneInfo
except ImportError:
    from backports.zoneinfo import ZoneInfo

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


class FallbackMonitor:
    """Monitors Matrix rooms and sends Telegram fallback notifications."""

    def __init__(self, config_path: str):
        self.config = self._load_config(config_path)
        self.client: Optional[AsyncClient] = None
        self._http_session: Optional[aiohttp.ClientSession] = None
        self._running = False

        # Per-room state: {room_id: {last_bot_msg_ts, last_user_msg_ts, fallback_sent}}
        self.room_state: dict[str, dict] = {}
        self._state_file = self.config.get("state_file", str(
            Path.home() / ".openclaw-matrix-fallback" / "state.json"
        ))

        # Config
        fallback_cfg = self.config.get("fallback", {})
        self.timeout_hours = fallback_cfg.get("timeout_hours", 12)
        self.check_interval = fallback_cfg.get("check_interval_minutes", 30) * 60
        self.active_start = fallback_cfg.get("active_hours", {}).get("start", 8)
        self.active_end = fallback_cfg.get("active_hours", {}).get("end", 22)
        self.tz = ZoneInfo(fallback_cfg.get("timezone", "Europe/Madrid"))
        self.allowed_users = self.config.get("allowed_users", [])

    def _load_config(self, path: str) -> dict:
        with open(path) as f:
            config = yaml.safe_load(f)
        log.info("Config loaded", path=path)
        return config

    def _load_state(self):
        """Load persisted state for crash recovery."""
        if Path(self._state_file).exists():
            try:
                with open(self._state_file) as f:
                    self.room_state = json.load(f)
                log.info("State restored", rooms=len(self.room_state))
            except (json.JSONDecodeError, IOError) as e:
                log.warning("State file corrupt, starting fresh", error=str(e))
                self.room_state = {}

    def _save_state(self):
        """Persist state to file."""
        Path(self._state_file).parent.mkdir(parents=True, exist_ok=True)
        with open(self._state_file, "w") as f:
            json.dump(self.room_state, f, indent=2)

    async def start(self):
        """Initialize and start monitoring."""
        self._load_state()

        matrix_cfg = self.config.get("matrix", {})
        base_dir = Path.home() / ".openclaw-matrix-fallback"
        store_dir = base_dir / "store"
        store_dir.mkdir(parents=True, exist_ok=True)

        client_config = AsyncClientConfig(
            max_limit_exceeded=0,
            max_timeouts=0,
            store_sync_tokens=True,
            encryption_enabled=True,
        )

        self.client = AsyncClient(
            matrix_cfg["homeserver"],
            matrix_cfg["bot_user"],
            config=client_config,
            store_path=str(store_dir),
        )

        # Load access token
        token_file = matrix_cfg["access_token_file"]
        if not Path(token_file).exists():
            log.error("Token file not found", path=token_file)
            sys.exit(1)

        with open(token_file) as f:
            access_token = f.read().strip()

        device_id_file = base_dir / "device_id"
        if device_id_file.exists():
            with open(device_id_file) as f:
                device_id = f.read().strip()
        else:
            device_id = "OPENCLAW_FALLBACK"
            with open(device_id_file, "w") as f:
                f.write(device_id)

        self.client.restore_login(
            user_id=matrix_cfg["bot_user"],
            device_id=device_id,
            access_token=access_token,
        )

        # Callbacks — track messages to update timestamps
        self.client.add_event_callback(self._on_message, RoomMessageText)
        self.client.add_event_callback(self._on_invite, InviteMemberEvent)
        self.client.add_event_callback(self._on_encrypted_message, MegolmEvent)

        # Initial sync
        log.info("Initial sync...")
        await self.client.sync(timeout=30000, full_state=True)
        await self._setup_encryption_trust()

        self._http_session = aiohttp.ClientSession()
        self._running = True

        log.info("Fallback monitor started", timeout_hours=self.timeout_hours)

        # Run sync and check loop concurrently
        await asyncio.gather(
            self.client.sync_forever(timeout=30000),
            self._check_loop(),
        )

    async def stop(self):
        self._running = False
        self._save_state()
        if self._http_session:
            await self._http_session.close()
        if self.client:
            await self.client.close()
        log.info("Fallback monitor stopped")

    async def _setup_encryption_trust(self):
        for user_id in self.allowed_users:
            devices = list(self.client.device_store.active_user_devices(user_id))
            for device in devices:
                if device.trust_state != TrustState.verified:
                    self.client.verify_device(device)

    async def _on_invite(self, room: MatrixRoom, event: InviteMemberEvent):
        if event.state_key == self.client.user_id and event.sender in self.allowed_users:
            await self.client.join(room.room_id)
            log.info("Joined room", room=room.room_id)

    async def _on_encrypted_message(self, room: MatrixRoom, event: MegolmEvent):
        """Try to request keys for encrypted messages we can't decrypt."""
        if event.sender != self.client.user_id:
            try:
                await self.client.request_room_key(event)
            except Exception:
                pass

    async def _on_message(self, room: MatrixRoom, event: RoomMessageText):
        """Track message timestamps per room."""
        rooms_cfg = self.config.get("rooms", {})
        if room.room_id not in rooms_cfg:
            return

        now = datetime.now(timezone.utc).isoformat()

        if room.room_id not in self.room_state:
            self.room_state[room.room_id] = {
                "last_bot_msg_ts": None,
                "last_user_msg_ts": None,
                "fallback_sent": False,
            }

        state = self.room_state[room.room_id]

        # Determine if sender is a bot or a user using explicit config list
        agent_bots = set(self.config.get("agents_bots", []))

        if event.sender in self.allowed_users:
            # User responded — reset fallback
            state["last_user_msg_ts"] = now
            state["fallback_sent"] = False
            log.debug("User message tracked", room=room.room_id, user=event.sender)
        elif event.sender in agent_bots or event.sender == self.client.user_id:
            # Bot message — start the fallback timer
            state["last_bot_msg_ts"] = now
            state["fallback_sent"] = False
            log.debug("Bot message tracked", room=room.room_id, bot=event.sender)

        self._save_state()

    async def _check_loop(self):
        """Periodically check for rooms needing Telegram fallback."""
        while self._running:
            await asyncio.sleep(self.check_interval)

            if not self._is_active_hours():
                log.debug("Outside active hours, skipping check")
                continue

            await self._check_rooms()

    def _is_active_hours(self) -> bool:
        """Check if current time is within active hours."""
        now = datetime.now(self.tz)
        return self.active_start <= now.hour < self.active_end

    async def _check_rooms(self):
        """Check each monitored room for overdue responses."""
        rooms_cfg = self.config.get("rooms", {})
        now = datetime.now(timezone.utc)

        for room_id, room_cfg in rooms_cfg.items():
            state = self.room_state.get(room_id, {})
            if not state:
                continue

            if state.get("fallback_sent"):
                continue

            last_bot = state.get("last_bot_msg_ts")
            if not last_bot:
                continue

            last_bot_dt = datetime.fromisoformat(last_bot)
            last_user = state.get("last_user_msg_ts")

            # Check if user responded after bot's last message
            if last_user:
                last_user_dt = datetime.fromisoformat(last_user)
                if last_user_dt > last_bot_dt:
                    continue  # User already responded

            # Check if timeout exceeded
            elapsed_hours = (now - last_bot_dt).total_seconds() / 3600
            if elapsed_hours >= self.timeout_hours:
                agent_name = room_cfg.get("agent_name", "Unknown")
                telegram_group = room_cfg.get("telegram_group_id")

                log.info(
                    "Triggering fallback",
                    agent=agent_name,
                    room=room_id,
                    elapsed_hours=round(elapsed_hours, 1),
                )

                await self._send_telegram_notification(
                    telegram_group, agent_name, elapsed_hours
                )
                state["fallback_sent"] = True
                self._save_state()

    async def _send_telegram_notification(
        self, chat_id: str, agent_name: str, elapsed_hours: float
    ):
        """Send fallback notification to Telegram group."""
        telegram_cfg = self.config.get("telegram", {})
        token_file = telegram_cfg.get("bot_token_file", "")

        if not token_file or not Path(token_file).exists():
            log.error("Telegram bot token file not found", path=token_file)
            return

        with open(token_file) as f:
            bot_token = f.read().strip()

        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        text = (
            f"[{agent_name}] Unread message on Matrix "
            f"(sent {elapsed_hours:.0f}h ago). Check Matrix."
        )

        try:
            async with self._http_session.post(
                url,
                json={"chat_id": chat_id, "text": text},
                timeout=aiohttp.ClientTimeout(total=30),
            ) as resp:
                if resp.status == 200:
                    log.info("Telegram notification sent", agent=agent_name)
                else:
                    body = await resp.text()
                    log.error("Telegram send failed", status=resp.status, body=body[:200])
        except Exception as e:
            log.error("Telegram send error", error=str(e))


async def main():
    parser = argparse.ArgumentParser(description="OpenClaw Matrix Fallback Monitor")
    parser.add_argument(
        "--config",
        default=str(Path.home() / ".openclaw-matrix-fallback" / "config.yaml"),
        help="Path to config file",
    )
    args = parser.parse_args()

    monitor = FallbackMonitor(args.config)

    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, lambda: asyncio.create_task(monitor.stop()))

    try:
        await monitor.start()
    except KeyboardInterrupt:
        pass
    finally:
        await monitor.stop()


if __name__ == "__main__":
    asyncio.run(main())
