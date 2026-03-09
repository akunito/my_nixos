#!/usr/bin/env python3
"""
Claude Matrix Bot - Main Entry Point

A Matrix bot that wraps Claude Code for remote assistance via chat.
Supports interactive permissions, streaming responses, session persistence,
access control, and mobile-optimized responses.

Usage:
    python bot.py [--config CONFIG_PATH]

Deploy to: ~/.claude-matrix-bot/bot.py on VPS_PROD
"""

import asyncio
import logging
import os
import shutil
import signal
import sys
import time
from pathlib import Path
from typing import Optional

import structlog
import yaml
from nio import (
    AsyncClient,
    AsyncClientConfig,
    LoginResponse,
    MatrixRoom,
    RoomMessageText,
    InviteMemberEvent,
    MegolmEvent,
    RoomSendResponse,
    ToDeviceError,
)
from nio.crypto import TrustState

from claude_cli import ClaudeBridge, ClaudeCLILegacy
from permission_manager import PermissionManager
from session_manager import SessionManager

# Configure structured logging
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


class ClaudeMatrixBot:
    """Matrix bot that provides Claude Code assistance via chat."""

    def __init__(self, config_path: str = "config.yaml"):
        self.config = self._load_config(config_path)
        self.client: Optional[AsyncClient] = None
        self.session_manager: Optional[SessionManager] = None
        self.permission_manager = PermissionManager()
        self._use_bridge = False
        self._bridge_config = {}
        self._legacy_cli: Optional[ClaudeCLILegacy] = None
        self._active_bridges: dict[str, ClaudeBridge] = {}  # room_id -> bridge
        self._stream_messages: dict[str, dict] = {}  # room_id -> {event_id, last_update}
        self._running = False

    def _load_config(self, config_path: str) -> dict:
        path = Path(config_path)
        if not path.exists():
            log.error("Config file not found", path=config_path)
            sys.exit(1)
        with open(path) as f:
            config = yaml.safe_load(f)
        log.info("Configuration loaded", path=config_path)
        return config

    def _setup_logging(self):
        log_config = self.config.get("logging", {})
        level = getattr(logging, log_config.get("level", "INFO").upper())
        logging.basicConfig(level=level)
        log_file = log_config.get("file")
        if log_file:
            handler = logging.FileHandler(log_file)
            handler.setLevel(level)
            logging.getLogger().addHandler(handler)

    async def start(self):
        """Initialize and start the bot."""
        self._setup_logging()
        log.info("Starting Claude Matrix Bot")

        # Initialize session manager
        db_path = self.config.get("database", {}).get("path", "sessions.db")
        self.session_manager = SessionManager(db_path)
        await self.session_manager.initialize()

        # Initialize Claude interface (bridge or legacy)
        await self._init_claude_interface()

        # Initialize Matrix client
        matrix_config = self.config.get("matrix", {})
        homeserver = matrix_config.get("homeserver")
        bot_user = matrix_config.get("bot_user")

        client_config = AsyncClientConfig(
            max_limit_exceeded=0,
            max_timeouts=0,
            store_sync_tokens=True,
            encryption_enabled=True,
        )

        self.client = AsyncClient(
            homeserver,
            bot_user,
            config=client_config,
            store_path=str(Path.home() / ".claude-matrix-bot" / "store"),
        )

        # Load access token and restore login
        token_file = matrix_config.get("access_token_file")
        device_id_file = Path.home() / ".claude-matrix-bot" / "device_id"

        if token_file and Path(token_file).exists():
            with open(token_file) as f:
                access_token = f.read().strip()

            if device_id_file.exists():
                with open(device_id_file) as f:
                    device_id = f.read().strip()
            else:
                device_id = "CLAUDEBOT"
                with open(device_id_file, "w") as f:
                    f.write(device_id)

            self.client.restore_login(
                user_id=bot_user,
                device_id=device_id,
                access_token=access_token,
            )
            log.info("Restored login", user=bot_user, device=device_id)
        else:
            log.error("Access token file not found", path=token_file)
            sys.exit(1)

        # Register event callbacks
        self.client.add_event_callback(self._on_message, RoomMessageText)
        self.client.add_event_callback(self._on_invite, InviteMemberEvent)
        self.client.add_event_callback(
            self._on_encrypted_message, MegolmEvent
        )

        # Initial sync
        log.info("Performing initial sync...")
        await self.client.sync(timeout=30000, full_state=True)
        await self._setup_encryption_trust()

        # Start sync loop
        self._running = True
        log.info("Bot started, syncing...")

        try:
            await self.client.sync_forever(timeout=30000)
        except Exception as e:
            log.error("Sync error", error=str(e))
            raise

    async def _init_claude_interface(self):
        """Initialize bridge or fall back to legacy CLI."""
        bridge_config = self.config.get("bridge", {})
        bridge_path = bridge_config.get("path", "")

        if (
            bridge_path
            and Path(bridge_path).exists()
            and shutil.which("node")
        ):
            self._use_bridge = True
            self._bridge_config = bridge_config
            log.info("Using Claude Code SDK bridge", path=bridge_path)
        else:
            self._use_bridge = False
            claude_config = self.config.get("claude", {})
            self._legacy_cli = ClaudeCLILegacy(
                working_directory=claude_config.get(
                    "working_directory", os.getcwd()
                ),
                timeout=claude_config.get("command_timeout", 300),
                skip_permissions=claude_config.get(
                    "dangerously_skip_permissions", False
                ),
            )
            health_ok = await self._legacy_cli.check_health()
            if not health_ok:
                log.warning(
                    "Legacy Claude CLI health check failed — bot will start "
                    "but Claude commands may fail"
                )
            log.info("Using legacy Claude CLI mode (bridge unavailable)")

    async def stop(self):
        """Gracefully stop the bot."""
        self._running = False
        # Abort all active bridges
        for room_id, bridge in list(self._active_bridges.items()):
            if bridge.is_active:
                await bridge.abort()
        self._active_bridges.clear()
        self.permission_manager.clear_all()
        if self.client:
            await self.client.close()
        if self.session_manager:
            await self.session_manager.close()
        log.info("Bot stopped")

    # --- Encryption ---

    async def _setup_encryption_trust(self):
        log.info("Setting up E2E encryption trust for allowed users")
        allowed_users = self.config.get("access", {}).get("allowed_users", [])
        for user_id in allowed_users:
            devices = list(
                self.client.device_store.active_user_devices(user_id)
            )
            for device in devices:
                if not device.trust_state == TrustState.verified:
                    self.client.verify_device(device)
                    log.info(
                        "Trusted device",
                        user=user_id,
                        device=device.device_id,
                    )

    async def _on_encrypted_message(
        self, room: MatrixRoom, event: MegolmEvent
    ):
        log.warning(
            "Failed to decrypt message",
            room=room.room_id,
            sender=event.sender,
            session_id=event.session_id,
            reason="Missing session keys",
        )
        if event.sender != self.client.user_id:
            try:
                await self.client.request_room_key(event)
            except Exception as e:
                log.error("Failed to request room key", error=str(e))
            await self._send_message(
                room,
                "I couldn't decrypt your message. This may be a session key "
                "issue. Try sending your message again, or use `/help` for "
                "commands.",
            )

    # --- Access control ---

    def _is_allowed_user(self, user_id: str) -> bool:
        allowed = self.config.get("access", {}).get("allowed_users", [])
        return user_id in allowed

    def _is_allowed_room(self, room_id: str) -> bool:
        allowed = self.config.get("access", {}).get("allowed_rooms", [])
        return len(allowed) == 0 or room_id in allowed

    async def _on_invite(self, room: MatrixRoom, event: InviteMemberEvent):
        if event.state_key != self.client.user_id:
            return
        if self._is_allowed_user(event.sender):
            log.info(
                "Accepting invite",
                room=room.room_id,
                from_user=event.sender,
            )
            await self.client.join(room.room_id)
        else:
            log.warning(
                "Rejecting invite from unauthorized user",
                room=room.room_id,
                from_user=event.sender,
            )

    # --- Message routing ---

    async def _on_message(self, room: MatrixRoom, event: RoomMessageText):
        # Ignore own messages
        if event.sender == self.client.user_id:
            return

        # Access control
        if not self._is_allowed_user(event.sender):
            log.warning(
                "Ignoring message from unauthorized user", user=event.sender
            )
            return
        if not self._is_allowed_room(room.room_id):
            log.warning(
                "Ignoring message from unauthorized room", room=room.room_id
            )
            return

        message = event.body.strip()
        log.info(
            "Received message",
            user=event.sender,
            room=room.room_id,
            message=message[:50] + ("..." if len(message) > 50 else ""),
        )

        # Route message
        if message.startswith("/"):
            await self._handle_command(room, event.sender, message)
        elif self.permission_manager.has_pending(room.room_id):
            await self._send_message(
                room,
                "Permission pending — respond `/yes` or `/no` first, "
                "or `/clear` to start fresh.",
            )
        elif room.room_id in self._active_bridges:
            await self._send_message(
                room,
                "Still processing... please wait, or `/clear` to cancel.",
            )
        else:
            await self._handle_claude_message(room, event.sender, message)

    # --- Commands ---

    async def _handle_command(
        self, room: MatrixRoom, sender: str, message: str
    ):
        parts = message.split(maxsplit=1)
        command = parts[0].lower()
        args = parts[1] if len(parts) > 1 else ""

        if command == "/yes":
            await self._handle_permission_response(room, "allow")

        elif command == "/no":
            await self._handle_permission_response(room, "deny")

        elif command in ("/clear", "/new"):
            await self._handle_clear(room, sender)

        elif command == "/status":
            await self._handle_status(room, sender)

        elif command == "/cd":
            await self._handle_cd(room, sender, args)

        elif command == "/trust":
            await self._handle_trust(room, sender)

        elif command == "/help":
            await self._handle_help(room)

        else:
            await self._send_message(
                room,
                f"Unknown command: `{command}`. Use `/help` for available "
                "commands.",
            )

    async def _handle_permission_response(
        self, room: MatrixRoom, action: str
    ):
        ipc_msg = self.permission_manager.resolve(room.room_id, action)
        if not ipc_msg:
            await self._send_message(room, "No pending permission request.")
            return

        bridge = self._active_bridges.get(room.room_id)
        if bridge and bridge.is_active:
            await bridge.send_permission_response(
                ipc_msg["requestId"], ipc_msg["action"]
            )
            label = "Approved" if action == "allow" else "Denied"
            await self._send_message(room, f"{label}.")
        else:
            await self._send_message(room, "No active query to respond to.")

    async def _handle_clear(self, room: MatrixRoom, sender: str):
        # Abort active bridge
        bridge = self._active_bridges.pop(room.room_id, None)
        if bridge and bridge.is_active:
            await bridge.abort()
        # Clear state
        self.permission_manager.clear(room.room_id)
        self._stream_messages.pop(room.room_id, None)
        await self.session_manager.reset_session(sender)
        await self._send_message(room, "Session reset. Starting fresh context.")

    async def _handle_status(self, room: MatrixRoom, sender: str):
        session = await self.session_manager.get_session(sender)
        status = "**Session Status**\n"
        if session:
            sid = session.get("session_id", session.get("claude_session_id", ""))
            if sid:
                status += f"- Session ID: `{sid[:8]}...`\n"
            status += f"- Working Dir: `{session['working_dir']}`\n"
            status += f"- Last Active: {session['last_active']}\n"
        else:
            status += "- Session: None (send any message to start)\n"

        # Mode
        mode = "SDK Bridge" if self._use_bridge else "Legacy CLI"
        status += f"- Mode: {mode}\n"

        # Active query
        if room.room_id in self._active_bridges:
            status += "- Query: **Active**\n"
        if self.permission_manager.has_pending(room.room_id):
            status += "- Permission: **Pending**\n"

        # Encryption
        status += f"\n**Encryption**\n"
        status += f"- Room Encrypted: {'Yes' if room.encrypted else 'No'}\n"
        if room.encrypted:
            devices = list(
                self.client.device_store.active_user_devices(sender)
            )
            verified = sum(
                1 for d in devices if d.trust_state.is_verified()
            )
            status += f"- Your Verified Devices: {verified}/{len(devices)}"

        await self._send_message(room, status)

    async def _handle_cd(self, room: MatrixRoom, sender: str, args: str):
        if args:
            path = Path(args).expanduser()
            if path.exists() and path.is_dir():
                await self.session_manager.update_working_dir(
                    sender, str(path)
                )
                await self._send_message(
                    room, f"Working directory changed to: `{path}`"
                )
            else:
                await self._send_message(
                    room, f"Directory not found: `{args}`"
                )
        else:
            await self._send_message(room, "Usage: `/cd <path>`")

    async def _handle_trust(self, room: MatrixRoom, sender: str):
        devices = list(
            self.client.device_store.active_user_devices(sender)
        )
        trusted = 0
        for device in devices:
            if not device.trust_state == TrustState.verified:
                self.client.verify_device(device)
                trusted += 1
        if trusted > 0:
            await self._send_message(
                room, f"Trusted {trusted} new device(s) for your account."
            )
        else:
            await self._send_message(
                room, "All your devices are already trusted."
            )

    async def _handle_help(self, room: MatrixRoom):
        help_text = """**Claude Bot Commands**
- `/yes` - Approve a pending permission request
- `/no` - Deny a pending permission request
- `/clear` - Abort active query, reset session
- `/new` - Same as /clear
- `/status` - Show session info & encryption status
- `/cd <path>` - Change working directory
- `/trust` - Trust all your devices for E2E encryption
- `/help` - Show this help message

Send any other message to interact with Claude Code.

*Note: Messages in encrypted rooms are end-to-end encrypted.*"""
        await self._send_message(room, help_text)

    # --- Claude message handling ---

    async def _handle_claude_message(
        self, room: MatrixRoom, sender: str, message: str
    ):
        session = await self.session_manager.get_or_create_session(sender)

        # Build context preamble
        preamble = self.config.get("response", {}).get("context_preamble", "")
        env_profile = os.environ.get("ENV_PROFILE", "VPS_PROD")
        preamble = preamble.replace("{env_profile}", env_profile)

        # Send typing indicator
        await self.client.room_typing(
            room.room_id, typing_state=True, timeout=30000
        )

        if self._use_bridge:
            await self._handle_bridge_message(
                room, sender, session, message, preamble
            )
        else:
            await self._handle_legacy_message(
                room, sender, session, message, preamble
            )

    async def _handle_bridge_message(
        self,
        room: MatrixRoom,
        sender: str,
        session: dict,
        message: str,
        preamble: str,
    ):
        """Handle message via SDK bridge with streaming and permissions."""
        bridge_path = self._bridge_config.get("path")
        debounce_ms = self._bridge_config.get("stream_debounce_ms", 500)
        claude_config = self.config.get("claude", {})
        working_dir = session.get("working_dir") or claude_config.get(
            "working_directory", os.getcwd()
        )

        bridge = ClaudeBridge(
            bridge_path=bridge_path,
            working_directory=working_dir,
            timeout=claude_config.get("command_timeout", 300),
            permission_timeout=self._bridge_config.get(
                "permission_timeout", 300
            ),
        )

        self._active_bridges[room.room_id] = bridge
        self._stream_messages[room.room_id] = {
            "event_id": None,
            "last_update": 0,
        }

        # --- Event handlers ---

        async def on_text_chunk(msg):
            now = time.time()
            stream_state = self._stream_messages.get(room.room_id)
            if not stream_state:
                return

            text = msg.get("text", "")
            text = self._truncate_response(text)

            if stream_state["event_id"] is None:
                # First chunk: send new message
                event_id = await self._send_message_get_id(room, text)
                stream_state["event_id"] = event_id
                stream_state["last_update"] = now
            elif (now - stream_state["last_update"]) * 1000 >= debounce_ms:
                # Subsequent chunks: edit message (debounced)
                await self._edit_message(
                    room, stream_state["event_id"], text
                )
                stream_state["last_update"] = now

        async def on_permission_request(msg):
            self.permission_manager.set_pending(
                room.room_id,
                msg["requestId"],
                msg["tool"],
                msg.get("input", {}),
            )
            display = self.permission_manager.get_display(room.room_id)
            await self._send_message(room, display)

        async def on_permission_timeout(msg):
            self.permission_manager.clear(room.room_id)
            await self._send_message(
                room, "Permission timed out. Use `/clear` to reset."
            )

        async def on_session_id(msg):
            sid = msg.get("sessionId")
            if sid:
                await self.session_manager.update_claude_session(sender, sid)

        bridge.on("text_chunk", on_text_chunk)
        bridge.on("permission_request", on_permission_request)
        bridge.on("permission_timeout", on_permission_timeout)
        bridge.on("session_id", on_session_id)

        try:
            system_prompt = preamble if preamble.strip() else None

            result = await bridge.send_query(
                message=message,
                session_id=session.get("claude_session_id"),
                working_dir=working_dir,
                system_prompt=system_prompt,
            )

            # Final update with complete result
            stream_state = self._stream_messages.get(room.room_id)
            result_text = self._truncate_response(
                result.get("text", "")
            )

            if stream_state and stream_state["event_id"] and result_text:
                # Edit streaming message with final text
                await self._edit_message(
                    room, stream_state["event_id"], result_text
                )
            elif result_text:
                # No streaming message was sent — send as new
                await self._send_message(room, result_text)
            elif not stream_state or not stream_state.get("event_id"):
                await self._send_message(
                    room, "No response from Claude."
                )

            # Update session ID
            if result.get("session_id"):
                await self.session_manager.update_claude_session(
                    sender, result["session_id"]
                )

        except asyncio.TimeoutError:
            await self._send_message(
                room, "Request timed out. Try a simpler question."
            )
        except Exception as e:
            log.error("Bridge error", error=str(e))
            await self._send_message(room, f"Error: {str(e)}")
        finally:
            await self.client.room_typing(
                room.room_id, typing_state=False
            )
            self._active_bridges.pop(room.room_id, None)
            self._stream_messages.pop(room.room_id, None)
            self.permission_manager.clear(room.room_id)

    async def _handle_legacy_message(
        self,
        room: MatrixRoom,
        sender: str,
        session: dict,
        message: str,
        preamble: str,
    ):
        """Handle message via legacy claude --print mode."""
        try:
            response = await self._legacy_cli.send_message(
                message=message,
                session_id=session.get("claude_session_id"),
                working_dir=session.get("working_dir"),
                context_preamble=preamble,
            )

            if response.get("session_id") and response[
                "session_id"
            ] != session.get("claude_session_id"):
                await self.session_manager.update_claude_session(
                    sender, response["session_id"]
                )

            response_text = self._truncate_response(
                response.get("text", "No response from Claude")
            )
            await self._send_message(room, response_text)

        except asyncio.TimeoutError:
            await self._send_message(
                room, "Request timed out. Try a simpler question."
            )
        except Exception as e:
            log.error("Error calling Claude", error=str(e))
            await self._send_message(room, f"Error: {str(e)}")
        finally:
            await self.client.room_typing(
                room.room_id, typing_state=False
            )

    # --- Response helpers ---

    def _truncate_response(self, text: str) -> str:
        max_length = self.config.get("claude", {}).get(
            "max_response_length", 4000
        )
        if len(text) > max_length:
            suffix = self.config.get("response", {}).get(
                "truncation_suffix",
                "\n\n... [Response truncated. Ask for specific parts if needed]",
            )
            text = text[: max_length - len(suffix)] + suffix
        return text

    # --- Matrix messaging ---

    async def _send_message(self, room: MatrixRoom, message: str):
        """Send a message to a room, encrypted if required."""
        if room.encrypted:
            try:
                await self._share_room_keys(room)
            except Exception as e:
                log.warning("Failed to share room keys", error=str(e))

        result = await self.client.room_send(
            room.room_id,
            message_type="m.room.message",
            content={
                "msgtype": "m.text",
                "body": message,
                "format": "org.matrix.custom.html",
                "formatted_body": self._markdown_to_html(message),
            },
        )

        if isinstance(result, ToDeviceError):
            log.error(
                "Failed to send encrypted message", error=str(result)
            )

    async def _send_message_get_id(
        self, room: MatrixRoom, message: str
    ) -> Optional[str]:
        """Send a message and return the event_id for later editing."""
        if room.encrypted:
            try:
                await self._share_room_keys(room)
            except Exception as e:
                log.warning("Failed to share room keys", error=str(e))

        result = await self.client.room_send(
            room.room_id,
            message_type="m.room.message",
            content={
                "msgtype": "m.text",
                "body": message,
                "format": "org.matrix.custom.html",
                "formatted_body": self._markdown_to_html(message),
            },
        )

        if isinstance(result, RoomSendResponse):
            return result.event_id
        if isinstance(result, ToDeviceError):
            log.error(
                "Failed to send encrypted message", error=str(result)
            )
        return None

    async def _edit_message(
        self, room: MatrixRoom, event_id: str, new_text: str
    ):
        """Edit an existing message using Matrix m.replace relation."""
        if not event_id:
            return

        if room.encrypted:
            try:
                await self._share_room_keys(room)
            except Exception:
                pass

        try:
            await self.client.room_send(
                room.room_id,
                message_type="m.room.message",
                content={
                    "msgtype": "m.text",
                    "body": f"* {new_text}",
                    "format": "org.matrix.custom.html",
                    "formatted_body": self._markdown_to_html(new_text),
                    "m.new_content": {
                        "msgtype": "m.text",
                        "body": new_text,
                        "format": "org.matrix.custom.html",
                        "formatted_body": self._markdown_to_html(new_text),
                    },
                    "m.relates_to": {
                        "rel_type": "m.replace",
                        "event_id": event_id,
                    },
                },
            )
        except Exception as e:
            log.warning("Failed to edit message", error=str(e))

    async def _share_room_keys(self, room: MatrixRoom):
        members = await self.client.joined_members(room.room_id)
        for member in members.members:
            devices = list(
                self.client.device_store.active_user_devices(
                    member.user_id
                )
            )
            for device in devices:
                if not device.trust_state == TrustState.verified:
                    if self._is_allowed_user(member.user_id):
                        self.client.verify_device(device)

    def _markdown_to_html(self, text: str) -> str:
        """Convert basic markdown to HTML for Matrix."""
        import re

        # Bold
        text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
        # Italic
        text = re.sub(r"\*(.+?)\*", r"<em>\1</em>", text)
        # Code blocks
        text = re.sub(
            r"```(\w+)?\n(.*?)```",
            r"<pre><code>\2</code></pre>",
            text,
            flags=re.DOTALL,
        )
        # Inline code
        text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
        # Line breaks
        text = text.replace("\n", "<br>")
        return text


async def main():
    import argparse

    parser = argparse.ArgumentParser(description="Claude Matrix Bot")
    parser.add_argument(
        "--config",
        default=str(Path.home() / ".claude-matrix-bot" / "config.yaml"),
        help="Path to config file",
    )
    args = parser.parse_args()

    bot = ClaudeMatrixBot(args.config)

    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(
            sig, lambda: asyncio.create_task(bot.stop())
        )

    try:
        await bot.start()
    except KeyboardInterrupt:
        pass
    finally:
        await bot.stop()


if __name__ == "__main__":
    asyncio.run(main())
