#!/usr/bin/env python3
"""
Claude Code Bridge & Legacy CLI Wrapper

Primary: ClaudeBridge — spawns Node.js bridge per query for SDK-based
interactive permissions and streaming via JSON-lines IPC.

Fallback: ClaudeCLILegacy — original claude --print subprocess mode.

Deploy to: ~/.claude-matrix-bot/claude_cli.py on VPS_PROD
"""

import asyncio
import json
import os
import re
import shutil
from pathlib import Path
from typing import Callable, Optional

import structlog

log = structlog.get_logger()


class ClaudeBridge:
    """Bridge to Claude Code SDK via Node.js subprocess.

    Spawns a bridge process per query. Events are delivered via async
    callbacks registered with on(). The bridge exits after query completion.
    """

    def __init__(
        self,
        bridge_path: str,
        working_directory: str = None,
        timeout: int = 300,
        permission_timeout: int = 300,
    ):
        self.bridge_path = bridge_path
        self.working_directory = working_directory or str(Path.home())
        self.timeout = timeout
        self.permission_timeout = permission_timeout
        self._process = None
        self._callbacks: dict[str, list[Callable]] = {}
        self._reader_task = None
        self._stderr_task = None
        self._complete_event = None
        self._result = None

    def on(self, event_type: str, callback: Callable):
        """Register async callback for an event type.

        Supported events: text_chunk, permission_request, permission_timeout,
        session_id, complete, error
        """
        self._callbacks.setdefault(event_type, []).append(callback)

    def off(self, event_type: str = None):
        """Remove callbacks for event_type, or all if None."""
        if event_type:
            self._callbacks.pop(event_type, None)
        else:
            self._callbacks.clear()

    async def send_query(
        self,
        message: str,
        session_id: Optional[str] = None,
        working_dir: Optional[str] = None,
        system_prompt: Optional[str] = None,
    ) -> dict:
        """Spawn bridge, send query, return when complete.

        Events are delivered via callbacks during execution.
        Returns dict with 'text', 'session_id', and optional 'error' key.
        """
        env = os.environ.copy()
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"

        cwd = working_dir or self.working_directory

        self._complete_event = asyncio.Event()
        self._result = None

        self._process = await asyncio.create_subprocess_exec(
            "node",
            self.bridge_path,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=cwd,
            env=env,
        )

        # Start reading stdout and stderr concurrently
        self._reader_task = asyncio.create_task(self._read_stdout())
        self._stderr_task = asyncio.create_task(self._read_stderr())

        # Build and send query message
        query_msg = {
            "type": "query",
            "message": message,
            "workingDir": cwd,
            "permissionTimeout": self.permission_timeout,
        }
        if session_id:
            query_msg["sessionId"] = session_id
        if system_prompt:
            query_msg["systemPrompt"] = system_prompt

        self._write(query_msg)

        # Wait for complete/error event or overall timeout
        try:
            await asyncio.wait_for(
                self._complete_event.wait(), timeout=self.timeout
            )
        except asyncio.TimeoutError:
            log.warning("Bridge query timeout", timeout=self.timeout)
            await self.abort()
            raise

        # Give reader a moment to finish after bridge exits
        if self._reader_task and not self._reader_task.done():
            try:
                await asyncio.wait_for(self._reader_task, timeout=5)
            except asyncio.TimeoutError:
                pass

        return self._result or {"text": "", "session_id": None}

    def _write(self, obj: dict):
        """Write a JSON line to bridge stdin."""
        if (
            self._process
            and self._process.stdin
            and not self._process.stdin.is_closing()
        ):
            data = json.dumps(obj) + "\n"
            self._process.stdin.write(data.encode())

    async def _read_stdout(self):
        """Read JSON lines from bridge stdout and dispatch events."""
        try:
            while True:
                line = await self._process.stdout.readline()
                if not line:
                    break
                line = line.decode().strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    log.debug("Non-JSON from bridge", output=line[:200])
                    continue

                event_type = msg.get("type")

                # Handle terminal events
                if event_type == "complete":
                    self._result = {
                        "text": msg.get("result", ""),
                        "session_id": msg.get("sessionId"),
                    }
                    self._complete_event.set()
                elif event_type == "error":
                    self._result = {
                        "text": f"Error: {msg.get('message', 'Unknown error')}",
                        "session_id": None,
                        "error": True,
                    }
                    self._complete_event.set()

                # Fire registered callbacks
                for cb in self._callbacks.get(event_type, []):
                    try:
                        await cb(msg)
                    except Exception as e:
                        log.error(
                            "Callback error", event=event_type, error=str(e)
                        )
        except Exception as e:
            log.error("Bridge stdout reader error", error=str(e))
            if not self._complete_event.is_set():
                self._result = {
                    "text": f"Bridge error: {str(e)}",
                    "session_id": None,
                    "error": True,
                }
                self._complete_event.set()

    async def _read_stderr(self):
        """Read debug output from bridge stderr."""
        try:
            while True:
                line = await self._process.stderr.readline()
                if not line:
                    break
                log.debug("bridge", output=line.decode().strip())
        except Exception:
            pass

    async def send_permission_response(self, request_id: str, action: str):
        """Send permission allow/deny to the bridge."""
        self._write(
            {
                "type": "permission_response",
                "requestId": request_id,
                "action": action,
            }
        )

    async def abort(self):
        """Abort active query and terminate bridge process."""
        if self._process and self._process.returncode is None:
            self._write({"type": "abort"})
            try:
                await asyncio.wait_for(self._process.wait(), timeout=5)
            except asyncio.TimeoutError:
                self._process.kill()
        self._process = None

    @property
    def is_active(self) -> bool:
        return self._process is not None and self._process.returncode is None

    async def check_health(self) -> bool:
        """Check if Node.js and bridge.mjs are available."""
        bridge_ok = Path(self.bridge_path).exists()
        node_ok = shutil.which("node") is not None

        if not bridge_ok:
            log.error("Bridge script not found", path=self.bridge_path)
        if not node_ok:
            log.error("Node.js not found in PATH")

        healthy = bridge_ok and node_ok
        if healthy:
            log.info("Bridge health check passed", path=self.bridge_path)
        return healthy


