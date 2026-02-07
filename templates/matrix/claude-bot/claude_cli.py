#!/usr/bin/env python3
"""
Claude CLI Wrapper

Wraps the Claude Code CLI for subprocess execution with session management.
Handles timeouts, error handling, and response parsing.

Deploy to: ~/.claude-matrix-bot/claude_cli.py on LXC_matrix
"""

import asyncio
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Optional

import structlog

log = structlog.get_logger()


class ClaudeCLI:
    """Wrapper for Claude Code CLI with session management."""

    def __init__(
        self,
        working_directory: str = None,
        timeout: int = 300,
        skip_permissions: bool = False,
    ):
        self.working_directory = working_directory or str(Path.home())
        self.timeout = timeout
        self.skip_permissions = skip_permissions

    async def send_message(
        self,
        message: str,
        session_id: Optional[str] = None,
        working_dir: Optional[str] = None,
        context_preamble: Optional[str] = None,
    ) -> dict:
        """
        Send a message to Claude Code CLI and return the response.

        Args:
            message: The user's message
            session_id: Optional session ID to resume
            working_dir: Optional working directory override
            context_preamble: Optional context to prepend to message

        Returns:
            dict with 'text' (response) and 'session_id' (for resuming)
        """
        # Build the full message with context
        full_message = message
        if context_preamble:
            full_message = f"{context_preamble}\n\nUser: {message}"

        # Build command
        cmd = ["claude", "--print"]

        if session_id:
            cmd.extend(["--resume", session_id])

        if self.skip_permissions:
            cmd.append("--dangerously-skip-permissions")

        # Set working directory
        cwd = working_dir or self.working_directory

        log.debug("Executing Claude CLI",
                 cmd=" ".join(cmd),
                 cwd=cwd,
                 message_length=len(full_message))

        try:
            # Run Claude CLI in subprocess
            result = await asyncio.wait_for(
                self._run_subprocess(cmd, full_message, cwd),
                timeout=self.timeout
            )

            # Parse response
            response_text = result.get("stdout", "")
            session_id = self._extract_session_id(result.get("stderr", ""))

            # Handle errors
            if result.get("returncode", 0) != 0:
                error_msg = result.get("stderr", "Unknown error")
                log.error("Claude CLI error", error=error_msg)

                # Check for specific error types
                if "permission" in error_msg.lower():
                    response_text = "Permission prompt required. Use `/new` to start a fresh session with --dangerously-skip-permissions if needed."
                elif "rate limit" in error_msg.lower():
                    response_text = "Rate limited. Please wait a moment and try again."
                else:
                    response_text = f"Error from Claude: {error_msg[:500]}"

            return {
                "text": response_text.strip(),
                "session_id": session_id,
                "returncode": result.get("returncode", 0),
            }

        except asyncio.TimeoutError:
            log.warning("Claude CLI timeout", timeout=self.timeout)
            raise
        except Exception as e:
            log.error("Claude CLI execution error", error=str(e))
            raise

    async def _run_subprocess(
        self,
        cmd: list,
        input_text: str,
        cwd: str,
    ) -> dict:
        """Run subprocess asynchronously."""
        # Prepare environment
        env = os.environ.copy()
        env["TERM"] = "dumb"  # Disable color codes
        env["NO_COLOR"] = "1"  # Alternative no-color flag

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=cwd,
            env=env,
        )

        stdout, stderr = await proc.communicate(input=input_text.encode())

        return {
            "stdout": stdout.decode("utf-8", errors="replace"),
            "stderr": stderr.decode("utf-8", errors="replace"),
            "returncode": proc.returncode,
        }

    def _extract_session_id(self, stderr: str) -> Optional[str]:
        """Extract session ID from Claude CLI stderr output."""
        # Claude Code outputs session info to stderr
        # Look for patterns like "Session: abc123" or "session_id: abc123"
        patterns = [
            r'session[_\s]*(?:id)?[:\s]+([a-zA-Z0-9_-]+)',
            r'resuming\s+([a-zA-Z0-9_-]+)',
        ]

        for pattern in patterns:
            match = re.search(pattern, stderr, re.IGNORECASE)
            if match:
                return match.group(1)

        return None

    async def check_health(self) -> bool:
        """Check if Claude CLI is available and working."""
        try:
            result = await asyncio.wait_for(
                self._run_subprocess(
                    ["claude", "--version"],
                    "",
                    self.working_directory,
                ),
                timeout=10,
            )
            return result.get("returncode", 1) == 0
        except Exception:
            return False


class ClaudeSession:
    """Represents a Claude Code session with history."""

    def __init__(self, session_id: str, working_dir: str):
        self.session_id = session_id
        self.working_dir = working_dir
        self.message_count = 0

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "working_dir": self.working_dir,
            "message_count": self.message_count,
        }
