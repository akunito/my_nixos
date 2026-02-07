#!/usr/bin/env python3
"""
Claude Matrix Bot - Main Entry Point

A Matrix bot that wraps Claude Code CLI for remote assistance via chat.
Supports session persistence, access control, and mobile-optimized responses.

Usage:
    python bot.py [--config CONFIG_PATH]

Deploy to: ~/.claude-matrix-bot/bot.py on LXC_matrix
"""

import asyncio
import logging
import os
import signal
import sys
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
)

from claude_cli import ClaudeCLI
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
        structlog.dev.ConsoleRenderer()
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
        self.claude_cli: Optional[ClaudeCLI] = None
        self._running = False

    def _load_config(self, config_path: str) -> dict:
        """Load configuration from YAML file."""
        path = Path(config_path)
        if not path.exists():
            log.error("Config file not found", path=config_path)
            sys.exit(1)

        with open(path) as f:
            config = yaml.safe_load(f)

        log.info("Configuration loaded", path=config_path)
        return config

    def _setup_logging(self):
        """Configure logging based on config."""
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

        # Initialize Claude CLI wrapper
        claude_config = self.config.get("claude", {})
        self.claude_cli = ClaudeCLI(
            working_directory=claude_config.get("working_directory", os.getcwd()),
            timeout=claude_config.get("command_timeout", 300),
            skip_permissions=claude_config.get("dangerously_skip_permissions", False),
        )

        # Initialize Matrix client
        matrix_config = self.config.get("matrix", {})
        homeserver = matrix_config.get("homeserver")
        bot_user = matrix_config.get("bot_user")

        client_config = AsyncClientConfig(
            max_limit_exceeded=0,
            max_timeouts=0,
            store_sync_tokens=True,
            encryption_enabled=False,  # Disable E2EE for simplicity
        )

        self.client = AsyncClient(
            homeserver,
            bot_user,
            config=client_config,
            store_path=str(Path.home() / ".claude-matrix-bot" / "store"),
        )

        # Load access token
        token_file = matrix_config.get("access_token_file")
        if token_file and Path(token_file).exists():
            with open(token_file) as f:
                access_token = f.read().strip()
            self.client.access_token = access_token
            self.client.user_id = bot_user
            log.info("Loaded access token", user=bot_user)
        else:
            log.error("Access token file not found", path=token_file)
            sys.exit(1)

        # Register event callbacks
        self.client.add_event_callback(self._on_message, RoomMessageText)
        self.client.add_event_callback(self._on_invite, InviteMemberEvent)

        # Start sync loop
        self._running = True
        log.info("Bot started, syncing...")

        try:
            await self.client.sync_forever(timeout=30000, full_state=True)
        except Exception as e:
            log.error("Sync error", error=str(e))
            raise

    async def stop(self):
        """Gracefully stop the bot."""
        self._running = False
        if self.client:
            await self.client.close()
        if self.session_manager:
            await self.session_manager.close()
        log.info("Bot stopped")

    def _is_allowed_user(self, user_id: str) -> bool:
        """Check if user is allowed to use the bot."""
        allowed = self.config.get("access", {}).get("allowed_users", [])
        return user_id in allowed

    def _is_allowed_room(self, room_id: str) -> bool:
        """Check if room is allowed (empty list = all rooms allowed)."""
        allowed = self.config.get("access", {}).get("allowed_rooms", [])
        return len(allowed) == 0 or room_id in allowed

    async def _on_invite(self, room: MatrixRoom, event: InviteMemberEvent):
        """Handle room invites - auto-join if from allowed user."""
        if event.state_key != self.client.user_id:
            return

        if self._is_allowed_user(event.sender):
            log.info("Accepting invite", room=room.room_id, from_user=event.sender)
            await self.client.join(room.room_id)
        else:
            log.warning("Rejecting invite from unauthorized user",
                       room=room.room_id, from_user=event.sender)

    async def _on_message(self, room: MatrixRoom, event: RoomMessageText):
        """Handle incoming messages."""
        # Ignore our own messages
        if event.sender == self.client.user_id:
            return

        # Check access control
        if not self._is_allowed_user(event.sender):
            log.warning("Ignoring message from unauthorized user", user=event.sender)
            return

        if not self._is_allowed_room(room.room_id):
            log.warning("Ignoring message from unauthorized room", room=room.room_id)
            return

        message = event.body.strip()
        log.info("Received message", user=event.sender, room=room.room_id,
                message=message[:50] + "..." if len(message) > 50 else message)

        # Handle bot commands
        if message.startswith("/"):
            await self._handle_command(room, event.sender, message)
        else:
            await self._handle_claude_message(room, event.sender, message)

    async def _handle_command(self, room: MatrixRoom, sender: str, message: str):
        """Handle bot commands (/new, /status, /cd)."""
        parts = message.split(maxsplit=1)
        command = parts[0].lower()
        args = parts[1] if len(parts) > 1 else ""

        if command == "/new":
            await self.session_manager.reset_session(sender)
            await self._send_message(room, "Session reset. Starting fresh context.")

        elif command == "/status":
            session = await self.session_manager.get_session(sender)
            if session:
                status = f"**Session Status**\n"
                status += f"- Session ID: `{session['session_id'][:8]}...`\n"
                status += f"- Working Dir: `{session['working_dir']}`\n"
                status += f"- Last Active: {session['last_active']}"
            else:
                status = "No active session. Send any message to start one."
            await self._send_message(room, status)

        elif command == "/cd":
            if args:
                path = Path(args).expanduser()
                if path.exists() and path.is_dir():
                    await self.session_manager.update_working_dir(sender, str(path))
                    await self._send_message(room, f"Working directory changed to: `{path}`")
                else:
                    await self._send_message(room, f"Directory not found: `{args}`")
            else:
                await self._send_message(room, "Usage: `/cd <path>`")

        elif command == "/help":
            help_text = """**Claude Bot Commands**
- `/new` - Start fresh session (clear context)
- `/status` - Show current session info
- `/cd <path>` - Change working directory
- `/help` - Show this help message

Send any other message to interact with Claude Code."""
            await self._send_message(room, help_text)

        else:
            await self._send_message(room, f"Unknown command: `{command}`. Use `/help` for available commands.")

    async def _handle_claude_message(self, room: MatrixRoom, sender: str, message: str):
        """Send message to Claude Code and return response."""
        # Get or create session
        session = await self.session_manager.get_or_create_session(sender)

        # Build context preamble
        preamble = self.config.get("response", {}).get("context_preamble", "")
        env_profile = os.environ.get("ENV_PROFILE", "LXC_matrix")
        preamble = preamble.replace("{env_profile}", env_profile)

        # Send typing indicator
        await self.client.room_typing(room.room_id, typing_state=True, timeout=30000)

        try:
            # Call Claude Code CLI
            response = await self.claude_cli.send_message(
                message=message,
                session_id=session.get("claude_session_id"),
                working_dir=session.get("working_dir"),
                context_preamble=preamble,
            )

            # Update session with Claude's session ID if new
            if response.get("session_id") and response["session_id"] != session.get("claude_session_id"):
                await self.session_manager.update_claude_session(
                    sender, response["session_id"]
                )

            # Truncate response if needed
            max_length = self.config.get("claude", {}).get("max_response_length", 4000)
            response_text = response.get("text", "No response from Claude")

            if len(response_text) > max_length:
                suffix = self.config.get("response", {}).get(
                    "truncation_suffix",
                    "\n\n... [Response truncated]"
                )
                response_text = response_text[:max_length - len(suffix)] + suffix

            await self._send_message(room, response_text)

        except asyncio.TimeoutError:
            await self._send_message(room, "Request timed out. Try a simpler question.")
        except Exception as e:
            log.error("Error calling Claude", error=str(e))
            await self._send_message(room, f"Error: {str(e)}")
        finally:
            await self.client.room_typing(room.room_id, typing_state=False)

    async def _send_message(self, room: MatrixRoom, message: str):
        """Send a message to a room."""
        await self.client.room_send(
            room.room_id,
            message_type="m.room.message",
            content={
                "msgtype": "m.text",
                "body": message,
                "format": "org.matrix.custom.html",
                "formatted_body": self._markdown_to_html(message),
            },
        )

    def _markdown_to_html(self, text: str) -> str:
        """Convert basic markdown to HTML for Matrix."""
        import re
        # Bold
        text = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', text)
        # Italic
        text = re.sub(r'\*(.+?)\*', r'<em>\1</em>', text)
        # Code blocks
        text = re.sub(r'```(\w+)?\n(.*?)```', r'<pre><code>\2</code></pre>', text, flags=re.DOTALL)
        # Inline code
        text = re.sub(r'`(.+?)`', r'<code>\1</code>', text)
        # Line breaks
        text = text.replace('\n', '<br>')
        return text


async def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Claude Matrix Bot")
    parser.add_argument(
        "--config",
        default=str(Path.home() / ".claude-matrix-bot" / "config.yaml"),
        help="Path to config file",
    )
    args = parser.parse_args()

    bot = ClaudeMatrixBot(args.config)

    # Handle shutdown signals
    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, lambda: asyncio.create_task(bot.stop()))

    try:
        await bot.start()
    except KeyboardInterrupt:
        pass
    finally:
        await bot.stop()


if __name__ == "__main__":
    asyncio.run(main())