class ClaudeCLILegacy:
    """Legacy wrapper for Claude Code CLI (claude --print).

    Used as fallback when the Node.js bridge is unavailable.
    """

    def __init__(
        self,
        working_directory: str = None,
        timeout: int = 300,
        skip_permissions: bool = False,
    ):
        self.working_directory = working_directory or str(Path.home())
        self.timeout = timeout
        self.skip_permissions = skip_permissions
        self.claude_path = shutil.which("claude") or "claude"
        log.info("Legacy Claude CLI path resolved", path=self.claude_path)

    async def send_message(
        self,
        message: str,
        session_id: Optional[str] = None,
        working_dir: Optional[str] = None,
        context_preamble: Optional[str] = None,
    ) -> dict:
        """Send a message to Claude Code CLI and return the response."""
        full_message = message
        if context_preamble:
            full_message = f"{context_preamble}\n\nUser: {message}"

        cmd = [self.claude_path, "--print"]
        if session_id:
            cmd.extend(["--resume", session_id])
        if self.skip_permissions:
            cmd.append("--dangerously-skip-permissions")

        cwd = working_dir or self.working_directory

        log.debug(
            "Executing Claude CLI",
            cmd=" ".join(cmd),
            cwd=cwd,
            message_length=len(full_message),
        )

        try:
            result = await asyncio.wait_for(
                self._run_subprocess(cmd, full_message, cwd),
                timeout=self.timeout,
            )

            response_text = result.get("stdout", "")
            session_id = self._extract_session_id(result.get("stderr", ""))

            if result.get("returncode", 0) != 0:
                stderr_msg = result.get("stderr", "").strip()
                stdout_msg = result.get("stdout", "").strip()
                error_msg = (
                    stderr_msg
                    or stdout_msg
                    or f"Exit code {result.get('returncode')}"
                )

                log.error(
                    "Claude CLI error",
                    returncode=result.get("returncode"),
                    stderr_preview=(
                        stderr_msg[:200] if stderr_msg else "(empty)"
                    ),
                    stdout_preview=(
                        stdout_msg[:200] if stdout_msg else "(empty)"
                    ),
                )

                error_combined = (stderr_msg + " " + stdout_msg).lower()
                if "permission" in error_combined:
                    response_text = (
                        "Permission prompt required. Use `/new` to start "
                        "a fresh session."
                    )
                elif "rate limit" in error_combined:
                    response_text = (
                        "Rate limited. Please wait a moment and try again."
                    )
                elif (
                    "authentication" in error_combined
                    or "expired" in error_combined
                    or "401" in error_combined
                ):
                    response_text = (
                        "Authentication error — Claude OAuth token may "
                        "have expired. Credential sync needed."
                    )
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
        self, cmd: list, input_text: str, cwd: str
    ) -> dict:
        env = os.environ.copy()
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env.setdefault("HOME", str(Path.home()))

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
        patterns = [
            r"session[_\s]*(?:id)?[:\s]+([a-zA-Z0-9_-]+)",
            r"resuming\s+([a-zA-Z0-9_-]+)",
        ]
        for pattern in patterns:
            match = re.search(pattern, stderr, re.IGNORECASE)
            if match:
                return match.group(1)
        return None

    async def check_health(self) -> bool:
        try:
            result = await asyncio.wait_for(
                self._run_subprocess(
                    [self.claude_path, "--version"], "", self.working_directory
                ),
                timeout=10,
            )
            healthy = result.get("returncode", 1) == 0
            version = result.get("stdout", "").strip()
            if healthy:
                log.info(
                    "Legacy Claude CLI health check passed", version=version
                )
            else:
                log.error(
                    "Legacy Claude CLI health check failed",
                    returncode=result.get("returncode"),
                    stdout=result.get("stdout", "")[:200],
                    stderr=result.get("stderr", "")[:200],
                )
            return healthy
        except Exception as e:
            log.error("Legacy Claude CLI health check exception", error=str(e))
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
